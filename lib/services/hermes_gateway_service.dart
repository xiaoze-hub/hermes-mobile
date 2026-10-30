import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../models/session.dart';

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error
}

class HermesGatewayService {
  String serverUrl;
  String token;

  late Dio _dio;
  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  int _connectionGeneration = 0;
  bool _jsonRpc = false;
  Completer<void>? _rpcReady;
  int _rpcId = 0;
  final Map<int, String> _rpcMethods = {};
  final Map<int, Completer<dynamic>> _rpcPending = {};

  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _streamEventController =
      StreamController<Map<String, dynamic>>.broadcast();

  ConnectionStatus get connectionStatus => _connectionStatus;
  Stream<ConnectionStatus> get statusStream => _statusController.stream;
  Stream<Map<String, dynamic>> get streamEvents =>
      _streamEventController.stream;

  HermesGatewayService({
    required this.serverUrl,
    required this.token,
  }) {
    _initDio();
  }

  void updateConfig(String newServerUrl, String newToken) {
    serverUrl = newServerUrl;
    token = newToken;
    _initDio();
    disconnect();
  }

  void _initDio() {
    _dio = Dio(BaseOptions(
      baseUrl: serverUrl.endsWith('/')
          ? serverUrl.substring(0, serverUrl.length - 1)
          : serverUrl,
      headers: {
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
    ));
  }

  // --- 1. REST API: 会话操作 ---

  Future<List<HermesSession>> getSessions() async {
    try {
      final res = await _dio.get('/api/sessions');
      final data = res.data;
      List rawList = [];
      if (data is List) {
        rawList = data;
      } else if (data is Map && data['sessions'] is List) {
        rawList = data['sessions'];
      }
      return rawList
          .map((e) => HermesSession.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getModelInfo() async =>
      Map<String, dynamic>.from(
          (await _dio.get('/api/model/info')).data as Map);

  Future<Map<String, dynamic>> getModelOptions() async =>
      Map<String, dynamic>.from((await _dio.get('/api/model/options',
              queryParameters: {'include_unconfigured': 1}))
          .data as Map);

  Future<Map<String, dynamic>> setModel(
          {required String provider,
          required String model,
          String? baseUrl}) async =>
      Map<String, dynamic>.from((await _dio.post('/api/model/set', data: {
        'scope': 'main',
        'provider': provider,
        'model': model,
        if (baseUrl != null && baseUrl.isNotEmpty) 'base_url': baseUrl,
      }))
          .data as Map);

  Future<Map<String, dynamic>> checkForUpdate() async =>
      Map<String, dynamic>.from(
          (await _dio.get('/api/hermes/update/check')).data as Map);

  Future<Map<String, dynamic>> restartGateway() async =>
      Map<String, dynamic>.from(
          (await _dio.post('/api/gateway/restart')).data as Map);

  Future<Map<String, dynamic>> updateHermes() async =>
      Map<String, dynamic>.from(
          (await _dio.post('/api/hermes/update')).data as Map);

  Future<Map<String, dynamic>> getActionStatus(String name) async =>
      Map<String, dynamic>.from((await _dio.get(
              '/api/actions/${Uri.encodeComponent(name)}/status',
              queryParameters: {'lines': 50}))
          .data as Map);

  Future<HermesSession> createSession({String title = '新会话'}) async {
    if (!_jsonRpc) {
      try {
        final res = await _dio.post('/api/sessions', data: {'title': title});
        return HermesSession.fromJson(res.data);
      } catch (restError) {
        if (_connectionStatus != ConnectionStatus.connected) {
          await connectWebSocket('');
        }
        try {
          await _rpcReady?.future.timeout(const Duration(seconds: 5));
        } catch (_) {
          throw restError;
        }
        if (!_jsonRpc) rethrow;
      }
    }
    final result = await _requestRpc('session.create', {'title': title});
    if (result is! Map || result['session_id'] == null) {
      throw const FormatException('网关未返回会话 ID');
    }
    return HermesSession(
        id: result['session_id'].toString(),
        title: title,
        updatedAt: DateTime.now());
  }

  Future<bool> deleteSession(String sessionId) async {
    final res = await _dio.delete('/api/sessions/$sessionId');
    return res.statusCode == 200 || res.statusCode == 204;
  }

  Future<List<Map<String, dynamic>>> getSessionMessages(String sessionId,
      {int offset = 0}) async {
    final res = await _dio.get(
        '/api/sessions/${Uri.encodeComponent(sessionId)}/messages',
        queryParameters: {
          'limit': 100,
          'offset': offset,
          'order': 'latest',
          'include_compacted': true,
          'inline_images': false
        });
    final data = res.data;
    final dynamic messages = data is List
        ? data
        : data is Map
            ? (data['messages'] ??
                (data['data'] is Map ? data['data']['messages'] : data['data']))
            : null;
    if (messages is! List) {
      throw const FormatException('历史消息格式无法识别');
    }
    return messages
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  // --- 2. WebSocket: 实时流式通信 ---

  Future<void> connectWebSocket(String currentSessionId) async {
    disconnect();
    final generation = _connectionGeneration;
    _jsonRpc = false;
    _rpcReady = Completer<void>();
    _rpcMethods.clear();

    _updateStatus(ConnectionStatus.connecting);
    final base = Uri.parse(serverUrl);
    final uri = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '${base.path.replaceFirst(RegExp(r'/+$'), '')}/api/ws',
      queryParameters: {
        'session_id': currentSessionId,
        if (token.isNotEmpty) 'token': token
      },
    );

    try {
      final channel = WebSocketChannel.connect(uri);
      _wsChannel = channel;
      await channel.ready;
      if (generation != _connectionGeneration) return;
      _updateStatus(ConnectionStatus.connected);
      _startHeartbeat();
      _wsSubscription = channel.stream.listen(
        (data) {
          if (_connectionStatus != ConnectionStatus.connected) {
            _updateStatus(ConnectionStatus.connected);
            _startHeartbeat();
          }
          try {
            final decoded = jsonDecode(data as String) as Map<String, dynamic>;
            _handleFrame(decoded, currentSessionId);
          } catch (e) {
            // Ignore malformed frames without terminating the connection.
          }
        },
        onError: (err) {
          if (generation == _connectionGeneration) {
            _scheduleReconnect(currentSessionId);
          }
        },
        onDone: () {
          if (generation == _connectionGeneration) {
            _scheduleReconnect(currentSessionId);
          }
        },
      );
    } catch (e) {
      if (generation == _connectionGeneration) {
        _scheduleReconnect(currentSessionId);
      }
    }
  }

  Future<dynamic> _requestRpc(
      String method, Map<String, dynamic> params) async {
    final id = _rpcId + 1;
    final completer = Completer<dynamic>();
    _rpcPending[id] = completer;
    _sendRpc(method, params);
    try {
      return await completer.future.timeout(const Duration(seconds: 15));
    } finally {
      _rpcPending.remove(id);
    }
  }

  void _sendRpc(String method, Map<String, dynamic> params) {
    final id = ++_rpcId;
    _rpcMethods[id] = method;
    _wsChannel!.sink.add(jsonEncode(
        {'jsonrpc': '2.0', 'id': id, 'method': method, 'params': params}));
  }

  void _handleFrame(Map<String, dynamic> frame, String sessionId) {
    if (frame['jsonrpc'] == '2.0') {
      final id = frame['id'];
      if (id is int && _rpcMethods.containsKey(id)) {
        final method = _rpcMethods.remove(id);
        final pending = _rpcPending.remove(id);
        if (pending != null) {
          if (frame['error'] != null) {
            pending.completeError(Exception(frame['error'].toString()));
          } else {
            pending.complete(frame['result']);
          }
          return;
        }
        if (frame['error'] != null) {
          _streamEventController
              .add({'type': 'error', 'content': '$method: ${frame['error']}'});
        } else if (method == 'session.resume' && frame['result'] is Map) {
          final result = Map<String, dynamic>.from(frame['result'] as Map);
          if (result['running'] == true && result['inflight'] is Map) {
            _streamEventController.add(
                {'type': 'resume_snapshot', 'inflight': result['inflight']});
          }
        }
        return;
      }
      if (frame['method'] != 'event' || frame['params'] is! Map) return;
      final event = Map<String, dynamic>.from(frame['params'] as Map);
      final type = event['type'];
      if (type == 'gateway.ready') {
        _jsonRpc = true;
        if (!(_rpcReady?.isCompleted ?? true)) _rpcReady!.complete();
        if (sessionId.isNotEmpty) {
          _sendRpc('session.resume', {
            'session_id': sessionId,
            'omit_messages': true,
            'inline_images': false
          });
        }
        return;
      }
      if (event['session_id'] != null && event['session_id'] != sessionId) {
        return;
      }
      final payload = event['payload'] is Map
          ? Map<String, dynamic>.from(event['payload'] as Map)
          : <String, dynamic>{};
      final mapped = <String, dynamic>{};
      switch (type) {
        case 'message.start':
          mapped.addAll({'type': 'start'});
          break;
        case 'message.delta':
          mapped.addAll({'type': 'content', 'content': payload['text'] ?? ''});
          break;
        case 'reasoning.delta':
        case 'thinking.delta':
          mapped.addAll({'type': 'thinking', 'content': payload['text'] ?? ''});
          break;
        case 'tool.start':
          mapped.addAll({
            'type': 'tool_start',
            'tool_id': payload['tool_id'],
            'tool_name': payload['name'],
            'arguments': payload['args_text'] ?? payload['args']
          });
          break;
        case 'tool.complete':
          mapped.addAll({
            'type': 'tool_end',
            'tool_id': payload['tool_id'],
            'result': payload['result_text'] ?? payload['result']
          });
          break;
        case 'message.complete':
          mapped.addAll({
            'type': 'done',
            'content': payload['text'],
            'error': payload['error']
          });
          break;
        case 'error':
          mapped.addAll({
            'type': 'error',
            'content': payload['message'] ?? payload.toString()
          });
          break;
      }
      if (mapped.isNotEmpty) _streamEventController.add(mapped);
      return;
    }
    _streamEventController.add(frame);
  }

  void sendMessage({required String sessionId, required String text}) {
    if (_wsChannel == null || _connectionStatus != ConnectionStatus.connected) {
      throw Exception("未连接到 Linux 服务器 Hermes 网关");
    }

    if (_jsonRpc) {
      _sendRpc('prompt.submit', {'session_id': sessionId, 'text': text});
      return;
    }
    final payload = {
      "type": "chat_message",
      "session_id": sessionId,
      "message": text,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
    };
    _wsChannel!.sink.add(jsonEncode(payload));
  }

  void _scheduleReconnect(String currentSessionId) {
    _cleanupWs();
    _updateStatus(ConnectionStatus.reconnecting);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 4), () {
      connectWebSocket(currentSessionId);
    });
  }

  void _startHeartbeat() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_connectionStatus == ConnectionStatus.connected &&
          _wsChannel != null &&
          !_jsonRpc) {
        _wsChannel!.sink.add(jsonEncode({"type": "ping"}));
      }
    });
  }

  void _updateStatus(ConnectionStatus newStatus) {
    _connectionStatus = newStatus;
    _statusController.add(newStatus);
  }

  void _cleanupWs() {
    _pingTimer?.cancel();
    _wsSubscription?.cancel();
    _wsChannel?.sink.close(status.goingAway);
    _wsChannel = null;
  }

  void disconnect() {
    for (final pending in _rpcPending.values) {
      if (!pending.isCompleted) pending.completeError(StateError('连接已关闭'));
    }
    _rpcPending.clear();
    _connectionGeneration++;
    _reconnectTimer?.cancel();
    _cleanupWs();
    _updateStatus(ConnectionStatus.disconnected);
  }

  void dispose() {
    disconnect();
    _statusController.close();
    _streamEventController.close();
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
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
  Completer<void>? _sessionReady;
  String _resumingSessionId = '';
  final Map<String, String> _runtimeSessionIds = {};
  Object? _sessionResumeError;
  final Set<String> _freshSessionIds = {};
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

  bool get supportsJsonRpc => _jsonRpc;

  Future<dynamic> callRpc(String method, Map<String, dynamic> params) async {
    try {
      await _rpcReady?.future.timeout(const Duration(seconds: 6));
    } catch (_) {}
    if (!_jsonRpc ||
        _wsChannel == null ||
        _connectionStatus != ConnectionStatus.connected) {
      throw StateError('当前网关未建立 JSON-RPC 连接');
    }
    return _requestRpc(method, _withRuntimeSessionId(method, params));
  }

  Map<String, dynamic> _withRuntimeSessionId(
      String method, Map<String, dynamic> params) {
    if (method == 'session.resume' || params['session_id'] == null) {
      return params;
    }
    final storedId = params['session_id'].toString();
    final runtimeId = _runtimeSessionIds[storedId];
    return runtimeId == null ? params : {...params, 'session_id': runtimeId};
  }

  void _captureRuntimeSessionId(String storedId, dynamic result) {
    if (result is! Map) return;
    final runtimeId = result['session_id']?.toString();
    if (runtimeId != null && runtimeId.isNotEmpty) {
      _runtimeSessionIds[storedId] = runtimeId;
    }
  }

  Future<dynamic> interruptSession(String sessionId) =>
      callRpc('session.interrupt', {'session_id': sessionId});

  Future<List<Map<String, dynamic>>> getPendingApprovals(
      String sessionId) async {
    final result = await callRpc('approval.pending', {'session_id': sessionId});
    final approvals = result is Map ? result['approvals'] : null;
    return approvals is List
        ? approvals
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
  }

  Future<dynamic> respondApproval(
          String sessionId, String requestId, String choice) =>
      callRpc('approval.respond', {
        'session_id': sessionId,
        'request_id': requestId,
        'choice': choice,
      });

  Future<dynamic> attachFile(
          {required String sessionId,
          required String name,
          required String dataUrl}) =>
      callRpc('file.attach',
          {'session_id': sessionId, 'name': name, 'data_url': dataUrl});

  Future<dynamic> attachImage(
          {required String sessionId,
          required String name,
          required String base64}) =>
      callRpc('image.attach_bytes', {
        'session_id': sessionId,
        'filename': name,
        'content_base64': base64
      });

  Future<dynamic> attachPdf(
          {required String sessionId,
          required String name,
          required String base64}) =>
      callRpc('pdf.attach', {
        'session_id': sessionId,
        'filename': name,
        'content_base64': base64
      });

  Future<Map<String, dynamic>> sessionContext(String sessionId) async {
    final result =
        await callRpc('session.context_breakdown', {'session_id': sessionId});
    return result is Map
        ? Map<String, dynamic>.from(result)
        : <String, dynamic>{};
  }

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

  /// Searches conversation titles and message contents on gateways that expose
  /// the Hermes session search endpoint. `null` means an older gateway does
  /// not implement this endpoint; callers can fall back to title-only search.
  Future<List<HermesSession>?> searchSessions(String query) async {
    try {
      final response =
          await _dio.get('/api/sessions/search', queryParameters: {'q': query});
      final data = response.data;
      final results = data is Map ? data['results'] : null;
      if (results is! List) {
        throw const FormatException('会话搜索结果格式无法识别');
      }
      return results
          .whereType<Map>()
          .map(
              (item) => HermesSession.fromJson(Map<String, dynamic>.from(item)))
          .where((session) => session.id.isNotEmpty)
          .toList();
    } on DioException catch (error) {
      if (error.response?.statusCode == 404 ||
          error.response?.statusCode == 405) {
        return null;
      }
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
        final session = HermesSession.fromJson(res.data);
        _freshSessionIds.add(session.id);
        return session;
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
    final runtimeId = result['session_id'].toString();
    final storedId = result['stored_session_id']?.toString();
    final sessionId =
        storedId == null || storedId.isEmpty ? runtimeId : storedId;
    _runtimeSessionIds[sessionId] = runtimeId;
    final session =
        HermesSession(id: sessionId, title: title, updatedAt: DateTime.now());
    _freshSessionIds.add(session.id);
    return session;
  }

  Future<bool> deleteSession(String sessionId) async {
    final res = await _dio.delete('/api/sessions/$sessionId');
    return res.statusCode == 200 || res.statusCode == 204;
  }

  Future<void> renameSession(String sessionId, String title) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw ArgumentError('对话名称不能为空');
    }
    await _mutateStoredSession(sessionId, {'title': normalizedTitle});
  }

  Future<Map<String, dynamic>> _mutateStoredSession(
      String sessionId, Map<String, dynamic> changes) async {
    final path = '/api/sessions/${Uri.encodeComponent(sessionId)}';
    final snapshotResponse = await _dio.get('$path/mutation-snapshot');
    final snapshot = snapshotResponse.data;
    if (snapshot is! Map || snapshot['exists'] != true) {
      throw const FormatException('网关未返回会话修改凭据');
    }
    final revision = snapshot['runtime_revision'];
    final generation = snapshot['runtime_generation'];
    if (revision is! num || generation is! num) {
      throw const FormatException('网关返回的会话修改凭据不完整');
    }
    final response = await _dio.patch(path, data: {
      ...changes,
      'request_id': const Uuid().v4(),
      'expected_revision': revision.toInt(),
      'expected_generation': generation.toInt(),
    });
    if (response.data is! Map) {
      throw const FormatException('网关未确认会话修改结果');
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<Map<String, dynamic>>> getSessionMessages(String sessionId,
      {int offset = 0}) async {
    Response<dynamic> res;
    try {
      res = await _dio.get(
          '/api/sessions/${Uri.encodeComponent(sessionId)}/messages',
          queryParameters: {
            'limit': 100,
            'offset': offset,
            'order': 'latest',
            'include_compacted': true,
            'inline_images': false
          });
    } on DioException catch (error) {
      if (error.response?.statusCode == 404 &&
          offset == 0 &&
          _freshSessionIds.contains(sessionId)) {
        return <Map<String, dynamic>>[];
      }
      rethrow;
    }
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
    _sessionReady = Completer<void>();
    _resumingSessionId = currentSessionId;
    _runtimeSessionIds.clear();
    _sessionResumeError = null;
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
            if (method == 'session.resume' && frame['result'] is Map) {
              final result = Map<String, dynamic>.from(frame['result'] as Map);
              _captureRuntimeSessionId(_resumingSessionId, result);
              if (result['running'] == true && result['inflight'] is Map) {
                _streamEventController.add({
                  'type': 'resume_snapshot',
                  'inflight': result['inflight']
                });
              }
            }
            pending.complete(frame['result']);
          }
          return;
        }
        if (frame['error'] != null) {
          _streamEventController
              .add({'type': 'error', 'content': '$method: ${frame['error']}'});
        } else if (method == 'session.resume' && frame['result'] is Map) {
          final result = Map<String, dynamic>.from(frame['result'] as Map);
          _captureRuntimeSessionId(_resumingSessionId, result);
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
          unawaited(_resumeForSubmit(sessionId, _connectionGeneration));
        } else if (!(_sessionReady?.isCompleted ?? true)) {
          _sessionReady!.complete();
        }
        return;
      }
      final expectedRuntimeId = _runtimeSessionIds[sessionId] ?? sessionId;
      if (event['session_id'] != null &&
          event['session_id'] != expectedRuntimeId &&
          event['session_id'] != sessionId) {
        return;
      }
      final payload = event['payload'] is Map
          ? Map<String, dynamic>.from(event['payload'] as Map)
          : <String, dynamic>{};
      final mapped = <String, dynamic>{};
      if (type is String && type.startsWith('approval.')) {
        _streamEventController.add({
          'type': type,
          ...event,
          if (event['payload'] is Map)
            ...Map<String, dynamic>.from(event['payload'] as Map),
        });
        return;
      }
      if (type == 'voice.transcript') {
        _streamEventController.add({
          'type': type,
          ...event,
          if (event['payload'] is Map)
            ...Map<String, dynamic>.from(event['payload'] as Map),
        });
        return;
      }
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

  Future<void> _resumeForSubmit(String sessionId, int generation) async {
    try {
      final result = await _requestRpc('session.resume', {
        'session_id': sessionId,
        'omit_messages': true,
        'inline_images': false
      });
      _captureRuntimeSessionId(sessionId, result);
      if (generation == _connectionGeneration &&
          !(_sessionReady?.isCompleted ?? true)) {
        _sessionReady!.complete();
      }
    } catch (error) {
      if (generation == _connectionGeneration &&
          !(_sessionReady?.isCompleted ?? true)) {
        _sessionResumeError = error;
        _sessionReady!.complete();
      }
    }
  }

  Future<void> sendMessage(
      {required String sessionId, required String text}) async {
    if (_wsChannel == null || _connectionStatus != ConnectionStatus.connected) {
      throw StateError('网关尚未连接，请连接恢复后重试');
    }

    // The socket can be open before the gateway announces which protocol it
    // supports. Wait for that handshake before choosing JSON-RPC or legacy
    // chat_message, otherwise the first send after connect can use the wrong
    // wire format.
    final generation = _connectionGeneration;
    final rpcReady = _rpcReady;
    try {
      await rpcReady?.future.timeout(const Duration(seconds: 6));
    } on TimeoutException {
      // Older gateways do not emit gateway.ready and use the legacy protocol.
    }
    if (generation != _connectionGeneration ||
        _wsChannel == null ||
        _connectionStatus != ConnectionStatus.connected) {
      throw StateError('网关连接已变化，请重新发送');
    }

    if (_jsonRpc) {
      if (_resumingSessionId != sessionId) {
        _resumingSessionId = sessionId;
        _sessionReady = Completer<void>();
        _sessionResumeError = null;
        await _resumeForSubmit(sessionId, _connectionGeneration);
      }
      await _sessionReady?.future.timeout(const Duration(seconds: 18));
      if (_sessionResumeError != null) {
        throw StateError(_sessionResumeError.toString());
      }
      final runtimeId = _runtimeSessionIds[sessionId] ?? sessionId;
      await _requestRpc(
          'prompt.submit', {'session_id': runtimeId, 'text': text});
      _freshSessionIds.remove(sessionId);
      return;
    }
    final payload = {
      "type": "chat_message",
      "session_id": sessionId,
      "message": text,
      "timestamp": DateTime.now().millisecondsSinceEpoch,
    };
    _wsChannel!.sink.add(jsonEncode(payload));
    _freshSessionIds.remove(sessionId);
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

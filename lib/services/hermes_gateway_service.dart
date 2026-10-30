import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../models/session.dart';

enum ConnectionStatus { disconnected, connecting, connected, reconnecting, error }

class HermesGatewayService {
  String serverUrl;
  String token;

  late Dio _dio;
  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  Timer? _reconnectTimer;
  Timer? _pingTimer;

  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _streamEventController = StreamController<Map<String, dynamic>>.broadcast();

  ConnectionStatus get connectionStatus => _connectionStatus;
  Stream<ConnectionStatus> get statusStream => _statusController.stream;
  Stream<Map<String, dynamic>> get streamEvents => _streamEventController.stream;

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
      baseUrl: serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl,
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
      return rawList.map((e) => HermesSession.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      print('拉取会话失败: $e');
      rethrow;
    }
  }

  Future<HermesSession> createSession({String title = '新会话'}) async {
    final res = await _dio.post('/api/sessions', data: {'title': title});
    return HermesSession.fromJson(res.data);
  }

  Future<bool> deleteSession(String sessionId) async {
    final res = await _dio.delete('/api/sessions/$sessionId');
    return res.statusCode == 200 || res.statusCode == 204;
  }

  Future<List<Map<String, dynamic>>> getSessionMessages(String sessionId) async {
    try {
      final res = await _dio.get('/api/sessions/$sessionId/messages');
      if (res.data is List) {
        return List<Map<String, dynamic>>.from(res.data);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // --- 2. WebSocket: 实时流式通信 ---

  void connectWebSocket(String currentSessionId) {
    if (_connectionStatus == ConnectionStatus.connected) return;

    _updateStatus(ConnectionStatus.connecting);
    final cleanUrl = serverUrl.replaceFirst(RegExp(r'^http'), 'ws');
    final uri = Uri.parse('$cleanUrl/api/ws?session_id=$currentSessionId${token.isNotEmpty ? '&token=$token' : ''}');

    try {
      _wsChannel = WebSocketChannel.connect(uri);
      _wsSubscription = _wsChannel!.stream.listen(
        (data) {
          if (_connectionStatus != ConnectionStatus.connected) {
            _updateStatus(ConnectionStatus.connected);
            _startHeartbeat();
          }
          try {
            final decoded = jsonDecode(data as String) as Map<String, dynamic>;
            _streamEventController.add(decoded);
          } catch (e) {
            print('解析 WS 消息失败: $e');
          }
        },
        onError: (err) {
          print('WS 连接异常: $err');
          _scheduleReconnect(currentSessionId);
        },
        onDone: () {
          print('WS 连接关闭');
          _scheduleReconnect(currentSessionId);
        },
      );
    } catch (e) {
      _scheduleReconnect(currentSessionId);
    }
  }

  void sendMessage({required String sessionId, required String text}) {
    if (_wsChannel == null || _connectionStatus != ConnectionStatus.connected) {
      throw Exception("未连接到 Linux 服务器 Hermes 网关");
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
      if (_connectionStatus == ConnectionStatus.connected && _wsChannel != null) {
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

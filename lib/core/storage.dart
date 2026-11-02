import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GatewayConfig {
  final String serverUrl;
  final String token;

  const GatewayConfig({required this.serverUrl, required this.token});

  bool get isValid => serverUrl.isNotEmpty;
}

class HermesStorage {
  static const _keyServerUrl = 'hermes_gateway_url';
  static const _keyToken = 'hermes_gateway_token';
  static const _keyLastSessionId = 'hermes_last_session_id';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  Future<GatewayConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_keyServerUrl) ?? 'http://192.168.1.100:9119';
    final token = await _secureStorage.read(key: _keyToken) ?? '';
    return GatewayConfig(serverUrl: url, token: token);
  }

  Future<void> saveConfig(String serverUrl, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyServerUrl, serverUrl.trim());
    await _secureStorage.write(key: _keyToken, value: token.trim());
  }

  Future<String?> getLastSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastSessionId);
  }

  Future<void> saveLastSessionId(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastSessionId, sessionId);
  }

  Future<String?> loadDraft(String sessionId) =>
      _secureStorage.read(key: 'hermes_draft_$sessionId');

  Future<void> saveDraft(String sessionId, String text) => text.isEmpty
      ? _secureStorage.delete(key: 'hermes_draft_$sessionId')
      : _secureStorage.write(key: 'hermes_draft_$sessionId', value: text);
}

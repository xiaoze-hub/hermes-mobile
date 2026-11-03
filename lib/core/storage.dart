import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GatewayConfig {
  final String serverUrl;
  final String token;

  const GatewayConfig({required this.serverUrl, required this.token});

  bool get isValid => serverUrl.isNotEmpty;
}

class GatewayProfile {
  final String id;
  final String name;
  final String serverUrl;
  final String token;

  const GatewayProfile({
    required this.id,
    required this.name,
    required this.serverUrl,
    required this.token,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'serverUrl': serverUrl,
        'token': token,
      };

  factory GatewayProfile.fromJson(Map<String, dynamic> map) => GatewayProfile(
        id: map['id']?.toString() ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        name: map['name']?.toString() ?? '未命名节点',
        serverUrl: map['serverUrl']?.toString() ?? '',
        token: map['token']?.toString() ?? '',
      );
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

  // --- 会话置顶 ---
  Future<Set<String>> getPinnedSessionIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList('hermes_pinned_sessions') ?? []).toSet();
  }

  Future<void> togglePinSession(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final current =
        (prefs.getStringList('hermes_pinned_sessions') ?? []).toSet();
    if (current.contains(sessionId)) {
      current.remove(sessionId);
    } else {
      current.add(sessionId);
    }
    await prefs.setStringList('hermes_pinned_sessions', current.toList());
  }

  // --- 会话标签 ---
  Future<Map<String, List<String>>> getAllSessionTags() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('hermes_session_tags');
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(
              k.toString(),
              v is List ? v.map((e) => e.toString()).toList() : <String>[],
            ));
      }
    } catch (_) {}
    return {};
  }

  Future<void> setSessionTags(String sessionId, List<String> tags) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await getAllSessionTags();
    if (tags.isEmpty) {
      all.remove(sessionId);
    } else {
      all[sessionId] = tags;
    }
    await prefs.setString('hermes_session_tags', jsonEncode(all));
  }

  // --- 网关集群多节点配置 ---
  Future<List<GatewayProfile>> getGatewayProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('hermes_gateway_profiles');
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => GatewayProfile.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> saveGatewayProfiles(List<GatewayProfile> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    final list = profiles.map((p) => p.toJson()).toList();
    await prefs.setString('hermes_gateway_profiles', jsonEncode(list));
  }

  // --- 安全锁 PIN ---
  Future<String?> getSecurityPin() async {
    return _secureStorage.read(key: 'hermes_security_pin');
  }

  Future<void> setSecurityPin(String? pin) async {
    if (pin == null || pin.isEmpty) {
      await _secureStorage.delete(key: 'hermes_security_pin');
    } else {
      await _secureStorage.write(key: 'hermes_security_pin', value: pin);
    }
  }

  // --- 桌面级多标签栏会话记录 ---
  Future<List<String>> getOpenTabSessionIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('hermes_open_tab_sessions') ?? [];
  }

  Future<void> saveOpenTabSessionIds(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('hermes_open_tab_sessions', ids);
  }
}

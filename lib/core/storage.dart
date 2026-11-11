import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/project.dart';
import '../models/kanban_task.dart';
import '../models/chat_message.dart';

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

  // --- 项目工程 (Projects) ---
  Future<List<HermesProject>> getProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('hermes_projects_data');
    if (raw == null || raw.isEmpty) {
      return [
        HermesProject(
          id: 'proj_default',
          name: '默认工作区',
          description: '系统默认特工执行与日常运维项目',
          colorValue: 0xFF6366F1,
          createdAt: DateTime.now(),
        ),
      ];
    }
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => HermesProject.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveProjects(List<HermesProject> projects) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(projects.map((p) => p.toJson()).toList());
    await prefs.setString('hermes_projects_data', raw);
  }

  Future<void> saveProject(HermesProject project) async {
    final projects = await getProjects();
    final index = projects.indexWhere((p) => p.id == project.id);
    if (index >= 0) {
      projects[index] = project;
    } else {
      projects.add(project);
    }
    await saveProjects(projects);
  }

  Future<void> deleteProject(String id) async {
    final projects = await getProjects();
    projects.removeWhere((p) => p.id == id);
    await saveProjects(projects);
  }

  // --- 看板任务 (Kanban Tasks) ---
  Future<List<KanbanTask>> getKanbanTasks({String? projectId}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('hermes_kanban_tasks');
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      final tasks = list.map((e) => KanbanTask.fromJson(e as Map<String, dynamic>)).toList();
      if (projectId != null && projectId.isNotEmpty) {
        return tasks.where((t) => t.projectId == projectId).toList();
      }
      return tasks;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveKanbanTasks(List<KanbanTask> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(tasks.map((t) => t.toJson()).toList());
    await prefs.setString('hermes_kanban_tasks', raw);
  }

  Future<void> saveKanbanTask(KanbanTask task) async {
    final tasks = await getKanbanTasks();
    final index = tasks.indexWhere((t) => t.id == task.id);
    if (index >= 0) {
      tasks[index] = task;
    } else {
      tasks.add(task);
    }
    await saveKanbanTasks(tasks);
  }

  Future<void> deleteKanbanTask(String id) async {
    final tasks = await getKanbanTasks();
    tasks.removeWhere((t) => t.id == id);
    await saveKanbanTasks(tasks);
  }

  // --- 跨平台 Webhook (Routines 推送) ---
  Future<Map<String, dynamic>> getWebhookConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('hermes_webhook_config');
    if (raw == null || raw.isEmpty) {
      return {
        'enabled': false,
        'telegramBotToken': '',
        'telegramChatId': '',
        'discordWebhookUrl': '',
        'slackWebhookUrl': '',
        'customWebhookUrl': '',
      };
    }
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> saveWebhookConfig(Map<String, dynamic> config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('hermes_webhook_config', jsonEncode(config));
  }

  // --- Usage & Spend 统计 ---
  Future<Map<String, dynamic>> getUsageStatistics() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('hermes_usage_stats');
    if (raw == null || raw.isEmpty) {
      return {
        'totalPromptTokens': 0,
        'totalCompletionTokens': 0,
        'totalRequests': 0,
        'models': <String, dynamic>{},
      };
    }
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> recordTokenUsage(String model, int promptTokens, int completionTokens) async {
    final prefs = await SharedPreferences.getInstance();
    final stats = await getUsageStatistics();
    stats['totalPromptTokens'] = ((stats['totalPromptTokens'] as num?) ?? 0) + promptTokens;
    stats['totalCompletionTokens'] = ((stats['totalCompletionTokens'] as num?) ?? 0) + completionTokens;
    stats['totalRequests'] = ((stats['totalRequests'] as num?) ?? 0) + 1;

    final models = (stats['models'] as Map<String, dynamic>?) ?? {};
    final modelStats = (models[model] as Map<String, dynamic>?) ?? {
      'promptTokens': 0,
      'completionTokens': 0,
      'requests': 0,
    };
    modelStats['promptTokens'] = ((modelStats['promptTokens'] as num?) ?? 0) + promptTokens;
    modelStats['completionTokens'] = ((modelStats['completionTokens'] as num?) ?? 0) + completionTokens;
    modelStats['requests'] = ((modelStats['requests'] as num?) ?? 0) + 1;
    models[model] = modelStats;
    stats['models'] = models;

    await prefs.setString('hermes_usage_stats', jsonEncode(stats));
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

  // --- 系统设置偏好 ---
  Future<bool> getTabStripEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('hermes_pref_tab_strip') ?? true;
  }

  Future<void> setTabStripEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hermes_pref_tab_strip', enabled);
  }

  Future<bool> getHapticFeedbackEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('hermes_pref_haptic') ?? true;
  }

  Future<void> setHapticFeedbackEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hermes_pref_haptic', enabled);
  }

  Future<bool> getNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('hermes_pref_notifications') ?? true;
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hermes_pref_notifications', enabled);
  }

  Future<bool> getHighRiskApprovalEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('hermes_pref_high_risk_approval') ?? true;
  }

  Future<void> setHighRiskApprovalEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hermes_pref_high_risk_approval', enabled);
  }

  // --- 会话本地秒开缓存 (Stale-While-Revalidate) ---
  Future<List<ChatMessage>> getCachedSessionMessages(String sessionId) async {
    if (sessionId.isEmpty) return [];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('hermes_msg_cache_$sessionId');
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveCachedSessionMessages(
      String sessionId, List<ChatMessage> messages) async {
    if (sessionId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final recent = messages.length > 40
        ? messages.sublist(messages.length - 40)
        : messages;
    await prefs.setString(
      'hermes_msg_cache_$sessionId',
      jsonEncode(recent.map((m) => m.toJson()).toList()),
    );

    // 维护最多 12 个活跃会话缓存索引，自动淘汰过旧缓存
    final keys =
        (prefs.getStringList('hermes_msg_cache_lru') ?? []).toList();
    keys.remove(sessionId);
    keys.add(sessionId);
    while (keys.length > 12) {
      final evicted = keys.removeAt(0);
      await prefs.remove('hermes_msg_cache_$evicted');
    }
    await prefs.setStringList('hermes_msg_cache_lru', keys);
  }

  // --- Hermes 长期记忆库 (MEMORY.md & USER.md) 本地镜像与持久化 ---
  Future<List<Map<String, dynamic>>> getMemoryEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('hermes_memory_entries');
    if (raw == null || raw.isEmpty) {
      return [
        {
          'id': 'mem_default_1',
          'target': 'memory',
          'content': 'Linux 生产环境默认使用 systemd 与 Docker Compose 管理容器服务。',
          'updatedAt': DateTime.now().toIso8601String(),
        },
        {
          'id': 'mem_default_2',
          'target': 'user',
          'content': '偏好简洁直接的中文技术报告，执行高危删除或重启前需先汇报影响面。',
          'updatedAt': DateTime.now().toIso8601String(),
        },
      ];
    }
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveMemoryEntries(List<Map<String, dynamic>> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('hermes_memory_entries', jsonEncode(entries));
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../models/chat_message.dart';
import '../../models/session.dart';
import '../../services/hermes_gateway_service.dart';
import '../sessions/session_drawer.dart';
import 'chat_input_bar.dart';
import 'thinking_bubble.dart';
import 'tool_card.dart';
import 'active_tasks_banner.dart';
import 'context_meter_chip.dart';
import 'session_tab_strip.dart';
import 'workspace_rail_drawer.dart';
import '../settings/system_settings_screen.dart';


class ChatScreen extends StatefulWidget {
  final HermesGatewayService gatewayService;

  const ChatScreen({super.key, required this.gatewayService});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final HermesStorage _storage = HermesStorage();

  HermesSession? _activeSession;
  final List<HermesSession> _openTabs = [];
  bool _tabStripEnabled = true;
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  bool _loadingHistory = false;
  String? _loadHistoryError;
  bool _loadingOlder = false;
  bool _hasOlder = false;
  bool _followLatest = true;

  String _currentModel = '';
  final List<Map<String, dynamic>> _approvals = [];
  final Set<String> _receivedApprovalIds = {};
  final List<InflightTaskInfo> _activeTasks = [];

  final Set<String> _loadedDrafts = {};
  final Map<String, String> _drafts = {};
  final Map<String, List<ChatPickedFile>> _draftAttachments = {};
  final Map<String, Future<void>> _draftWrites = {};

  StreamSubscription? _statusSub;
  StreamSubscription? _streamSub;

  bool get _isCurrentlyStreaming {
    return _messages.isNotEmpty &&
        _messages.last.role == MessageRole.assistant &&
        _messages.last.isStreaming;
  }

  @override
  void initState() {
    super.initState();
    _initConnectionAndSession();
  }

  void _initConnectionAndSession() {
    _statusSub = widget.gatewayService.statusStream.listen((s) {
      if (mounted) setState(() => _connectionStatus = s);
    });

    _streamSub = widget.gatewayService.streamEvents.listen(_handleStreamEvent);

    _loadOrRestoreSession();
    _loadCurrentModel();
    _storage.getTabStripEnabled().then((v) {
      if (mounted) setState(() => _tabStripEnabled = v);
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _streamSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  // ==========================================
  // 模型与节点切换
  // ==========================================
  Future<void> _loadCurrentModel() async {
    try {
      final info = await widget.gatewayService.getModelInfo();
      if (!mounted) return;
      setState(() {
        _currentModel = [
          info['provider']?.toString(),
          info['model']?.toString(),
        ].where((part) => part != null && part.isNotEmpty).join('/');
      });
    } catch (_) {
      // Model info is optional
    }
  }

  Future<void> _showModelPicker() async {
    try {
      final result = await widget.gatewayService.getModelOptions();
      final providers = result['providers'];
      final options = <Map<String, String>>[];
      final providerLabels = <String, String>{};

      if (providers is List) {
        for (final rawProvider in providers.whereType<Map>()) {
          final provider = (rawProvider['slug'] ??
                  rawProvider['id'] ??
                  rawProvider['name'] ??
                  '')
              .toString();
          final providerLabel = (rawProvider['display_name'] ??
                  rawProvider['label'] ??
                  rawProvider['name'] ??
                  provider)
              .toString();
          if (provider.isNotEmpty) providerLabels[provider] = providerLabel;
          final models = rawProvider['models'];
          if (models is! List) continue;
          for (final model in models) {
            final id = model is Map
                ? (model['id'] ?? model['model'] ?? model['name']).toString()
                : model.toString();
            final label = model is Map
                ? (model['name'] ?? model['id'] ?? model['model']).toString()
                : id;
            if (provider.isNotEmpty && id.isNotEmpty) {
              options.add({
                'provider': provider,
                'providerLabel': providerLabel,
                'id': id,
                'label': label,
              });
            }
          }
        }
      }

      if (!mounted) return;
      if (options.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('网关暂未返回可用模型列表')),
        );
        return;
      }

      final searchController = TextEditingController();
      final selected = await showModalBottomSheet<Map<String, String>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: HermesTheme.surfaceElevated,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final query = searchController.text.trim().toLowerCase();
            final groups = <String, List<Map<String, String>>>{};
            for (final opt in options) {
              final matches = query.isEmpty ||
                  [opt['provider'], opt['providerLabel'], opt['id'], opt['label']]
                      .any((v) => v!.toLowerCase().contains(query));
              if (matches) {
                groups.putIfAbsent(opt['provider']!, () => []).add(opt);
              }
            }

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(sheetContext).size.height * 0.78,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 10),
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: HermesTheme.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.auto_awesome_rounded, size: 20, color: HermesTheme.accent),
                          const SizedBox(width: 8),
                          const Text(
                            '切换执行模型',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: HermesTheme.textMain),
                          ),
                          const Spacer(),
                          Text(
                            '${groups.values.fold<int>(0, (sum, m) => sum + m.length)} 个可用',
                            style: const TextStyle(fontSize: 12, color: HermesTheme.textDim),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                      child: TextField(
                        controller: searchController,
                        onChanged: (_) => setSheetState(() {}),
                        decoration: InputDecoration(
                          hintText: '搜索模型名称或厂商 (如 claude, gpt, deepseek)...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 18, color: HermesTheme.textDim),
                          suffixIcon: searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 16),
                                  onPressed: () {
                                    searchController.clear();
                                    setSheetState(() {});
                                  },
                                ),
                          filled: true,
                          fillColor: HermesTheme.surfaceLight,
                        ),
                        style: const TextStyle(fontSize: 13, color: HermesTheme.textMain),
                      ),
                    ),
                    Expanded(
                      child: groups.isEmpty
                          ? const Center(
                              child: Text('无匹配模型', style: TextStyle(color: HermesTheme.textDim)),
                            )
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                              children: groups.entries.map((entry) {
                                final label = providerLabels[entry.key] ?? entry.key;
                                final currentProvider = _currentModel.split('/').first;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: HermesTheme.surface,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: HermesTheme.borderSubtle),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: ExpansionTile(
                                    key: PageStorageKey('provider-${entry.key}'),
                                    initiallyExpanded: query.isNotEmpty || currentProvider == entry.key,
                                    leading: CircleAvatar(
                                      radius: 14,
                                      backgroundColor: HermesTheme.surfaceLight,
                                      child: Text(
                                        label.isNotEmpty ? label[0].toUpperCase() : 'M',
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: HermesTheme.accent),
                                      ),
                                    ),
                                    title: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: HermesTheme.textMain)),
                                    subtitle: Text('${entry.value.length} 个模型 · ${entry.key}', style: const TextStyle(fontSize: 11, color: HermesTheme.textDim)),
                                    children: entry.value.map((opt) {
                                      final isCurrent = '${opt['provider']}/${opt['id']}' == _currentModel;
                                      return ListTile(
                                        dense: true,
                                        contentPadding: const EdgeInsets.only(left: 48, right: 14),
                                        leading: Icon(
                                          isCurrent ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                          size: 16,
                                          color: isCurrent ? HermesTheme.accent : HermesTheme.textDim,
                                        ),
                                        title: Text(
                                          opt['label']!,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                            color: isCurrent ? HermesTheme.accent : HermesTheme.textMain,
                                          ),
                                        ),
                                        subtitle: opt['label'] == opt['id']
                                            ? null
                                            : Text(opt['id']!, style: const TextStyle(fontSize: 11, color: HermesTheme.textDim)),
                                        trailing: isCurrent
                                            ? Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: HermesTheme.accent.withOpacity(0.15),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: const Text('当前使用', style: TextStyle(fontSize: 10, color: HermesTheme.accent)),
                                              )
                                            : null,
                                        onTap: () => Navigator.pop(sheetContext, opt),
                                      );
                                    }).toList(),
                                  ),
                                );
                              }).toList(),
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

      searchController.dispose();
      if (selected == null || !mounted) return;

      await widget.gatewayService.setModel(provider: selected['provider']!, model: selected['id']!);
      await _loadCurrentModel();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已切换执行模型为: ${selected['label']}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('模型切换失败: $e')));
      }
    }
  }

  // ==========================================
  // 会话与草稿管理
  // ==========================================
  Future<void> _loadOrRestoreSession() async {
    try {
      final sessions = await widget.gatewayService.getSessions();
      final savedTabIds = await _storage.getOpenTabSessionIds();

      if (savedTabIds.isNotEmpty && sessions.isNotEmpty) {
        _openTabs.clear();
        for (final id in savedTabIds) {
          for (final s in sessions) {
            if (s.id == id) {
              _openTabs.add(s);
              break;
            }
          }
        }
      }

      if (_openTabs.isEmpty && sessions.isNotEmpty) {
        _openTabs.addAll(sessions.take(4));
      }

      if (sessions.isNotEmpty) {
        final lastId = await _storage.getLastSessionId();
        final match = sessions.firstWhere((s) => s.id == lastId,
            orElse: () => _openTabs.isNotEmpty ? _openTabs.first : sessions.first);
        if (!_openTabs.any((t) => t.id == match.id)) {
          _openTabs.insert(0, match);
        }
        _switchSession(match);
      } else {
        _createNewSession();
      }
    } catch (_) {
      final fallback = HermesSession(id: 'default', title: '主指令会话', updatedAt: DateTime.now());
      _openTabs.clear();
      _openTabs.add(fallback);
      _switchSession(fallback);
    }
  }

  void _switchSession(HermesSession session) {
    setState(() {
      _activeSession = session;
      if (!_openTabs.any((t) => t.id == session.id)) {
        _openTabs.add(session);
      }
      _messages.clear();
      _approvals.clear();
      _loadHistoryError = null;
      _hasOlder = false;
      _followLatest = true;
    });

    _storage.saveLastSessionId(session.id);
    _storage.saveOpenTabSessionIds(_openTabs.map((t) => t.id).toList());
    widget.gatewayService.connectWebSocket(session.id);
    _loadSessionHistory(session.id);

    // 加载会话草稿
    if (!_loadedDrafts.contains(session.id)) {
      _storage.loadDraft(session.id).then((draft) {
        if (mounted && _activeSession?.id == session.id) {
          setState(() {
            _loadedDrafts.add(session.id);
            if (draft != null && draft.isNotEmpty) {
              _drafts[session.id] = draft;
            }
          });
        }
      });
    }
  }

  void _closeTab(HermesSession session) {
    setState(() {
      _openTabs.removeWhere((t) => t.id == session.id);
      if (_activeSession?.id == session.id) {
        if (_openTabs.isNotEmpty) {
          _switchSession(_openTabs.last);
        } else {
          _createNewSession();
        }
      }
      _storage.saveOpenTabSessionIds(_openTabs.map((t) => t.id).toList());
    });
  }

  void _onSessionRenamed(HermesSession renamed) {
    setState(() {
      if (_activeSession?.id == renamed.id) {
        _activeSession = renamed;
      }
      final idx = _openTabs.indexWhere((t) => t.id == renamed.id);
      if (idx != -1) {
        _openTabs[idx] = renamed;
      }
    });
  }

  Future<void> _renameCurrentSession() async {
    final session = _activeSession;
    if (session == null) return;
    final controller = TextEditingController(text: session.title);
    final requestedTitle = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: HermesTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('重命名当前会话',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: HermesTheme.textMain)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          style: const TextStyle(color: HermesTheme.textMain),
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: '会话标题',
            hintText: '输入新标题...',
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: HermesTheme.primary),
            child: const Text('保存修改'),
          ),
        ],
      ),
    );
    controller.dispose();
    final title = requestedTitle?.trim();
    if (title == null || title.isEmpty || title == session.title || !mounted) {
      return;
    }

    try {
      await widget.gatewayService.renameSession(session.id, title);
      final updated = HermesSession(
        id: session.id,
        title: title,
        updatedAt: DateTime.now(),
      );
      if (mounted) {
        setState(() {
          _activeSession = updated;
          final idx = _openTabs.indexWhere((t) => t.id == session.id);
          if (idx != -1) _openTabs[idx] = updated;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('会话已重命名为「$title」'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('重命名失败: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _exportCurrentSession() {
    final session = _activeSession;
    if (session == null || _messages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('当前会话暂无消息可导出'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('# 会话记录: ${session.title}');
    buffer.writeln('导出时间: ${DateTime.now().toString().substring(0, 19)}');
    buffer.writeln('消息总数: ${_messages.length}');
    buffer.writeln('\n---\n');

    for (final msg in _messages) {
      final role = msg.role == MessageRole.user ? '👤 用户' : '🤖 Hermes Agent';
      buffer.writeln('### $role\n');
      if (msg.content.isNotEmpty) {
        buffer.writeln(msg.content);
        buffer.writeln();
      }
      if (msg.toolCalls.isNotEmpty) {
        for (final tc in msg.toolCalls) {
          buffer.writeln('> 🛠️ 工具调用: `${tc.name}`');
          if (tc.arguments.isNotEmpty) {
            buffer.writeln('> 参数: ${tc.arguments}');
          }
          if (tc.result != null && tc.result!.isNotEmpty) {
            buffer.writeln('>\n> 执行结果:');
            buffer.writeln('> ```');
            for (final line in tc.result!.split('\n')) {
              buffer.writeln('> $line');
            }
            buffer.writeln('> ```');
          }
          buffer.writeln();
        }
      }
      buffer.writeln('---\n');
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已将完整对话记录复制为 Markdown 格式'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _clearCurrentMessages() async {
    if (_messages.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HermesTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('清空当前对话',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: HermesTheme.textMain)),
        content: const Text(
            '确定清空当前对话中的所有消息吗？\n（此操作只清理当前展示界面，不会删除服务端会话记录）',
            style: TextStyle(fontSize: 13, color: HermesTheme.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: HermesTheme.danger),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        _messages.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('当前对话消息已清空'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _createNewSession() async {
    try {
      final newSession = await widget.gatewayService.createSession(title: '新任务指令');
      _switchSession(newSession);
    } catch (e) {
      final fallback = HermesSession(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: '新任务指令',
        updatedAt: DateTime.now(),
      );
      _switchSession(fallback);
    }
  }

  // ==========================================
  // 历史消息与翻页
  // ==========================================
  Future<void> _loadSessionHistory(String sessionId) async {
    setState(() {
      _loadingHistory = true;
      _loadHistoryError = null;
    });

    _loadPendingApprovals();

    try {
      final rawMessages = await widget.gatewayService.getSessionMessages(sessionId);
      if (!mounted || _activeSession?.id != sessionId) return;

      final List<ChatMessage> parsedList = [];
      for (final m in rawMessages) {
        final msg = ChatMessage.fromRawMap(m);

        if (msg.role == MessageRole.system && msg.content.trim().isEmpty) {
          continue;
        }

        if (m['role'] == 'tool' && parsedList.isNotEmpty && parsedList.last.role == MessageRole.assistant) {
          final toolCallId = m['tool_call_id']?.toString();
          final lastMsg = parsedList.last;
          if (toolCallId != null && toolCallId.isNotEmpty) {
            final idx = lastMsg.toolCalls.indexWhere((t) => t.id == toolCallId);
            if (idx != -1) {
              lastMsg.toolCalls[idx] = lastMsg.toolCalls[idx].copyWith(
                result: m['content']?.toString() ?? '',
                isRunning: false,
              );
              continue;
            }
          }
        }

        parsedList.add(msg);
      }

      setState(() {
        _messages.clear();
        _messages.addAll(parsedList);
        _loadingHistory = false;
        _hasOlder = rawMessages.length >= 100;
      });

      _scrollToBottom(force: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingHistory = false;
          _loadHistoryError = "获取历史失败: $e";
        });
      }
    }
  }

  Future<void> _loadOlder() async {
    final session = _activeSession;
    if (session == null || _loadingOlder || !_hasOlder || _messages.isEmpty) return;

    setState(() => _loadingOlder = true);
    try {
      final rawMessages = await widget.gatewayService.getSessionMessages(
        session.id,
        offset: _messages.length,
      );

      if (!mounted || _activeSession?.id != session.id) return;

      final List<ChatMessage> older = [];
      for (final m in rawMessages) {
        final msg = ChatMessage.fromRawMap(m);
        if (msg.role == MessageRole.system && msg.content.trim().isEmpty) continue;
        older.add(msg);
      }

      setState(() {
        _messages.insertAll(0, older);
        _hasOlder = rawMessages.length >= 100;
        _loadingOlder = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  // ==========================================
  void _notifyTaskCompleted() {
    try {
      const MethodChannel('com.hermes.mobile/files')
          .invokeMethod<void>('vibrate', {'durationMs': 80});
    } catch (_) {}
  }

  void _notifyApprovalRequired(String command) {
    try {
      const MethodChannel('com.hermes.mobile/files')
          .invokeMethod<void>('vibrate', {'durationMs': 200});
      const MethodChannel('com.hermes.mobile/files').invokeMethod<void>('showNotification', {
        'title': 'Hermes 正在请求特权执行确认',
        'content': command,
        'id': 2001,
      });
    } catch (_) {}
  }

  // 特工指令流式与权限审批
  // ==========================================
  Future<void> _loadPendingApprovals() async {
    final id = _activeSession?.id;
    if (id == null || !widget.gatewayService.supportsJsonRpc) return;
    try {
      final items = await widget.gatewayService.getPendingApprovals(id);
      if (mounted && _activeSession?.id == id) {
        setState(() {
          _approvals.clear();
          _approvals.addAll(items);
        });
        for (final item in items) {
          final requestId = item['request_id']?.toString() ?? '';
          if (requestId.isNotEmpty && _receivedApprovalIds.add(requestId)) {
            widget.gatewayService.callRpc('approval.received', {
              'session_id': id,
              'request_id': requestId,
            }).catchError((_) {});
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _respondApproval(Map<String, dynamic> approval, String choice) async {
    final sessionId = _activeSession?.id;
    if (sessionId == null) return;
    try {
      await widget.gatewayService.respondApproval(
        sessionId,
        approval['request_id']?.toString() ?? '',
        choice,
      );
      if (mounted) {
        setState(() => _approvals.remove(approval));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('审批提交失败: $e')));
      }
    }
  }

  void _handleStreamEvent(Map<String, dynamic> event) {
    final type = event['type']?.toString();
    if (!mounted) return;

    // 1. 处理恢复快照 (后台任务运行感知)
    if (type == 'resume_snapshot') {
      final inflight = event['inflight'];
      if (inflight is Map) {
        final taskName = (inflight['name'] ?? inflight['tool'] ?? inflight['task'] ?? '后台运行任务').toString();
        final detail = (inflight['command'] ?? inflight['prompt'] ?? inflight['detail'] ?? '').toString();
        final lower = taskName.toLowerCase() + detail.toLowerCase();
        ToolCategory cat = ToolCategory.system;
        if (lower.contains('subagent') || lower.contains('delegate')) {
          cat = ToolCategory.subagent;
        } else if (lower.contains('cron') || lower.contains('schedule')) {
          cat = ToolCategory.cron;
        } else if (lower.contains('nohup') || lower.contains('&') || lower.contains('daemon')) {
          cat = ToolCategory.daemon;
        }

        setState(() {
          _activeTasks.clear();
          _activeTasks.add(InflightTaskInfo(
            id: inflight['task_id']?.toString() ?? 'resumed_task',
            name: taskName,
            category: cat,
            detail: detail,
          ));

          // 若历史记录未挂起流式占位，新增占位以便增量流式呈现
          if (_messages.isEmpty || !_messages.last.isStreaming) {
            _messages.add(ChatMessage.assistant(isStreaming: true));
          }
        });
      }
      return;
    }

    // 2. 处理安全审批流式通知与震动提示
    if (type == 'approval.requested') {
      _loadPendingApprovals();
      final cmd = (event['command'] ?? event['description'] ?? 'Hermes 特权命令').toString();
      _notifyApprovalRequired(cmd);
      return;
    } else if (type == 'approval.resolved') {
      final reqId = event['request_id']?.toString();
      if (reqId != null) {
        setState(() => _approvals.removeWhere((a) => a['request_id']?.toString() == reqId));
      }
      return;
    }

    // 3. 处理子智能体独立流式事件
    if (type != null && type.startsWith('subagent.')) {
      final agentName = (event['agent'] ?? event['name'] ?? '子智能体').toString();
      final content = (event['content'] ?? event['text'] ?? '').toString();
      if (type == 'subagent.start') {
        setState(() {
          _activeTasks.removeWhere((t) => t.id == 'subagent_$agentName');
          _activeTasks.add(InflightTaskInfo(
            id: 'subagent_$agentName',
            name: agentName,
            category: ToolCategory.subagent,
            detail: content,
          ));
        });
      } else if (type == 'subagent.complete') {
        setState(() {
          _activeTasks.removeWhere((t) => t.id == 'subagent_$agentName');
        });
      }
      return;
    }

    // 4. 处理定时任务触发事件
    if (type != null && (type.startsWith('cron.') || type.startsWith('job.'))) {
      final jobName = (event['name'] ?? event['job_id'] ?? '定时任务').toString();
      final detail = (event['prompt'] ?? event['schedule'] ?? '').toString();
      if (type.contains('trigger') || type.contains('start')) {
        setState(() {
          _activeTasks.removeWhere((t) => t.id == 'cron_$jobName');
          _activeTasks.add(InflightTaskInfo(
            id: 'cron_$jobName',
            name: jobName,
            category: ToolCategory.cron,
            detail: detail,
          ));
        });
      } else if (type.contains('complete') || type.contains('finish')) {
        setState(() {
          _activeTasks.removeWhere((t) => t.id == 'cron_$jobName');
        });
      }
      return;
    }

    setState(() {
      ChatMessage? currentAssistant;
      if (_messages.isNotEmpty && _messages.last.role == MessageRole.assistant && _messages.last.isStreaming) {
        currentAssistant = _messages.last;
      }

      if (type == 'thought' || type == 'thinking') {
        final text = event['content']?.toString() ?? '';
        currentAssistant?.thinking += text;
      } else if (type == 'content' || type == 'chunk') {
        final text = event['content']?.toString() ?? '';
        currentAssistant?.content += text;
      } else if (type == 'tool_start') {
        final toolName = event['tool_name']?.toString() ?? '系统工具';
        final toolId = event['tool_id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
        final args = event['arguments']?.toString() ?? '';
        final toolInfo = ToolCallInfo(
          id: toolId,
          name: toolName,
          arguments: args,
          isRunning: true,
        );
        currentAssistant?.toolCalls.add(toolInfo);

        if (toolInfo.category == ToolCategory.daemon ||
            toolInfo.category == ToolCategory.subagent ||
            toolInfo.category == ToolCategory.cron ||
            args.contains('&')) {
          _activeTasks.removeWhere((t) => t.id == toolId);
          _activeTasks.add(InflightTaskInfo(
            id: toolId,
            name: toolName,
            category: toolInfo.category,
            detail: toolInfo.arguments,
          ));
        }
      } else if (type == 'tool_end') {
        final toolId = event['tool_id']?.toString();
        final result = event['result']?.toString() ?? '';
        final idx = currentAssistant?.toolCalls.indexWhere((t) => t.id == toolId) ?? -1;
        if (idx != -1 && currentAssistant != null) {
          currentAssistant.toolCalls[idx] = currentAssistant.toolCalls[idx].copyWith(
            result: result,
            isRunning: false,
          );
        }
        _activeTasks.removeWhere((t) => t.id == toolId);
      } else if (type == 'done' || type == 'message_end') {
        currentAssistant?.isStreaming = false;
        _activeTasks.clear();
        _notifyTaskCompleted();
      }
    });

    _scrollToBottom();
  }

  // ==========================================
  // 发送指令、附件上传与终止
  // ==========================================
  Future<List<String>> _uploadAttachments(String sessionId, List<ChatPickedFile> files) async {
    final refs = <String>[];
    for (final file in files) {
      final bytes = file.bytes;
      if (bytes.length > 15 * 1024 * 1024) {
        throw StateError('${file.name} 超过 15 MB 上传限制');
      }
      final encoded = base64Encode(bytes);
      final ext = file.extension;

      if (ext == 'pdf') {
        final result = await widget.gatewayService.attachPdf(
          sessionId: sessionId,
          name: file.name,
          base64: encoded,
        );
        if (result is Map && result['ref_text'] != null) {
          refs.add(result['ref_text'].toString());
        }
      } else if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'heic'].contains(ext)) {
        final result = await widget.gatewayService.attachImage(
          sessionId: sessionId,
          name: file.name,
          base64: encoded,
        );
        if (result is Map && result['ref_text'] != null) {
          refs.add(result['ref_text'].toString());
        }
      } else {
        final mime = ext == 'txt' ? 'text/plain' : 'application/octet-stream';
        final result = await widget.gatewayService.attachFile(
          sessionId: sessionId,
          name: file.name,
          dataUrl: 'data:$mime;base64,$encoded',
        );
        if (result is Map && result['ref_text'] != null) {
          refs.add(result['ref_text'].toString());
        }
      }
    }
    return refs;
  }

  Future<bool> _sendMessageWithAttachments(String text, List<ChatPickedFile> attachments) async {
    final session = _activeSession;
    if (session == null) return false;

    List<String> refs = [];
    if (attachments.isNotEmpty) {
      try {
        refs = await _uploadAttachments(session.id, attachments);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('附件上传失败: $e')));
        }
        return false;
      }
    }

    if (!mounted || _activeSession?.id != session.id) return false;

    final names = attachments.map((f) => f.name).toList();
    final visibleText = text.trim().isEmpty && names.isNotEmpty ? '请查看并分析这些附件。' : text;
    final outgoingText = [
      visibleText,
      if (names.isNotEmpty) '附件: ${names.join('、')}',
      ...refs,
    ].where((part) => part.trim().isNotEmpty).join('\n\n');

    final alreadyRunning = _messages.any((m) => m.isStreaming);
    final placeholder = alreadyRunning ? null : ChatMessage.assistant(isStreaming: true);

    setState(() {
      _messages.add(ChatMessage.user(visibleText, attachments: names));
      if (placeholder != null) _messages.add(placeholder);
    });

    try {
      await widget.gatewayService.sendMessage(sessionId: session.id, text: outgoingText);
    } catch (e) {
      if (!mounted || _activeSession?.id != session.id) return false;
      setState(() {
        if (placeholder != null) {
          placeholder.content = '下发指令失败: $e';
          placeholder.isStreaming = false;
        } else {
          _messages.add(ChatMessage.assistant(isStreaming: false)..content = '下发指令失败: $e');
        }
      });
      return false;
    }

    _scrollToBottom(force: true);
    return true;
  }

  Future<void> _stopGeneration() async {
    final sessionId = _activeSession?.id;
    if (sessionId == null) return;
    try {
      await widget.gatewayService.interruptSession(sessionId);
      if (mounted) {
        setState(() {
          for (final msg in _messages.where((m) => m.isStreaming)) {
            msg.isStreaming = false;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('终止任务失败: $e')));
      }
    }
  }

  Future<void> _regenerateLastReply() async {
    if (_messages.isEmpty || _isCurrentlyStreaming) return;
    final lastAssistantIdx = _messages.lastIndexWhere((m) => m.role == MessageRole.assistant);
    if (lastAssistantIdx == -1) return;

    final lastUserIdx = _messages.lastIndexWhere((m) => m.role == MessageRole.user, lastAssistantIdx);
    if (lastUserIdx == -1) return;

    final lastUserMsg = _messages[lastUserIdx];
    setState(() {
      _messages.removeRange(lastAssistantIdx, _messages.length);
    });

    await _sendMessageWithAttachments(lastUserMsg.content, const []);
  }

  void _scrollToBottom({bool force = false}) {
    if (!force && !_followLatest) return;
    if (force && !_followLatest) setState(() => _followLatest = true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _copyToClipboard(String text, String tip) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tip),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ==========================================
  // UI 构件
  // ==========================================
  Widget _buildTelemetryBadge() {
    Color dotColor;
    String statusText;

    switch (_connectionStatus) {
      case ConnectionStatus.connected:
        dotColor = HermesTheme.accent;
        statusText = "Hermes · 连通在线";
        break;
      case ConnectionStatus.connecting:
      case ConnectionStatus.reconnecting:
        dotColor = HermesTheme.warning;
        statusText = "网关重连中...";
        break;
      case ConnectionStatus.disconnected:
      case ConnectionStatus.error:
      default:
        dotColor = HermesTheme.danger;
        statusText = "网关未就绪";
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: HermesTheme.surfaceLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: HermesTheme.borderSubtle, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
              boxShadow: [
                BoxShadow(color: dotColor.withOpacity(0.5), blurRadius: 4, spreadRadius: 0.5),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Text(
            statusText,
            style: const TextStyle(fontSize: 10, color: HermesTheme.textMuted, letterSpacing: 0.2),
          ),
        ],
      ),
    );
  }

  Widget _buildApprovalCard(Map<String, dynamic> approval) {
    final requestId = approval['request_id']?.toString() ?? '';
    final command = approval['command']?.toString() ??
        approval['description']?.toString() ??
        'Hermes 正在请求执行高权限操作';
    final choices = approval['choices'] is List
        ? List<String>.from(approval['choices'])
        : const ['once', 'deny'];

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: HermesTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HermesTheme.warning.withOpacity(0.5), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: HermesTheme.warning.withOpacity(0.08),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shield_outlined, color: HermesTheme.warning, size: 18),
              SizedBox(width: 8),
              Text(
                '特工操作权限授权确认',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: HermesTheme.textMain),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: HermesTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: HermesTheme.borderSubtle),
            ),
            child: SelectableText(
              command,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: HermesTheme.textMain,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (choices.contains('once'))
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    backgroundColor: HermesTheme.accent.withOpacity(0.15),
                    foregroundColor: HermesTheme.accent,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _respondApproval(approval, 'once'),
                  child: const Text('仅本次允许', style: TextStyle(fontSize: 12)),
                ),
              if (choices.contains('session'))
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    backgroundColor: HermesTheme.primary.withOpacity(0.2),
                    foregroundColor: HermesTheme.primaryLight,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _respondApproval(approval, 'session'),
                  child: const Text('本会话允许', style: TextStyle(fontSize: 12)),
                ),
              if (choices.contains('always') && approval['allow_permanent'] == true)
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _respondApproval(approval, 'always'),
                  child: const Text('始终允许', style: TextStyle(fontSize: 12)),
                ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: HermesTheme.danger,
                  side: const BorderSide(color: HermesTheme.danger, width: 0.8),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _respondApproval(approval, 'deny'),
                child: const Text('拒绝执行', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          if (requestId.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '请求 ID: ${requestId.length > 12 ? requestId.substring(0, 12) : requestId}',
                style: const TextStyle(color: HermesTheme.textDim, fontSize: 10),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HermesTheme.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _activeSession?.title ?? "Hermes Agent",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: HermesTheme.textMain),
            ),
            const SizedBox(height: 2),
            _buildTelemetryBadge(),
          ],
        ),
        actions: [
          // 上下文容量透视芯片
          ContextMeterChip(
            gateway: widget.gatewayService,
            sessionId: _activeSession?.id ?? '',
            onSendCompactionPrompt: (p) => _sendMessageWithAttachments(p, const []),
          ),
          const SizedBox(width: 4),

          // 模型快速切换 Pill
          TextButton.icon(
            onPressed: _showModelPicker,
            icon: const Icon(Icons.auto_awesome_rounded, size: 15, color: HermesTheme.accent),
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 82),
              child: Text(
                _currentModel.isEmpty ? '模型' : _currentModel.split('/').last,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: HermesTheme.textMain),
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              backgroundColor: HermesTheme.surfaceLight,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
          const SizedBox(width: 4),

          // 桌面级工作区控制台 (Workspace Rails) 快捷抽屉
          Builder(
            builder: (drawerCtx) => IconButton(
              icon: const Icon(Icons.developer_board_rounded, size: 20, color: HermesTheme.accent),
              tooltip: "工作区控制台 (终端/文件/工件)",
              onPressed: () => Scaffold.of(drawerCtx).openEndDrawer(),
            ),
          ),
          const SizedBox(width: 2),

          // 新建会话按钮
          IconButton(
            icon: const Icon(Icons.edit_square, size: 19, color: HermesTheme.textMain),
            tooltip: "新建对话",
            onPressed: _createNewSession,
          ),

          // 当前会话与系统控制菜单
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, size: 20, color: HermesTheme.textMain),
            color: HermesTheme.surfaceElevated,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (val) {
              if (val == 'rename') {
                _renameCurrentSession();
              } else if (val == 'export') {
                _exportCurrentSession();
              } else if (val == 'clear') {
                _clearCurrentMessages();
              } else if (val == 'system_settings') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SystemSettingsScreen(
                      gatewayService: widget.gatewayService,
                      onConfigChanged: () {
                        _loadOrRestoreSession();
                        _loadCurrentModel();
                        _storage.getTabStripEnabled().then((v) {
                          if (mounted) setState(() => _tabStripEnabled = v);
                        });
                      },
                    ),
                  ),
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'rename',
                height: 38,
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 16, color: HermesTheme.accent),
                    SizedBox(width: 10),
                    Text('重命名当前会话', style: TextStyle(fontSize: 13, color: HermesTheme.textMain)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'export',
                height: 38,
                child: Row(
                  children: [
                    Icon(Icons.file_download_outlined, size: 16, color: HermesTheme.primaryLight),
                    SizedBox(width: 10),
                    Text('导出对话 (Markdown)', style: TextStyle(fontSize: 13, color: HermesTheme.textMain)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'clear',
                height: 38,
                child: Row(
                  children: [
                    Icon(Icons.cleaning_services_outlined, size: 16, color: HermesTheme.warning),
                    SizedBox(width: 10),
                    Text('清空当前对话消息', style: TextStyle(fontSize: 13, color: HermesTheme.textMain)),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                enabled: false,
                height: 1,
                child: Divider(color: HermesTheme.borderSubtle, height: 1),
              ),
              PopupMenuItem(
                value: 'system_settings',
                height: 38,
                child: Row(
                  children: [
                    Icon(Icons.settings_rounded, size: 16, color: HermesTheme.textMuted),
                    SizedBox(width: 10),
                    Text('系统设置与控制中枢',
                        style: TextStyle(
                            fontSize: 13,
                            color: HermesTheme.textMain)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
        bottom: _tabStripEnabled
            ? PreferredSize(
                preferredSize: const Size.fromHeight(38),
                child: SessionTabStrip(
                  tabs: _openTabs,
                  activeSessionId: _activeSession?.id ?? '',
                  onSelectTab: _switchSession,
                  onCloseTab: _closeTab,
                  onNewTab: _createNewSession,
                ),
              )
            : null,
      ),
      drawer: SessionDrawer(
        gatewayService: widget.gatewayService,
        activeSessionId: _activeSession?.id,
        onSelectSession: _switchSession,
        onSessionRenamed: _onSessionRenamed,
        onNewSession: _createNewSession,
      ),
      endDrawer: _activeSession == null
          ? null
          : WorkspaceRailDrawer(
              gateway: widget.gatewayService,
              sessionId: _activeSession!.id,
              messages: _messages,
              onSendCommand: (cmd) => _sendMessageWithAttachments(cmd, const []),
            ),
      body: Stack(
        children: [
          // 消息流列表
          Positioned.fill(
            child: _loadingHistory
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(strokeWidth: 2, color: HermesTheme.primary),
                        SizedBox(height: 14),
                        Text(
                          "正在同步云端指令记录...",
                          style: TextStyle(color: HermesTheme.textMuted, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : _loadHistoryError != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.wifi_off_rounded, size: 38, color: HermesTheme.danger),
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Text(
                                _loadHistoryError!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: HermesTheme.textMuted, fontSize: 13),
                              ),
                            ),
                            const SizedBox(height: 14),
                            OutlinedButton.icon(
                              onPressed: _activeSession != null ? () => _loadSessionHistory(_activeSession!.id) : null,
                              icon: const Icon(Icons.refresh_rounded, size: 14),
                              label: const Text("重新尝试同步", style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                      )
                    : _messages.isEmpty && !_hasOlder
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: HermesTheme.surfaceLight,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: HermesTheme.border),
                                  ),
                                  child: const Icon(Icons.code_rounded, size: 32, color: HermesTheme.primary),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  "Hermes Agent 已就绪",
                                  style: TextStyle(color: HermesTheme.textMain, fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  "输入指令下发任务，或点击快捷运维芯片",
                                  style: TextStyle(color: HermesTheme.textDim, fontSize: 13),
                                ),
                              ],
                            ),
                          )
                        : NotificationListener<UserScrollNotification>(
                            onNotification: (notification) {
                              final follow = notification.metrics.extentAfter < 120;
                              if (follow != _followLatest) {
                                setState(() => _followLatest = follow);
                              }
                              return false;
                            },
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.only(
                                left: 14,
                                right: 14,
                                top: 12,
                                bottom: 150, // 避让输入栏和快捷芯片
                              ),
                              itemCount: _messages.length + (_hasOlder ? 1 : 0),
                              itemBuilder: (context, index) {
                                // 历史翻页头部
                                if (_hasOlder && index == 0) {
                                  return Center(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      child: TextButton.icon(
                                        onPressed: _loadingOlder ? null : _loadOlder,
                                        icon: _loadingOlder
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child: CircularProgressIndicator(strokeWidth: 1.8, color: HermesTheme.primary),
                                              )
                                            : const Icon(Icons.history_rounded, size: 16),
                                        label: Text(
                                          _loadingOlder ? '正在加载更早记录...' : '加载更早的指令记录',
                                          style: const TextStyle(fontSize: 12, color: HermesTheme.textMuted),
                                        ),
                                      ),
                                    ),
                                  );
                                }

                                final msg = _messages[index - (_hasOlder ? 1 : 0)];
                                final isUser = msg.role == MessageRole.user;

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 18),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                                    children: [
                                      // Assistant 头像
                                      if (!isUser) ...[
                                        Container(
                                          width: 30,
                                          height: 30,
                                          margin: const EdgeInsets.only(right: 10, top: 2),
                                          decoration: BoxDecoration(
                                            gradient: HermesTheme.assistantBubbleGradient,
                                            borderRadius: BorderRadius.circular(9),
                                            border: Border.all(color: HermesTheme.borderSubtle),
                                          ),
                                          child: const Icon(Icons.smart_toy_rounded, size: 17, color: HermesTheme.primaryLight),
                                        ),
                                      ],

                                      // 气泡主体
                                      Flexible(
                                        child: Column(
                                          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                          children: [
                                            // 思考过程抽屉
                                            if (!isUser && msg.thinking.isNotEmpty) ...[
                                              ThinkingBubble(
                                                thinking: msg.thinking,
                                                isStreaming: msg.isStreaming,
                                              ),
                                              const SizedBox(height: 8),
                                            ],

                                            // 工具调用卡片
                                            if (!isUser && msg.toolCalls.isNotEmpty) ...[
                                              for (final tool in msg.toolCalls) ...[
                                                ToolCard(toolCall: tool),
                                                const SizedBox(height: 8),
                                              ],
                                            ],

                                            // 气泡卡片
                                            if (msg.content.isNotEmpty || msg.attachments.isNotEmpty || (msg.isStreaming && !isUser))
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                                decoration: BoxDecoration(
                                                  gradient: isUser ? HermesTheme.userBubbleGradient : null,
                                                  color: isUser ? null : HermesTheme.surfaceElevated,
                                                  borderRadius: BorderRadius.only(
                                                    topLeft: const Radius.circular(14),
                                                    topRight: const Radius.circular(14),
                                                    bottomLeft: Radius.circular(isUser ? 14 : 3),
                                                    bottomRight: Radius.circular(isUser ? 3 : 14),
                                                  ),
                                                  border: isUser
                                                      ? null
                                                      : Border.all(color: HermesTheme.borderSubtle, width: 0.8),
                                                  boxShadow: isUser
                                                      ? const [HermesTheme.primaryGlow]
                                                      : const [HermesTheme.elevation1],
                                                ),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    // 用户上传的附件胶囊
                                                    if (isUser && msg.attachments.isNotEmpty)
                                                      Padding(
                                                        padding: const EdgeInsets.only(bottom: 8),
                                                        child: Wrap(
                                                          spacing: 6,
                                                          runSpacing: 6,
                                                          children: msg.attachments.map((name) {
                                                            return Container(
                                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                              decoration: BoxDecoration(
                                                                color: Colors.white.withOpacity(0.15),
                                                                borderRadius: BorderRadius.circular(8),
                                                              ),
                                                              child: Row(
                                                                mainAxisSize: MainAxisSize.min,
                                                                children: [
                                                                  const Icon(Icons.attach_file_rounded, size: 13, color: Colors.white),
                                                                  const SizedBox(width: 4),
                                                                  ConstrainedBox(
                                                                    constraints: const BoxConstraints(maxWidth: 160),
                                                                    child: Text(
                                                                      name,
                                                                      style: const TextStyle(fontSize: 11.5, color: Colors.white),
                                                                      overflow: TextOverflow.ellipsis,
                                                                    ),
                                                                  ),
                                                                ],
                                                             ),
                                                            );
                                                          }).toList(),
                                                        ),
                                                      ),

                                                    // 正文内容
                                                    if (isUser)
                                                      SelectableText(
                                                        msg.content,
                                                        style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.45),
                                                      )
                                                    else
                                                      MarkdownBody(
                                                        data: msg.content.isEmpty && msg.isStreaming ? "▌" : msg.content,
                                                        selectable: true,
                                                        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                                                          p: const TextStyle(fontSize: 14, color: HermesTheme.textMain, height: 1.55),
                                                          code: const TextStyle(
                                                            fontFamily: 'monospace',
                                                            backgroundColor: HermesTheme.surfaceLight,
                                                            fontSize: 12.5,
                                                            color: HermesTheme.accent,
                                                          ),
                                                          codeblockDecoration: BoxDecoration(
                                                            color: HermesTheme.surface,
                                                            borderRadius: BorderRadius.circular(8),
                                                            border: Border.all(color: HermesTheme.borderSubtle),
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),

                                            // 消息下方操作按钮栏 (复制/分享/重试)
                                            if (!msg.isStreaming)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 4),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(Icons.copy_rounded, size: 14, color: HermesTheme.textDim),
                                                      tooltip: isUser ? "复制指令" : "复制回答",
                                                      visualDensity: VisualDensity.compact,
                                                      onPressed: () => _copyToClipboard(
                                                        msg.content,
                                                        isUser ? "已复制指令内容" : "已复制回答内容",
                                                      ),
                                                    ),
                                                    if (!isUser) ...[
                                                      IconButton(
                                                        icon: const Icon(Icons.share_outlined, size: 14, color: HermesTheme.textDim),
                                                        tooltip: "系统分享",
                                                        visualDensity: VisualDensity.compact,
                                                        onPressed: () async {
                                                          try {
                                                            await const MethodChannel('com.hermes.mobile/files')
                                                                .invokeMethod<void>('shareText', {'text': msg.content});
                                                          } catch (_) {
                                                            _copyToClipboard(msg.content, "已复制内容至剪贴板");
                                                          }
                                                        },
                                                      ),
                                                      if (index == _messages.length - 1 + (_hasOlder ? 1 : 0))
                                                        IconButton(
                                                          icon: const Icon(Icons.refresh_rounded, size: 15, color: HermesTheme.textDim),
                                                          tooltip: "重新生成回答",
                                                          visualDensity: VisualDensity.compact,
                                                          onPressed: _regenerateLastReply,
                                                        ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),

                                      // User 头像
                                      if (isUser) ...[
                                        Container(
                                          width: 30,
                                          height: 30,
                                          margin: const EdgeInsets.only(left: 10, top: 2),
                                          decoration: BoxDecoration(
                                            color: HermesTheme.surfaceLight,
                                            borderRadius: BorderRadius.circular(9),
                                            border: Border.all(color: HermesTheme.borderSubtle),
                                          ),
                                          child: const Icon(Icons.person_rounded, size: 18, color: HermesTheme.textMuted),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
          ),

          // 当前窗口后台任务 / 子智能体 / 定时任务活动监视条
          if (_activeTasks.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              top: _approvals.isNotEmpty ? 130 : 0,
              child: SafeArea(
                child: ActiveTasksBanner(
                  tasks: _activeTasks,
                  onStopAll: _stopGeneration,
                ),
              ),
            ),

          // 待审批操作浮层 (若有审批请求则置顶展示)
          if (_approvals.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: SafeArea(
                child: Column(
                  children: _approvals.map((app) => _buildApprovalCard(app)).toList(),
                ),
              ),
            ),

          // 悬浮：返回最新消息 FAB
          if (!_followLatest)
            Positioned(
              right: 16,
              bottom: 140,
              child: FloatingActionButton.small(
                backgroundColor: HermesTheme.surfaceElevated,
                foregroundColor: HermesTheme.accent,
                tooltip: "返回最新消息",
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: HermesTheme.borderSubtle),
                ),
                onPressed: () => _scrollToBottom(force: true),
                child: const Icon(Icons.arrow_downward_rounded, size: 18),
              ),
            ),

          // 底部输入控制台
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ChatInputBar(
              key: ValueKey('chat-input-${_activeSession?.id ?? 'none'}-${_loadedDrafts.contains(_activeSession?.id)}'),
              isConnected: _connectionStatus == ConnectionStatus.connected,
              draftReady: _loadedDrafts.contains(_activeSession?.id),
              draftText: _drafts[_activeSession?.id] ?? '',
              draftAttachments: _draftAttachments[_activeSession?.id] ?? const [],
              onDraftTextChanged: (val) {
                final id = _activeSession?.id;
                if (id != null) {
                  _drafts[id] = val;
                  final prev = _draftWrites[id] ?? Future<void>.value();
                  _draftWrites[id] = prev.catchError((_) {}).then((_) => _storage.saveDraft(id, val)).catchError((_) {});
                }
              },
              onDraftAttachmentsChanged: (files) {
                final id = _activeSession?.id;
                if (id != null) {
                  _draftAttachments[id] = files;
                }
              },
              onSend: _sendMessageWithAttachments,
              isStreaming: _isCurrentlyStreaming,
              onStop: _stopGeneration,
            ),
          ),
        ],
      ),
    );
  }
}

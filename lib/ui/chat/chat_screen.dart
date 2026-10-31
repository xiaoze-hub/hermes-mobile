import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:dio/dio.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../models/chat_message.dart';
import '../../models/session.dart';
import '../../services/hermes_gateway_service.dart';
import '../sessions/session_drawer.dart';
import '../settings/gateway_settings_dialog.dart';
import '../settings/gateway_management_screen.dart';
import 'chat_input_bar.dart';
import 'thinking_bubble.dart';
import 'tool_card.dart';
import '../settings/agent_workspace_screen.dart';
import '../settings/app_update_screen.dart';

class ChatScreen extends StatefulWidget {
  final HermesGatewayService gatewayService;

  const ChatScreen({super.key, required this.gatewayService});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  final List<HermesSession> _sessions = [];
  final Map<String, String> _drafts = {};
  final Map<String, List<ChatPickedFile>> _draftAttachments = {};
  final ScrollController _scrollController = ScrollController();
  final HermesStorage _storage = HermesStorage();

  HermesSession? _activeSession;
  bool _loadingHistory = false;
  String? _historyError;
  int _historyRequest = 0;
  int _historyOffset = 0;
  bool _hasOlder = false;
  bool _loadingOlder = false;
  final List<Map<String, dynamic>> _pendingEvents = [];
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  String _currentModel = '';
  final List<Map<String, dynamic>> _approvals = [];
  final Set<String> _receivedApprovalIds = {};

  StreamSubscription? _statusSub;
  StreamSubscription? _streamSub;

  @override
  void initState() {
    super.initState();
    _initConnectionAndSession();
  }

  void _initConnectionAndSession() {
    _statusSub = widget.gatewayService.statusStream.listen((s) {
      if (mounted) {
        setState(() => _connectionStatus = s);
        if (s == ConnectionStatus.connected && _activeSession != null) {
          _loadPendingApprovals();
        }
      }
    });

    _streamSub = widget.gatewayService.streamEvents.listen(_handleStreamEvent);

    _loadCurrentModel();

    _loadOrRestoreSession();
  }

  Future<void> _loadPendingApprovals() async {
    final id = _activeSession?.id;
    if (id == null || !widget.gatewayService.supportsJsonRpc) return;
    try {
      final items = await widget.gatewayService.getPendingApprovals(id);
      if (mounted && _activeSession?.id == id) {
        setState(() => _approvals
          ..clear()
          ..addAll(items));
        for (final item in items) {
          final requestId = item['request_id']?.toString() ?? '';
          if (requestId.isNotEmpty && _receivedApprovalIds.add(requestId)) {
            widget.gatewayService.callRpc('approval.received',
                {'session_id': id, 'request_id': requestId}).catchError((_) {});
          }
        }
      }
    } catch (_) {
      // Approval controls are optional on older gateway builds.
    }
  }

  Future<void> _respondApproval(
      Map<String, dynamic> approval, String choice) async {
    try {
      await widget.gatewayService.respondApproval(
          _activeSession!.id, approval['request_id']?.toString() ?? '', choice);
      if (mounted) setState(() => _approvals.remove(approval));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('审批未能提交：$error')));
      }
    }
  }

  Future<List<String>> _uploadAttachments(
      String sessionId, List<ChatPickedFile> files) async {
    final refs = <String>[];
    for (final file in files) {
      final bytes = file.bytes;
      if (bytes.length > 15 * 1024 * 1024) {
        throw StateError('${file.name} 超过 15 MB 限制');
      }
      final encoded = base64Encode(bytes);
      final ext = file.extension;
      if (ext == 'pdf') {
        final result = await widget.gatewayService
            .attachPdf(sessionId: sessionId, name: file.name, base64: encoded);
        if (result is Map && result['ref_text'] != null) {
          refs.add(result['ref_text'].toString());
        }
      } else if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'heic'].contains(ext)) {
        final result = await widget.gatewayService.attachImage(
            sessionId: sessionId, name: file.name, base64: encoded);
        if (result is Map && result['ref_text'] != null) {
          refs.add(result['ref_text'].toString());
        }
      } else {
        final mime = ext == 'txt' ? 'text/plain' : 'application/octet-stream';
        final result = await widget.gatewayService.attachFile(
            sessionId: sessionId,
            name: file.name,
            dataUrl: 'data:$mime;base64,$encoded');
        if (result is Map && result['ref_text'] != null) {
          refs.add(result['ref_text'].toString());
        }
      }
    }
    return refs;
  }

  Future<void> _stopGeneration() async {
    final sessionId = _activeSession?.id;
    if (sessionId == null) return;
    try {
      await widget.gatewayService.interruptSession(sessionId);
      if (mounted) {
        setState(() {
          for (final message in _messages.where((m) => m.isStreaming)) {
            message.isStreaming = false;
          }
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法停止任务：$error（当前网关可能需要升级）')));
      }
    }
  }

  Future<void> _loadCurrentModel() async {
    try {
      final info = await widget.gatewayService.getModelInfo();
      if (!mounted) return;
      setState(() => _currentModel = [
            info['provider']?.toString(),
            info['model']?.toString(),
          ].where((part) => part != null && part.isNotEmpty).join('/'));
    } catch (_) {
      // Model info is an optional enhancement; chat remains available if absent.
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
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('网关没有返回可用模型')));
        return;
      }
      final searchController = TextEditingController();
      final selected = await showModalBottomSheet<Map<String, String>>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) =>
            StatefulBuilder(builder: (context, setSheetState) {
          final query = searchController.text.trim().toLowerCase();
          final groups = <String, List<Map<String, String>>>{};
          for (final option in options) {
            final matches = query.isEmpty ||
                [
                  option['provider'],
                  option['providerLabel'],
                  option['id'],
                  option['label']
                ].any((value) => value!.toLowerCase().contains(query));
            if (matches) {
              groups.putIfAbsent(option['provider']!, () => []).add(option);
            }
          }
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .82,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
                      child: Text('选择模型',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w700)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                      child: TextField(
                        controller: searchController,
                        onChanged: (_) => setSheetState(() {}),
                        decoration: InputDecoration(
                          hintText: '搜索模型或供应商',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: '清除搜索',
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    searchController.clear();
                                    setSheetState(() {});
                                  },
                                ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Text(
                          '${groups.values.fold<int>(0, (sum, models) => sum + models.length)} 个模型 · 按供应商分组',
                          style: const TextStyle(
                              color: HermesTheme.textMuted, fontSize: 12)),
                    ),
                    Expanded(
                      child: groups.isEmpty
                          ? const Center(
                              child: Text('没有匹配的模型',
                                  style:
                                      TextStyle(color: HermesTheme.textMuted)))
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                              children: groups.entries.map((entry) {
                                final label =
                                    providerLabels[entry.key] ?? entry.key;
                                final currentProvider =
                                    _currentModel.split('/').first;
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  clipBehavior: Clip.antiAlias,
                                  child: ExpansionTile(
                                    key: PageStorageKey(
                                        'model-provider-${entry.key}'),
                                    initiallyExpanded: query.isNotEmpty ||
                                        currentProvider == entry.key,
                                    leading: CircleAvatar(
                                      radius: 17,
                                      backgroundColor: HermesTheme.surfaceLight,
                                      child: Text(
                                          label.isNotEmpty
                                              ? label[0].toUpperCase()
                                              : 'M',
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700)),
                                    ),
                                    title: Text(label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    subtitle: Text(
                                        '${entry.value.length} 个模型 · ${entry.key}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    children: entry.value.map((option) {
                                      final isCurrent =
                                          '${option['provider']}/${option['id']}' ==
                                              _currentModel;
                                      return ListTile(
                                        dense: true,
                                        contentPadding: const EdgeInsets.only(
                                            left: 58, right: 16),
                                        leading: Icon(
                                            isCurrent
                                                ? Icons.check_circle
                                                : Icons.auto_awesome_outlined,
                                            size: 19,
                                            color: isCurrent
                                                ? HermesTheme.accent
                                                : HermesTheme.textMuted),
                                        title: Text(option['label']!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                        subtitle:
                                            option['label'] == option['id']
                                                ? null
                                                : Text(option['id']!,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis),
                                        trailing: isCurrent
                                            ? const Text('当前',
                                                style: TextStyle(
                                                    color: HermesTheme.accent,
                                                    fontSize: 12))
                                            : null,
                                        onTap: () =>
                                            Navigator.pop(context, option),
                                      );
                                    }).toList(),
                                  ),
                                );
                              }).toList(),
                            ),
                    ),
                  ]),
            ),
          );
        }),
      );
      searchController.dispose();
      if (selected == null || !mounted) return;
      await widget.gatewayService
          .setModel(provider: selected['provider']!, model: selected['id']!);
      await _loadCurrentModel();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已切换到 ${selected['label']}')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('模型切换失败：$error')));
      }
    }
  }

  Future<void> _regenerateLastReply() async {
    if (_messages.isEmpty ||
        _messages.last.role != MessageRole.assistant ||
        _messages.last.isStreaming) return;
    final assistantIndex = _messages.length - 1;
    if (assistantIndex == 0 ||
        _messages[assistantIndex - 1].role != MessageRole.user) return;
    final prompt = _messages[assistantIndex - 1].content;
    setState(() {
      _messages.removeRange(assistantIndex, _messages.length);
      _messages.add(ChatMessage.assistant(isStreaming: true));
    });
    try {
      await widget.gatewayService
          .sendMessage(sessionId: _activeSession!.id, text: prompt);
    } catch (error) {
      if (mounted) {
        setState(() {
          _messages.last.content = _sendErrorText(error);
          _messages.last.isStreaming = false;
        });
      }
    }
  }

  Future<void> _loadOrRestoreSession() async {
    try {
      final sessions = await widget.gatewayService.getSessions();
      if (mounted) {
        setState(() {
          _sessions
            ..clear()
            ..addAll(sessions);
        });
      }
      if (sessions.isNotEmpty) {
        final lastId = await _storage.getLastSessionId();
        final match = sessions.firstWhere((s) => s.id == lastId,
            orElse: () => sessions.first);
        _switchSession(match);
      } else {
        _createNewSession();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _historyError = '无法读取会话列表，请检查网关连接后重试。';
        _loadingHistory = false;
      });
    }
  }

  void _switchSession(HermesSession session) {
    setState(() {
      _activeSession = session;
      _messages.clear();
      _approvals.clear();
      _pendingEvents.clear();
      _loadingHistory = true;
      _historyOffset = 0;
      _hasOlder = false;
      _loadingOlder = false;
      _historyError = null;
    });
    _storage.saveLastSessionId(session.id);
    widget.gatewayService.connectWebSocket(session.id);
    _loadSessionHistory(session.id);
  }

  void _onSessionRenamed(HermesSession renamed) {
    if (!mounted) return;
    setState(() {
      final index = _sessions.indexWhere((session) => session.id == renamed.id);
      if (index >= 0) _sessions[index] = renamed;
      if (_activeSession?.id == renamed.id) _activeSession = renamed;
    });
  }

  Future<void> _loadSessionHistory(String sessionId) async {
    final request = ++_historyRequest;
    try {
      final rawMessages =
          await widget.gatewayService.getSessionMessages(sessionId);
      if (!mounted ||
          request != _historyRequest ||
          _activeSession?.id != sessionId) return;
      setState(() {
        _messages.clear();
        _messages.addAll(_parseHistory(rawMessages));
        _historyOffset = rawMessages.length;
        _hasOlder = rawMessages.length == 100;
        _loadingHistory = false;
      });
      final pending = List<Map<String, dynamic>>.from(_pendingEvents);
      _pendingEvents.clear();
      for (final event in pending) {
        _handleStreamEvent(event);
      }
      _scrollToBottom();
    } catch (error) {
      if (!mounted ||
          request != _historyRequest ||
          _activeSession?.id != sessionId) return;
      setState(() {
        _loadingHistory = false;
        _historyError = _historyErrorText(error);
      });
    }
  }

  List<ChatMessage> _parseHistory(List<Map<String, dynamic>> rawMessages) {
    final messages = <ChatMessage>[];
    for (final m in rawMessages) {
      if (m['role'] != 'user' && m['role'] != 'assistant') continue;
      final rawContent = m['content'];
      final content = rawContent is List
          ? rawContent
              .map((part) =>
                  part is Map ? (part['text'] ?? part['content'] ?? '') : part)
              .join('\n')
          : rawContent?.toString() ?? '';
      if (content.isEmpty && (m['thinking']?.toString() ?? '').isEmpty) {
        continue;
      }
      final rawAttachments = m['attachments'] ?? m['files'];
      final attachments = rawAttachments is List
          ? rawAttachments.map((item) {
              if (item is Map) {
                return (item['name'] ??
                        item['filename'] ??
                        item['file_name'] ??
                        '附件')
                    .toString();
              }
              return item.toString();
            }).toList()
          : <String>[];
      messages.add(ChatMessage(
        id: m['id']?.toString() ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        role: m['role'] == 'user' ? MessageRole.user : MessageRole.assistant,
        content: content,
        thinking: m['thinking']?.toString() ?? '',
        attachments: attachments,
      ));
    }
    return messages;
  }

  Future<void> _loadOlder() async {
    final sessionId = _activeSession?.id;
    if (sessionId == null || _loadingOlder || !_hasOlder) return;
    final request = _historyRequest;
    final oldExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    final oldOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    setState(() => _loadingOlder = true);
    try {
      final raw = await widget.gatewayService
          .getSessionMessages(sessionId, offset: _historyOffset);
      if (!mounted ||
          request != _historyRequest ||
          _activeSession?.id != sessionId) return;
      setState(() {
        _messages.insertAll(0, _parseHistory(raw));
        _historyOffset += raw.length;
        _hasOlder = raw.length == 100;
        _loadingOlder = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          final position = _scrollController.position;
          _scrollController.jumpTo(
              (oldOffset + position.maxScrollExtent - oldExtent)
                  .clamp(0.0, position.maxScrollExtent));
        }
      });
    } catch (_) {
      if (!mounted ||
          request != _historyRequest ||
          _activeSession?.id != sessionId) return;
      setState(() => _loadingOlder = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('加载更早的消息失败，请重试')));
    }
  }

  Future<void> _createNewSession() async {
    try {
      final newSession =
          await widget.gatewayService.createSession(title: '新对话');
      _switchSession(newSession);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法新建对话：$e')));
      }
    }
  }

  void _handleStreamEvent(Map<String, dynamic> event) {
    final type = event['type']?.toString();
    if (!mounted) return;
    if (type == 'approval.requested' || type == 'approval.pending') {
      _loadPendingApprovals();
      return;
    }
    if (type == 'voice.transcript') {
      final text = event['text']?.toString() ?? event['transcript']?.toString();
      if (text != null && text.isNotEmpty) _sendMessage(text);
      return;
    }
    if (_loadingHistory) {
      _pendingEvents.add(event);
      return;
    }

    setState(() {
      ChatMessage? currentAssistant;
      if (_messages.isNotEmpty &&
          _messages.last.role == MessageRole.assistant &&
          _messages.last.isStreaming) {
        currentAssistant = _messages.last;
      }

      if (type == 'resume_snapshot' && currentAssistant == null) {
        final inflight = event['inflight'];
        if (inflight is Map) {
          currentAssistant = ChatMessage.assistant();
          currentAssistant.content = inflight['assistant']?.toString() ?? '';
          _messages.add(currentAssistant);
        }
      } else if (type == 'start' && currentAssistant == null) {
        currentAssistant = ChatMessage.assistant();
        _messages.add(currentAssistant);
      } else if (type == 'thought' || type == 'thinking') {
        final text = event['content']?.toString() ?? '';
        currentAssistant?.thinking += text;
      } else if (type == 'content' || type == 'chunk') {
        final text = event['content']?.toString() ?? '';
        currentAssistant?.content += text;
      } else if (type == 'tool_start') {
        final toolName = event['tool_name']?.toString() ?? '未知工具';
        final toolId = event['tool_id']?.toString() ??
            DateTime.now().millisecondsSinceEpoch.toString();
        final args = event['arguments']?.toString() ?? '';
        currentAssistant?.toolCalls.add(ToolCallInfo(
          id: toolId,
          name: toolName,
          arguments: args,
          isRunning: true,
        ));
      } else if (type == 'tool_end') {
        final toolId = event['tool_id']?.toString();
        final result = event['result']?.toString() ?? '';
        final idx =
            currentAssistant?.toolCalls.indexWhere((t) => t.id == toolId) ?? -1;
        if (idx != -1 && currentAssistant != null) {
          currentAssistant.toolCalls[idx] =
              currentAssistant.toolCalls[idx].copyWith(
            result: result,
            isRunning: false,
          );
        }
      } else if (type == 'done' || type == 'message_end') {
        if (currentAssistant != null) {
          if (currentAssistant.content.isEmpty && event['content'] != null) {
            currentAssistant.content = event['content'].toString();
          }
          if (event['error'] != null) {
            currentAssistant.content += '\n${event['error']}';
          }
          currentAssistant.isStreaming = false;
        }
      } else if (type == 'error') {
        if (currentAssistant != null) {
          currentAssistant.content += '\n${event['content']}';
          currentAssistant.isStreaming = false;
        }
      }
    });

    _scrollToBottom();
  }

  Future<void> _sendMessage(String text) =>
      _sendMessageWithAttachments(text, const []);

  Future<void> _sendMessageWithAttachments(
      String text, List<ChatPickedFile> attachments) async {
    final session = _activeSession;
    if (session == null) return;
    final refs = attachments.isEmpty
        ? <String>[]
        : await _uploadAttachments(session.id, attachments);
    final names = attachments.map((file) => file.name).toList();
    final visibleText =
        text.trim().isEmpty && names.isNotEmpty ? '请查看并处理这些附件。' : text;
    final outgoingText = [
      visibleText,
      if (names.isNotEmpty) '附件：${names.join('、')}',
      ...refs,
    ].where((part) => part.trim().isNotEmpty).join('\n\n');
    final alreadyRunning = _messages.any((message) => message.isStreaming);
    final placeholder =
        alreadyRunning ? null : ChatMessage.assistant(isStreaming: true);

    setState(() {
      _messages.add(ChatMessage.user(visibleText, attachments: names));
      if (placeholder != null) _messages.add(placeholder);
    });

    try {
      await widget.gatewayService
          .sendMessage(sessionId: session.id, text: outgoingText);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (placeholder != null) {
          placeholder.content = _sendErrorText(e);
          placeholder.isStreaming = false;
        } else {
          _messages.add(ChatMessage.assistant(
            isStreaming: false,
          )..content = _sendErrorText(e));
        }
      });
    }

    _scrollToBottom();
  }

  String _sendErrorText(Object error) {
    final detail = error.toString().toLowerCase();
    if (detail.contains('session not found') || detail.contains('session_id')) {
      return '网关暂时找不到这段会话。请返回会话列表重新打开；如果仍失败，请新建对话后重试。';
    }
    return '消息未发送成功。请检查网关连接后重试。';
  }

  String _historyErrorText(Object error) {
    if (error is DioException && error.response?.statusCode == 404) {
      return '网关暂时找不到这段对话。请刷新会话列表后重试。';
    }
    return '无法读取对话内容，请检查网关连接后重试。';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildStatusIndicator() {
    Color color;
    String text;
    switch (_connectionStatus) {
      case ConnectionStatus.connected:
        color = HermesTheme.accent;
        text = "已连接网关";
        break;
      case ConnectionStatus.connecting:
      case ConnectionStatus.reconnecting:
        color = HermesTheme.warning;
        text = "网关重连中...";
        break;
      case ConnectionStatus.disconnected:
      case ConnectionStatus.error:
      default:
        color = Colors.redAccent;
        text = "网关未连接";
        break;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 6),
        Text(text,
            style: const TextStyle(fontSize: 11, color: HermesTheme.textMuted)),
      ],
    );
  }

  Widget _buildApprovalCard(Map<String, dynamic> approval) {
    final requestId = approval['request_id']?.toString() ?? '';
    final command = approval['command']?.toString() ??
        approval['description']?.toString() ??
        'Hermes 请求执行一项需要授权的操作';
    final choices = approval['choices'] is List
        ? List<String>.from(approval['choices'])
        : const ['once', 'deny'];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: Card(
          margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.shield_outlined, color: HermesTheme.warning),
                SizedBox(width: 8),
                Text('需要你的授权', style: TextStyle(fontWeight: FontWeight.w700))
              ]),
              const SizedBox(height: 8),
              SelectableText(command,
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 13)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                if (choices.contains('once'))
                  OutlinedButton(
                      onPressed: () => _respondApproval(approval, 'once'),
                      child: const Text('仅本次允许')),
                if (choices.contains('session'))
                  OutlinedButton(
                      onPressed: () => _respondApproval(approval, 'session'),
                      child: const Text('本会话允许')),
                if (choices.contains('always') &&
                    approval['allow_permanent'] == true)
                  OutlinedButton(
                      onPressed: () => _respondApproval(approval, 'always'),
                      child: const Text('始终允许')),
                FilledButton.tonal(
                    onPressed: () => _respondApproval(approval, 'deny'),
                    child: const Text('拒绝')),
              ]),
              if (requestId.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                        '请求 ${requestId.length > 12 ? requestId.substring(0, 12) : requestId}',
                        style: const TextStyle(
                            color: HermesTheme.textMuted, fontSize: 11))),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopSessions() => ColoredBox(
        color: HermesTheme.surface,
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 10, 10),
              child: Row(children: [
                const Expanded(
                    child: Text('Hermes 工作区',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700))),
                IconButton(
                    tooltip: '新对话',
                    onPressed: _createNewSession,
                    icon: const Icon(Icons.edit_square))
              ])),
          const Divider(height: 1),
          Expanded(
              child: ListView.builder(
                  itemCount: _sessions.length,
                  itemBuilder: (context, index) {
                    final session = _sessions[index];
                    return ListTile(
                        selected: session.id == _activeSession?.id,
                        leading:
                            const Icon(Icons.chat_bubble_outline, size: 18),
                        title: Text(session.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => _switchSession(session));
                  })),
        ]),
      );

  Widget _buildWelcome() {
    final suggestions = <(IconData, String)>[
      (Icons.lightbulb_outline, '介绍一下你能做什么'),
      (Icons.travel_explore_outlined, '帮我研究一个问题'),
      (Icons.summarize_outlined, '总结一段内容'),
      (Icons.code, '帮我看一段代码'),
    ];
    final canSend = _connectionStatus == ConnectionStatus.connected;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: HermesTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.auto_awesome,
                    size: 26, color: HermesTheme.textMain),
              ),
              const SizedBox(height: 22),
              const Text(
                '今天想做点什么？',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 25,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4),
              ),
              const SizedBox(height: 9),
              Text(
                canSend ? '向 Hermes 提问、写作、分析或处理任务。' : '连接网关后即可开始新对话。',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: HermesTheme.textMuted, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: suggestions
                    .map((suggestion) => OutlinedButton.icon(
                          onPressed: canSend
                              ? () => _sendMessage(suggestion.$2)
                              : null,
                          icon: Icon(suggestion.$1, size: 17),
                          label: Text(suggestion.$2),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            foregroundColor: HermesTheme.textMain,
                            side: const BorderSide(color: HermesTheme.border),
                            shape: const StadiumBorder(),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _streamSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_activeSession?.title ?? "Hermes Agent",
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            _buildStatusIndicator(),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _showModelPicker,
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 88),
              child: Text(
                _currentModel.isEmpty ? '模型' : _currentModel.split('/').last,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            style: TextButton.styleFrom(foregroundColor: HermesTheme.textMain),
          ),
          IconButton(
            tooltip: '新建对话',
            icon: const Icon(Icons.edit_square),
            onPressed: _createNewSession,
          ),
          PopupMenuButton<String>(
            tooltip: '更多选项',
            onSelected: (action) {
              if (action == 'gateway') {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      GatewayManagementScreen(gateway: widget.gatewayService),
                ));
              } else if (action == 'settings') {
                showDialog(
                  context: context,
                  builder: (ctx) => GatewaySettingsDialog(
                    gatewayService: widget.gatewayService,
                    onSaved: _loadOrRestoreSession,
                  ),
                );
              } else if (action == 'app_update') {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const AppUpdateScreen(),
                ));
              } else if (action == 'workspace') {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AgentWorkspaceScreen(
                    gateway: widget.gatewayService,
                    sessionId: _activeSession?.id ?? '',
                  ),
                ));
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'workspace',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.terminal),
                  title: Text('Agent 工作台'),
                ),
              ),
              PopupMenuItem(
                value: 'gateway',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.tune),
                  title: Text('网关管理'),
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.settings_outlined),
                  title: Text('连接设置'),
                ),
              ),
              PopupMenuItem(
                value: 'app_update',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.system_update_alt),
                  title: Text('App 更新'),
                ),
              ),
            ],
          ),
        ],
      ),
      drawer: SessionDrawer(
        gatewayService: widget.gatewayService,
        activeSessionId: _activeSession?.id,
        onSelectSession: _switchSession,
        onSessionRenamed: _onSessionRenamed,
        onNewSession: _createNewSession,
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        final content = Column(
          children: [
            ..._approvals.map(_buildApprovalCard),
            Expanded(
              child: _loadingHistory
                  ? const Center(child: CircularProgressIndicator())
                  : _historyError != null
                      ? Center(
                          child: Padding(
                          padding: const EdgeInsets.all(24),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            const Text('无法加载对话记录',
                                style: TextStyle(fontSize: 16)),
                            const SizedBox(height: 8),
                            Text(_historyError!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: HermesTheme.textMuted,
                                    fontSize: 12)),
                            TextButton(
                                onPressed: () {
                                  setState(() {
                                    _loadingHistory = true;
                                    _historyError = null;
                                  });
                                  if (_activeSession == null) {
                                    _loadOrRestoreSession();
                                  } else {
                                    _loadSessionHistory(_activeSession!.id);
                                  }
                                },
                                child: const Text('重试')),
                          ]),
                        ))
                      : _messages.isEmpty && !_hasOlder
                          ? _buildWelcome()
                          : ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              itemCount: _messages.length + (_hasOlder ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (_hasOlder && index == 0) {
                                  return Center(
                                      child: TextButton(
                                          onPressed:
                                              _loadingOlder ? null : _loadOlder,
                                          child: Text(_loadingOlder
                                              ? '加载中…'
                                              : '加载更早的消息')));
                                }
                                final msg =
                                    _messages[index - (_hasOlder ? 1 : 0)];
                                final isUser = msg.role == MessageRole.user;

                                return Center(
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 820),
                                    child: Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 16),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment: isUser
                                            ? MainAxisAlignment.end
                                            : MainAxisAlignment.start,
                                        children: [
                                          if (!isUser) ...[
                                            Container(
                                              width: 26,
                                              height: 26,
                                              margin: const EdgeInsets.only(
                                                  right: 8, top: 2),
                                              decoration: BoxDecoration(
                                                color: HermesTheme.primary
                                                    .withOpacity(0.2),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                  Icons.smart_toy_outlined,
                                                  size: 15,
                                                  color: HermesTheme.primary),
                                            ),
                                          ],
                                          Flexible(
                                            child: ConstrainedBox(
                                              constraints: BoxConstraints(
                                                maxWidth: isUser
                                                    ? (MediaQuery.sizeOf(
                                                                    context)
                                                                .width <
                                                            720
                                                        ? MediaQuery.sizeOf(
                                                                    context)
                                                                .width *
                                                            0.78
                                                        : 620)
                                                    : 760,
                                              ),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 14,
                                                        vertical: 10),
                                                decoration: BoxDecoration(
                                                  color: isUser
                                                      ? HermesTheme.surfaceLight
                                                      : Colors.transparent,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: Colors.transparent,
                                                  ),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    if (!isUser &&
                                                        msg.thinking
                                                            .isNotEmpty) ...[
                                                      ThinkingBubble(
                                                        thinking: msg.thinking,
                                                        isStreaming:
                                                            msg.isStreaming,
                                                      ),
                                                    ],
                                                    if (!isUser &&
                                                        msg.toolCalls
                                                            .isNotEmpty) ...[
                                                      for (final tool
                                                          in msg.toolCalls)
                                                        ToolCard(
                                                            toolCall: tool),
                                                    ],
                                                    if (isUser)
                                                      Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          if (msg.attachments
                                                              .isNotEmpty)
                                                            Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .only(
                                                                      bottom:
                                                                          8),
                                                              child: Wrap(
                                                                spacing: 6,
                                                                runSpacing: 6,
                                                                children: msg
                                                                    .attachments
                                                                    .map(
                                                                        (name) =>
                                                                            Chip(
                                                                              avatar: const Icon(Icons.attach_file, size: 16),
                                                                              label: Text(name, overflow: TextOverflow.ellipsis),
                                                                              visualDensity: VisualDensity.compact,
                                                                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                                            ))
                                                                    .toList(),
                                                              ),
                                                            ),
                                                          SelectableText(
                                                            msg.content,
                                                            style: const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontSize: 14),
                                                          ),
                                                          if (msg.content
                                                              .isNotEmpty)
                                                            Align(
                                                              alignment: Alignment
                                                                  .centerLeft,
                                                              child: IconButton(
                                                                tooltip: '复制提问',
                                                                visualDensity:
                                                                    VisualDensity
                                                                        .compact,
                                                                icon: const Icon(
                                                                    Icons
                                                                        .content_copy,
                                                                    size: 15),
                                                                onPressed: () {
                                                                  Clipboard.setData(
                                                                      ClipboardData(
                                                                          text:
                                                                              msg.content));
                                                                  ScaffoldMessenger.of(
                                                                          context)
                                                                      .showSnackBar(
                                                                    const SnackBar(
                                                                        content:
                                                                            Text('已复制提问')),
                                                                  );
                                                                },
                                                              ),
                                                            ),
                                                        ],
                                                      )
                                                    else
                                                      MarkdownBody(
                                                        data: msg.content
                                                                    .isEmpty &&
                                                                msg.isStreaming
                                                            ? "▍"
                                                            : msg.content,
                                                        styleSheet:
                                                            MarkdownStyleSheet
                                                                    .fromTheme(
                                                                        Theme.of(
                                                                            context))
                                                                .copyWith(
                                                          p: const TextStyle(
                                                              fontSize: 14,
                                                              color: HermesTheme
                                                                  .textMain,
                                                              height: 1.5),
                                                          code: const TextStyle(
                                                            fontFamily:
                                                                'monospace',
                                                            backgroundColor:
                                                                Color(
                                                                    0xFF1E222D),
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                      ),
                                                    if (!isUser &&
                                                        msg.content
                                                            .isNotEmpty &&
                                                        !msg.isStreaming)
                                                      Wrap(
                                                        spacing: 2,
                                                        children: [
                                                          IconButton(
                                                            tooltip: '复制回复',
                                                            visualDensity:
                                                                VisualDensity
                                                                    .compact,
                                                            icon: const Icon(
                                                                Icons
                                                                    .content_copy,
                                                                size: 16),
                                                            onPressed: () {
                                                              Clipboard.setData(
                                                                  ClipboardData(
                                                                      text: msg
                                                                          .content));
                                                              ScaffoldMessenger
                                                                      .of(
                                                                          context)
                                                                  .showSnackBar(
                                                                      const SnackBar(
                                                                          content:
                                                                              Text('已复制回复')));
                                                            },
                                                          ),
                                                          IconButton(
                                                            tooltip: '分享回复',
                                                            visualDensity:
                                                                VisualDensity
                                                                    .compact,
                                                            icon: const Icon(
                                                                Icons
                                                                    .share_outlined,
                                                                size: 16),
                                                            onPressed:
                                                                () async {
                                                              try {
                                                                await const MethodChannel(
                                                                        'com.hermes.mobile/files')
                                                                    .invokeMethod<
                                                                            void>(
                                                                        'shareText',
                                                                        {
                                                                      'text': msg
                                                                          .content
                                                                    });
                                                              } on PlatformException {
                                                                if (context
                                                                    .mounted) {
                                                                  ScaffoldMessenger.of(
                                                                          context)
                                                                      .showSnackBar(
                                                                    const SnackBar(
                                                                        content:
                                                                            Text('无法打开系统分享面板')),
                                                                  );
                                                                }
                                                              }
                                                            },
                                                          ),
                                                          if (index ==
                                                              _messages.length -
                                                                  1)
                                                            IconButton(
                                                              tooltip: '重新生成',
                                                              visualDensity:
                                                                  VisualDensity
                                                                      .compact,
                                                              icon: const Icon(
                                                                  Icons.refresh,
                                                                  size: 17),
                                                              onPressed:
                                                                  _regenerateLastReply,
                                                            ),
                                                        ],
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 840),
                child: ChatInputBar(
                  key:
                      ValueKey('chat-composer-${_activeSession?.id ?? 'none'}'),
                  onSend: _sendMessageWithAttachments,
                  draftText: _drafts[_activeSession?.id] ?? '',
                  draftAttachments:
                      _draftAttachments[_activeSession?.id] ?? const [],
                  onDraftTextChanged: (value) {
                    final id = _activeSession?.id;
                    if (id != null) _drafts[id] = value;
                  },
                  onDraftAttachmentsChanged: (files) {
                    final id = _activeSession?.id;
                    if (id != null) _draftAttachments[id] = List.of(files);
                  },
                  isStreaming: _messages.any((message) => message.isStreaming),
                  onStop: _stopGeneration,
                  isConnected:
                      _connectionStatus == ConnectionStatus.connected &&
                          !_loadingHistory &&
                          _historyError == null,
                ),
              ),
            ),
          ],
        );
        if (constraints.maxWidth < 1080) return content;
        return Row(children: [
          SizedBox(width: 280, child: _buildDesktopSessions()),
          const VerticalDivider(width: 1),
          Expanded(child: content)
        ]);
      }),
    );
  }
}

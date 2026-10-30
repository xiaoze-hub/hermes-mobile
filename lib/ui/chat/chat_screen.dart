import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../models/chat_message.dart';
import '../../models/session.dart';
import '../../services/hermes_gateway_service.dart';
import '../sessions/session_drawer.dart';
import '../settings/gateway_settings_dialog.dart';
import 'chat_input_bar.dart';
import 'thinking_bubble.dart';
import 'tool_card.dart';

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
  bool _loadingHistory = false;
  String? _historyError;
  int _historyRequest = 0;
  int _historyOffset = 0;
  bool _hasOlder = false;
  bool _loadingOlder = false;
  final List<Map<String, dynamic>> _pendingEvents = [];
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;

  StreamSubscription? _statusSub;
  StreamSubscription? _streamSub;

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
  }

  Future<void> _loadOrRestoreSession() async {
    try {
      final sessions = await widget.gatewayService.getSessions();
      if (sessions.isNotEmpty) {
        final lastId = await _storage.getLastSessionId();
        final match = sessions.firstWhere((s) => s.id == lastId,
            orElse: () => sessions.first);
        _switchSession(match);
      } else {
        _createNewSession();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _historyError = '无法读取会话列表：$error';
        _loadingHistory = false;
      });
    }
  }

  void _switchSession(HermesSession session) {
    setState(() {
      _activeSession = session;
      _messages.clear();
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
        _historyError = error.toString();
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
      messages.add(ChatMessage(
        id: m['id']?.toString() ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        role: m['role'] == 'user' ? MessageRole.user : MessageRole.assistant,
        content: content,
        thinking: m['thinking']?.toString() ?? '',
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

  void _sendMessage(String text) {
    if (_activeSession == null) return;

    setState(() {
      _messages.add(ChatMessage.user(text));
      _messages.add(ChatMessage.assistant(isStreaming: true));
    });

    try {
      widget.gatewayService
          .sendMessage(sessionId: _activeSession!.id, text: text);
    } catch (e) {
      setState(() {
        if (_messages.isNotEmpty) {
          _messages.last.content = '发送失败: $e';
          _messages.last.isStreaming = false;
        }
      });
    }

    _scrollToBottom();
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
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => GatewaySettingsDialog(
                  gatewayService: widget.gatewayService,
                  onSaved: () {
                    _loadOrRestoreSession();
                  },
                ),
              );
            },
          ),
        ],
      ),
      drawer: SessionDrawer(
        gatewayService: widget.gatewayService,
        activeSessionId: _activeSession?.id,
        onSelectSession: _switchSession,
        onNewSession: _createNewSession,
      ),
      body: Column(
        children: [
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
                                  color: HermesTheme.textMuted, fontSize: 12)),
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
                        ? const Center(
                            child: Text(
                              "向远程 Hermes Agent 发送第一条指令...",
                              style: TextStyle(
                                  color: HermesTheme.textMuted, fontSize: 13),
                            ),
                          )
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

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 10),
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
                                                msg.thinking.isNotEmpty) ...[
                                              ThinkingBubble(
                                                thinking: msg.thinking,
                                                isStreaming: msg.isStreaming,
                                              ),
                                            ],
                                            if (!isUser &&
                                                msg.toolCalls.isNotEmpty) ...[
                                              for (final tool in msg.toolCalls)
                                                ToolCard(toolCall: tool),
                                            ],
                                            if (!isUser &&
                                                msg.content.isNotEmpty &&
                                                !msg.isStreaming)
                                              Align(
                                                  alignment:
                                                      Alignment.centerRight,
                                                  child: IconButton(
                                                    tooltip: '复制回复',
                                                    icon: const Icon(Icons.copy,
                                                        size: 17),
                                                    onPressed: () {
                                                      Clipboard.setData(
                                                          ClipboardData(
                                                              text:
                                                                  msg.content));
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                              const SnackBar(
                                                                  content: Text(
                                                                      '已复制回复')));
                                                    },
                                                  )),
                                            if (isUser)
                                              SelectableText(
                                                msg.content,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 14),
                                              )
                                            else
                                              MarkdownBody(
                                                data: msg.content.isEmpty &&
                                                        msg.isStreaming
                                                    ? "▍"
                                                    : msg.content,
                                                styleSheet: MarkdownStyleSheet
                                                        .fromTheme(
                                                            Theme.of(context))
                                                    .copyWith(
                                                  p: const TextStyle(
                                                      fontSize: 14,
                                                      color:
                                                          HermesTheme.textMain,
                                                      height: 1.5),
                                                  code: const TextStyle(
                                                    fontFamily: 'monospace',
                                                    backgroundColor:
                                                        Color(0xFF1E222D),
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
          ChatInputBar(
            onSend: _sendMessage,
            isConnected: _connectionStatus == ConnectionStatus.connected &&
                !_loadingHistory &&
                _historyError == null &&
                !_messages.any((message) => message.isStreaming),
          ),
        ],
      ),
    );
  }
}

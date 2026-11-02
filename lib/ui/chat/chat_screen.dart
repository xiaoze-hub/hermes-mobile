import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../models/chat_message.dart';
import '../../models/session.dart';
import '../../services/hermes_gateway_service.dart';
import '../sessions/session_drawer.dart';
import '../settings/gateway_settings_dialog.dart';
import '../settings/app_update_screen.dart';
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
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  bool _loadingHistory = false;
  String? _loadHistoryError;

  StreamSubscription? _statusSub;
  StreamSubscription? _streamSub;

  bool get _isCurrentlyStreaming {
    return _messages.isNotEmpty && _messages.last.role == MessageRole.assistant && _messages.last.isStreaming;
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
  }

  Future<void> _loadOrRestoreSession() async {
    try {
      final sessions = await widget.gatewayService.getSessions();
      if (sessions.isNotEmpty) {
        final lastId = await _storage.getLastSessionId();
        final match = sessions.firstWhere((s) => s.id == lastId, orElse: () => sessions.first);
        _switchSession(match);
      } else {
        _createNewSession();
      }
    } catch (_) {
      _switchSession(HermesSession(id: 'default', title: '主指令会话', updatedAt: DateTime.now()));
    }
  }

  void _switchSession(HermesSession session) {
    setState(() {
      _activeSession = session;
      _messages.clear();
      _loadHistoryError = null;
    });
    _storage.saveLastSessionId(session.id);
    widget.gatewayService.connectWebSocket(session.id);
    _loadSessionHistory(session.id);
  }

  Future<void> _loadSessionHistory(String sessionId) async {
    setState(() {
      _loadingHistory = true;
      _loadHistoryError = null;
    });

    try {
      final rawMessages = await widget.gatewayService.getSessionMessages(sessionId);
      if (!mounted) return;

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
      });

      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingHistory = false;
          _loadHistoryError = "获取历史失败: $e";
        });
      }
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

  void _handleStreamEvent(Map<String, dynamic> event) {
    final type = event['type']?.toString();
    if (!mounted) return;

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
        currentAssistant?.toolCalls.add(ToolCallInfo(
          id: toolId,
          name: toolName,
          arguments: args,
          isRunning: true,
        ));
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
      } else if (type == 'done' || type == 'message_end') {
        currentAssistant?.isStreaming = false;
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
      widget.gatewayService.sendMessage(sessionId: _activeSession!.id, text: text);
    } catch (e) {
      setState(() {
        if (_messages.isNotEmpty) {
          _messages.last.content = '下发指令失败: $e';
          _messages.last.isStreaming = false;
        }
      });
    }

    _scrollToBottom();
  }

  void _stopGeneration() {
    setState(() {
      if (_messages.isNotEmpty && _messages.last.role == MessageRole.assistant) {
        _messages.last.isStreaming = false;
      }
    });
  }

  void _scrollToBottom() {
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

  Widget _buildTelemetryBadge() {
    Color dotColor;
    String statusText;

    switch (_connectionStatus) {
      case ConnectionStatus.connected:
        dotColor = HermesTheme.accent;
        statusText = "Hermes Agent · 连通在线";
        break;
      case ConnectionStatus.connecting:
      case ConnectionStatus.reconnecting:
        dotColor = HermesTheme.warning;
        statusText = "中控重连中...";
        break;
      case ConnectionStatus.disconnected:
      case ConnectionStatus.error:
      default:
        dotColor = HermesTheme.danger;
        statusText = "网关未就绪";
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: HermesTheme.surfaceLight,
        borderRadius: BorderRadius.circular(12),
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
            style: const TextStyle(fontSize: 10.5, color: HermesTheme.textMuted, letterSpacing: 0.2),
          ),
        ],
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
            const SizedBox(height: 3),
            _buildTelemetryBadge(),
          ],
        ),
        actions: [
          IconButton(
            icon: _loadingHistory
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: HermesTheme.primary),
                  )
                : const Icon(Icons.sync_rounded, size: 20),
            tooltip: "重新同步当前会话记录",
            onPressed: _loadingHistory || _activeSession == null
                ? null
                : () => _loadSessionHistory(_activeSession!.id),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, size: 20),
            color: HermesTheme.surfaceElevated,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (val) {
              if (val == 'settings') {
                showDialog(
                  context: context,
                  builder: (ctx) => GatewaySettingsDialog(
                    gatewayService: widget.gatewayService,
                    onSaved: () {
                      if (_activeSession != null) {
                        widget.gatewayService.connectWebSocket(_activeSession!.id);
                        _loadSessionHistory(_activeSession!.id);
                      }
                    },
                  ),
                );
              } else if (val == 'update') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AppUpdateScreen()),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'settings',
                height: 40,
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded, size: 16, color: HermesTheme.textMuted),
                    SizedBox(width: 10),
                    Text('网关连接设置', style: TextStyle(fontSize: 13, color: HermesTheme.textMain)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'update',
                height: 40,
                child: Row(
                  children: [
                    Icon(Icons.system_update_alt_rounded, size: 16, color: HermesTheme.accent),
                    SizedBox(width: 10),
                    Text('检查 App 在线更新', style: TextStyle(fontSize: 13, color: HermesTheme.textMain)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      drawer: SessionDrawer(
        gatewayService: widget.gatewayService,
        activeSessionId: _activeSession?.id,
        onSelectSession: _switchSession,
        onNewSession: _createNewSession,
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
                    : _messages.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: HermesTheme.surfaceLight,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: HermesTheme.borderSubtle),
                                  ),
                                  child: const Icon(Icons.terminal_rounded, size: 30, color: HermesTheme.cyan),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  "Hermes Agent 已就绪",
                                  style: TextStyle(color: HermesTheme.textMain, fontSize: 15, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  "可通过下方悬浮输入舱或快捷指令\n下发远程 Linux 运维、搜索与代码任务",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: HermesTheme.textDim, fontSize: 12.5, height: 1.4),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            // 预留底部 padding，避免被悬浮输入岛遮挡
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 120),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final msg = _messages[index];
                              final isUser = msg.role == MessageRole.user;

                              if (isUser) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: Container(
                                      constraints: BoxConstraints(
                                        maxWidth: MediaQuery.of(context).size.width * 0.84,
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                                      decoration: BoxDecoration(
                                        gradient: HermesTheme.userBubbleGradient,
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(18),
                                          bottomLeft: Radius.circular(18),
                                          bottomRight: Radius.circular(18),
                                          topRight: Radius.circular(4),
                                        ),
                                        border: Border.all(color: Colors.white.withOpacity(0.12), width: 0.8),
                                        boxShadow: const [HermesTheme.primaryGlow],
                                      ),
                                      child: SelectableText(
                                        msg.content,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13.5,
                                          height: 1.45,
                                          letterSpacing: 0.1,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }

                              // Assistant 回复气泡
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 18),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Agent 智能体徽标头像
                                    Container(
                                      width: 28,
                                      height: 28,
                                      margin: const EdgeInsets.only(right: 10, top: 2),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [Color(0xFF4338CA), Color(0xFF6366F1)],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: HermesTheme.primary.withOpacity(0.4), width: 0.8),
                                      ),
                                      child: const Icon(Icons.auto_awesome_rounded, size: 15, color: Colors.white),
                                    ),

                                    // 主体卡片
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: HermesTheme.surface,
                                          borderRadius: const BorderRadius.only(
                                            topRight: Radius.circular(18),
                                            bottomLeft: Radius.circular(18),
                                            bottomRight: Radius.circular(18),
                                            topLeft: Radius.circular(4),
                                          ),
                                          border: Border.all(color: HermesTheme.border, width: 1),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // 1. 深度推导思维链折叠块
                                            if (msg.thinking.isNotEmpty || (msg.isStreaming && msg.content.isEmpty)) ...[
                                              ThinkingBubble(
                                                thinking: msg.thinking,
                                                isStreaming: msg.isStreaming,
                                              ),
                                            ],

                                            // 2. 特工工具执行卡片流
                                            if (msg.toolCalls.isNotEmpty) ...[
                                              for (final tool in msg.toolCalls) ToolCard(toolCall: tool),
                                            ],

                                            // 3. 正文 Markdown 流式呈现
                                            MarkdownBody(
                                              data: msg.content.isEmpty && msg.isStreaming ? "▍" : msg.content,
                                              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                                                p: const TextStyle(
                                                  fontSize: 13.5,
                                                  color: HermesTheme.textMain,
                                                  height: 1.55,
                                                  letterSpacing: 0.1,
                                                ),
                                                code: const TextStyle(
                                                  fontFamily: 'monospace',
                                                  backgroundColor: Color(0xFF090B12),
                                                  color: Color(0xFF38BDF8),
                                                  fontSize: 12,
                                                ),
                                                codeblockDecoration: BoxDecoration(
                                                  color: const Color(0xFF090B12),
                                                  borderRadius: BorderRadius.circular(10),
                                                  border: Border.all(color: HermesTheme.border),
                                                ),
                                              ),
                                            ),

                                            // 4. 底部微型工具栏 (复制回答、时间)
                                            if (!msg.isStreaming && msg.content.isNotEmpty) ...[
                                              const SizedBox(height: 10),
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.end,
                                                children: [
                                                  Text(
                                                    DateFormat('HH:mm').format(msg.createdAt),
                                                    style: const TextStyle(fontSize: 10, color: HermesTheme.textDim),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  InkWell(
                                                    onTap: () => _copyToClipboard(msg.content, '已复制回答内容'),
                                                    borderRadius: BorderRadius.circular(4),
                                                    child: const Padding(
                                                      padding: EdgeInsets.all(4),
                                                      child: Icon(Icons.copy_rounded, size: 13, color: HermesTheme.textDim),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
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

          // 悬浮底部输入控制岛
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ChatInputBar(
              onSend: _sendMessage,
              onStop: _stopGeneration,
              isConnected: _connectionStatus == ConnectionStatus.connected,
              isStreaming: _isCurrentlyStreaming,
            ),
          ),
        ],
      ),
    );
  }
}

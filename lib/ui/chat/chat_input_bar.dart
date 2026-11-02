import 'package:flutter/material.dart';
import '../../core/theme.dart';

class ChatInputBar extends StatefulWidget {
  final Function(String) onSend;
  final VoidCallback? onStop;
  final bool isConnected;
  final bool isStreaming;

  const ChatInputBar({
    super.key,
    required this.onSend,
    this.onStop,
    required this.isConnected,
    this.isStreaming = false,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final TextEditingController _controller = TextEditingController();
  bool _hasText = false;

  // 预置 Linux / Hermes Agent 常用中控快捷指令
  final List<Map<String, String>> _quickMacros = [
    {'label': '🐳 容器状态', 'cmd': '请检查服务器当前 Docker 容器状态，标出任何异常退出的容器。'},
    {'label': '📊 内存占用', 'cmd': '执行 free -h 和 vmstat，分析当前 Linux 内存是否充裕。'},
    {'label': '🔥 CPU 负载', 'cmd': '执行 top -b -n 1 并排查消耗 CPU 最多的前 5 个进程。'},
    {'label': '💾 磁盘空间', 'cmd': '执行 df -h 查看根分区和挂载点的剩余磁盘空间。'},
    {'label': '📜 系统错误日志', 'cmd': '排查 journalctl -p err -n 10 最近的系统错误记录。'},
  ];

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) {
        setState(() => _hasText = has);
      }
    });
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.isConnected || widget.isStreaming) return;
    widget.onSend(text);
    _controller.clear();
  }

  void _applyMacro(String cmd) {
    _controller.text = cmd;
    _controller.selection = TextSelection.fromPosition(TextPosition(offset: cmd.length));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        // 上方柔和渐隐阴影
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            HermesTheme.background.withOpacity(0.0),
            HermesTheme.background.withOpacity(0.85),
            HermesTheme.background,
          ],
          stops: const [0.0, 0.35, 1.0],
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        12,
        4,
        12,
        8 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. 横向快捷宏指令栏 (Quick Telemetry Chips)
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _quickMacros.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final macro = _quickMacros[index];
                  return ActionChip(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: HermesTheme.surfaceLight,
                    side: const BorderSide(color: HermesTheme.borderSubtle, width: 0.8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    label: Text(
                      macro['label']!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: HermesTheme.textMuted,
                        letterSpacing: 0.1,
                      ),
                    ),
                    onPressed: widget.isConnected ? () => _applyMacro(macro['cmd']!) : null,
                  );
                },
              ),
            ),
            const SizedBox(height: 8),

            // 2. 核心悬浮输入胶囊 (Floating Command Capsule)
            Container(
              decoration: BoxDecoration(
                color: HermesTheme.surfaceGlass,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _hasText ? HermesTheme.primary.withOpacity(0.6) : HermesTheme.borderSubtle,
                  width: 1.2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 左侧辅助图标 (特工斜杠命令快捷键提示)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 10),
                    child: Icon(
                      Icons.terminal_rounded,
                      size: 18,
                      color: widget.isConnected ? HermesTheme.cyan : HermesTheme.textDim,
                    ),
                  ),

                  // 中间输入框
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      maxLines: 5,
                      minLines: 1,
                      keyboardType: TextInputType.multiline,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: HermesTheme.textMain,
                        height: 1.45,
                      ),
                      decoration: InputDecoration(
                        filled: false,
                        hintText: widget.isConnected
                            ? "向 Linux Hermes Agent 下发指令..."
                            : "远程网关未连接，请点击右上角配置...",
                        hintStyle: const TextStyle(fontSize: 12.5, color: HermesTheme.textDim),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                      ),
                      onSubmitted: (_) => _handleSend(),
                    ),
                  ),

                  // 右侧动作按钮 (发送 / 停止生成动态切换)
                  Padding(
                    padding: const EdgeInsets.only(right: 6, bottom: 6),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                      child: widget.isStreaming
                          ? IconButton.filled(
                              key: const ValueKey('stop_btn'),
                              onPressed: widget.onStop,
                              icon: const Icon(Icons.stop_rounded, size: 18),
                              tooltip: '停止生成',
                              style: IconButton.styleFrom(
                                backgroundColor: HermesTheme.danger,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(36, 36),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                            )
                          : IconButton.filled(
                              key: const ValueKey('send_btn'),
                              onPressed: (widget.isConnected && _hasText) ? _handleSend : null,
                              icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                              tooltip: '发送指令',
                              style: IconButton.styleFrom(
                                backgroundColor: HermesTheme.primary,
                                disabledBackgroundColor: HermesTheme.surfaceLight,
                                foregroundColor: Colors.white,
                                disabledForegroundColor: HermesTheme.textDim,
                                minimumSize: const Size(36, 36),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

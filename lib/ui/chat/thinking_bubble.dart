import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';

class ThinkingBubble extends StatefulWidget {
  final String thinking;
  final bool isStreaming;

  const ThinkingBubble({
    super.key,
    required this.thinking,
    this.isStreaming = false,
  });

  @override
  State<ThinkingBubble> createState() => _ThinkingBubbleState();
}

class _ThinkingBubbleState extends State<ThinkingBubble> with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _copyThinking() {
    if (widget.thinking.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: widget.thinking));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已复制思考推导过程到剪贴板'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.thinking.isEmpty && !widget.isStreaming) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: HermesTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isStreaming ? HermesTheme.warning.withOpacity(0.35) : HermesTheme.border,
          width: 1,
        ),
        boxShadow: widget.isStreaming ? const [HermesTheme.thinkingGlow] : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部交互胶囊条
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            splashColor: HermesTheme.warning.withOpacity(0.08),
            highlightColor: HermesTheme.surfaceLight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  // 呼吸式琥珀微光圆点
                  if (widget.isStreaming)
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: HermesTheme.warning.withOpacity(_pulseAnimation.value),
                            boxShadow: [
                              BoxShadow(
                                color: HermesTheme.warning.withOpacity(_pulseAnimation.value * 0.6),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        );
                      },
                    )
                  else
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: HermesTheme.warning,
                      ),
                    ),

                  Text(
                    widget.isStreaming ? "Hermes 正在深度推导中..." : "已完成推导思考",
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                      color: Color(0xFFFDE68A), // Amber 200
                    ),
                  ),

                  if (widget.thinking.isNotEmpty && !_expanded) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: HermesTheme.surfaceLight,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: HermesTheme.borderSubtle, width: 0.8),
                      ),
                      child: Text(
                        '${widget.thinking.length} 字',
                        style: const TextStyle(fontSize: 10, color: HermesTheme.textDim, fontFamily: 'monospace'),
                      ),
                    ),
                  ],

                  const Spacer(),

                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: HermesTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 展开的思维链内容
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: HermesTheme.border, width: 0.8)),
                color: Color(0xFF0C0F1A), // 更深层的代码底色
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(11)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'INTERNAL REASONING MONOLOGUE',
                        style: TextStyle(
                          fontSize: 9,
                          fontFamily: 'monospace',
                          letterSpacing: 1.0,
                          fontWeight: FontWeight.w700,
                          color: HermesTheme.textDim,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 13, color: HermesTheme.textMuted),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: '复制思维链',
                        onPressed: _copyThinking,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    widget.thinking,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Color(0xFFCBD5E1),
                      height: 1.5,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
            ),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
    );
  }
}

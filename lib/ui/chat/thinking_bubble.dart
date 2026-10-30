import 'package:flutter/material.dart';
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

class _ThinkingBubbleState extends State<ThinkingBubble> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.thinking.isEmpty && !widget.isStreaming) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: HermesTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: HermesTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  Icon(
                    widget.isStreaming ? Icons.psychology : Icons.lightbulb_outline,
                    size: 15,
                    color: Colors.amberAccent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.isStreaming ? "Hermes 正在深度推导中..." : "已完成思考推导",
                    style: const TextStyle(fontSize: 12, color: HermesTheme.textMuted),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 16,
                    color: HermesTheme.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: SelectableText(
                widget.thinking,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: Color(0xFF9CA3AF),
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

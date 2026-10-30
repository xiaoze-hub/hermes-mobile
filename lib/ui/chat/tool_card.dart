import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/chat_message.dart';

class ToolCard extends StatefulWidget {
  final ToolCallInfo toolCall;

  const ToolCard({super.key, required this.toolCall});

  @override
  State<ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<ToolCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tool = widget.toolCall;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: HermesTheme.surfaceLight,
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
                    tool.isRunning ? Icons.play_circle_outline : Icons.terminal,
                    size: 14,
                    color: tool.isRunning ? HermesTheme.warning : HermesTheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '工具调用: ${tool.name}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: HermesTheme.textMain,
                    ),
                  ),
                  const Spacer(),
                  if (tool.isRunning)
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: HermesTheme.warning),
                    )
                  else
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (tool.arguments.isNotEmpty) ...[
                    const Text('入参 (Arguments):', style: TextStyle(fontSize: 11, color: HermesTheme.textMuted)),
                    const SizedBox(height: 2),
                    SelectableText(
                      tool.arguments,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white70),
                    ),
                    const SizedBox(height: 6),
                  ],
                  if (tool.result != null) ...[
                    const Text('执行结果 (Output):', style: TextStyle(fontSize: 11, color: HermesTheme.textMuted)),
                    const SizedBox(height: 2),
                    SelectableText(
                      tool.result!,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.greenAccent),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

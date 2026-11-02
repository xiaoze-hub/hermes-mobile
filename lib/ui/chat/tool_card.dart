import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  void _copyText(String text, String label) {
    if (text.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: text));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已复制 $label'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  IconData _getToolIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('bash') || lower.contains('shell') || lower.contains('exec') || lower.contains('cmd')) {
      return Icons.terminal_rounded;
    } else if (lower.contains('python') || lower.contains('code')) {
      return Icons.code_rounded;
    } else if (lower.contains('search') || lower.contains('web')) {
      return Icons.travel_explore_rounded;
    } else if (lower.contains('file') || lower.contains('read') || lower.contains('write')) {
      return Icons.folder_open_rounded;
    }
    return Icons.settings_suggest_rounded;
  }

  String _formatCategory(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('bash') || lower.contains('shell')) return 'BASH';
    if (lower.contains('python')) return 'PYTHON';
    if (lower.contains('search')) return 'WEB';
    if (lower.contains('file')) return 'IO';
    return 'SYSTEM';
  }

  @override
  Widget build(BuildContext context) {
    final tool = widget.toolCall;
    final isRunning = tool.isRunning;
    final category = _formatCategory(tool.name);
    final icon = _getToolIcon(tool.name);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: HermesTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRunning ? HermesTheme.warning.withOpacity(0.4) : HermesTheme.border,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 终端顶栏：工具名与状态指示
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF141A2B), // 微对比度中控顶栏
                borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 14, color: isRunning ? HermesTheme.warning : HermesTheme.accent),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: HermesTheme.primary.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: HermesTheme.primary.withOpacity(0.3), width: 0.6),
                    ),
                    child: Text(
                      category,
                      style: const TextStyle(
                        fontSize: 9,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFA5B4FC),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      tool.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        color: HermesTheme.textMain,
                      ),
                    ),
                  ),
                  if (isRunning) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: HermesTheme.warning.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(strokeWidth: 1.5, color: HermesTheme.warning),
                          ),
                          SizedBox(width: 4),
                          Text('执行中', style: TextStyle(fontSize: 10, color: HermesTheme.warning)),
                        ],
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: HermesTheme.accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_rounded, size: 11, color: HermesTheme.accent),
                          SizedBox(width: 3),
                          Text('已就绪', style: TextStyle(fontSize: 10, color: HermesTheme.accent)),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: HermesTheme.textDim),
                  ),
                ],
              ),
            ),
          ),

          // 核心内容区：指令入参
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tool.arguments.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'COMMAND / PARAMS',
                        style: TextStyle(
                          fontSize: 9,
                          fontFamily: 'monospace',
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.bold,
                          color: HermesTheme.textDim,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 12, color: HermesTheme.textDim),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: '复制入参指令',
                        onPressed: () => _copyText(tool.arguments, '工具入参'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF090B12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: HermesTheme.border),
                    ),
                    child: SelectableText(
                      tool.arguments,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Color(0xFF38BDF8), // Sky 400
                        height: 1.4,
                      ),
                    ),
                  ),
                ],

                // 折叠输出部分 (Output)
                if (tool.result != null && _expanded) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'STDOUT / EXECUTION OUTPUT',
                        style: TextStyle(
                          fontSize: 9,
                          fontFamily: 'monospace',
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.bold,
                          color: HermesTheme.textDim,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 12, color: HermesTheme.textDim),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: '复制执行结果',
                        onPressed: () => _copyText(tool.result!, '执行结果'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 220),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF07090F),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: HermesTheme.border),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        tool.result!.isEmpty ? '(无终端输出内容)' : tool.result!,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Color(0xFF4ADE80), // Terminal green
                          height: 1.4,
                        ),
                      ),
                    ),
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

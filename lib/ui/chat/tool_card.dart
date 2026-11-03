import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../models/chat_message.dart';
import 'ansi_terminal_view.dart';
import 'diff_card_view.dart';

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

  (IconData, Color, String) _getCategoryMeta(ToolCategory category) {
    switch (category) {
      case ToolCategory.subagent:
        return (Icons.smart_toy_rounded, const Color(0xFFC084FC), 'SUBAGENT');
      case ToolCategory.cron:
        return (Icons.schedule_rounded, const Color(0xFFFBBF24), 'CRON');
      case ToolCategory.daemon:
        return (Icons.memory_rounded, const Color(0xFF38BDF8), 'DAEMON');
      case ToolCategory.bash:
        return (Icons.terminal_rounded, HermesTheme.accent, 'BASH');
      case ToolCategory.python:
        return (Icons.code_rounded, HermesTheme.primaryLight, 'PYTHON');
      case ToolCategory.web:
        return (Icons.travel_explore_rounded, HermesTheme.primaryLight, 'WEB');
      case ToolCategory.io:
        return (Icons.folder_open_rounded, HermesTheme.accent, 'IO');
      case ToolCategory.system:
        return (Icons.settings_suggest_rounded, HermesTheme.textMuted, 'SYSTEM');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tool = widget.toolCall;
    final isRunning = tool.isRunning;
    final (icon, accentColor, categoryTag) = _getCategoryMeta(tool.category);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: HermesTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRunning
              ? accentColor.withOpacity(0.5)
              : HermesTheme.border,
          width: 1,
        ),
        boxShadow: isRunning
            ? [
                BoxShadow(
                  color: accentColor.withOpacity(0.08),
                  blurRadius: 8,
                  spreadRadius: 1,
                )
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 终端顶栏：工具名、分类徽标与状态指示
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF141A2B),
                borderRadius: BorderRadius.vertical(top: Radius.circular(11)),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 14, color: accentColor),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: accentColor.withOpacity(0.3), width: 0.6),
                    ),
                    child: Text(
                      categoryTag,
                      style: TextStyle(
                        fontSize: 9,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      tool.category == ToolCategory.subagent
                          ? '子智能体: ${tool.subagentRole}'
                          : (tool.category == ToolCategory.cron &&
                                  tool.cronSchedule.isNotEmpty
                              ? '定时任务: ${tool.cronSchedule}'
                              : tool.name),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5, color: accentColor),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            tool.category == ToolCategory.daemon
                                ? '后台运行中'
                                : '执行中',
                            style: TextStyle(
                                fontSize: 10, color: accentColor),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: HermesTheme.accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_rounded,
                              size: 11, color: HermesTheme.accent),
                          SizedBox(width: 3),
                          Text('已就绪',
                              style: TextStyle(
                                  fontSize: 10, color: HermesTheme.accent)),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        size: 16, color: HermesTheme.textDim),
                  ),
                ],
              ),
            ),
          ),

          // 核心内容区：指令入参与输出
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 入参栏
                if (tool.arguments.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        tool.category == ToolCategory.subagent
                            ? 'SUBAGENT INSTRUCTION'
                            : (tool.category == ToolCategory.cron
                                ? 'SCHEDULE CONFIG'
                                : 'COMMAND / PARAMS'),
                        style: const TextStyle(
                          fontSize: 9,
                          fontFamily: 'monospace',
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.bold,
                          color: HermesTheme.textDim,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded,
                            size: 12, color: HermesTheme.textDim),
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
                      color: const Color(0xFF090D16),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: HermesTheme.borderSubtle),
                    ),
                    child: SelectableText(
                      tool.category == ToolCategory.subagent
                          ? tool.subagentPrompt
                          : tool.arguments,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: HermesTheme.textMain,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],

                // Diff 代码补丁展示 或 执行输出日志
                if (tool.result != null && tool.result!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        tool.isDiff
                            ? 'GIT DIFF PATCH'
                            : (tool.category == ToolCategory.subagent
                                ? 'SUBAGENT REPORT'
                                : 'OUTPUT / RESULT'),
                        style: const TextStyle(
                          fontSize: 9,
                          fontFamily: 'monospace',
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.bold,
                          color: HermesTheme.textDim,
                        ),
                      ),
                      Row(
                        children: [
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(40, 20),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () =>
                                setState(() => _expanded = !_expanded),
                            child: Text(
                              _expanded ? '折叠' : '展开完整日志',
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: HermesTheme.primaryLight),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded,
                                size: 12, color: HermesTheme.textDim),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: '复制输出结果',
                            onPressed: () =>
                                _copyText(tool.result!, '执行结果'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (tool.isDiff)
                    DiffCardView(diffText: tool.result!)
                  else
                    AnsiTerminalView(
                      text: tool.result!,
                      maxLines: _expanded ? null : 6,
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

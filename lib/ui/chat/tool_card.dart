import 'dart:convert';
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
  bool _showRawJson = false;

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

  (IconData, Color) _getCategoryMeta(ToolCategory category) {
    switch (category) {
      case ToolCategory.subagent:
        return (Icons.smart_toy_rounded, const Color(0xFFC084FC));
      case ToolCategory.cron:
        return (Icons.schedule_rounded, const Color(0xFFFBBF24));
      case ToolCategory.daemon:
        return (Icons.memory_rounded, const Color(0xFF38BDF8));
      case ToolCategory.bash:
        return (Icons.terminal_rounded, HermesTheme.accent);
      case ToolCategory.python:
        return (Icons.code_rounded, HermesTheme.primaryLight);
      case ToolCategory.web:
        return (Icons.travel_explore_rounded, const Color(0xFF60A5FA));
      case ToolCategory.io:
        return (Icons.folder_open_rounded, const Color(0xFF34D399));
      case ToolCategory.system:
        return (Icons.settings_suggest_rounded, HermesTheme.textMuted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tool = widget.toolCall;
    final isRunning = tool.isRunning;
    final (icon, accentColor) = _getCategoryMeta(tool.category);
    final categoryName = tool.humanCategoryName;
    final summary = tool.humanActionSummary;
    final hasResult = tool.result != null && tool.result!.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: HermesTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isRunning
              ? accentColor.withOpacity(0.45)
              : HermesTheme.borderSubtle,
          width: 1,
        ),
        boxShadow: isRunning
            ? [
                BoxShadow(
                  color: accentColor.withOpacity(0.08),
                  blurRadius: 10,
                  spreadRadius: 1,
                )
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 顶部极简状态条 (Collapsed Header - 始终展示，轻量优雅)
          InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _expanded = !_expanded);
            },
            borderRadius: BorderRadius.circular(13),
            splashColor: accentColor.withOpacity(0.08),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  // 类别微图标
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: accentColor.withOpacity(0.25),
                        width: 0.8,
                      ),
                    ),
                    child: Icon(icon, size: 16, color: accentColor),
                  ),
                  const SizedBox(width: 10),

                  // 动作概要与分类名
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: HermesTheme.textMain,
                            letterSpacing: 0.1,
                          ),
                        ),
                        const SizedBox(height: 1.5),
                        Text(
                          categoryName,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: HermesTheme.textDim,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 状态胶囊 (运行中 / 已完成)
                  if (isRunning) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: accentColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 9,
                            height: 9,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: accentColor,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            tool.category == ToolCategory.daemon
                                ? '后台运行'
                                : '执行中',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: accentColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: HermesTheme.accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_rounded,
                              size: 11, color: HermesTheme.accent),
                          SizedBox(width: 3),
                          Text(
                            '完成',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: HermesTheme.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
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

          // 2. 展开后的技术详情 (惰性按需渲染：未展开时零构建开销，保证长列表 60fps 滑动)
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_expanded
                ? const SizedBox(width: double.infinity, height: 0)
                : Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: HermesTheme.borderSubtle,
                          width: 0.8,
                        ),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 指令内容呈现 (人性化终端栏)
                        if (tool.arguments.isNotEmpty) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '执行指令与参数',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: HermesTheme.textMuted,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy_rounded,
                                    size: 13, color: HermesTheme.textDim),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: '复制指令',
                                onPressed: () =>
                                    _copyText(tool.humanActionSummary, '指令'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0C101A),
                              borderRadius: BorderRadius.circular(9),
                              border:
                                  Border.all(color: HermesTheme.borderSubtle),
                            ),
                            child: SelectableText(
                              tool.humanActionSummary,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11.5,
                                color: HermesTheme.textMain,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],

                        // 产出展示：Diff 差异卡片 或 ANSI 终端日志
                        if (hasResult) ...[
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                tool.isDiff ? '代码变更对比 (Diff)' : '执行日志与输出',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: HermesTheme.textMuted,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy_rounded,
                                    size: 13, color: HermesTheme.textDim),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: '复制输出结果',
                                onPressed: () =>
                                    _copyText(tool.result!, '输出日志'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          if (tool.isDiff)
                            DiffCardView(diffText: tool.result!)
                          else
                            Container(
                              constraints: const BoxConstraints(maxHeight: 220),
                              child: SingleChildScrollView(
                                child: AnsiTerminalView(
                                  text: tool.result!,
                                  maxLines: null,
                                ),
                              ),
                            ),
                        ],

                        // 3. 底层 Raw JSON 调试参数 (渐进折叠收纳)
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () =>
                              setState(() => _showRawJson = !_showRawJson),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _showRawJson
                                      ? Icons.arrow_drop_down_rounded
                                      : Icons.arrow_right_rounded,
                                  size: 16,
                                  color: HermesTheme.textDim,
                                ),
                                Text(
                                  _showRawJson
                                      ? '收起底层参数 (JSON)'
                                      : '查看底层参数 (JSON)',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: HermesTheme.textDim,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        if (_showRawJson) ...[
                          const SizedBox(height: 4),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF080B12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: HermesTheme.borderSubtle
                                      .withOpacity(0.5)),
                            ),
                            child: SelectableText(
                              _prettifyJson(tool.arguments),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10,
                                color: HermesTheme.textMuted,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _prettifyJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(decoded);
    } catch (_) {
      return raw;
    }
  }
}

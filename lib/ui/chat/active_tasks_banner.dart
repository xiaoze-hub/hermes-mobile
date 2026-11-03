import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/chat_message.dart';

class ActiveTasksBanner extends StatefulWidget {
  final List<InflightTaskInfo> tasks;
  final VoidCallback onStopAll;
  final ValueChanged<InflightTaskInfo>? onInspectTask;

  const ActiveTasksBanner({
    super.key,
    required this.tasks,
    required this.onStopAll,
    this.onInspectTask,
  });

  @override
  State<ActiveTasksBanner> createState() => _ActiveTasksBannerState();
}

class _ActiveTasksBannerState extends State<ActiveTasksBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseAnim;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.tasks.isNotEmpty) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pulseAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tasks.isEmpty) return const SizedBox.shrink();

    final primary = widget.tasks.first;
    final count = widget.tasks.length;

    IconData icon;
    Color accentColor;
    String prefix;

    switch (primary.category) {
      case ToolCategory.subagent:
        icon = Icons.smart_toy_rounded;
        accentColor = const Color(0xFFC084FC); // Purple
        prefix = '子智能体协同中';
        break;
      case ToolCategory.cron:
        icon = Icons.schedule_rounded;
        accentColor = const Color(0xFFFBBF24); // Amber
        prefix = '定时计划任务执行中';
        break;
      case ToolCategory.daemon:
        icon = Icons.memory_rounded;
        accentColor = const Color(0xFF38BDF8); // Cyan
        prefix = '后台脚本常驻运行';
        break;
      default:
        icon = Icons.terminal_rounded;
        accentColor = HermesTheme.accent;
        prefix = '特工后台任务处理中';
        break;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF111728).withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withOpacity(0.5), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.12),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          // 呼吸动画状态点
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (context, _) => Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accentColor,
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withOpacity(0.7 * _pulseAnim.value),
                    blurRadius: 6,
                    spreadRadius: 2 * _pulseAnim.value,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          Icon(icon, size: 16, color: accentColor),
          const SizedBox(width: 8),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      prefix,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                      ),
                    ),
                    if (count > 1) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: accentColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '+$count 个',
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: accentColor),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      primary.elapsedFormatted,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        color: HermesTheme.textDim,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  primary.detail.isNotEmpty ? primary.detail : primary.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: HermesTheme.textMain,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // 终止按钮
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: HermesTheme.danger,
              side: const BorderSide(color: HermesTheme.danger, width: 0.8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(40, 26),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: widget.onStopAll,
            child: const Text('终止', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

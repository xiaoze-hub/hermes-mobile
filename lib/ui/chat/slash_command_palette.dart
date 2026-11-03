import 'package:flutter/material.dart';
import '../../core/theme.dart';

class SlashCommandItem {
  final String slash;
  final String label;
  final String description;
  final String prompt;
  final IconData icon;

  const SlashCommandItem({
    required this.slash,
    required this.label,
    required this.description,
    required this.prompt,
    required this.icon,
  });
}

class SlashCommandPalette extends StatelessWidget {
  final String query;
  final ValueChanged<SlashCommandItem> onSelect;

  static const List<SlashCommandItem> allCommands = [
    SlashCommandItem(
      slash: '/docker',
      label: 'Docker 容器巡检',
      description: '执行 docker ps 并检查是否有异常退出的容器',
      prompt: '请执行 docker ps -a 并分析当前容器健康状态，列出任何异常或未运行的容器。',
      icon: Icons.layers_rounded,
    ),
    SlashCommandItem(
      slash: '/top',
      label: 'CPU 负载排查',
      description: '分析当前 CPU 与高资源消耗的前 5 个进程',
      prompt: '请执行 top -b -n 1 并排查消耗 CPU 最多的前 5 个进程及系统负载。',
      icon: Icons.speed_rounded,
    ),
    SlashCommandItem(
      slash: '/memory',
      label: '内存与缓存占用',
      description: '执行 free -h 和 vmstat 查看内存是否充裕',
      prompt: '请执行 free -h 查看当前系统内存、Swap 占用，并评估是否存在内存泄漏。',
      icon: Icons.memory_rounded,
    ),
    SlashCommandItem(
      slash: '/disk',
      label: '磁盘空间余量',
      description: '执行 df -h 查看根分区和挂载点余量',
      prompt: '请执行 df -h 查看当前各个挂载分区的剩余磁盘空间，标出使用率超 80% 的分区。',
      icon: Icons.storage_rounded,
    ),
    SlashCommandItem(
      slash: '/git',
      label: 'Git 仓库状态',
      description: '查看当前分支与工作区未提交的文件变更',
      prompt: '请执行 git status 和 git log -n 3 --oneline，告诉我当前仓库的工作区状态。',
      icon: Icons.merge_type_rounded,
    ),
    SlashCommandItem(
      slash: '/diff',
      label: '审查代码补丁',
      description: '执行 git diff 审查工作区具体的代码改动',
      prompt: '请执行 git diff，详细审查并向我汇报所有文件的改动情况。',
      icon: Icons.difference_rounded,
    ),
    SlashCommandItem(
      slash: '/compact',
      label: '精炼压缩记忆',
      description: '总结之前关键决策并释放上下文 Token',
      prompt: '请将我们之前的关键决策、重要参数与系统状态总结提炼为一份精简备忘录，帮助压缩上下文，以便后续高效协作。',
      icon: Icons.auto_fix_high_rounded,
    ),
    SlashCommandItem(
      slash: '/cron',
      label: '定时计划任务',
      description: '查看或管理当前常驻系统的 Cron 计划',
      prompt: '请列出当前所有配置的定时计划任务（cron），并汇报各自的执行周期与状态。',
      icon: Icons.schedule_rounded,
    ),
    SlashCommandItem(
      slash: '/subagent',
      label: '派生协同子智能体',
      description: '启动独立的并行 Subagent 展开多维调研',
      prompt: '请派生一个子智能体（Subagent）并行调研该任务的技术方案，并向我汇报结论。',
      icon: Icons.smart_toy_rounded,
    ),
  ];

  const SlashCommandPalette({
    super.key,
    required this.query,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final lower = query.toLowerCase().trim();
    final filtered = allCommands.where((cmd) {
      if (lower.isEmpty || lower == '/') return true;
      return cmd.slash.toLowerCase().contains(lower) ||
          cmd.label.toLowerCase().contains(lower) ||
          cmd.description.toLowerCase().contains(lower);
    }).toList();

    if (filtered.isEmpty) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF111728),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: HermesTheme.primary.withOpacity(0.5), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题微栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF161F36),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: const Row(
              children: [
                Icon(Icons.terminal_rounded, size: 13, color: HermesTheme.accent),
                SizedBox(width: 6),
                Text(
                  'DESKTOP SLASH COMMAND PALETTE',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: HermesTheme.primaryLight,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),

          // 指令列表
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: filtered.length,
              separatorBuilder: (_, __) =>
                  const Divider(color: HermesTheme.borderSubtle, height: 1),
              itemBuilder: (ctx, idx) {
                final item = filtered[idx];
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(item.icon, size: 16, color: HermesTheme.accent),
                  title: Row(
                    children: [
                      Text(
                        item.slash,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: HermesTheme.primaryLight,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        item.label,
                        style: const TextStyle(
                          fontSize: 12,
                          color: HermesTheme.textMain,
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    item.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: HermesTheme.textDim,
                    ),
                  ),
                  onTap: () => onSelect(item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

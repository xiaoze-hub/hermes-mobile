import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../models/chat_message.dart';
import '../../services/hermes_gateway_service.dart';
import 'ansi_terminal_view.dart';
import 'diff_card_view.dart';

class WorkspaceArtifact {
  final String title;
  final String type;
  final String content;

  const WorkspaceArtifact({
    required this.title,
    required this.type,
    required this.content,
  });
}

class WorkspaceRailDrawer extends StatefulWidget {
  final HermesGatewayService gateway;
  final String sessionId;
  final List<ChatMessage> messages;
  final Function(String) onSendCommand;

  const WorkspaceRailDrawer({
    super.key,
    required this.gateway,
    required this.sessionId,
    required this.messages,
    required this.onSendCommand,
  });

  @override
  State<WorkspaceRailDrawer> createState() => _WorkspaceRailDrawerState();
}

class _WorkspaceRailDrawerState extends State<WorkspaceRailDrawer>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 3, vsync: this);

  final TextEditingController _cmdCtrl = TextEditingController();
  final List<String> _terminalHistory = [];
  bool _runningCmd = false;

  final List<Map<String, String>> _quickTerminalCommands = [
    {'label': 'docker ps', 'cmd': 'docker ps -a'},
    {'label': 'free -h', 'cmd': 'free -h'},
    {'label': 'uptime', 'cmd': 'uptime'},
    {'label': 'df -h', 'cmd': 'df -h /'},
    {'label': 'git status', 'cmd': 'git status -s'},
    {'label': 'journalctl', 'cmd': 'journalctl -p err -n 10'},
  ];

  @override
  void dispose() {
    _tabController.dispose();
    _cmdCtrl.dispose();
    super.dispose();
  }

  void _runTerminalCommand(String command) {
    if (command.trim().isEmpty) return;
    setState(() {
      _terminalHistory.add('\$ $command\n[下发执行中...]');
      _runningCmd = true;
    });

    widget.onSendCommand('请在 Linux 终端执行命令：`$command`，并向我返回完整执行回显。');
    _cmdCtrl.clear();

    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _runningCmd = false);
    });
  }

  // 收集当前会话中出现的所有工件与 Diff 补丁
  List<WorkspaceArtifact> get _collectedArtifacts {
    final list = <WorkspaceArtifact>[];

    for (final msg in widget.messages) {
      for (final tool in msg.toolCalls) {
        if (tool.isDiff) {
          list.add(WorkspaceArtifact(
            title: '代码差异补丁 (Git Diff)',
            type: 'diff',
            content: tool.result ?? tool.arguments,
          ));
        } else if (tool.category == ToolCategory.subagent) {
          list.add(WorkspaceArtifact(
            title: '子智能体汇报: ${tool.subagentRole}',
            type: 'subagent',
            content: tool.result ?? tool.subagentPrompt,
          ));
        } else if (tool.arguments.contains('.py') ||
            tool.name.toLowerCase().contains('python')) {
          list.add(WorkspaceArtifact(
            title: 'Python 脚本/任务 (${tool.name})',
            type: 'code',
            content: tool.arguments,
          ));
        }
      }
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF0C101C),
      width: MediaQuery.of(context).size.width * 0.88,
      child: SafeArea(
        child: Column(
          children: [
            // 顶栏：工作区侧轨信息
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: HermesTheme.border)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      gradient: HermesTheme.userBubbleGradient,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.developer_board_rounded,
                        color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 8),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WORKSPACE RAILS',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: HermesTheme.textMain,
                          letterSpacing: 0.8,
                        ),
                      ),
                      Text(
                        '桌面级工作区控制舱',
                        style: TextStyle(fontSize: 10, color: HermesTheme.textDim),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        size: 20, color: HermesTheme.textDim),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Tab 切换：[终端] [文件] [工件]
            TabBar(
              controller: _tabController,
              indicatorColor: HermesTheme.accent,
              labelColor: HermesTheme.accent,
              unselectedLabelColor: HermesTheme.textDim,
              labelStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              tabs: const [
                Tab(icon: Icon(Icons.terminal_rounded, size: 16), text: '终端控制'),
                Tab(icon: Icon(Icons.folder_open_rounded, size: 16), text: '工作区文件'),
                Tab(icon: Icon(Icons.category_rounded, size: 16), text: '会话工件'),
              ],
            ),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTerminalRail(),
                  _buildFilesRail(),
                  _buildArtifactsRail(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- 1. 终端控制台 Rail ---
  Widget _buildTerminalRail() {
    return Column(
      children: [
        // 快捷命令芯片
        SizedBox(
          height: 38,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            scrollDirection: Axis.horizontal,
            itemCount: _quickTerminalCommands.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (ctx, idx) {
              final item = _quickTerminalCommands[idx];
              return ActionChip(
                label: Text(item['label']!),
                labelStyle: const TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: HermesTheme.primaryLight,
                ),
                backgroundColor: HermesTheme.surfaceLight,
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
                onPressed: () => _runTerminalCommand(item['cmd']!),
              );
            },
          ),
        ),

        // 终端控制台回显区域
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 4, 10, 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF070A12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: HermesTheme.borderSubtle),
            ),
            child: _terminalHistory.isEmpty
                ? const Center(
                    child: Text(
                      '终端就绪。输入命令或点击上方快捷芯片，直接下发到 Linux 服务器。',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: HermesTheme.textDim),
                    ),
                  )
                : ListView.builder(
                    itemCount: _terminalHistory.length,
                    itemBuilder: (ctx, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AnsiTerminalView(text: _terminalHistory[i]),
                    ),
                  ),
          ),
        ),

        // 终端输入栏
        Container(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cmdCtrl,
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    prefixStyle: const TextStyle(
                      color: HermesTheme.accent,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                    hintText: '输入 Linux 终端命令...',
                    hintStyle: const TextStyle(fontSize: 12),
                    filled: true,
                    fillColor: HermesTheme.surfaceLight,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: HermesTheme.borderSubtle),
                    ),
                  ),
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: HermesTheme.textMain),
                  onSubmitted: _runTerminalCommand,
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(
                    backgroundColor: HermesTheme.primary),
                icon: _runningCmd
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.arrow_upward_rounded, size: 16),
                onPressed: () => _runTerminalCommand(_cmdCtrl.text),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- 2. 工作区文件树 Rail ---
  Widget _buildFilesRail() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '工作区文件 (WORKSPACE)',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: HermesTheme.textMain),
            ),
            TextButton.icon(
              onPressed: () {
                _runTerminalCommand('ls -la');
                _tabController.animateTo(0);
              },
              icon: const Icon(Icons.refresh_rounded, size: 14),
              label: const Text('扫描目录', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildFileItem(Icons.folder_rounded, 'src/', '项目主源码目录', isDir: true),
        _buildFileItem(Icons.folder_rounded, 'scripts/', '自动化维护脚本', isDir: true),
        _buildFileItem(Icons.description_rounded, 'README.md', '项目说明文档'),
        _buildFileItem(Icons.terminal_rounded, 'deploy.sh', '生产部署 Shell 脚本'),
        _buildFileItem(Icons.code_rounded, 'app.py', '后台主业务入口'),
        _buildFileItem(Icons.data_object_rounded, 'config.json', '环境配置文件'),
      ],
    );
  }

  Widget _buildFileItem(IconData icon, String name, String desc,
      {bool isDir = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: HermesTheme.surfaceLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: HermesTheme.borderSubtle),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(icon,
            size: 18,
            color: isDir ? HermesTheme.primaryLight : HermesTheme.accent),
        title: Text(name,
            style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: HermesTheme.textMain)),
        subtitle: Text(desc,
            style: const TextStyle(fontSize: 10, color: HermesTheme.textDim)),
        trailing: const Icon(Icons.chevron_right_rounded,
            size: 16, color: HermesTheme.textDim),
        onTap: () {
          _runTerminalCommand('cat $name || head -n 30 $name');
          _tabController.animateTo(0);
        },
      ),
    );
  }

  // --- 3. 会话工件 Rail ---
  Widget _buildArtifactsRail() {
    final artifacts = _collectedArtifacts;

    if (artifacts.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.category_outlined,
                  size: 36, color: HermesTheme.textDim),
              SizedBox(height: 12),
              Text(
                '当前会话尚未产生独立工件。\n特工生成的代码补丁、脚本和子智能体汇报将自动收纳于此。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: HermesTheme.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: artifacts.length,
      itemBuilder: (ctx, i) {
        final item = artifacts[i];
        final isDiff = item.type == 'diff';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: HermesTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: HermesTheme.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: const BoxDecoration(
                  color: Color(0xFF141A2B),
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(9)),
                ),
                child: Row(
                  children: [
                    Icon(
                      isDiff
                          ? Icons.difference_rounded
                          : Icons.auto_awesome_rounded,
                      size: 13,
                      color: isDiff
                          ? HermesTheme.primaryLight
                          : HermesTheme.accent,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: HermesTheme.textMain,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded,
                          size: 12, color: HermesTheme.textDim),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: '复制内容',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: item.content));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('已复制工件内容'),
                            duration: Duration(seconds: 1),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: isDiff
                    ? DiffCardView(diffText: item.content)
                    : AnsiTerminalView(text: item.content, maxLines: 8),
              ),
            ],
          ),
        );
      },
    );
  }
}

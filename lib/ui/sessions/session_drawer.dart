import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../models/session.dart';
import '../../services/hermes_gateway_service.dart';
import '../settings/app_update_screen.dart';

class SessionDrawer extends StatefulWidget {
  final HermesGatewayService gatewayService;
  final String? activeSessionId;
  final Function(HermesSession) onSelectSession;
  final VoidCallback onNewSession;

  const SessionDrawer({
    super.key,
    required this.gatewayService,
    required this.activeSessionId,
    required this.onSelectSession,
    required this.onNewSession,
  });

  @override
  State<SessionDrawer> createState() => _SessionDrawerState();
}

class _SessionDrawerState extends State<SessionDrawer> {
  List<HermesSession> _sessions = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.gatewayService.getSessions();
      setState(() => _sessions = list);
    } catch (e) {
      setState(() => _error = "同步会话失败: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteSession(HermesSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HermesTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除会话', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text('确定要删除会话「${session.title}」吗？云端历史也将被清空。', style: const TextStyle(fontSize: 13, color: HermesTheme.textMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: HermesTheme.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await widget.gatewayService.deleteSession(session.id);
        _loadSessions();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('删除失败: $e')));
        }
      }
    }
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes.clamp(1, 60)} 分钟前';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} 小时前';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} 天前';
    } else {
      return DateFormat('MM-dd HH:mm').format(dt);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: HermesTheme.background,
      child: SafeArea(
        child: Column(
          children: [
            // 抽屉头部：中枢信息与刷新
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: HermesTheme.userBubbleGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.hub_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Hermes Control Hub",
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: HermesTheme.textMain),
                      ),
                      Text(
                        "云端历史会话中枢",
                        style: TextStyle(fontSize: 10, color: HermesTheme.textDim),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 18, color: HermesTheme.textMuted),
                    tooltip: '刷新会话',
                    onPressed: _loading ? null : _loadSessions,
                  ),
                ],
              ),
            ),

            // 新建会话 Hero 按钮
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onNewSession();
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: HermesTheme.userBubbleGradient,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [HermesTheme.primaryGlow],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_rounded, size: 18, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        "开启全新会话",
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),
            const Divider(color: HermesTheme.border),

            // 会话列表
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: HermesTheme.primary))
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_error!, style: const TextStyle(fontSize: 12, color: HermesTheme.textDim), textAlign: TextAlign.center),
                                const SizedBox(height: 8),
                                OutlinedButton(onPressed: _loadSessions, child: const Text('重试', style: TextStyle(fontSize: 12))),
                              ],
                            ),
                          ),
                        )
                      : _sessions.isEmpty
                          ? const Center(
                              child: Text("暂无历史会话记录", style: TextStyle(color: HermesTheme.textDim, fontSize: 13)),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              itemCount: _sessions.length,
                              itemBuilder: (context, index) {
                                final session = _sessions[index];
                                final isSelected = session.id == widget.activeSessionId;

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  decoration: BoxDecoration(
                                    color: isSelected ? HermesTheme.surfaceLight : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected ? HermesTheme.primary.withOpacity(0.5) : Colors.transparent,
                                      width: 1,
                                    ),
                                  ),
                                  child: ListTile(
                                    dense: true,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                    leading: Icon(
                                      isSelected ? Icons.chat_bubble_rounded : Icons.chat_bubble_outline_rounded,
                                      size: 16,
                                      color: isSelected ? HermesTheme.primary : HermesTheme.textDim,
                                    ),
                                    title: Text(
                                      session.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                        color: isSelected ? HermesTheme.textMain : HermesTheme.textMuted,
                                      ),
                                    ),
                                    subtitle: Text(
                                      _formatDate(session.updatedAt),
                                      style: const TextStyle(fontSize: 10, color: HermesTheme.textDim),
                                    ),
                                    trailing: PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_horiz_rounded, size: 16, color: HermesTheme.textDim),
                                      padding: EdgeInsets.zero,
                                      color: HermesTheme.surfaceElevated,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      onSelected: (val) {
                                        if (val == 'delete') {
                                          _deleteSession(session);
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: 'delete',
                                          height: 36,
                                          child: Row(
                                            children: [
                                              Icon(Icons.delete_outline_rounded, size: 15, color: HermesTheme.danger),
                                              SizedBox(width: 8),
                                              Text('删除会话', style: TextStyle(fontSize: 12, color: HermesTheme.danger)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    onTap: () {
                                      Navigator.of(context).pop();
                                      widget.onSelectSession(session);
                                    },
                                  ),
                                );
                              },
                            ),
            ),
            const Divider(color: HermesTheme.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: ListTile(
                dense: true,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                leading: const Icon(Icons.system_update_alt_rounded, size: 16, color: HermesTheme.accent),
                title: const Text('App 版本与在线更新', style: TextStyle(fontSize: 12.5, color: HermesTheme.textMuted)),
                trailing: const Icon(Icons.chevron_right_rounded, size: 16, color: HermesTheme.textDim),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AppUpdateScreen()));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

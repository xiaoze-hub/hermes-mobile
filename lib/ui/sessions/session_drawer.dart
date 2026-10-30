import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/session.dart';
import '../../services/hermes_gateway_service.dart';

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
  String _query = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _loading = true);
    try {
      final list = await widget.gatewayService.getSessions();
      if (mounted) {
        setState(() {
          _sessions = list;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: HermesTheme.background,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(
                children: [
                  const Icon(Icons.forum_outlined,
                      color: HermesTheme.primary, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    "云端历史会话",
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: HermesTheme.textMain),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh,
                        size: 18, color: HermesTheme.textMuted),
                    onPressed: _loadSessions,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onNewSession();
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text("新建对话", style: TextStyle(fontSize: 13)),
                style: FilledButton.styleFrom(
                  backgroundColor: HermesTheme.surfaceLight,
                  minimumSize: const Size.fromHeight(40),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: TextField(
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search), hintText: '搜索对话'),
              ),
            ),
            const Divider(color: HermesTheme.border, height: 20),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: HermesTheme.primary))
                  : _error != null
                      ? Center(
                          child: TextButton(
                              onPressed: _loadSessions,
                              child: const Text('加载失败，点击重试')))
                      : _sessions
                              .where(
                                  (s) => s.title.toLowerCase().contains(_query))
                              .isEmpty
                          ? const Center(
                              child: Text("没有找到对话",
                                  style: TextStyle(
                                      color: HermesTheme.textMuted,
                                      fontSize: 13)))
                          : ListView.builder(
                              itemCount: _sessions
                                  .where((s) =>
                                      s.title.toLowerCase().contains(_query))
                                  .length,
                              itemBuilder: (context, index) {
                                final session = _sessions
                                    .where((s) =>
                                        s.title.toLowerCase().contains(_query))
                                    .toList()[index];
                                final isSelected =
                                    session.id == widget.activeSessionId;

                                return ListTile(
                                  selected: isSelected,
                                  selectedTileColor: HermesTheme.surfaceLight,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 2),
                                  leading: Icon(
                                    Icons.chat_bubble_outline,
                                    size: 16,
                                    color: isSelected
                                        ? HermesTheme.primary
                                        : HermesTheme.textMuted,
                                  ),
                                  title: Text(
                                    session.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      color: isSelected
                                          ? HermesTheme.textMain
                                          : HermesTheme.textMuted,
                                    ),
                                  ),
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    widget.onSelectSession(session);
                                  },
                                  trailing: PopupMenuButton<String>(
                                    tooltip: '会话操作',
                                    icon: const Icon(Icons.more_horiz,
                                        size: 19, color: HermesTheme.textMuted),
                                    onSelected: (action) async {
                                      if (action != 'delete') return;
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: const Text('删除这条对话？'),
                                          content: Text(
                                              '“${session.title}”将从网关历史中删除。此操作无法撤销。'),
                                          actions: [
                                            TextButton(
                                                onPressed: () => Navigator.pop(
                                                    context, false),
                                                child: const Text('取消')),
                                            FilledButton(
                                                onPressed: () => Navigator.pop(
                                                    context, true),
                                                child: const Text('删除')),
                                          ],
                                        ),
                                      );
                                      if (confirmed != true) return;
                                      try {
                                        await widget.gatewayService
                                            .deleteSession(session.id);
                                        if (!context.mounted) return;
                                        setState(() => _sessions.removeWhere(
                                            (item) => item.id == session.id));
                                        if (session.id ==
                                            widget.activeSessionId) {
                                          Navigator.of(context).pop();
                                          widget.onNewSession();
                                        }
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(const SnackBar(
                                                content: Text('对话已删除')));
                                      } catch (error) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(SnackBar(
                                                  content:
                                                      Text('删除失败：$error')));
                                        }
                                      }
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(
                                          value: 'delete', child: Text('删除对话')),
                                    ],
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

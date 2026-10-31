import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/session.dart';
import '../../services/hermes_gateway_service.dart';

class SessionDrawer extends StatefulWidget {
  final HermesGatewayService gatewayService;
  final String? activeSessionId;
  final Function(HermesSession) onSelectSession;
  final Function(HermesSession)? onSessionRenamed;
  final VoidCallback onNewSession;

  const SessionDrawer({
    super.key,
    required this.gatewayService,
    required this.activeSessionId,
    required this.onSelectSession,
    this.onSessionRenamed,
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
  List<HermesSession>? _searchResults;
  bool _searching = false;
  bool _titleOnlyFallback = false;
  Timer? _searchDebounce;
  int _searchRequest = 0;

  List<HermesSession> get _matchingSessions {
    final results = _searchResults;
    if (_query.length >= 2 && results != null) return results;
    final normalizedQuery = _query.toLowerCase();
    return _sessions
        .where(
            (session) => session.title.toLowerCase().contains(normalizedQuery))
        .toList();
  }

  void _onSearchChanged(String value) {
    final query = value.trim();
    final request = ++_searchRequest;
    _searchDebounce?.cancel();
    setState(() {
      _query = query;
      _searchResults = null;
      _searching = false;
      _titleOnlyFallback = false;
    });
    if (query.length < 2) return;

    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted || request != _searchRequest) return;
      setState(() => _searching = true);
      try {
        final results = await widget.gatewayService.searchSessions(query);
        if (!mounted || request != _searchRequest) return;
        setState(() {
          _searchResults = results;
          _titleOnlyFallback = results == null;
          _searching = false;
        });
      } catch (_) {
        if (!mounted || request != _searchRequest) return;
        setState(() {
          _titleOnlyFallback = true;
          _searching = false;
        });
      }
    });
  }

  List<({String? section, HermesSession? session})> get _visibleRows {
    final filtered = _matchingSessions;
    final grouped = <String, List<HermesSession>>{};
    for (final session in filtered) {
      grouped
          .putIfAbsent(_sectionFor(session.updatedAt), () => [])
          .add(session);
    }

    final rows = <({String? section, HermesSession? session})>[];
    for (final entry in grouped.entries) {
      rows.add((section: entry.key, session: null));
      for (final session in entry.value) {
        rows.add((section: null, session: session));
      }
    }
    return rows;
  }

  String _sectionFor(DateTime updatedAt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final localDate = updatedAt.toLocal();
    final date = DateTime(localDate.year, localDate.month, localDate.day);
    final daysAgo = today.difference(date).inDays;
    if (daysAgo <= 0) return '今天';
    if (daysAgo == 1) return '昨天';
    if (daysAgo < 7) return '过去 7 天';
    if (daysAgo < 30) return '过去 30 天';
    return '${date.year} 年 ${date.month} 月';
  }

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

  Future<void> _renameSession(HermesSession session) async {
    final controller = TextEditingController(text: session.title);
    final requestedTitle = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重命名对话'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: '对话名称'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    final title = requestedTitle?.trim();
    if (title == null || title.isEmpty || title == session.title || !mounted) {
      return;
    }

    try {
      await widget.gatewayService.renameSession(session.id, title);
      if (!mounted) return;
      final renamed = HermesSession(
        id: session.id,
        title: title,
        preview: session.preview,
        updatedAt: session.updatedAt,
      );
      setState(() {
        final index = _sessions.indexWhere((item) => item.id == session.id);
        if (index >= 0) _sessions[index] = renamed;
        final searchIndex =
            _searchResults?.indexWhere((item) => item.id == session.id);
        if (searchIndex != null && searchIndex >= 0) {
          _searchResults![searchIndex] = renamed;
        }
      });
      widget.onSessionRenamed?.call(renamed);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('对话名称已更新')),
      );
    } catch (error) {
      if (!mounted) return;
      final unsupported =
          error.toString().contains('404') || error.toString().contains('405');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(unsupported ? '当前网关版本暂不支持重命名对话' : '重命名未成功，请检查网关连接后重试'),
      ));
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visibleRows = _visibleRows;
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
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: '搜索对话和消息',
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _query.isNotEmpty
                          ? IconButton(
                              tooltip: '清除搜索',
                              onPressed: () => _onSearchChanged(''),
                              icon: const Icon(Icons.close),
                            )
                          : null,
                ),
              ),
            ),
            if (_titleOnlyFallback && _query.length >= 2)
              const Padding(
                padding: EdgeInsets.fromLTRB(18, 0, 18, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '当前网关不支持消息内容搜索，已按标题筛选',
                    style:
                        TextStyle(color: HermesTheme.textMuted, fontSize: 11),
                  ),
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
                      : visibleRows.isEmpty
                          ? const Center(
                              child: Text("没有找到对话",
                                  style: TextStyle(
                                      color: HermesTheme.textMuted,
                                      fontSize: 13)))
                          : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 20),
                              itemCount: visibleRows.length,
                              itemBuilder: (context, index) {
                                final row = visibleRows[index];
                                if (row.section != null) {
                                  return Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 18, 16, 6),
                                    child: Text(
                                      row.section!,
                                      style: const TextStyle(
                                        color: HermesTheme.textMuted,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  );
                                }
                                final session = row.session!;
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
                                  subtitle: _query.length >= 2 &&
                                          session.preview.isNotEmpty
                                      ? Text(
                                          session.preview,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: HermesTheme.textMuted,
                                            fontSize: 11,
                                          ),
                                        )
                                      : null,
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    widget.onSelectSession(session);
                                  },
                                  trailing: PopupMenuButton<String>(
                                    tooltip: '会话操作',
                                    icon: const Icon(Icons.more_horiz,
                                        size: 19, color: HermesTheme.textMuted),
                                    onSelected: (action) async {
                                      if (action == 'rename') {
                                        await _renameSession(session);
                                        return;
                                      }
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
                                          value: 'rename', child: Text('重命名')),
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

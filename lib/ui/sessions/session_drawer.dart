import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../models/session.dart';
import '../../services/hermes_gateway_service.dart';
import '../settings/app_update_screen.dart';
import '../settings/system_settings_screen.dart';

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
  final HermesStorage _storage = HermesStorage();
  List<HermesSession> _sessions = [];
  bool _loading = false;
  String _query = '';
  String? _error;
  List<HermesSession>? _searchResults;
  bool _searching = false;
  Timer? _searchDebounce;
  int _searchRequest = 0;

  Set<String> _pinnedIds = {};
  Map<String, List<String>> _sessionTags = {};
  String _selectedTag = '全部';
  final List<String> _commonTags = ['全部', '运维', '代码', '研究', '日常'];

  List<HermesSession> get _matchingSessions {
    final results = _searchResults;
    List<HermesSession> list;
    if (_query.length >= 2 && results != null) {
      list = results;
    } else {
      final normalizedQuery = _query.toLowerCase();
      list = _sessions
          .where((s) => s.title.toLowerCase().contains(normalizedQuery))
          .toList();
    }

    if (_selectedTag != '全部') {
      list = list.where((s) {
        final tags = _sessionTags[s.id] ?? [];
        return tags.contains(_selectedTag);
      }).toList();
    }

    return list;
  }

  void _onSearchChanged(String value) {
    final query = value.trim();
    final request = ++_searchRequest;
    _searchDebounce?.cancel();
    setState(() {
      _query = query;
      _searchResults = null;
      _searching = false;
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
          _searching = false;
        });
      } catch (_) {
        if (!mounted || request != _searchRequest) return;
        setState(() {
          _searching = false;
        });
      }
    });
  }

  List<({String? section, HermesSession? session})> get _visibleRows {
    final filtered = _matchingSessions;
    final rows = <({String? section, HermesSession? session})>[];

    // 置顶会话优先
    final pinned = filtered.where((s) => _pinnedIds.contains(s.id)).toList();
    final unpinned = filtered.where((s) => !_pinnedIds.contains(s.id)).toList();

    if (pinned.isNotEmpty) {
      rows.add((section: '📌 置顶任务会话', session: null));
      for (final session in pinned) {
        rows.add((section: null, session: session));
      }
    }

    final grouped = <String, List<HermesSession>>{};
    for (final session in unpinned) {
      grouped
          .putIfAbsent(_sectionFor(session.updatedAt), () => [])
          .add(session);
    }

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
    _loadCustomizations();
    _loadSessions();
  }

  Future<void> _loadCustomizations() async {
    final pinned = await _storage.getPinnedSessionIds();
    final tags = await _storage.getAllSessionTags();
    if (mounted) {
      setState(() {
        _pinnedIds = pinned;
        _sessionTags = tags;
      });
    }
  }

  Future<void> _togglePin(HermesSession session) async {
    await _storage.togglePinSession(session.id);
    await _loadCustomizations();
  }

  Future<void> _manageTags(HermesSession session) async {
    final current = List<String>.from(_sessionTags[session.id] ?? []);
    final available = ['运维', '代码', '研究', '日常', '高优'];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: HermesTheme.surfaceElevated,
          title: const Text('管理会话标签',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          content: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: available.map((tag) {
              final active = current.contains(tag);
              return FilterChip(
                label: Text('#$tag'),
                selected: active,
                onSelected: (val) {
                  setModalState(() {
                    if (val) {
                      current.add(tag);
                    } else {
                      current.remove(tag);
                    }
                  });
                },
                selectedColor: HermesTheme.primary.withOpacity(0.3),
                checkmarkColor: HermesTheme.primaryLight,
              );
            }).toList(),
          ),
          actions: [
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: HermesTheme.primary),
              onPressed: () async {
                Navigator.pop(ctx);
                await _storage.setSessionTags(session.id, current);
                await _loadCustomizations();
              },
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.gatewayService.getSessions();
      if (mounted) {
        setState(() {
          _sessions = list;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = "同步会话失败: $error");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _renameSession(HermesSession session) async {
    final controller = TextEditingController(text: session.title);
    final requestedTitle = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: HermesTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('重命名任务会话',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: '会话标题',
            hintText: '输入新会话名称...',
          ),
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
            style: FilledButton.styleFrom(backgroundColor: HermesTheme.primary),
            child: const Text('保存修改'),
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
      final updated = HermesSession(
        id: session.id,
        title: title,
        updatedAt: DateTime.now(),
      );
      setState(() {
        final index = _sessions.indexWhere((s) => s.id == session.id);
        if (index != -1) _sessions[index] = updated;
        final searchIdx =
            _searchResults?.indexWhere((s) => s.id == session.id) ?? -1;
        if (searchIdx != -1) _searchResults![searchIdx] = updated;
      });
      widget.onSessionRenamed?.call(updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('重命名失败: $e')));
      }
    }
  }

  Future<void> _deleteSession(HermesSession session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HermesTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除会话',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text(
          '确定要删除会话「${session.title}」吗？云端任务历史记录也将被彻底清空。',
          style: const TextStyle(fontSize: 13, color: HermesTheme.textMuted),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: HermesTheme.danger),
            child: const Text('彻底删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await widget.gatewayService.deleteSession(session.id);
        if (!mounted) return;
        setState(() {
          _sessions.removeWhere((s) => s.id == session.id);
          _searchResults?.removeWhere((s) => s.id == session.id);
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('删除失败: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleRows = _visibleRows;

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
                    child: const Icon(Icons.hub_rounded,
                        color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Hermes Control Hub",
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: HermesTheme.textMain),
                      ),
                      Text(
                        "特工中枢 · 历史会话检索",
                        style: TextStyle(fontSize: 10, color: HermesTheme.textDim),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: HermesTheme.primary),
                          )
                        : const Icon(Icons.refresh_rounded,
                            size: 18, color: HermesTheme.textMuted),
                    tooltip: '刷新会话',
                    onPressed: _loading ? null : _loadSessions,
                  ),
                ],
              ),
            ),

            // 新建会话 Hero 按钮
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
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
                        "开启全新任务会话",
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 搜索输入框
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              child: TextField(
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: '搜索历史指令与会话...',
                  prefixIcon: const Icon(Icons.search_rounded,
                      size: 18, color: HermesTheme.textDim),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.8, color: HermesTheme.primary),
                          ),
                        )
                      : _query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  size: 16, color: HermesTheme.textDim),
                              onPressed: () => _onSearchChanged(''),
                            )
                          : null,
                  filled: true,
                  fillColor: HermesTheme.surfaceLight,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: HermesTheme.borderSubtle),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: HermesTheme.borderSubtle),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                        color: HermesTheme.primary, width: 1.2),
                  ),
                ),
                style:
                    const TextStyle(fontSize: 13, color: HermesTheme.textMain),
              ),
            ),

            // 标签快捷筛选栏
            SizedBox(
              height: 32,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                scrollDirection: Axis.horizontal,
                itemCount: _commonTags.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (ctx, idx) {
                  final tag = _commonTags[idx];
                  final isSelected = _selectedTag == tag;

                  return ChoiceChip(
                    label: Text(tag == '全部' ? '全部' : '#$tag'),
                    selected: isSelected,
                    onSelected: (val) {
                      if (val) setState(() => _selectedTag = tag);
                    },
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected
                          ? HermesTheme.primaryLight
                          : HermesTheme.textDim,
                    ),
                    backgroundColor: HermesTheme.surfaceLight,
                    selectedColor: HermesTheme.primary.withOpacity(0.25),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  );
                },
              ),
            ),

            const SizedBox(height: 6),
            const Divider(color: HermesTheme.border, height: 1),

            // 会话列表
            Expanded(
              child: _loading && _sessions.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: HermesTheme.primary))
                  : _error != null && _sessions.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_error!,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: HermesTheme.textDim),
                                    textAlign: TextAlign.center),
                                const SizedBox(height: 8),
                                OutlinedButton(
                                    onPressed: _loadSessions,
                                    child: const Text('重试',
                                        style: TextStyle(fontSize: 12))),
                              ],
                            ),
                          ),
                        )
                      : visibleRows.isEmpty
                          ? Center(
                              child: Text(
                                _query.isNotEmpty
                                    ? "没有找到符合条件的会话"
                                    : "暂无历史会话记录",
                                style: const TextStyle(
                                    color: HermesTheme.textDim, fontSize: 13),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
                              itemCount: visibleRows.length,
                              itemBuilder: (context, index) {
                                final row = visibleRows[index];

                                // 日期或置顶分组标签
                                if (row.section != null) {
                                  final isPinnedSection =
                                      row.section!.contains('置顶');
                                  return Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(12, 12, 12, 4),
                                    child: Text(
                                      row.section!,
                                      style: TextStyle(
                                        color: isPinnedSection
                                            ? const Color(0xFFFBBF24)
                                            : HermesTheme.textDim,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  );
                                }

                                final session = row.session!;
                                final isSelected =
                                    session.id == widget.activeSessionId;
                                final isPinned =
                                    _pinnedIds.contains(session.id);
                                final tags = _sessionTags[session.id] ?? [];

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 4),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? HermesTheme.surfaceLight
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected
                                          ? HermesTheme.primary.withOpacity(0.5)
                                          : Colors.transparent,
                                      width: 1,
                                    ),
                                  ),
                                  child: ListTile(
                                    dense: true,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    contentPadding:
                                        const EdgeInsets.only(left: 10, right: 4),
                                    leading: isPinned
                                        ? const Icon(Icons.push_pin_rounded,
                                            size: 16, color: Color(0xFFFBBF24))
                                        : Icon(
                                            isSelected
                                                ? Icons.terminal_rounded
                                                : Icons.chat_bubble_outline_rounded,
                                            size: 16,
                                            color: isSelected
                                                ? HermesTheme.accent
                                                : HermesTheme.textMuted,
                                          ),
                                    title: Text(
                                      session.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isSelected || isPinned
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                        color: isSelected
                                            ? HermesTheme.textMain
                                            : HermesTheme.textMuted,
                                      ),
                                    ),
                                    subtitle: tags.isNotEmpty
                                        ? Padding(
                                            padding:
                                                const EdgeInsets.only(top: 2),
                                            child: Wrap(
                                              spacing: 4,
                                              children: tags.map((t) {
                                                return Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                          horizontal: 4,
                                                          vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: HermesTheme.primary
                                                        .withOpacity(0.15),
                                                    borderRadius:
                                                        BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    '#$t',
                                                    style: const TextStyle(
                                                        fontSize: 9,
                                                        color: HermesTheme
                                                            .primaryLight),
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                          )
                                        : null,
                                    trailing: PopupMenuButton<String>(
                                      tooltip: '会话操作',
                                      icon: const Icon(Icons.more_horiz_rounded,
                                          size: 18,
                                          color: HermesTheme.textDim),
                                      color: HermesTheme.surfaceElevated,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      onSelected: (action) {
                                        if (action == 'pin') {
                                          _togglePin(session);
                                        } else if (action == 'tags') {
                                          _manageTags(session);
                                        } else if (action == 'rename') {
                                          _renameSession(session);
                                        } else if (action == 'delete') {
                                          _deleteSession(session);
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        PopupMenuItem(
                                          value: 'pin',
                                          height: 38,
                                          child: Row(
                                            children: [
                                              Icon(
                                                isPinned
                                                    ? Icons.push_pin_outlined
                                                    : Icons.push_pin_rounded,
                                                size: 16,
                                                color: const Color(0xFFFBBF24),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(isPinned ? '取消置顶' : '置顶此会话',
                                                  style: const TextStyle(
                                                      fontSize: 13,
                                                      color:
                                                          HermesTheme.textMain)),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'tags',
                                          height: 38,
                                          child: Row(
                                            children: [
                                              Icon(Icons.label_outline_rounded,
                                                  size: 16,
                                                  color: HermesTheme.accent),
                                              SizedBox(width: 8),
                                              Text('设置会话标签',
                                                  style: TextStyle(
                                                      fontSize: 13,
                                                      color:
                                                          HermesTheme.textMain)),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'rename',
                                          height: 38,
                                          child: Row(
                                            children: [
                                              Icon(Icons.edit_rounded,
                                                  size: 16,
                                                  color: HermesTheme.textMuted),
                                              SizedBox(width: 8),
                                              Text('重命名会话',
                                                  style: TextStyle(
                                                      fontSize: 13,
                                                      color:
                                                          HermesTheme.textMain)),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          height: 38,
                                          child: Row(
                                            children: [
                                              Icon(Icons.delete_outline_rounded,
                                                  size: 16,
                                                  color: HermesTheme.danger),
                                              SizedBox(width: 8),
                                              Text('删除此会话',
                                                  style: TextStyle(
                                                      fontSize: 13,
                                                      color:
                                                          HermesTheme.danger)),
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

            // 抽屉底部：统一系统设置与控制中枢入口
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFF0F1424),
                border: Border(top: BorderSide(color: HermesTheme.border)),
              ),
              child: ListTile(
                dense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: HermesTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: HermesTheme.borderSubtle),
                  ),
                  child: const Icon(Icons.settings_rounded,
                      size: 18, color: HermesTheme.primaryLight),
                ),
                title: const Text('系统设置与控制中枢',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: HermesTheme.textMain)),
                subtitle: const Text('网关集群 · 特工管控 · 固件版本',
                    style: TextStyle(fontSize: 10.5, color: HermesTheme.textDim)),
                trailing: const Icon(Icons.chevron_right_rounded,
                    size: 18, color: HermesTheme.textDim),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SystemSettingsScreen(
                        gateway: widget.gatewayService,
                      ),
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

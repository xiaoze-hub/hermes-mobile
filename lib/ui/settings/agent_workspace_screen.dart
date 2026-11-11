import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../services/hermes_gateway_service.dart';

class AgentWorkspaceScreen extends StatefulWidget {
  final HermesGatewayService gateway;
  final String sessionId;
  const AgentWorkspaceScreen({super.key, required this.gateway, required this.sessionId});

  @override
  State<AgentWorkspaceScreen> createState() => _AgentWorkspaceScreenState();
}

class _AgentWorkspaceScreenState extends State<AgentWorkspaceScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);
  final HermesStorage _storage = HermesStorage();
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _toolsets = [];
  List<Map<String, dynamic>> _jobs = [];
  Map<String, dynamic> _context = {};
  Map<String, dynamic> _skills = {};
  List<Map<String, dynamic>> _memories = [];
  String _memoryFilter = 'all';
  final _skillQuery = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _skillQuery.dispose();
    super.dispose();
  }

  Future<dynamic> _rpc(String method, Map<String, dynamic> params) => widget.gateway.callRpc(method, params);

  Future<dynamic> _fetchCronJobs() async {
    try {
      final res = await _rpc('cron.manage', {'action': 'list'});
      if (res is Map || res is List) return res;
    } catch (_) {}
    try {
      final res = await _rpc('cronjob_manage', {'action': 'list'});
      if (res is Map || res is List) return res;
    } catch (_) {}
    try {
      final res = await _rpc('cron.list', {});
      if (res is Map || res is List) return res;
    } catch (_) {}
    return {'jobs': []};
  }

  Future<void> _refresh() async {
    final localMemories = await _storage.getMemoryEntries();
    if (mounted) {
      setState(() => _memories = localMemories);
    }

    if (!widget.gateway.supportsJsonRpc || widget.sessionId.isEmpty) {
      setState(() => _error = '当前会话未连接到支持 JSON-RPC 的 Hermes 网关。请升级网关并重新连接后使用 Agent 管理功能。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final results = await Future.wait([
      _rpc('tools.list', {'session_id': widget.sessionId}),
      _fetchCronJobs(),
      _rpc('session.context_breakdown', {'session_id': widget.sessionId}),
      _rpc('skills.manage', {'action': 'list'}),
      _fetchRemoteMemories(),
    ].map((future) async {
      try {
        return await future;
      } catch (e) {
        return {'_error': e.toString()};
      }
    }));
    if (!mounted) return;
    setState(() {
      final tools = results[0];
      _toolsets = tools is Map && tools['toolsets'] is List
          ? List<Map<String, dynamic>>.from((tools['toolsets'] as List).whereType<Map>())
          : [];
      final cron = results[1];
      List<Map<String, dynamic>> extractedJobs = [];
      if (cron is List) {
        extractedJobs = List<Map<String, dynamic>>.from(cron.whereType<Map>());
      } else if (cron is Map) {
        final list = cron['jobs'] ?? cron['cron_jobs'] ?? cron['tasks'] ?? cron['data'];
        if (list is List) {
          extractedJobs = List<Map<String, dynamic>>.from(list.whereType<Map>());
        }
      }
      _jobs = extractedJobs;
      _context = results[2] is Map ? Map<String, dynamic>.from(results[2] as Map) : {};
      _skills = results[3] is Map ? Map<String, dynamic>.from(results[3] as Map) : {};
      final remoteMem = results[4];
      if (remoteMem is List && remoteMem.isNotEmpty) {
        _memories = List<Map<String, dynamic>>.from(remoteMem.whereType<Map>());
        _storage.saveMemoryEntries(_memories).catchError((_) {});
      }
      final errors = results.take(4).whereType<Map>().map((r) => r['_error']).whereType<String>().toList();
      if (errors.length == 4) _error = '此网关版本尚未开放 Agent 管理方法。\n${errors.first}';
      _busy = false;
    });
  }

  Future<List<Map<String, dynamic>>> _fetchRemoteMemories() async {
    try {
      final res = await _rpc('memory.manage', {'action': 'list'});
      if (res is Map && res['entries'] is List) {
        return (res['entries'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      if (res is List) {
        return res
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<void> _addOrEditMemory({Map<String, dynamic>? existing}) async {
    String selectedTarget = existing?['target']?.toString() ?? 'memory';
    final controller = TextEditingController(
      text: existing?['content']?.toString() ?? '',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: HermesTheme.surfaceElevated,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            existing == null ? '新增长期记忆条目' : '编辑长期记忆条目',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: HermesTheme.textMain,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '存储目标文件',
                  style: TextStyle(fontSize: 12, color: HermesTheme.textMuted),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('MEMORY.md (环境记忆)'),
                        selected: selectedTarget == 'memory',
                        onSelected: (_) =>
                            setModalState(() => selectedTarget = 'memory'),
                        selectedColor: HermesTheme.primary.withOpacity(0.25),
                        labelStyle: TextStyle(
                          fontSize: 11.5,
                          color: selectedTarget == 'memory'
                              ? HermesTheme.primaryLight
                              : HermesTheme.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('USER.md (用户画像)'),
                        selected: selectedTarget == 'user',
                        onSelected: (_) =>
                            setModalState(() => selectedTarget = 'user'),
                        selectedColor: HermesTheme.accent.withOpacity(0.2),
                        labelStyle: TextStyle(
                          fontSize: 11.5,
                          color: selectedTarget == 'user'
                              ? HermesTheme.accent
                              : HermesTheme.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 6,
                  style: const TextStyle(fontSize: 13, color: HermesTheme.textMain),
                  decoration: const InputDecoration(
                    labelText: '记忆内容',
                    hintText: '如: 生产数据库运行在 10.0.1.15:5432，备份目录为 /data/backup...',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: HermesTheme.primary),
              child: const Text('保存并同步'),
            ),
          ],
        ),
      ),
    );

    final text = controller.text.trim();
    controller.dispose();
    if (confirmed != true || text.isEmpty) return;

    final updatedList = List<Map<String, dynamic>>.from(_memories);
    if (existing != null) {
      final idx = updatedList.indexWhere((e) => e['id'] == existing['id']);
      final newEntry = {
        ...existing,
        'target': selectedTarget,
        'content': text,
        'updatedAt': DateTime.now().toIso8601String(),
      };
      if (idx >= 0) {
        updatedList[idx] = newEntry;
      } else {
        updatedList.insert(0, newEntry);
      }
      try {
        await _rpc('memory.manage', {
          'action': 'replace',
          'target': selectedTarget,
          'old_text': existing['content'],
          'content': text,
        });
      } catch (_) {}
    } else {
      final newEntry = {
        'id': 'mem_${DateTime.now().millisecondsSinceEpoch}',
        'target': selectedTarget,
        'content': text,
        'updatedAt': DateTime.now().toIso8601String(),
      };
      updatedList.insert(0, newEntry);
      try {
        await _rpc('memory.manage', {
          'action': 'add',
          'target': selectedTarget,
          'content': text,
        });
      } catch (_) {}
    }

    await _storage.saveMemoryEntries(updatedList);
    if (mounted) {
      HapticFeedback.lightImpact();
      setState(() => _memories = updatedList);
    }
  }

  Future<void> _deleteMemory(Map<String, dynamic> entry) async {
    final updated = List<Map<String, dynamic>>.from(_memories)
      ..removeWhere((e) => e['id'] == entry['id']);
    try {
      await _rpc('memory.manage', {
        'action': 'remove',
        'target': entry['target'] ?? 'memory',
        'old_text': entry['content'],
      });
    } catch (_) {}
    await _storage.saveMemoryEntries(updated);
    if (mounted) {
      HapticFeedback.lightImpact();
      setState(() => _memories = updated);
    }
  }

  Future<void> _configureTool(Map<String, dynamic> row, bool enabled) async {
    final name = (row['name'] ?? row['key'] ?? row['toolset'] ?? '').toString();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      await _rpc('tools.configure', {
        'action': enabled ? 'enable' : 'disable',
        'names': [name],
        'session_id': widget.sessionId
      });
      await _refresh();
    } catch (e) {
      if (mounted) setState(() {
        _busy = false;
        _error = '工具配置失败：$e';
      });
    }
  }

  Future<void> _cronAction(String action, String id) async {
    try {
      await _rpc('cron.manage', {'action': action, 'name': id});
      await _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('定时任务操作失败：$e')));
    }
  }

  Future<void> _addCron() async {
    final name = TextEditingController();
    final schedule = TextEditingController(text: '0 9 * * *');
    final prompt = TextEditingController();
    final form = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HermesTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('新增定时计划任务', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: HermesTheme.textMain)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                style: const TextStyle(fontSize: 13, color: HermesTheme.textMain),
                decoration: const InputDecoration(labelText: '任务名称', hintText: '如: 每日早报 / 容器巡检'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: schedule,
                style: const TextStyle(fontSize: 13, color: HermesTheme.textMain),
                decoration: const InputDecoration(
                  labelText: 'Cron 表达式',
                  helperText: '标准 5 段式，如 0 9 * * *（每天 09:00）',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: prompt,
                minLines: 2,
                maxLines: 4,
                style: const TextStyle(fontSize: 13, color: HermesTheme.textMain),
                decoration: const InputDecoration(labelText: '交给 Hermes 执行的指令', hintText: '具体的自动化巡检提示词'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: HermesTheme.primary),
            child: const Text('创建任务'),
          ),
        ],
      ),
    );
    if (form != true || name.text.trim().isEmpty || prompt.text.trim().isEmpty) {
      return;
    }
    try {
      await _rpc('cron.manage', {
        'action': 'add',
        'name': name.text.trim(),
        'schedule': schedule.text.trim(),
        'prompt': prompt.text.trim()
      });
      await _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建失败：$e')));
    }
  }

  Future<void> _searchSkills({bool install = false}) async {
    final query = _skillQuery.text.trim();
    if (query.isEmpty) return;
    try {
      final result = await _rpc('skills.manage', {'action': install ? 'install' : 'search', 'query': query});
      if (mounted) setState(() => _skills = Map<String, dynamic>.from(result as Map));
    } catch (e) {
      if (mounted) setState(() => _error = '技能中心不可用：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HermesTheme.background,
      appBar: AppBar(
        title: const Text('Agent 特工工作台', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: HermesTheme.textMain)),
        actions: [
          IconButton(
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: '刷新特工状态',
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: HermesTheme.primary,
          indicatorWeight: 2.5,
          labelColor: HermesTheme.primaryLight,
          unselectedLabelColor: HermesTheme.textDim,
          labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: '工具箱 & MCP'),
            Tab(text: '长期记忆 (Memory)'),
            Tab(text: '技能扩展'),
            Tab(text: '定时任务 (Cron)'),
            Tab(text: '上下文容量'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _toolsView(),
          _memoryView(),
          _skillsView(),
          _cronView(),
          _contextView(),
        ],
      ),
    );
  }

  Widget _toolsView() {
    if (_toolsets.isEmpty) return _empty('网关暂未返回可用工具集与 MCP 服务');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('工具与 MCP 协议扩展', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: HermesTheme.textMain)),
        const SizedBox(height: 4),
        const Text('开关将即时生效，调整特工拥有的环境感知与指令执行权限。', style: TextStyle(fontSize: 11.5, color: HermesTheme.textDim)),
        const SizedBox(height: 14),
        ..._toolsets.map((row) {
          final enabled = row['enabled'] == true || row['is_enabled'] == true;
          final title = (row['label'] ?? row['name'] ?? row['key'] ?? '工具集').toString();
          final tools = row['tools'] is List
              ? (row['tools'] as List).join(' · ')
              : (row['description'] ?? '').toString();

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: HermesTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: enabled ? HermesTheme.primary.withOpacity(0.3) : HermesTheme.borderSubtle),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: enabled ? HermesTheme.primary.withOpacity(0.15) : HermesTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.construction_rounded,
                    size: 18,
                    color: enabled ? HermesTheme.accent : HermesTheme.textDim,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: HermesTheme.textMain)),
                      const SizedBox(height: 2),
                      Text(
                        tools,
                        style: const TextStyle(fontSize: 11, color: HermesTheme.textDim),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: enabled,
                  activeColor: HermesTheme.accent,
                  onChanged: _busy ? null : (val) => _configureTool(row, val),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _skillsView() {
    final installed = _skills['skills'];
    final results = _skills['results'];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('技能市场与生态发现', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: HermesTheme.textMain)),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: HermesTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: HermesTheme.borderSubtle),
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              const Icon(Icons.search_rounded, size: 18, color: HermesTheme.textDim),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _skillQuery,
                  style: const TextStyle(fontSize: 13, color: HermesTheme.textMain),
                  decoration: const InputDecoration(
                    hintText: '搜索技能 (如: docker, git, sql, devops)...',
                    border: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    enabledBorder: InputBorder.none,
                  ),
                  onSubmitted: (_) => _searchSkills(),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_rounded, size: 18, color: HermesTheme.accent),
                onPressed: () => _searchSkills(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (results is List && results.isNotEmpty) ...[
          const Text('搜索结果', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: HermesTheme.primaryLight)),
          const SizedBox(height: 8),
          ...results.whereType<Map>().map((item) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: HermesTheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: HermesTheme.borderSubtle),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text((item['name'] ?? item['title'] ?? '技能').toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: HermesTheme.textMain)),
                          const SizedBox(height: 2),
                          Text((item['description'] ?? '').toString(), style: const TextStyle(fontSize: 11, color: HermesTheme.textDim), maxLines: 2, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '安装技能',
                      icon: const Icon(Icons.download_rounded, size: 18, color: HermesTheme.accent),
                      onPressed: () {
                        _skillQuery.text = (item['name'] ?? item['id'] ?? '').toString();
                        _searchSkills(install: true);
                      },
                    ),
                  ],
                ),
              )),
        ],
        if (installed is Map && installed.isNotEmpty) ...[
          const Text('已安装技能包', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: HermesTheme.textMain)),
          const SizedBox(height: 8),
          ...installed.entries.expand((entry) => (entry.value is List ? entry.value as List : const []).map((name) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: HermesTheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: HermesTheme.borderSubtle),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bolt_rounded, size: 18, color: HermesTheme.warning),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name.toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: HermesTheme.textMain)),
                          Text('来源: ${entry.key}', style: const TextStyle(fontSize: 10.5, color: HermesTheme.textDim)),
                        ],
                      ),
                    ),
                  ],
                ),
              ))),
        ],
        if (installed == null && results == null) _empty('已安装技能和搜索结果将在此清晰展示'),
      ],
    );
  }

  Widget _cronView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Linux 定时任务 (Cron)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: HermesTheme.textMain)),
                  SizedBox(height: 2),
                  Text('无人值守后台自动化，支持执行结果 Webhook 推送。', style: TextStyle(fontSize: 11, color: HermesTheme.textDim)),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _addCron,
              style: FilledButton.styleFrom(
                backgroundColor: HermesTheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('新增计划', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (_jobs.isEmpty) _empty('还没有定时任务。可添加周期指令，让 Hermes 按计划执行运维巡检。'),
        ..._jobs.map((job) {
          final id = (job['job_id'] ?? job['name'] ?? '').toString();
          final paused = job['enabled'] == false || job['paused'] == true;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: HermesTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: HermesTheme.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      paused ? Icons.pause_circle_outline_rounded : Icons.schedule_rounded,
                      size: 18,
                      color: paused ? HermesTheme.warning : HermesTheme.accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        (job['name'] ?? '未命名任务').toString(),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: HermesTheme.textMain),
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_horiz_rounded, size: 18, color: HermesTheme.textDim),
                      color: HermesTheme.surfaceElevated,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      onSelected: (action) => _cronAction(action, id),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: paused ? 'resume' : 'pause',
                          height: 36,
                          child: Text(paused ? '恢复执行' : '暂停计划', style: const TextStyle(fontSize: 13, color: HermesTheme.textMain)),
                        ),
                        const PopupMenuItem(
                          value: 'remove',
                          height: 36,
                          child: Text('删除任务', style: TextStyle(fontSize: 13, color: HermesTheme.danger)),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: HermesTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '计划表达式: ${job['schedule'] ?? '无计划'}',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: HermesTheme.primaryLight),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '指令: ${job['prompt_preview'] ?? job['prompt'] ?? '无提示词'}',
                  style: const TextStyle(fontSize: 12, color: HermesTheme.textMuted),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '下次执行时间: ${job['next_run_at'] ?? '计算中...'}',
                  style: const TextStyle(fontSize: 10.5, color: HermesTheme.textDim),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _contextView() {
    final used = (_context['context_used'] as num?)?.toDouble() ?? 0;
    final max = (_context['context_max'] as num?)?.toDouble() ?? 0;
    final percent = (_context['context_percent'] as num?)?.toDouble() ?? (max > 0 ? used / max * 100 : 0);
    final categories = _context['categories'];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('会话上下文深度透视', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: HermesTheme.textMain)),
        const SizedBox(height: 12),
        if (max > 0)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: HermesTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: HermesTheme.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${percent.toStringAsFixed(1)}% 容量已占用', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: HermesTheme.textMain)),
                    Text('${_context['model'] ?? ''}', style: const TextStyle(fontSize: 12, color: HermesTheme.primaryLight)),
                  ],
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: (percent / 100).clamp(0, 1),
                  backgroundColor: HermesTheme.surfaceLight,
                  color: percent > 80 ? HermesTheme.danger : HermesTheme.accent,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 10),
                Text(
                  '当前占用: ${used.toStringAsFixed(0)} / ${max.toStringAsFixed(0)} Tokens',
                  style: const TextStyle(fontSize: 12, color: HermesTheme.textMuted, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        if (categories is List) ...[
          const Text('Token 构成明细', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: HermesTheme.textMain)),
          const SizedBox(height: 8),
          ...categories.whereType<Map>().map((row) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: HermesTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: HermesTheme.borderSubtle),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text((row['label'] ?? row['name'] ?? '分类').toString(), style: const TextStyle(fontSize: 13, color: HermesTheme.textMain)),
                    Text('${row['tokens'] ?? row['count'] ?? ''} Tokens', style: const TextStyle(fontSize: 12, color: HermesTheme.textDim, fontFamily: 'monospace')),
                  ],
                ),
              )),
        ],
        if (max == 0) _empty('暂时无法读取上下文统计。此方法需要较新的 Hermes 网关，或当前 Agent 会话尚未产生对话历史。'),
      ],
    );
  }

  Widget _memoryView() {
    final filtered = _memoryFilter == 'all'
        ? _memories
        : _memories.where((m) => (m['target'] ?? 'memory') == _memoryFilter).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hermes 跨会话长期记忆库',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: HermesTheme.textMain)),
                  SizedBox(height: 2),
                  Text('可视化管理 MEMORY.md (环境认知) 与 USER.md (个人偏好)',
                      style: TextStyle(fontSize: 11, color: HermesTheme.textDim)),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: () => _addOrEditMemory(),
              style: FilledButton.styleFrom(
                backgroundColor: HermesTheme.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('新增记忆', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('全部记忆'),
              selected: _memoryFilter == 'all',
              onSelected: (_) => setState(() => _memoryFilter = 'all'),
              visualDensity: VisualDensity.compact,
            ),
            ChoiceChip(
              label: const Text('MEMORY.md · 环境经验'),
              selected: _memoryFilter == 'memory',
              onSelected: (_) => setState(() => _memoryFilter = 'memory'),
              visualDensity: VisualDensity.compact,
            ),
            ChoiceChip(
              label: const Text('USER.md · 用户画像'),
              selected: _memoryFilter == 'user',
              onSelected: (_) => setState(() => _memoryFilter = 'user'),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (filtered.isEmpty)
          _empty('暂无对应类别的长期记忆条目，点击右上角「新增记忆」添加。'),
        ...filtered.map((item) {
          final isUser = (item['target'] ?? 'memory') == 'user';
          final badgeColor =
              isUser ? HermesTheme.accent : HermesTheme.primaryLight;
          final badgeLabel = isUser ? 'USER.md · 用户画像' : 'MEMORY.md · 环境经验';

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: HermesTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: HermesTheme.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: badgeColor.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isUser
                                ? Icons.person_outline_rounded
                                : Icons.psychology_rounded,
                            size: 13,
                            color: badgeColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            badgeLabel,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: badgeColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined,
                          size: 16, color: HermesTheme.textMuted),
                      visualDensity: VisualDensity.compact,
                      tooltip: '编辑条目',
                      onPressed: () => _addOrEditMemory(existing: item),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded,
                          size: 16, color: HermesTheme.danger),
                      visualDensity: VisualDensity.compact,
                      tooltip: '删除条目',
                      onPressed: () => _deleteMemory(item),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  (item['content'] ?? '').toString(),
                  style: const TextStyle(
                    fontSize: 13,
                    color: HermesTheme.textMain,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _empty(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
        child: Center(child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: HermesTheme.textDim, fontSize: 13))),
      );
}

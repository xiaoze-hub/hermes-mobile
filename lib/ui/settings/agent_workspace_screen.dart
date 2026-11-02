import 'package:flutter/material.dart';
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
  late final TabController _tabs = TabController(length: 4, vsync: this);
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _toolsets = [];
  List<Map<String, dynamic>> _jobs = [];
  Map<String, dynamic> _context = {};
  Map<String, dynamic> _skills = {};
  final _skillQuery = TextEditingController();

  @override
  void initState() { super.initState(); _refresh(); }
  @override
  void dispose() { _tabs.dispose(); _skillQuery.dispose(); super.dispose(); }

  Future<dynamic> _rpc(String method, Map<String, dynamic> params) => widget.gateway.callRpc(method, params);

  Future<void> _refresh() async {
    if (!widget.gateway.supportsJsonRpc || widget.sessionId.isEmpty) {
      setState(() => _error = '当前会话未连接到支持 JSON-RPC 的 Hermes 网关。请升级网关并重新连接后使用 Agent 管理功能。');
      return;
    }
    setState(() { _busy = true; _error = null; });
    final results = await Future.wait([
      _rpc('tools.list', {'session_id': widget.sessionId}),
      _rpc('cron.manage', {'action': 'list'}),
      _rpc('session.context_breakdown', {'session_id': widget.sessionId}),
      _rpc('skills.manage', {'action': 'list'}),
    ].map((future) async { try { return await future; } catch (e) { return {'_error': e.toString()}; } }));
    if (!mounted) return;
    setState(() {
      final tools = results[0]; _toolsets = tools is Map && tools['toolsets'] is List ? List<Map<String, dynamic>>.from((tools['toolsets'] as List).whereType<Map>()) : [];
      final cron = results[1]; _jobs = cron is Map && cron['jobs'] is List ? List<Map<String, dynamic>>.from((cron['jobs'] as List).whereType<Map>()) : [];
      _context = results[2] is Map ? Map<String, dynamic>.from(results[2] as Map) : {};
      _skills = results[3] is Map ? Map<String, dynamic>.from(results[3] as Map) : {};
      final errors = results.whereType<Map>().map((r) => r['_error']).whereType<String>().toList();
      if (errors.length == results.length) _error = '此网关版本尚未开放 Agent 管理方法。\n${errors.first}';
      _busy = false;
    });
  }

  Future<void> _configureTool(Map<String, dynamic> row, bool enabled) async {
    final name = (row['name'] ?? row['key'] ?? row['toolset'] ?? '').toString();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      await _rpc('tools.configure', {'action': enabled ? 'enable' : 'disable', 'names': [name], 'session_id': widget.sessionId});
      await _refresh();
    } catch (e) { if (mounted) setState(() { _busy = false; _error = '工具配置失败：$e'; }); }
  }

  Future<void> _cronAction(String action, String id) async {
    try { await _rpc('cron.manage', {'action': action, 'name': id}); await _refresh(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('定时任务操作失败：$e'))); }
  }

  Future<void> _addCron() async {
    final name = TextEditingController(); final schedule = TextEditingController(text: '0 9 * * *'); final prompt = TextEditingController();
    final form = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('新增定时任务'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: '任务名称')),
        TextField(controller: schedule, decoration: const InputDecoration(labelText: 'Cron 表达式', helperText: '例如 0 9 * * *（每天 09:00）')),
        TextField(controller: prompt, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: '交给 Hermes 执行的指令')),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('创建'))],
    ));
    if (form != true || name.text.trim().isEmpty || prompt.text.trim().isEmpty) return;
    try {
      await _rpc('cron.manage', {'action': 'add', 'name': name.text.trim(), 'schedule': schedule.text.trim(), 'prompt': prompt.text.trim()});
      await _refresh();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('创建失败：$e'))); }
  }

  Future<void> _searchSkills({bool install = false}) async {
    final query = _skillQuery.text.trim(); if (query.isEmpty) return;
    try {
      final result = await _rpc('skills.manage', {'action': install ? 'install' : 'search', 'query': query});
      if (mounted) setState(() => _skills = Map<String, dynamic>.from(result as Map));
    } catch (e) { if (mounted) setState(() => _error = '技能中心不可用：$e'); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Agent 工作台'), actions: [IconButton(onPressed: _busy ? null : _refresh, icon: const Icon(Icons.refresh))], bottom: TabBar(controller: _tabs, isScrollable: true, tabs: const [Tab(text: '工具'), Tab(text: '技能'), Tab(text: '定时任务'), Tab(text: '上下文') ])),
    body: _error != null && _toolsets.isEmpty && _jobs.isEmpty && _context.isEmpty
      ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.extension_off_outlined, size: 42, color: HermesTheme.textMuted), const SizedBox(height: 14), Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 12), OutlinedButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('重新连接并重试'))])))
      : TabBarView(controller: _tabs, children: [_toolsView(), _skillsView(), _cronView(), _contextView()]),
  );

  Widget _toolsView() => _toolsets.isEmpty ? _empty('网关未返回工具集') : ListView(padding: const EdgeInsets.all(16), children: [
    const Text('工具和 MCP 服务', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
    const SizedBox(height: 6), const Text('开关会立即重建当前会话中的 Agent。', style: TextStyle(color: HermesTheme.textMuted)),
    const SizedBox(height: 12),
    ..._toolsets.map((row) { final enabled = row['enabled'] == true || row['is_enabled'] == true; final title = (row['label'] ?? row['name'] ?? row['key'] ?? '工具集').toString(); final tools = row['tools'] is List ? (row['tools'] as List).join(' · ') : (row['description'] ?? '').toString(); return SwitchListTile(title: Text(title), subtitle: Text(tools, maxLines: 2, overflow: TextOverflow.ellipsis), value: enabled, onChanged: _busy ? null : (value) => _configureTool(row, value)); }),
  ]);

  Widget _skillsView() { final installed = _skills['skills']; final results = _skills['results']; return ListView(padding: const EdgeInsets.all(16), children: [
    const Text('技能', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
    const SizedBox(height: 10), Row(children: [Expanded(child: TextField(controller: _skillQuery, decoration: const InputDecoration(hintText: '搜索技能中心'))), IconButton(onPressed: () => _searchSkills(), icon: const Icon(Icons.search))]),
    if (results is List) ...results.whereType<Map>().map((item) => ListTile(title: Text((item['name'] ?? item['title'] ?? '技能').toString()), subtitle: Text((item['description'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis), trailing: IconButton(tooltip: '安装技能', onPressed: () { _skillQuery.text = (item['name'] ?? item['id'] ?? '').toString(); _searchSkills(install: true); }, icon: const Icon(Icons.download_outlined)))),
    if (installed is Map) ...installed.entries.expand((entry) => (entry.value is List ? entry.value as List : const []).map((name) => ListTile(leading: const Icon(Icons.bolt_outlined), title: Text(name.toString()), subtitle: Text(entry.key.toString())))),
    if (installed == null && results == null) _empty('已安装技能和搜索结果将在此显示'),
  ]); }

  Widget _cronView() => ListView(padding: const EdgeInsets.all(16), children: [
    Row(children: [const Expanded(child: Text('定时任务', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))), FilledButton.icon(onPressed: _addCron, icon: const Icon(Icons.add), label: const Text('新增'))]),
    const SizedBox(height: 8),
    if (_jobs.isEmpty) _empty('还没有定时任务。可添加周期指令，让 Hermes 按计划执行。'),
    ..._jobs.map((job) { final id = (job['job_id'] ?? job['name'] ?? '').toString(); final paused = job['enabled'] == false || job['paused'] == true; return ListTile(leading: Icon(paused ? Icons.pause_circle_outline : Icons.schedule), title: Text((job['name'] ?? '未命名任务').toString()), subtitle: Text('${job['schedule'] ?? '无计划'} · ${job['prompt_preview'] ?? ''}\n下次运行：${job['next_run_at'] ?? '未知'}', maxLines: 3, overflow: TextOverflow.ellipsis), isThreeLine: true, trailing: PopupMenuButton<String>(onSelected: (action) => _cronAction(action, id), itemBuilder: (_) => [PopupMenuItem(value: paused ? 'resume' : 'pause', child: Text(paused ? '恢复' : '暂停')), const PopupMenuItem(value: 'remove', child: Text('删除'))])); }),
  ]);

  Widget _contextView() { final used = (_context['context_used'] as num?)?.toDouble() ?? 0; final max = (_context['context_max'] as num?)?.toDouble() ?? 0; final percent = (_context['context_percent'] as num?)?.toDouble() ?? (max > 0 ? used / max * 100 : 0); final categories = _context['categories']; return ListView(padding: const EdgeInsets.all(16), children: [
    const Text('会话上下文', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)), const SizedBox(height: 14),
    if (max > 0) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${percent.toStringAsFixed(0)}% 已使用', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)), const SizedBox(height: 10), LinearProgressIndicator(value: (percent / 100).clamp(0, 1)), const SizedBox(height: 8), Text('${used.toStringAsFixed(0)} / ${max.toStringAsFixed(0)} tokens · ${_context['model'] ?? ''}', style: const TextStyle(color: HermesTheme.textMuted))]))),
    if (categories is List) ...categories.whereType<Map>().map((row) => ListTile(title: Text((row['label'] ?? row['name'] ?? '分类').toString()), subtitle: Text('${row['tokens'] ?? row['count'] ?? ''} tokens'))),
    if (max == 0) _empty('暂时无法读取上下文统计。此方法需要较新的 Hermes 网关，或 Agent 尚未初始化。'),
    const SizedBox(height: 12), OutlinedButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('刷新统计')),
  ]); }

  Widget _empty(String text) => Padding(padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16), child: Center(child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: HermesTheme.textMuted))));
}

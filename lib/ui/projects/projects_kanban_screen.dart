import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/storage.dart';
import '../../models/project.dart';
import '../../models/kanban_task.dart';
import '../../services/hermes_gateway_service.dart';

class ProjectsKanbanScreen extends StatefulWidget {
  final HermesGatewayService gateway;
  final ValueChanged<String>? onOpenSession;

  const ProjectsKanbanScreen({
    super.key,
    required this.gateway,
    this.onOpenSession,
  });

  @override
  State<ProjectsKanbanScreen> createState() => _ProjectsKanbanScreenState();
}

class _ProjectsKanbanScreenState extends State<ProjectsKanbanScreen> with SingleTickerProviderStateMixin {
  final HermesStorage _storage = HermesStorage();
  late final TabController _tabController;
  List<HermesProject> _projects = [];
  HermesProject? _selectedProject;
  List<KanbanTask> _tasks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final projects = await _storage.getProjects();
    final currentProject = _selectedProject != null
        ? projects.firstWhere((p) => p.id == _selectedProject!.id, orElse: () => projects.first)
        : (projects.isNotEmpty ? projects.first : null);
    final tasks = await _storage.getKanbanTasks(projectId: currentProject?.id);
    if (!mounted) return;
    setState(() {
      _projects = projects;
      _selectedProject = currentProject;
      _tasks = tasks;
      _loading = false;
    });
  }

  Future<void> _createNewProject() async {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HermesTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('新建特工项目', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: HermesTheme.textMain)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              autofocus: true,
              style: const TextStyle(fontSize: 13, color: HermesTheme.textMain),
              decoration: const InputDecoration(labelText: '项目名称', hintText: '如: 生产运维巡检 / API 重构'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              maxLines: 2,
              style: const TextStyle(fontSize: 13, color: HermesTheme.textMain),
              decoration: const InputDecoration(labelText: '项目描述 (选填)', hintText: '简要说明项目目标与特工指派范围'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: HermesTheme.primary),
            child: const Text('创建'),
          ),
        ],
      ),
    );

    if (created == true && titleController.text.trim().isNotEmpty) {
      final newProj = HermesProject(
        id: 'proj_${DateTime.now().millisecondsSinceEpoch}',
        name: titleController.text.trim(),
        description: descController.text.trim(),
        colorValue: 0xFF6366F1,
        createdAt: DateTime.now(),
      );
      await _storage.saveProject(newProj);
      _selectedProject = newProj;
      await _loadData();
    }
  }

  Future<void> _createTask(KanbanStatus initialStatus) async {
    if (_selectedProject == null) return;
    final titleController = TextEditingController();
    final descController = TextEditingController();
    final roleController = TextEditingController(text: '运维助手');

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HermesTheme.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('添加看板任务 (${initialStatus.label})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: HermesTheme.textMain)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                style: const TextStyle(fontSize: 13, color: HermesTheme.textMain),
                decoration: const InputDecoration(labelText: '任务名称', hintText: '如: 监控 Docker 磁盘占用'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descController,
                maxLines: 2,
                style: const TextStyle(fontSize: 13, color: HermesTheme.textMain),
                decoration: const InputDecoration(labelText: '详细描述 / 指令提示', hintText: '具体派发要求或巡检参数'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: roleController,
                style: const TextStyle(fontSize: 13, color: HermesTheme.textMain),
                decoration: const InputDecoration(labelText: '协同角色', hintText: '如: DevOps / Security / Coder'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: HermesTheme.primary),
            child: const Text('添加'),
          ),
        ],
      ),
    );

    if (created == true && titleController.text.trim().isNotEmpty) {
      final newTask = KanbanTask(
        id: 'task_${DateTime.now().millisecondsSinceEpoch}',
        projectId: _selectedProject!.id,
        title: titleController.text.trim(),
        description: descController.text.trim(),
        status: initialStatus,
        assignedAgentRole: roleController.text.trim(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _storage.saveKanbanTask(newTask);
      await _loadData();
    }
  }

  Future<void> _advanceTaskStatus(KanbanTask task, bool forward) async {
    const values = KanbanStatus.values;
    final currentIndex = values.indexOf(task.status);
    final targetIndex = forward ? currentIndex + 1 : currentIndex - 1;
    if (targetIndex >= 0 && targetIndex < values.length) {
      final updated = task.copyWith(status: values[targetIndex]);
      await _storage.saveKanbanTask(updated);
      await _loadData();
    }
  }

  Future<void> _deleteTask(KanbanTask task) async {
    await _storage.deleteKanbanTask(task.id);
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HermesTheme.background,
      appBar: AppBar(
        title: const Text('项目与特工任务看板', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: HermesTheme.textMain)),
        actions: [
          IconButton(
            tooltip: '新建项目',
            icon: const Icon(Icons.create_new_folder_outlined, size: 20),
            onPressed: _createNewProject,
          ),
          IconButton(
            tooltip: '刷新看板',
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: _loadData,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(88),
          child: Column(
            children: [
              // 1. 项目选择器横向条
              SizedBox(
                height: 38,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  scrollDirection: Axis.horizontal,
                  itemCount: _projects.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    if (index == _projects.length) {
                      return ActionChip(
                        avatar: const Icon(Icons.add, size: 14, color: HermesTheme.textMuted),
                        label: const Text('新建项目', style: TextStyle(fontSize: 11, color: HermesTheme.textMuted)),
                        backgroundColor: HermesTheme.surfaceLight,
                        side: const BorderSide(color: HermesTheme.borderSubtle, width: 0.8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        onPressed: _createNewProject,
                      );
                    }
                    final proj = _projects[index];
                    final isSelected = proj.id == _selectedProject?.id;
                    return ChoiceChip(
                      selected: isSelected,
                      label: Text(proj.name, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                      selectedColor: HermesTheme.primary.withOpacity(0.25),
                      backgroundColor: HermesTheme.surfaceLight,
                      side: BorderSide(
                        color: isSelected ? HermesTheme.primary : HermesTheme.borderSubtle,
                        width: isSelected ? 1.2 : 0.8,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      onSelected: (_) {
                        setState(() => _selectedProject = proj);
                        _loadData();
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),

              // 2. 四状态 Tab 指示条
              TabBar(
                controller: _tabController,
                indicatorColor: HermesTheme.primary,
                indicatorWeight: 2.5,
                labelColor: HermesTheme.primaryLight,
                unselectedLabelColor: HermesTheme.textDim,
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                tabs: [
                  Tab(text: '待规划 (${_tasks.where((t) => t.status == KanbanStatus.backlog).length})'),
                  Tab(text: '执行中 (${_tasks.where((t) => t.status == KanbanStatus.inProgress).length})'),
                  Tab(text: '待审批 (${_tasks.where((t) => t.status == KanbanStatus.review).length})'),
                  Tab(text: '已完成 (${_tasks.where((t) => t.status == KanbanStatus.done).length})'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: HermesTheme.primary))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildKanbanColumn(KanbanStatus.backlog),
                _buildKanbanColumn(KanbanStatus.inProgress),
                _buildKanbanColumn(KanbanStatus.review),
                _buildKanbanColumn(KanbanStatus.done),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: HermesTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_task_rounded, size: 18),
        label: const Text('添加任务', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        onPressed: () => _createTask(KanbanStatus.values[_tabController.index]),
      ),
    );
  }

  Widget _buildKanbanColumn(KanbanStatus status) {
    final columnTasks = _tasks.where((t) => t.status == status).toList();

    if (columnTasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.dashboard_customize_outlined, size: 42, color: HermesTheme.borderHighlight),
            const SizedBox(height: 12),
            Text('当前暂无【${status.label}】任务', style: const TextStyle(fontSize: 13, color: HermesTheme.textDim)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: Text('指派任务到${status.label}', style: const TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: HermesTheme.borderSubtle),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _createTask(status),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
      itemCount: columnTasks.length,
      itemBuilder: (context, index) {
        final task = columnTasks[index];
        return _buildTaskCard(task);
      },
    );
  }

  Widget _buildTaskCard(KanbanTask task) {
    Color statusColor;
    switch (task.status) {
      case KanbanStatus.backlog:
        statusColor = HermesTheme.textMuted;
        break;
      case KanbanStatus.inProgress:
        statusColor = HermesTheme.accent;
        break;
      case KanbanStatus.review:
        statusColor = HermesTheme.warning;
        break;
      case KanbanStatus.done:
        statusColor = const Color(0xFF38BDF8);
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HermesTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HermesTheme.borderSubtle),
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.title,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: HermesTheme.textMain),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz_rounded, size: 18, color: HermesTheme.textDim),
                color: HermesTheme.surfaceElevated,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (val) {
                  if (val == 'delete') _deleteTask(task);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'delete',
                    height: 36,
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, size: 16, color: HermesTheme.danger),
                        SizedBox(width: 8),
                        Text('删除任务', style: TextStyle(fontSize: 13, color: HermesTheme.textMain)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (task.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              task.description,
              style: const TextStyle(fontSize: 12, color: HermesTheme.textMuted, height: 1.4),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (task.assignedAgentRole.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: HermesTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: HermesTheme.borderSubtle, width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.smart_toy_rounded, size: 11, color: HermesTheme.primaryLight),
                      const SizedBox(width: 4),
                      Text(task.assignedAgentRole, style: const TextStyle(fontSize: 10.5, color: HermesTheme.primaryLight)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              const Spacer(),

              // 后退动作
              if (task.status != KanbanStatus.backlog)
                IconButton(
                  tooltip: '后退阶段',
                  icon: const Icon(Icons.chevron_left_rounded, size: 20, color: HermesTheme.textDim),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _advanceTaskStatus(task, false),
                ),

              // 前进动作
              if (task.status != KanbanStatus.done)
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: HermesTheme.surfaceLight,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.chevron_right_rounded, size: 16, color: HermesTheme.accent),
                  label: const Text('推进', style: TextStyle(fontSize: 11, color: HermesTheme.accent)),
                  onPressed: () => _advanceTaskStatus(task, true),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

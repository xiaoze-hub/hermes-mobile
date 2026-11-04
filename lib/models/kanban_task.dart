enum KanbanStatus { backlog, inProgress, review, done }

extension KanbanStatusExtension on KanbanStatus {
  String get label {
    switch (this) {
      case KanbanStatus.backlog:
        return '待规划';
      case KanbanStatus.inProgress:
        return '执行中';
      case KanbanStatus.review:
        return '待审批';
      case KanbanStatus.done:
        return '已完成';
    }
  }
}

class KanbanTask {
  final String id;
  final String projectId;
  final String title;
  final String description;
  final KanbanStatus status;
  final String associatedSessionId;
  final String assignedAgentRole;
  final DateTime createdAt;
  final DateTime updatedAt;

  KanbanTask({
    required this.id,
    required this.projectId,
    required this.title,
    this.description = '',
    this.status = KanbanStatus.backlog,
    this.associatedSessionId = '',
    this.assignedAgentRole = '',
    required this.createdAt,
    required this.updatedAt,
  });

  KanbanTask copyWith({
    String? title,
    String? description,
    KanbanStatus? status,
    String? associatedSessionId,
    String? assignedAgentRole,
    DateTime? updatedAt,
  }) {
    return KanbanTask(
      id: id,
      projectId: projectId,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      associatedSessionId: associatedSessionId ?? this.associatedSessionId,
      assignedAgentRole: assignedAgentRole ?? this.assignedAgentRole,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    'title': title,
    'description': description,
    'status': status.name,
    'associatedSessionId': associatedSessionId,
    'assignedAgentRole': assignedAgentRole,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory KanbanTask.fromJson(Map<String, dynamic> json) => KanbanTask(
    id: json['id'] as String,
    projectId: json['projectId'] as String? ?? '',
    title: json['title'] as String? ?? '未命名任务',
    description: json['description'] as String? ?? '',
    status: KanbanStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => KanbanStatus.backlog,
    ),
    associatedSessionId: json['associatedSessionId'] as String? ?? '',
    assignedAgentRole: json['assignedAgentRole'] as String? ?? '',
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
  );
}

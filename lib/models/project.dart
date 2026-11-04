class HermesProject {
  final String id;
  final String name;
  final String description;
  final int colorValue;
  final DateTime createdAt;
  final List<String> sessionIds;

  HermesProject({
    required this.id,
    required this.name,
    this.description = '',
    this.colorValue = 0xFF6366F1,
    required this.createdAt,
    this.sessionIds = const [],
  });

  HermesProject copyWith({
    String? name,
    String? description,
    int? colorValue,
    List<String>? sessionIds,
  }) {
    return HermesProject(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      colorValue: colorValue ?? this.colorValue,
      createdAt: createdAt,
      sessionIds: sessionIds ?? this.sessionIds,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'colorValue': colorValue,
    'createdAt': createdAt.toIso8601String(),
    'sessionIds': sessionIds,
  };

  factory HermesProject.fromJson(Map<String, dynamic> json) => HermesProject(
    id: json['id'] as String,
    name: json['name'] as String? ?? '未命名项目',
    description: json['description'] as String? ?? '',
    colorValue: json['colorValue'] as int? ?? 0xFF6366F1,
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    sessionIds: (json['sessionIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
  );
}

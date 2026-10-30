class HermesSession {
  final String id;
  final String title;
  final DateTime updatedAt;

  HermesSession({
    required this.id,
    required this.title,
    required this.updatedAt,
  });

  factory HermesSession.fromJson(Map<String, dynamic> json) {
    return HermesSession(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '新会话',
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

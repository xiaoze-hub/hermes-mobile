class HermesSession {
  final String id;
  final String title;
  final String preview;
  final DateTime updatedAt;

  HermesSession({
    required this.id,
    required this.title,
    this.preview = '',
    required this.updatedAt,
  });

  factory HermesSession.fromJson(Map<String, dynamic> json) {
    final rawUpdatedAt = json['updated_at'] ??
        json['last_active'] ??
        json['session_started'] ??
        json['started_at'];
    return HermesSession(
      id: (json['id'] ?? json['session_id'])?.toString() ?? '',
      title: json['title']?.toString() ?? '新会话',
      preview: (json['preview'] ?? json['snippet'])?.toString() ?? '',
      updatedAt: _parseTimestamp(rawUpdatedAt) ?? DateTime.now(),
    );
  }

  static DateTime? _parseTimestamp(dynamic value) {
    if (value is num) {
      final milliseconds =
          value.abs() < 1000000000000 ? (value * 1000).round() : value.round();
      return DateTime.fromMillisecondsSinceEpoch(milliseconds);
    }
    if (value == null) return null;
    final text = value.toString().trim();
    final parsed = DateTime.tryParse(text);
    if (parsed != null) return parsed;
    final numeric = num.tryParse(text);
    if (numeric == null) return null;
    final milliseconds = numeric.abs() < 1000000000000
        ? (numeric * 1000).round()
        : numeric.round();
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }
}

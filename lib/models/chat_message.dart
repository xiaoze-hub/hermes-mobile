enum MessageRole { user, assistant, system }

class ToolCallInfo {
  final String id;
  final String name;
  final String arguments;
  final String? result;
  final bool isRunning;

  ToolCallInfo({
    required this.id,
    required this.name,
    required this.arguments,
    this.result,
    this.isRunning = false,
  });

  ToolCallInfo copyWith({
    String? result,
    bool? isRunning,
  }) {
    return ToolCallInfo(
      id: id,
      name: name,
      arguments: arguments,
      result: result ?? this.result,
      isRunning: isRunning ?? this.isRunning,
    );
  }
}

class ChatMessage {
  final String id;
  final MessageRole role;
  String content;
  String thinking;
  final List<String> attachments;
  List<ToolCallInfo> toolCalls;
  bool isStreaming;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.role,
    this.content = '',
    this.thinking = '',
    List<String> attachments = const [],
    List<ToolCallInfo>? toolCalls,
    this.isStreaming = false,
    DateTime? createdAt,
  })  : attachments = List.unmodifiable(attachments),
        toolCalls = toolCalls ?? [],
        createdAt = createdAt ?? DateTime.now();

  factory ChatMessage.user(String content,
      {List<String> attachments = const []}) {
    return ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: MessageRole.user,
      content: content,
      attachments: attachments,
    );
  }

  factory ChatMessage.assistant({String id = '', bool isStreaming = true}) {
    return ChatMessage(
      id: id.isNotEmpty ? id : DateTime.now().millisecondsSinceEpoch.toString(),
      role: MessageRole.assistant,
      isStreaming: isStreaming,
    );
  }
}

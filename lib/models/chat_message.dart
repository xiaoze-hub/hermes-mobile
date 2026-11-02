import 'dart:convert';

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

  static ChatMessage fromRawMap(Map<String, dynamic> raw) {
    final rawRole = (raw['role'] ?? 'assistant').toString().toLowerCase();
    MessageRole role = MessageRole.assistant;
    if (rawRole == 'user') {
      role = MessageRole.user;
    } else if (rawRole == 'system') {
      role = MessageRole.system;
    }

    // 提取正文内容
    String content = '';
    final rawContent = raw['content'] ?? raw['text'] ?? raw['message'] ?? raw['body'];
    if (rawContent is String) {
      content = rawContent;
    } else if (rawContent is List) {
      for (final item in rawContent) {
        if (item is Map) {
          if (item['type'] == 'text' && item['text'] != null) {
            content += item['text'].toString();
          } else if (item['text'] != null) {
            content += item['text'].toString();
          }
        } else if (item is String) {
          content += item;
        }
      }
    } else if (rawContent != null) {
      content = rawContent.toString();
    }

    // 提取思考推导过程 (thinking / thought / reasoning_content / XML tags)
    String thinking = (raw['thinking'] ?? raw['thought'] ?? raw['reasoning_content'] ?? '').toString();
    final thoughtRegex = RegExp(r'<(?:thought|thinking)>([\s\S]*?)<\/(?:thought|thinking)>', caseSensitive: false);
    final match = thoughtRegex.firstMatch(content);
    if (match != null) {
      if (thinking.isEmpty) {
        thinking = match.group(1)?.trim() ?? '';
      }
      content = content.replaceFirst(match.group(0)!, '').trim();
    }

    // 提取工具调用
    List<ToolCallInfo> toolCalls = [];
    if (raw['tool_calls'] is List) {
      for (final tc in raw['tool_calls']) {
        if (tc is Map) {
          final id = tc['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
          String name = '';
          String args = '';
          if (tc['function'] is Map) {
            name = tc['function']['name']?.toString() ?? '';
            final rawArgs = tc['function']['arguments'];
            args = rawArgs is String ? rawArgs : jsonEncode(rawArgs ?? {});
          } else {
            name = tc['name']?.toString() ?? '';
            final rawArgs = tc['arguments'] ?? tc['params'];
            args = rawArgs is String ? rawArgs : jsonEncode(rawArgs ?? {});
          }
          final result = tc['result'] ?? tc['output'];
          toolCalls.add(ToolCallInfo(
            id: id,
            name: name.isNotEmpty ? name : 'tool',
            arguments: args,
            result: result?.toString(),
            isRunning: false,
          ));
        }
      }
    }

    // 若当前条目本身是 tool 角色
    if (rawRole == 'tool') {
      toolCalls.add(ToolCallInfo(
        id: raw['tool_call_id']?.toString() ?? raw['id']?.toString() ?? 'tool_result',
        name: raw['name']?.toString() ?? 'tool_output',
        arguments: '',
        result: content,
        isRunning: false,
      ));
      content = '';
    }

    return ChatMessage(
      id: raw['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      role: role,
      content: content,
      thinking: thinking,
      toolCalls: toolCalls,
      isStreaming: false,
      createdAt: raw['timestamp'] != null
          ? DateTime.tryParse(raw['timestamp'].toString()) ?? DateTime.now()
          : (raw['created_at'] != null ? DateTime.tryParse(raw['created_at'].toString()) : null),
    );
  }
}

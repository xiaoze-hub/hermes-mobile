import 'dart:convert';

enum MessageRole { user, assistant, system }

enum ToolCategory { bash, python, web, io, subagent, cron, daemon, system }

class ToolCallInfo {
  final String id;
  final String name;
  final String arguments;
  final String? result;
  final bool isRunning;
  final DateTime startedAt;

  ToolCallInfo({
    required this.id,
    required this.name,
    required this.arguments,
    this.result,
    this.isRunning = false,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();

  ToolCallInfo copyWith({
    String? result,
    bool? isRunning,
    DateTime? startedAt,
  }) {
    return ToolCallInfo(
      id: id,
      name: name,
      arguments: arguments,
      result: result ?? this.result,
      isRunning: isRunning ?? this.isRunning,
      startedAt: startedAt ?? this.startedAt,
    );
  }

  ToolCategory get category {
    final lower = name.toLowerCase();
    if (lower.contains('subagent') ||
        lower.contains('delegate') ||
        lower.contains('spawn') ||
        lower.contains('child_agent')) {
      return ToolCategory.subagent;
    }
    if (lower.contains('cron') ||
        lower.contains('schedule') ||
        lower.contains('timer')) {
      return ToolCategory.cron;
    }
    if (lower.contains('daemon') ||
        lower.contains('background') ||
        _isBackgroundCommand(arguments)) {
      return ToolCategory.daemon;
    }
    if (lower.contains('bash') ||
        lower.contains('shell') ||
        lower.contains('exec') ||
        lower.contains('cmd')) {
      return ToolCategory.bash;
    }
    if (lower.contains('python') || lower.contains('code')) {
      return ToolCategory.python;
    }
    if (lower.contains('search') || lower.contains('web')) {
      return ToolCategory.web;
    }
    if (lower.contains('file') ||
        lower.contains('read') ||
        lower.contains('write')) {
      return ToolCategory.io;
    }
    return ToolCategory.system;
  }

  static bool _isBackgroundCommand(String args) {
    if (args.isEmpty) return false;
    final trimmed = args.trim();
    if (trimmed.endsWith('&') || trimmed.contains('& ') || trimmed.contains('nohup ') || trimmed.contains('disown') || trimmed.contains('tmux') || trimmed.contains('screen')) {
      return true;
    }
    try {
      final decoded = jsonDecode(args);
      if (decoded is Map) {
        final cmd = (decoded['command'] ?? decoded['cmd'] ?? decoded['script'] ?? '').toString();
        if (cmd.trim().endsWith('&') || cmd.contains('& ') || cmd.contains('nohup') || cmd.contains('tmux') || cmd.contains('screen')) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  bool get isDiff {
    final text = (result ?? '').isNotEmpty ? result! : arguments;
    return text.contains('diff --git') ||
        text.contains('--- a/') ||
        text.contains('+++ b/') ||
        RegExp(r'@@ -\d+,\d+ \+\d+,\d+ @@').hasMatch(text);
  }

  String get subagentRole {
    try {
      final decoded = jsonDecode(arguments);
      if (decoded is Map) {
        return (decoded['role'] ??
                decoded['name'] ??
                decoded['agent'] ??
                '子智能体')
            .toString();
      }
    } catch (_) {}
    return '协同子智能体';
  }

  String get subagentPrompt {
    try {
      final decoded = jsonDecode(arguments);
      if (decoded is Map) {
        return (decoded['prompt'] ??
                decoded['instruction'] ??
                decoded['task'] ??
                '')
            .toString();
      }
    } catch (_) {}
    return arguments;
  }

  String get cronSchedule {
    try {
      final decoded = jsonDecode(arguments);
      if (decoded is Map) {
        return (decoded['schedule'] ?? decoded['cron'] ?? '').toString();
      }
    } catch (_) {}
    return '';
  }

  String get elapsedFormatted {
    final diff = DateTime.now().difference(startedAt);
    final m = diff.inMinutes.toString().padLeft(2, '0');
    final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get humanCategoryName {
    switch (category) {
      case ToolCategory.bash:
        return '终端命令';
      case ToolCategory.daemon:
        return '后台进程';
      case ToolCategory.python:
        return 'Python';
      case ToolCategory.web:
        return '网络检索';
      case ToolCategory.io:
        return '文件读写';
      case ToolCategory.subagent:
        return '子特工';
      case ToolCategory.cron:
        return '定时任务';
      case ToolCategory.system:
        return '系统服务';
    }
  }

  String get humanActionSummary {
    if (category == ToolCategory.subagent) {
      return '协同特工: $subagentRole';
    }
    if (category == ToolCategory.cron && cronSchedule.isNotEmpty) {
      return '定时巡检: $cronSchedule';
    }
    if (arguments.trim().isEmpty) {
      return name;
    }
    try {
      final decoded = jsonDecode(arguments);
      if (decoded is Map) {
        if (decoded.containsKey('command') && decoded['command'] != null) {
          final cmd = decoded['command'].toString().trim();
          return cmd.startsWith('\$') ? cmd : '\$ $cmd';
        }
        if (decoded.containsKey('cmd') && decoded['cmd'] != null) {
          final cmd = decoded['cmd'].toString().trim();
          return cmd.startsWith('\$') ? cmd : '\$ $cmd';
        }
        if (decoded.containsKey('query') && decoded['query'] != null) {
          return '检索: "${decoded['query']}"';
        }
        if (decoded.containsKey('path') && decoded['path'] != null) {
          return '路径: ${decoded['path']}';
        }
        if (decoded.containsKey('file') && decoded['file'] != null) {
          return '文件: ${decoded['file']}';
        }
        if (decoded.containsKey('prompt') && decoded['prompt'] != null) {
          return decoded['prompt'].toString();
        }
      }
    } catch (_) {}
    final trimmed = arguments.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      return name;
    }
    return trimmed;
  }
}

class InflightTaskInfo {
  final String id;
  final String name;
  final ToolCategory category;
  final String detail;
  final DateTime startedAt;

  InflightTaskInfo({
    required this.id,
    required this.name,
    required this.category,
    required this.detail,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();

  String get elapsedFormatted {
    final diff = DateTime.now().difference(startedAt);
    final m = diff.inMinutes.toString().padLeft(2, '0');
    final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
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
    final rawContent =
        raw['content'] ?? raw['text'] ?? raw['message'] ?? raw['body'];
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
    String thinking = (raw['thinking'] ??
            raw['thought'] ??
            raw['reasoning_content'] ??
            '')
        .toString();
    final thoughtRegex = RegExp(
        r'<(?:thought|thinking)>([\s\S]*?)<\/(?:thought|thinking)>',
        caseSensitive: false);
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
          final id = tc['id']?.toString() ??
              DateTime.now().millisecondsSinceEpoch.toString();
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
        id: raw['tool_call_id']?.toString() ??
            raw['id']?.toString() ??
            'tool_result',
        name: raw['name']?.toString() ?? 'tool_output',
        arguments: '',
        result: content,
        isRunning: false,
      ));
      content = '';
    }

    return ChatMessage(
      id: raw['id']?.toString() ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      role: role,
      content: content,
      thinking: thinking,
      toolCalls: toolCalls,
      isStreaming: false,
      createdAt: raw['timestamp'] != null
          ? DateTime.tryParse(raw['timestamp'].toString()) ?? DateTime.now()
          : (raw['created_at'] != null
              ? DateTime.tryParse(raw['created_at'].toString())
              : null),
    );
  }
}

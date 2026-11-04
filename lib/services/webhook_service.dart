import 'package:dio/dio.dart';
import '../core/storage.dart';

class WebhookService {
  static final WebhookService _instance = WebhookService._internal();
  factory WebhookService() => _instance;
  WebhookService._internal();

  final HermesStorage _storage = HermesStorage();
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
  ));

  Future<void> dispatchTaskNotification({
    required String title,
    required String status,
    required String details,
  }) async {
    final config = await _storage.getWebhookConfig();
    if (config['enabled'] != true) return;

    final timestamp = DateTime.now().toLocal().toString().split('.').first;
    final message = '🤖 *[Hermes Agent 任务通知]*\n\n'
        '📌 *任务*: $title\n'
        '⚡ *状态*: $status\n'
        '📝 *详情*: $details\n'
        '🕒 *时间*: $timestamp';

    // 1. Telegram
    final tgToken = config['telegramBotToken']?.toString().trim();
    final tgChatId = config['telegramChatId']?.toString().trim();
    if (tgToken != null && tgToken.isNotEmpty && tgChatId != null && tgChatId.isNotEmpty) {
      _sendTelegram(tgToken, tgChatId, message);
    }

    // 2. Discord
    final discordUrl = config['discordWebhookUrl']?.toString().trim();
    if (discordUrl != null && discordUrl.isNotEmpty) {
      _sendDiscord(discordUrl, title, status, details, timestamp);
    }

    // 3. Slack
    final slackUrl = config['slackWebhookUrl']?.toString().trim();
    if (slackUrl != null && slackUrl.isNotEmpty) {
      _sendSlack(slackUrl, message);
    }

    // 4. Custom Webhook
    final customUrl = config['customWebhookUrl']?.toString().trim();
    if (customUrl != null && customUrl.isNotEmpty) {
      _sendCustom(customUrl, {
        'event': 'task_completion',
        'title': title,
        'status': status,
        'details': details,
        'timestamp': timestamp,
      });
    }
  }

  Future<void> _sendTelegram(String token, String chatId, String text) async {
    try {
      await _dio.post(
        'https://api.telegram.org/bot$token/sendMessage',
        data: {
          'chat_id': chatId,
          'text': text,
          'parse_mode': 'Markdown',
        },
      );
    } catch (_) {}
  }

  Future<void> _sendDiscord(String url, String title, String status, String details, String timestamp) async {
    try {
      await _dio.post(
        url,
        data: {
          'embeds': [
            {
              'title': 'Hermes Agent 自动化任务完成',
              'color': status == 'success' ? 0x10B981 : 0xEF4444,
              'fields': [
                {'name': '任务名称', 'value': title, 'inline': true},
                {'name': '执行状态', 'value': status, 'inline': true},
                {'name': '输出摘要', 'value': details.length > 500 ? '${details.substring(0, 500)}...' : details},
              ],
              'footer': {'text': 'Hermes Mobile · $timestamp'}
            }
          ]
        },
      );
    } catch (_) {}
  }

  Future<void> _sendSlack(String url, String text) async {
    try {
      await _dio.post(url, data: {'text': text});
    } catch (_) {}
  }

  Future<void> _sendCustom(String url, Map<String, dynamic> payload) async {
    try {
      await _dio.post(url, data: payload);
    } catch (_) {}
  }
}

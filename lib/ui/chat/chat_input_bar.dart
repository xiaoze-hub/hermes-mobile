import 'package:flutter/material.dart';
import '../../core/theme.dart';

class ChatInputBar extends StatefulWidget {
  final Function(String) onSend;
  final bool isConnected;

  const ChatInputBar({
    super.key,
    required this.onSend,
    required this.isConnected,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final TextEditingController _controller = TextEditingController();

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.isConnected) return;
    widget.onSend(text);
    _controller.clear();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(color: HermesTheme.surface),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: 4,
                minLines: 1,
                keyboardType: TextInputType.multiline,
                style:
                    const TextStyle(fontSize: 14, color: HermesTheme.textMain),
                decoration: InputDecoration(
                  hintText:
                      widget.isConnected ? "向 Hermes 发送消息" : "网关未连接，请检查配置...",
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  filled: true,
                  fillColor: HermesTheme.surfaceLight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide:
                        const BorderSide(color: HermesTheme.primary, width: 1),
                  ),
                ),
                onSubmitted: (_) => _handleSend(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: widget.isConnected ? _handleSend : null,
              icon: const Icon(Icons.arrow_upward, size: 20),
              style: IconButton.styleFrom(
                backgroundColor: HermesTheme.primary,
                foregroundColor: HermesTheme.background,
                disabledBackgroundColor: HermesTheme.surfaceLight,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

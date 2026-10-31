import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';

class ChatInputBar extends StatefulWidget {
  final Future<bool> Function(String text, List<ChatPickedFile> attachments)
      onSend;
  final bool isConnected;
  final bool draftReady;
  final bool isStreaming;
  final VoidCallback? onStop;
  final String draftText;
  final List<ChatPickedFile> draftAttachments;
  final ValueChanged<String>? onDraftTextChanged;
  final ValueChanged<List<ChatPickedFile>>? onDraftAttachmentsChanged;

  const ChatInputBar({
    super.key,
    required this.onSend,
    required this.isConnected,
    this.draftReady = true,
    this.isStreaming = false,
    this.onStop,
    this.draftText = '',
    this.draftAttachments = const [],
    this.onDraftTextChanged,
    this.onDraftAttachmentsChanged,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class ChatPickedFile {
  final String name;
  final Uint8List bytes;
  const ChatPickedFile({required this.name, required this.bytes});
  String get extension =>
      name.contains('.') ? name.split('.').last.toLowerCase() : '';
}

class _ChatInputBarState extends State<ChatInputBar> {
  late final TextEditingController _controller;
  late final List<ChatPickedFile> _attachments;
  bool _listening = false;
  bool _uploading = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.draftText);
    _attachments = List.of(widget.draftAttachments);
  }

  Future<void> _pickFiles() async {
    if (_uploading || _sending) return;
    if (mounted) setState(() => _uploading = true);
    try {
      final result = await const MethodChannel('com.hermes.mobile/files')
          .invokeMethod<List<dynamic>>('pickFiles');
      if (result == null || result.isEmpty || !mounted) return;
      final files = result
          .whereType<Map>()
          .map((file) => ChatPickedFile(
                name: file['name']?.toString() ?? 'attachment',
                bytes: file['bytes'] as Uint8List,
              ))
          .toList();
      const maxFiles = 5;
      const maxFileBytes = 15 * 1024 * 1024;
      const maxTotalBytes = 30 * 1024 * 1024;
      final picked = <ChatPickedFile>[];
      var totalBytes =
          _attachments.fold<int>(0, (total, file) => total + file.bytes.length);
      for (final file in files) {
        if (_attachments.length + picked.length >= maxFiles) break;
        if (file.bytes.length > maxFileBytes ||
            totalBytes + file.bytes.length > maxTotalBytes) {
          continue;
        }
        picked.add(file);
        totalBytes += file.bytes.length;
      }
      if (!mounted) return;
      setState(() {
        _attachments.addAll(picked);
        _uploading = false;
      });
      widget.onDraftAttachmentsChanged?.call(List.unmodifiable(_attachments));
      if (picked.length < files.length) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('最多添加 5 个文件，单个不超过 15 MB，总计不超过 30 MB。'),
        ));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('附件处理失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _toggleVoice() async {
    if (_listening) return;
    try {
      if (mounted) setState(() => _listening = true);
      final transcript = await const MethodChannel('com.hermes.mobile/files')
          .invokeMethod<String>('recognizeSpeech');
      if (transcript != null && transcript.isNotEmpty) {
        _controller.value = TextEditingValue(
          text: _controller.text.isEmpty
              ? transcript
              : '${_controller.text} $transcript',
          selection: TextSelection.collapsed(
              offset: (_controller.text.isEmpty
                      ? transcript
                      : '${_controller.text} $transcript')
                  .length),
        );
        widget.onDraftTextChanged?.call(_controller.text);
      }
    } on PlatformException catch (error) {
      if (mounted) {
        final permissionDenied =
            error.code == 'speech_service_permission_denied';
        final message = switch (error.code) {
          'microphone_permission_denied' => '请允许 Hermes 使用麦克风后再试。',
          'speech_service_permission_denied' => '系统语音服务没有麦克风权限，请在设置中为语音识别服务授权。',
          'speech_network_error' => '语音服务连接失败，请检查网络或系统语音服务。',
          'speech_no_match' => '没有听清内容，请靠近麦克风再试一次。',
          'recognizer_unavailable' => '此设备没有可用的语音识别服务。',
          _ => error.message ?? '语音输入暂时不可用，请检查系统语音服务设置。',
        };
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 5),
          action: permissionDenied
              ? SnackBarAction(
                  label: '打开设置',
                  onPressed: () {
                    const MethodChannel('com.hermes.mobile/files')
                        .invokeMethod<void>('openSpeechServiceSettings', {
                      'packageName': error.details?.toString(),
                    });
                  },
                )
              : null,
        ));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法启动语音输入，请检查系统语音服务。')),
        );
      }
    } finally {
      if (mounted) setState(() => _listening = false);
    }
  }

  Future<void> _handleSend() async {
    final text = _controller.text.trim();
    if ((text.isEmpty && _attachments.isEmpty) ||
        !widget.isConnected ||
        _sending) return;
    setState(() => _sending = true);
    try {
      final sent = await widget.onSend(text, List.unmodifiable(_attachments));
      if (!mounted) return;
      if (!sent) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('消息未确认发送，草稿已保留。重试前请先检查对话记录。'),
        ));
        return;
      }
      _controller.clear();
      setState(() => _attachments.clear());
      widget.onDraftTextChanged?.call('');
      widget.onDraftAttachmentsChanged?.call(const []);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('附件上传失败，草稿已保留，请检查连接后重试。'),
          duration: Duration(seconds: 5),
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_attachments.isNotEmpty)
              SizedBox(
                height: 58,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                  itemCount: _attachments.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final file = _attachments[index];
                    final isImage = [
                      'png',
                      'jpg',
                      'jpeg',
                      'gif',
                      'webp',
                      'heic'
                    ].contains(file.extension);
                    return InputChip(
                      avatar: isImage
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.memory(
                                file.bytes,
                                width: 30,
                                height: 30,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.image_outlined, size: 18),
                              ),
                            )
                          : Icon(
                              file.extension == 'pdf'
                                  ? Icons.picture_as_pdf_outlined
                                  : Icons.insert_drive_file_outlined,
                              size: 18,
                            ),
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      onDeleted: _sending
                          ? null
                          : () {
                              setState(() => _attachments.removeAt(index));
                              widget.onDraftAttachmentsChanged
                                  ?.call(List.unmodifiable(_attachments));
                            },
                      backgroundColor: HermesTheme.surfaceLight,
                      side: BorderSide.none,
                    );
                  },
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: '添加图片或文件',
                  onPressed: widget.isConnected && !_uploading && !_sending
                      ? _pickFiles
                      : null,
                  icon: _uploading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.add),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !_sending && widget.draftReady,
                    maxLines: 4,
                    minLines: 1,
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(
                        fontSize: 14, color: HermesTheme.textMain),
                    decoration: InputDecoration(
                      hintText: widget.isConnected
                          ? "向 Hermes 发送消息"
                          : "网关未连接，请检查配置...",
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
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
                        borderSide: const BorderSide(
                            color: HermesTheme.primary, width: 1),
                      ),
                    ),
                    onSubmitted: (_) => _handleSend(),
                    onChanged: (value) {
                      setState(() {});
                      widget.onDraftTextChanged?.call(value);
                    },
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: _listening ? '正在听写' : '语音听写',
                  onPressed: widget.isConnected && !_listening && !_sending
                      ? _toggleVoice
                      : null,
                  icon: Icon(_listening ? Icons.mic : Icons.mic_none,
                      color: _listening ? HermesTheme.accent : null),
                ),
                if (widget.isStreaming)
                  IconButton.filledTonal(
                    tooltip: '停止任务',
                    onPressed: widget.onStop,
                    icon: const Icon(Icons.stop_rounded, size: 20),
                  ),
                IconButton.filled(
                  onPressed: widget.isConnected &&
                          !_sending &&
                          (_controller.text.trim().isNotEmpty ||
                              _attachments.isNotEmpty)
                      ? _handleSend
                      : null,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_upward, size: 20),
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
          ],
        ),
      ),
    );
  }
}

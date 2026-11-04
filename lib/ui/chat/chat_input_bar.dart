import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import 'slash_command_palette.dart';

class ChatPickedFile {
  final String name;
  final Uint8List bytes;
  const ChatPickedFile({required this.name, required this.bytes});
  String get extension =>
      name.contains('.') ? name.split('.').last.toLowerCase() : '';
}

class ChatInputBar extends StatefulWidget {
  final Future<bool> Function(String text, List<ChatPickedFile> attachments) onSend;
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

class _ChatInputBarState extends State<ChatInputBar> {
  late final TextEditingController _controller;
  late final List<ChatPickedFile> _attachments;
  bool _listening = false;
  bool _uploading = false;
  bool _sending = false;
  bool _showSlashPalette = false;

  // Linux 常用运维指令宏
  final List<Map<String, String>> _quickMacros = [
    {'label': '🐳 容器状态', 'cmd': '请检查服务器当前 Docker 容器状态，标出任何异常退出的容器。'},
    {'label': '📊 内存占用', 'cmd': '执行 free -h 和 vmstat，分析当前 Linux 内存是否充裕。'},
    {'label': '🔥 CPU 负载', 'cmd': '执行 top -b -n 1 并排查消耗 CPU 最多的前 5 个进程。'},
    {'label': '💾 磁盘空间', 'cmd': '执行 df -h 查看根分区和挂载点的剩余磁盘空间。'},
    {'label': '📜 错误日志', 'cmd': '排查 journalctl -p err -n 10 最近的系统错误记录。'},
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.draftText);
    _attachments = List.of(widget.draftAttachments);
  }

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draftText != widget.draftText && _controller.text != widget.draftText) {
      _controller.text = widget.draftText;
    }
    if (oldWidget.draftAttachments != widget.draftAttachments) {
      _attachments.clear();
      _attachments.addAll(widget.draftAttachments);
    }
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
      var totalBytes = _attachments.fold<int>(0, (total, file) => total + file.bytes.length);
      for (final file in files) {
        if (_attachments.length + picked.length >= maxFiles) break;
        if (file.bytes.length > maxFileBytes || totalBytes + file.bytes.length > maxTotalBytes) {
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
          content: Text('最多添加 5 个文件，单个不超过 15 MB，总计不超过 30 MB'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('附件处理失败：$error'),
          behavior: SnackBarBehavior.floating,
        ));
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
          text: _controller.text.isEmpty ? transcript : '${_controller.text} $transcript',
          selection: TextSelection.collapsed(
            offset: (_controller.text.isEmpty ? transcript : '${_controller.text} $transcript').length,
          ),
        );
        widget.onDraftTextChanged?.call(_controller.text);
      }
    } on PlatformException catch (error) {
      if (mounted) {
        final permissionDenied = error.code == 'speech_service_permission_denied';
        final message = switch (error.code) {
          'microphone_permission_denied' => '请允许 Hermes 使用麦克风后再试',
          'speech_service_permission_denied' => '系统语音服务没有麦克风权限，请在设置中为语音识别服务授权',
          'speech_network_error' => '语音服务连接失败，请检查网络或系统语音服务',
          'speech_no_match' => '没有听清内容，请靠近麦克风再试一次',
          'recognizer_unavailable' => '此设备没有可用的系统语音识别服务',
          _ => error.message ?? '语音输入暂时不可用，请检查系统语音服务设置',
        };
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          action: permissionDenied
              ? SnackBarAction(
                  label: '设置',
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
          const SnackBar(content: Text('无法启动语音输入，请检查系统语音服务'), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _listening = false);
    }
  }

  Future<void> _handleSend() async {
    final text = _controller.text.trim();
    if ((text.isEmpty && _attachments.isEmpty) || !widget.isConnected || _sending) return;
    setState(() => _sending = true);
    try {
      final sent = await widget.onSend(text, List.unmodifiable(_attachments));
      if (!mounted) return;
      if (!sent) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('消息未确认发送，草稿已保留。重试前请先检查网络'),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      _controller.clear();
      setState(() => _attachments.clear());
      widget.onDraftTextChanged?.call('');
      widget.onDraftAttachmentsChanged?.call(const []);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('发送失败，草稿已保留：$error'),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _applyMacro(String cmd) {
    _controller.text = cmd;
    _controller.selection = TextSelection.fromPosition(TextPosition(offset: cmd.length));
    widget.onDraftTextChanged?.call(cmd);
    setState(() {});
  }

  void _showActionSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: HermesTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: HermesTheme.borderSubtle,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: HermesTheme.cyan.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.attach_file_rounded, color: HermesTheme.cyan, size: 20),
                ),
                title: const Text('上传图片或文件', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: HermesTheme.textMain)),
                subtitle: const Text('支持代码、图片、日志、PDF (最大 15MB)', style: TextStyle(fontSize: 11, color: HermesTheme.textDim)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFiles();
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: HermesTheme.accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.terminal_rounded, color: HermesTheme.accent, size: 20),
                ),
                title: const Text('斜杠指令面板 (Slash Commands)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: HermesTheme.textMain)),
                subtitle: const Text('浏览所有可用命令与快捷工具', style: TextStyle(fontSize: 11, color: HermesTheme.textDim)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _showSlashPalette = true);
                },
              ),
              const Divider(color: HermesTheme.borderSubtle, height: 20),
              const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text('快捷运维巡检 (Quick Macros)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: HermesTheme.textMuted)),
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _quickMacros.map((macro) => ActionChip(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    backgroundColor: HermesTheme.surfaceLight,
                    side: const BorderSide(color: HermesTheme.borderSubtle, width: 0.8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    label: Text(macro['label']!, style: const TextStyle(fontSize: 11.5, color: HermesTheme.textMain)),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _applyMacro(macro['cmd']!);
                    },
                  )).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasContent = _controller.text.trim().isNotEmpty || _attachments.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            HermesTheme.background.withOpacity(0.0),
            HermesTheme.background.withOpacity(0.9),
            HermesTheme.background,
          ],
          stops: const [0.0, 0.35, 1.0],
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        12,
        4,
        12,
        8 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 0. 桌面级 Slash 命令快捷面板
            if (_showSlashPalette || (_controller.text.startsWith('/') && !_controller.text.contains('\n') && _controller.text.length < 25))
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                constraints: const BoxConstraints(maxHeight: 250),
                child: SlashCommandPalette(
                  query: _controller.text,
                  onSelect: (item) {
                    _applyMacro(item.prompt);
                    setState(() => _showSlashPalette = false);
                  },
                ),
              ),

            // 1. 横向快捷运维宏指令栏 (Quick Macros & Slash Trigger)
            SizedBox(
              height: 30,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  ActionChip(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: _showSlashPalette
                        ? HermesTheme.primary.withOpacity(0.25)
                        : HermesTheme.surfaceLight,
                    side: BorderSide(
                      color: _showSlashPalette ? HermesTheme.accent : HermesTheme.borderSubtle,
                      width: 0.9,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    avatar: const Icon(Icons.terminal_rounded, size: 13, color: HermesTheme.accent),
                    label: const Text(
                      '[/] 指令面板',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: HermesTheme.accent,
                      ),
                    ),
                    onPressed: () {
                      setState(() => _showSlashPalette = !_showSlashPalette);
                    },
                  ),
                  const SizedBox(width: 6),
                  ...List.generate(_quickMacros.length, (index) {
                    final macro = _quickMacros[index];
                    return Padding(
                      padding: EdgeInsets.only(right: index == _quickMacros.length - 1 ? 0 : 6),
                      child: ActionChip(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        backgroundColor: HermesTheme.surfaceLight,
                        side: const BorderSide(color: HermesTheme.borderSubtle, width: 0.8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        label: Text(
                          macro['label']!,
                          style: const TextStyle(fontSize: 10.5, color: HermesTheme.textMuted),
                        ),
                        onPressed: widget.isConnected ? () => _applyMacro(macro['cmd']!) : null,
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // 2. 附件缩略图预览栏 (Attachments Strip)
            if (_attachments.isNotEmpty)
              Container(
                height: 48,
                margin: const EdgeInsets.only(bottom: 6),
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _attachments.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final file = _attachments[index];
                    final isImage = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'heic'].contains(file.extension);

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: HermesTheme.surfaceLight,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: HermesTheme.borderSubtle),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isImage)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.memory(
                                file.bytes,
                                width: 28,
                                height: 28,
                                fit: BoxFit.cover,
                              ),
                            )
                          else
                            Icon(
                              file.extension == 'pdf' ? Icons.picture_as_pdf_rounded : Icons.insert_drive_file_rounded,
                              size: 18,
                              color: HermesTheme.cyan,
                            ),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 110),
                            child: Text(
                              file.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: HermesTheme.textMain),
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: _sending ? null : () {
                              setState(() => _attachments.removeAt(index));
                              widget.onDraftAttachmentsChanged?.call(List.unmodifiable(_attachments));
                            },
                            child: const Icon(Icons.close_rounded, size: 14, color: HermesTheme.textDim),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

            // 3. 核心悬浮输入岛 (Floating Command Dock)
            Container(
              decoration: BoxDecoration(
                color: HermesTheme.surfaceGlass,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: hasContent ? HermesTheme.primary.withOpacity(0.6) : HermesTheme.borderSubtle,
                  width: 1.2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 左侧添加附件与功能菜单按钮 (+)
                  Padding(
                    padding: const EdgeInsets.only(left: 6, bottom: 5),
                    child: IconButton(
                      tooltip: '功能菜单与附件',
                      onPressed: widget.isConnected && !_uploading && !_sending ? _showActionSheet : null,
                      icon: _uploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: HermesTheme.cyan),
                            )
                          : const Icon(Icons.add_circle_outline_rounded, size: 20, color: HermesTheme.cyan),
                    ),
                  ),

                  // 中间输入框
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_sending && widget.draftReady,
                      maxLines: 5,
                      minLines: 1,
                      keyboardType: TextInputType.multiline,
                      style: const TextStyle(fontSize: 13.5, color: HermesTheme.textMain, height: 1.45),
                      decoration: InputDecoration(
                        filled: false,
                        hintText: widget.isConnected
                            ? "向 Linux Hermes Agent 下发指令..."
                            : "远程网关未连接，请点击右上角配置...",
                        hintStyle: const TextStyle(fontSize: 12.5, color: HermesTheme.textDim),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
                      ),
                      onSubmitted: (_) => _handleSend(),
                      onChanged: (val) {
                        setState(() {});
                        widget.onDraftTextChanged?.call(val);
                      },
                    ),
                  ),

                  // 语音听写按钮 (Mic)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: IconButton(
                      tooltip: _listening ? '正在听写...' : '语音听写输入',
                      onPressed: widget.isConnected && !_listening && !_sending ? _toggleVoice : null,
                      icon: Icon(
                        _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                        size: 20,
                        color: _listening ? HermesTheme.warning : HermesTheme.textMuted,
                      ),
                    ),
                  ),

                  // 右侧动作按钮 (发送 / 停止生成动态切换)
                  Padding(
                    padding: const EdgeInsets.only(right: 6, bottom: 6),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                      child: widget.isStreaming
                          ? IconButton.filled(
                              key: const ValueKey('stop_btn'),
                              onPressed: widget.onStop,
                              icon: const Icon(Icons.stop_rounded, size: 18),
                              tooltip: '停止生成',
                              style: IconButton.styleFrom(
                                backgroundColor: HermesTheme.danger,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(36, 36),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                            )
                          : IconButton.filled(
                              key: const ValueKey('send_btn'),
                              onPressed: (widget.isConnected && !_sending && hasContent) ? _handleSend : null,
                              icon: _sending
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.arrow_upward_rounded, size: 18),
                              tooltip: '发送指令',
                              style: IconButton.styleFrom(
                                backgroundColor: HermesTheme.primary,
                                disabledBackgroundColor: HermesTheme.surfaceLight,
                                foregroundColor: Colors.white,
                                disabledForegroundColor: HermesTheme.textDim,
                                minimumSize: const Size(36, 36),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

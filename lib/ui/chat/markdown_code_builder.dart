import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../core/theme.dart';

class _MarkdownSegment {
  final bool isCodeBlock;
  final String language;
  final String content;

  const _MarkdownSegment({
    required this.isCodeBlock,
    this.language = '',
    required this.content,
  });
}

/// 增强版 Markdown 渲染组件：
/// - 自动识别围栏代码块（支持流式输出中尚未闭合的代码块）
/// - 为每个代码块提供「语言标签」、「一键复制代码」、「下发终端执行」顶部工具栏
/// - 流式输出时底部附带极光呼吸光标
class HermesRichMarkdownView extends StatelessWidget {
  final String data;
  final bool isStreaming;
  final ValueChanged<String>? onRunCommand;

  const HermesRichMarkdownView({
    super.key,
    required this.data,
    this.isStreaming = false,
    this.onRunCommand,
  });

  List<_MarkdownSegment> _parseSegments(String raw) {
    if (raw.isEmpty) return const [];
    final segments = <_MarkdownSegment>[];
    final lines = raw.split('\n');
    final buffer = StringBuffer();
    bool inCode = false;
    String codeLang = '';

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('```')) {
        if (!inCode) {
          if (buffer.isNotEmpty) {
            segments.add(_MarkdownSegment(
              isCodeBlock: false,
              content: buffer.toString().trimRight(),
            ));
            buffer.clear();
          }
          inCode = true;
          codeLang = trimmed.substring(3).trim();
        } else {
          segments.add(_MarkdownSegment(
            isCodeBlock: true,
            language: codeLang,
            content: buffer.toString().replaceFirst(RegExp(r'\n$'), ''),
          ));
          buffer.clear();
          inCode = false;
          codeLang = '';
        }
      } else {
        buffer.writeln(line);
      }
    }

    if (buffer.isNotEmpty) {
      segments.add(_MarkdownSegment(
        isCodeBlock: inCode,
        language: codeLang,
        content: buffer.toString().replaceFirst(RegExp(r'\n$'), ''),
      ));
    }

    return segments;
  }

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty && isStreaming) {
      return const StreamingPulseIndicator();
    }

    final segments = _parseSegments(data);
    final styleSheet = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: const TextStyle(
        fontSize: 14,
        color: HermesTheme.textMain,
        height: 1.55,
      ),
      h1: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: HermesTheme.textMain,
        height: 1.4,
      ),
      h2: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: HermesTheme.textMain,
        height: 1.4,
      ),
      h3: const TextStyle(
        fontSize: 14.5,
        fontWeight: FontWeight.bold,
        color: HermesTheme.textMain,
        height: 1.4,
      ),
      listBullet: const TextStyle(
        fontSize: 14,
        color: HermesTheme.accent,
      ),
      blockquoteDecoration: BoxDecoration(
        color: HermesTheme.surface.withOpacity(0.6),
        borderRadius: BorderRadius.circular(6),
        border: const Border(
          left: BorderSide(color: HermesTheme.primaryLight, width: 3),
        ),
      ),
      code: const TextStyle(
        fontFamily: 'monospace',
        backgroundColor: HermesTheme.surfaceLight,
        fontSize: 12.5,
        color: HermesTheme.accent,
      ),
      codeblockDecoration: BoxDecoration(
        color: HermesTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: HermesTheme.borderSubtle),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < segments.length; i++) ...[
          if (segments[i].isCodeBlock)
            Padding(
              padding: EdgeInsets.only(bottom: i == segments.length - 1 ? 0 : 10, top: i == 0 ? 0 : 4),
              child: _InteractiveCodeBlockCard(
                language: segments[i].language,
                code: segments[i].content,
                onRunCommand: onRunCommand,
              ),
            )
          else if (segments[i].content.trim().isNotEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: i == segments.length - 1 ? 0 : 8),
              child: MarkdownBody(
                data: segments[i].content,
                selectable: true,
                styleSheet: styleSheet,
              ),
            ),
        ],
        if (isStreaming) ...[
          const SizedBox(height: 6),
          const StreamingPulseIndicator(),
        ],
      ],
    );
  }
}

class _InteractiveCodeBlockCard extends StatefulWidget {
  final String language;
  final String code;
  final ValueChanged<String>? onRunCommand;

  const _InteractiveCodeBlockCard({
    required this.language,
    required this.code,
    this.onRunCommand,
  });

  @override
  State<_InteractiveCodeBlockCard> createState() =>
      _InteractiveCodeBlockCardState();
}

class _InteractiveCodeBlockCardState extends State<_InteractiveCodeBlockCard> {
  bool _copied = false;

  bool get _isShellLike {
    final lang = widget.language.toLowerCase();
    return lang == 'bash' ||
        lang == 'sh' ||
        lang == 'shell' ||
        lang == 'zsh' ||
        lang == 'console';
  }

  void _handleCopy() {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final displayLang =
        widget.language.isEmpty ? 'code' : widget.language.toLowerCase();

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E17),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: HermesTheme.borderSubtle, width: 0.9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部工具条：语言标签 + 一键复制 + 一键执行
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF111726),
              borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
              border: Border(
                bottom: BorderSide(color: HermesTheme.borderSubtle, width: 0.7),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: HermesTheme.primary.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    displayLang,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: HermesTheme.primaryLight,
                    ),
                  ),
                ),
                const Spacer(),
                if (_isShellLike &&
                    widget.onRunCommand != null &&
                    widget.code.trim().isNotEmpty) ...[
                  InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      widget.onRunCommand!(
                          '请在终端执行以下命令并汇报结果：\n```bash\n${widget.code.trim()}\n```');
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_arrow_rounded,
                              size: 13, color: HermesTheme.accent),
                          SizedBox(width: 2),
                          Text(
                            '下发执行',
                            style: TextStyle(
                              fontSize: 11,
                              color: HermesTheme.accent,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                InkWell(
                  onTap: _handleCopy,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _copied ? Icons.check_rounded : Icons.copy_rounded,
                          size: 12.5,
                          color: _copied
                              ? HermesTheme.accent
                              : HermesTheme.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _copied ? '已复制' : '复制代码',
                          style: TextStyle(
                            fontSize: 11,
                            color: _copied
                                ? HermesTheme.accent
                                : HermesTheme.textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 代码内容区（支持横向滚动与自由复制）
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: SelectableText(
              widget.code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                color: Color(0xFFE2E8F0),
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 流式生成时的极光呼吸指示器
class StreamingPulseIndicator extends StatefulWidget {
  const StreamingPulseIndicator({super.key});

  @override
  State<StreamingPulseIndicator> createState() =>
      _StreamingPulseIndicatorState();
}

class _StreamingPulseIndicatorState extends State<StreamingPulseIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: HermesTheme.accent,
              boxShadow: [
                BoxShadow(
                  color: HermesTheme.accent.withOpacity(0.5),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'Hermes 正在实时生成...',
            style: TextStyle(
              fontSize: 11,
              color: HermesTheme.accent,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// 会话首次同步时的微光骨架屏（替代单调的转圈等待）
class ChatShimmerSkeleton extends StatefulWidget {
  const ChatShimmerSkeleton({super.key});

  @override
  State<ChatShimmerSkeleton> createState() => _ChatShimmerSkeletonState();
}

class _ChatShimmerSkeletonState extends State<ChatShimmerSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildBubbleSkeleton({
    required bool isUser,
    required double widthFactor,
    required double height,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 30,
              height: 30,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: HermesTheme.surfaceLight,
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ],
          Flexible(
            child: FractionallySizedBox(
              widthFactor: widthFactor,
              child: Container(
                height: height,
                decoration: BoxDecoration(
                  color: isUser
                      ? HermesTheme.primary.withOpacity(0.18)
                      : HermesTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: HermesTheme.borderSubtle),
                ),
              ),
            ),
          ),
          if (isUser) ...[
            Container(
              width: 30,
              height: 30,
              margin: const EdgeInsets.only(left: 10),
              decoration: BoxDecoration(
                color: HermesTheme.surfaceLight,
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 0.9).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: ListView(
        reverse: true,
        padding: const EdgeInsets.fromLTRB(14, 20, 14, 150),
        children: [
          _buildBubbleSkeleton(isUser: false, widthFactor: 0.84, height: 110),
          _buildBubbleSkeleton(isUser: true, widthFactor: 0.56, height: 46),
          _buildBubbleSkeleton(isUser: false, widthFactor: 0.76, height: 82),
          _buildBubbleSkeleton(isUser: true, widthFactor: 0.62, height: 46),
        ],
      ),
    );
  }
}

/// 全屏图片缩放预览器（支持双指缩放与平移查看细节）
class FullScreenImageViewer extends StatelessWidget {
  final String title;
  final Uint8List bytes;

  const FullScreenImageViewer({
    super.key,
    required this.title,
    required this.bytes,
  });

  static void show(BuildContext context, {required String title, required Uint8List bytes}) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black.withOpacity(0.92),
        pageBuilder: (ctx, anim, _) => FadeTransition(
          opacity: anim,
          child: FullScreenImageViewer(title: title, bytes: bytes),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.black54,
        title: Text(
          title,
          style: const TextStyle(fontSize: 14, color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.6,
          maxScale: 4.5,
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

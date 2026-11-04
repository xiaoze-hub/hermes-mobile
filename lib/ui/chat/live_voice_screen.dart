import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../services/hermes_gateway_service.dart';

enum LiveVoiceState { ready, listening, thinking, speaking }

class LiveVoiceScreen extends StatefulWidget {
  final HermesGatewayService gateway;
  final String sessionId;
  final String currentModel;
  final ValueChanged<String>? onUserSpoke;

  const LiveVoiceScreen({
    super.key,
    required this.gateway,
    required this.sessionId,
    required this.currentModel,
    this.onUserSpoke,
  });

  @override
  State<LiveVoiceScreen> createState() => _LiveVoiceScreenState();
}

class _LiveVoiceScreenState extends State<LiveVoiceScreen> with TickerProviderStateMixin {
  static const MethodChannel _platform = MethodChannel('com.hermes.mobile/files');
  LiveVoiceState _state = LiveVoiceState.ready;
  late final AnimationController _pulseController;
  late final AnimationController _waveController;

  String _liveSubtitle = '轻触下方麦克风开始实时对话';
  final List<Map<String, String>> _transcriptHistory = [];
  bool _autoListenLoop = true;
  StreamSubscription? _chatSubscription;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _setupPlatformCallbacks();
    // 延迟 400ms 后自动开启首次聆听
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _startListening();
      });
    });
  }

  void _setupPlatformCallbacks() {
    _platform.setMethodCallHandler((call) async {
      if (call.method == 'onTtsDone') {
        if (mounted && _state == LiveVoiceState.speaking) {
          setState(() {
            _state = LiveVoiceState.ready;
            _liveSubtitle = '回答完毕，等待说话...';
          });
          if (_autoListenLoop) {
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted && _state == LiveVoiceState.ready) {
                _startListening();
              }
            });
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    _chatSubscription?.cancel();
    _stopSpeaking();
    super.dispose();
  }

  Future<void> _stopSpeaking() async {
    try {
      await _platform.invokeMethod('stopSpeaking');
    } catch (_) {}
  }

  Future<void> _startListening() async {
    if (_state == LiveVoiceState.listening) return;
    await _stopSpeaking();
    setState(() {
      _state = LiveVoiceState.listening;
      _liveSubtitle = '正在聆听您的声音...';
    });

    try {
      final transcript = await _platform.invokeMethod<String>('recognizeSpeech');
      if (!mounted) return;
      if (transcript != null && transcript.trim().isNotEmpty) {
        final text = transcript.trim();
        setState(() {
          _liveSubtitle = '您: "$text"';
          _transcriptHistory.add({'role': 'user', 'text': text});
        });
        widget.onUserSpoke?.call(text);
        _sendToAgent(text);
      } else {
        setState(() {
          _state = LiveVoiceState.ready;
          _liveSubtitle = '未检测到声音，轻触可重新开始';
        });
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = LiveVoiceState.ready;
        _liveSubtitle = e.message ?? '语音输入暂不可用';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _state = LiveVoiceState.ready;
        _liveSubtitle = '请轻触麦克风重试';
      });
    }
  }

  Future<void> _sendToAgent(String prompt) async {
    setState(() {
      _state = LiveVoiceState.thinking;
      _liveSubtitle = 'Hermes 正在深度推导思考...';
    });

    try {
      final responseBuffer = StringBuffer();
      _chatSubscription = widget.gateway.streamEvents.listen((event) async {
        final type = event['type']?.toString();
        if (type == 'content' || type == 'chunk') {
          final delta = (event['content'] ?? event['text'] ?? '').toString();
          responseBuffer.write(delta);
        } else if (type == 'done' || type == 'message_end') {
          _chatSubscription?.cancel();
          if (!mounted) return;
          final answer = responseBuffer.toString().trim();
          if (answer.isNotEmpty) {
            setState(() {
              _state = LiveVoiceState.speaking;
              _liveSubtitle = 'Hermes 正在回答...';
              _transcriptHistory.add({'role': 'agent', 'text': answer});
            });
            final cleanVoiceText = _cleanMarkdownForSpeech(answer);
            try {
              await _platform.invokeMethod('speak', {
                'text': cleanVoiceText,
                'lang': 'zh',
              });
            } catch (_) {
              if (mounted) setState(() => _state = LiveVoiceState.ready);
            }
          } else {
            setState(() {
              _state = LiveVoiceState.ready;
              _liveSubtitle = '等待您的指令';
            });
          }
        }
      });

      await widget.gateway.sendMessage(
        sessionId: widget.sessionId,
        text: prompt,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _state = LiveVoiceState.ready;
          _liveSubtitle = '发送失败，请重试';
        });
      }
    }
  }

  String _cleanMarkdownForSpeech(String md) {
    var text = md;
    text = text.replaceAll(RegExp(r'```[\s\S]*?```'), '代码片段已执行');
    text = text.replaceAll(RegExp(r'`.*?`'), '');
    text = text.replaceAll(RegExp(r'#+\s'), '');
    text = text.replaceAll(RegExp(r'[*_~]'), '');
    text = text.replaceAll(RegExp(r'\[(.*?)\]\(.*?\)'), r'$1');
    return text.trim();
  }

  void _interrupt() {
    _stopSpeaking();
    _chatSubscription?.cancel();
    setState(() {
      _state = LiveVoiceState.ready;
      _liveSubtitle = '已打断，轻触麦克风继续';
    });
  }

  @override
  Widget build(BuildContext context) {
    Color orbColor;
    switch (_state) {
      case LiveVoiceState.ready:
        orbColor = const Color(0xFF6366F1);
        break;
      case LiveVoiceState.listening:
        orbColor = HermesTheme.accent;
        break;
      case LiveVoiceState.thinking:
        orbColor = HermesTheme.warning;
        break;
      case LiveVoiceState.speaking:
        orbColor = const Color(0xFF38BDF8);
        break;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF07090F),
      body: SafeArea(
        child: Stack(
          children: [
            // 1. 顶部状态栏与控制按钮
            Positioned(
              top: 12,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: HermesTheme.textDim, size: 24),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: HermesTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: HermesTheme.borderSubtle, width: 0.8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.auto_awesome_rounded, size: 12, color: HermesTheme.accent),
                        const SizedBox(width: 5),
                        Text(
                          widget.currentModel.isEmpty ? 'Hermes Live' : widget.currentModel.split('/').last,
                          style: const TextStyle(fontSize: 11, color: HermesTheme.textMain, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      _autoListenLoop ? Icons.all_inclusive_rounded : Icons.touch_app_rounded,
                      color: _autoListenLoop ? HermesTheme.accent : HermesTheme.textDim,
                      size: 20,
                    ),
                    tooltip: _autoListenLoop ? '全自动双工循环开启' : '单次手动点按模式',
                    onPressed: () => setState(() => _autoListenLoop = !_autoListenLoop),
                  ),
                ],
              ),
            ),

            // 2. 核心流体脉冲拟人音球 (Fluid Glowing Voice Orb)
            Center(
              child: GestureDetector(
                onTap: () {
                  if (_state == LiveVoiceState.speaking || _state == LiveVoiceState.thinking) {
                    _interrupt();
                  } else {
                    _startListening();
                  }
                },
                child: AnimatedBuilder(
                  animation: Listenable.merge([_pulseController, _waveController]),
                  builder: (context, child) {
                    final pulse = _pulseController.value;
                    final wave = _waveController.value;

                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        // 外层扩散波纹 (Wave Ring 1)
                        if (_state == LiveVoiceState.speaking || _state == LiveVoiceState.listening)
                          Container(
                            width: 220 + (wave * 50),
                            height: 220 + (wave * 50),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: orbColor.withOpacity((1.0 - wave) * 0.4),
                                width: 2,
                              ),
                            ),
                          ),

                        // 外层呼吸辉光 (Glow Sphere)
                        Container(
                          width: 170 + (pulse * 25),
                          height: 170 + (pulse * 25),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                orbColor.withOpacity(0.4),
                                orbColor.withOpacity(0.1),
                                Colors.transparent,
                              ],
                              stops: const [0.2, 0.6, 1.0],
                            ),
                          ),
                        ),

                        // 核心能量球 (Core Orb)
                        Container(
                          width: 130 + (pulse * 10),
                          height: 130 + (pulse * 10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                orbColor,
                                orbColor.withOpacity(0.7),
                                const Color(0xFF1E1B4B),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: orbColor.withOpacity(0.6),
                                blurRadius: 35,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              _state == LiveVoiceState.listening
                                  ? Icons.mic_rounded
                                  : (_state == LiveVoiceState.speaking
                                      ? Icons.graphic_eq_rounded
                                      : (_state == LiveVoiceState.thinking
                                          ? Icons.psychology_rounded
                                          : Icons.touch_app_rounded)),
                              size: 44,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),

            // 3. 底部实时字幕与控制区
            Positioned(
              bottom: 30,
              left: 20,
              right: 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 实时动态字幕条
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    constraints: const BoxConstraints(minHeight: 48, maxHeight: 110),
                    decoration: BoxDecoration(
                      color: HermesTheme.surfaceGlass,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: HermesTheme.borderSubtle, width: 0.9),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        _liveSubtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                          color: _state == LiveVoiceState.listening
                              ? HermesTheme.accent
                              : (_state == LiveVoiceState.speaking
                                  ? const Color(0xFF38BDF8)
                                  : HermesTheme.textMain),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 底部动作按钮行
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // 打断 / 暂停按钮
                      IconButton.filledTonal(
                        style: IconButton.styleFrom(
                          backgroundColor: HermesTheme.surfaceLight,
                          minimumSize: const Size(48, 48),
                        ),
                        icon: const Icon(Icons.stop_rounded, size: 22, color: HermesTheme.warning),
                        tooltip: '打断发言',
                        onPressed: _interrupt,
                      ),

                      // 核心麦克风按键
                      IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: orbColor,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(64, 64),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                        ),
                        icon: Icon(
                          _state == LiveVoiceState.listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                          size: 30,
                        ),
                        onPressed: () {
                          if (_state == LiveVoiceState.listening) {
                            // 手动停止
                            setState(() => _state = LiveVoiceState.ready);
                          } else {
                            _startListening();
                          }
                        },
                      ),

                      // 对话历史速览按钮
                      IconButton.filledTonal(
                        style: IconButton.styleFrom(
                          backgroundColor: HermesTheme.surfaceLight,
                          minimumSize: const Size(48, 48),
                        ),
                        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 22, color: HermesTheme.textMain),
                        tooltip: '速览语音转写历史',
                        onPressed: _showTranscriptSheet,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTranscriptSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: HermesTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: HermesTheme.borderSubtle,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text('本次 Live 语音转写记录', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: HermesTheme.textMain)),
              const SizedBox(height: 12),
              if (_transcriptHistory.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('暂无语音转写记录', style: TextStyle(color: HermesTheme.textDim, fontSize: 13)),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _transcriptHistory.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = _transcriptHistory[index];
                      final isUser = item['role'] == 'user';
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isUser ? HermesTheme.surfaceLight : HermesTheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: HermesTheme.borderSubtle),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isUser ? '👤 您' : '🤖 Hermes Agent',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isUser ? HermesTheme.accent : HermesTheme.primaryLight,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(item['text']!, style: const TextStyle(fontSize: 13, color: HermesTheme.textMain)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

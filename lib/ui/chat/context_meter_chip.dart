import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../services/hermes_gateway_service.dart';

class ContextMeterChip extends StatefulWidget {
  final HermesGatewayService gateway;
  final String sessionId;
  final ValueChanged<String>? onSendCompactionPrompt;

  const ContextMeterChip({
    super.key,
    required this.gateway,
    required this.sessionId,
    this.onSendCompactionPrompt,
  });

  @override
  State<ContextMeterChip> createState() => _ContextMeterChipState();
}

class _ContextMeterChipState extends State<ContextMeterChip> {
  Map<String, dynamic>? _contextData;

  @override
  void initState() {
    super.initState();
    _fetchContext();
  }

  @override
  void didUpdateWidget(covariant ContextMeterChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId &&
        widget.sessionId.isNotEmpty) {
      _fetchContext();
    }
  }

  Future<void> _fetchContext() async {
    if (widget.sessionId.isEmpty || !widget.gateway.supportsJsonRpc) return;
    try {
      final res = await widget.gateway.sessionContext(widget.sessionId);
      if (mounted) {
        setState(() {
          _contextData = res;
        });
      }
    } catch (_) {}
  }

  void _showContextDetails() {
    final data = _contextData ?? {};
    final used = (data['context_used'] as num?)?.toInt() ?? 0;
    final max = (data['context_max'] as num?)?.toInt() ?? 128000;
    final percent = max > 0 ? (used / max * 100).clamp(0, 100) : 0;
    final model = data['model']?.toString() ?? 'Default';

    showModalBottomSheet(
      context: context,
      backgroundColor: HermesTheme.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pie_chart_outline_rounded,
                    color: HermesTheme.accent, size: 20),
                const SizedBox(width: 8),
                const Text(
                  '会话上下文 Token 透视盘',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: HermesTheme.textMain),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded,
                      size: 18, color: HermesTheme.textDim),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _fetchContext();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: HermesTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: HermesTheme.borderSubtle),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '模型: $model',
                        style: const TextStyle(
                            fontSize: 12, color: HermesTheme.textMuted),
                      ),
                      Text(
                        '${percent.toStringAsFixed(1)}% 已用',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: percent > 80
                              ? HermesTheme.danger
                              : (percent > 60
                                  ? HermesTheme.warning
                                  : HermesTheme.accent),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: percent / 100,
                    backgroundColor: HermesTheme.surfaceLight,
                    color: percent > 80
                        ? HermesTheme.danger
                        : (percent > 60
                            ? HermesTheme.warning
                            : HermesTheme.accent),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '当前: $used Tokens',
                        style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: HermesTheme.textDim),
                      ),
                      Text(
                        '窗口上限: $max Tokens',
                        style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: HermesTheme.textDim),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: HermesTheme.primary,
                minimumSize: const Size.fromHeight(40),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                widget.onSendCompactionPrompt?.call(
                    '请将我们之前的关键决策、重要参数与系统状态总结提炼为一份精简备忘录，帮助压缩上下文，以便后续高效协作。');
              },
              icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
              label: const Text('✨ 提炼精炼记忆 (释放 Token 压力)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.gateway.supportsJsonRpc) return const SizedBox.shrink();

    final data = _contextData ?? {};
    final used = (data['context_used'] as num?)?.toInt() ?? 0;
    final max = (data['context_max'] as num?)?.toInt() ?? 0;
    final percent = max > 0 ? (used / max * 100).clamp(0, 100) : 0;

    String label = 'Tokens';
    if (used > 0) {
      label = used > 1000
          ? '${(used / 1000).toStringAsFixed(1)}k'
          : used.toString();
    }

    return InkWell(
      onTap: _showContextDetails,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: HermesTheme.surfaceLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: HermesTheme.borderSubtle, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.data_usage_rounded,
                size: 12,
                color: percent > 80 ? HermesTheme.danger : HermesTheme.accent),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: HermesTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

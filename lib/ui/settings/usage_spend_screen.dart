import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/storage.dart';

class UsageSpendScreen extends StatefulWidget {
  const UsageSpendScreen({super.key});

  @override
  State<UsageSpendScreen> createState() => _UsageSpendScreenState();
}

class _UsageSpendScreenState extends State<UsageSpendScreen> {
  final HermesStorage _storage = HermesStorage();
  Map<String, dynamic> _stats = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    final stats = await _storage.getUsageStatistics();
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final promptTokens = (_stats['totalPromptTokens'] as num?)?.toInt() ?? 0;
    final completionTokens = (_stats['totalCompletionTokens'] as num?)?.toInt() ?? 0;
    final totalTokens = promptTokens + completionTokens;
    final totalRequests = (_stats['totalRequests'] as num?)?.toInt() ?? 0;
    final models = (_stats['models'] as Map<String, dynamic>?) ?? {};

    // 预估花费 (按混合模型 $0.002 / 1k Tokens 计算)
    final estimatedCostUsd = (totalTokens / 1000.0) * 0.002;
    final estimatedCostCny = estimatedCostUsd * 7.25;

    return Scaffold(
      backgroundColor: HermesTheme.background,
      appBar: AppBar(
        title: const Text('Token 用量与开销大盘', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: HermesTheme.textMain)),
        actions: [
          IconButton(
            tooltip: '刷新数据',
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: _loadStats,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: HermesTheme.primary))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
              children: [
                // 1. 核心开销与总量总览卡片 (KPI Card)
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF1E1B4B), Color(0xFF141926)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: HermesTheme.primary.withOpacity(0.4)),
                    boxShadow: const [
                      BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4)),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.account_balance_wallet_outlined, size: 18, color: HermesTheme.accent),
                          SizedBox(width: 8),
                          Text('预估 API 累计算力开销', style: TextStyle(fontSize: 12, color: HermesTheme.textMuted)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '\$${estimatedCostUsd.toStringAsFixed(3)}',
                            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: HermesTheme.textMain),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '≈ ¥${estimatedCostCny.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 14, color: HermesTheme.accent, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(color: HermesTheme.borderSubtle, height: 1),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildMetricCol('总 Token 消耗', _formatNumber(totalTokens)),
                          _buildMetricCol('输入 (Prompt)', _formatNumber(promptTokens)),
                          _buildMetricCol('输出 (Completion)', _formatNumber(completionTokens)),
                          _buildMetricCol('总请求数', '$totalRequests 次'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 2. 模型用量细分占比
                const Text('各模型算力分布明细', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: HermesTheme.textMain)),
                const SizedBox(height: 10),
                if (models.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: HermesTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: HermesTheme.borderSubtle),
                    ),
                    child: const Center(
                      child: Text('当前暂无模型请求记录，下发指令后将在此自动统计', style: TextStyle(fontSize: 12, color: HermesTheme.textDim)),
                    ),
                  )
                else
                  ...models.entries.map((entry) {
                    final modelName = entry.key;
                    final mData = entry.value as Map<String, dynamic>;
                    final mPrompt = (mData['promptTokens'] as num?)?.toInt() ?? 0;
                    final mCompletion = (mData['completionTokens'] as num?)?.toInt() ?? 0;
                    final mTotal = mPrompt + mCompletion;
                    final mRequests = (mData['requests'] as num?)?.toInt() ?? 0;
                    final ratio = totalTokens > 0 ? (mTotal / totalTokens).clamp(0.0, 1.0) : 0.0;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: HermesTheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: HermesTheme.borderSubtle),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(modelName, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: HermesTheme.textMain)),
                              Text('${(ratio * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: HermesTheme.primaryLight)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: ratio,
                            backgroundColor: HermesTheme.surfaceLight,
                            color: HermesTheme.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Token 消耗: ${_formatNumber(mTotal)}', style: const TextStyle(fontSize: 11, color: HermesTheme.textMuted)),
                              Text('请求: $mRequests 次', style: const TextStyle(fontSize: 11, color: HermesTheme.textDim)),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
    );
  }

  Widget _buildMetricCol(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10.5, color: HermesTheme.textDim)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: HermesTheme.textMain)),
      ],
    );
  }

  String _formatNumber(int num) {
    if (num >= 1000000) return '${(num / 1000000.0).toStringAsFixed(2)}M';
    if (num >= 1000) return '${(num / 1000.0).toStringAsFixed(1)}k';
    return num.toString();
  }
}

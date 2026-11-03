import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';

class DiffCardView extends StatelessWidget {
  final String diffText;

  const DiffCardView({super.key, required this.diffText});

  @override
  Widget build(BuildContext context) {
    final lines = diffText.split('\n');
    int additions = 0;
    int deletions = 0;
    String fileName = 'Code Patch';

    for (final line in lines) {
      if (line.startsWith('+++ b/')) {
        fileName = line.replaceFirst('+++ b/', '').trim();
      } else if (line.startsWith('+') && !line.startsWith('+++')) {
        additions++;
      } else if (line.startsWith('-') && !line.startsWith('---')) {
        deletions++;
      }
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF090D17),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: HermesTheme.borderSubtle, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Diff 顶部标题栏与改动统计
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: const BoxDecoration(
              color: Color(0xFF131929),
              borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
            ),
            child: Row(
              children: [
                const Icon(Icons.difference_rounded,
                    size: 13, color: HermesTheme.primaryLight),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    fileName,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: HermesTheme.textMain,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (additions > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: HermesTheme.accent.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '+$additions',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: HermesTheme.accent,
                      ),
                    ),
                  ),
                if (deletions > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: HermesTheme.danger.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '-$deletions',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: HermesTheme.danger,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.copy_rounded,
                      size: 13, color: HermesTheme.textDim),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: '复制完整 Diff 补丁',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: diffText));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已复制 Diff 补丁内容'),
                        duration: Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Diff 行列表
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: lines.map((line) {
                Color? bg;
                Color textColor = const Color(0xFFCBD5E1);
                FontWeight weight = FontWeight.normal;

                if (line.startsWith('+') && !line.startsWith('+++')) {
                  bg = const Color(0x2210B981);
                  textColor = const Color(0xFF34D399);
                } else if (line.startsWith('-') && !line.startsWith('---')) {
                  bg = const Color(0x22EF4444);
                  textColor = const Color(0xFFF87171);
                } else if (line.startsWith('@@')) {
                  bg = const Color(0x18818CF8);
                  textColor = const Color(0xFFA5B4FC);
                  weight = FontWeight.bold;
                } else if (line.startsWith('diff --git') ||
                    line.startsWith('index ') ||
                    line.startsWith('---') ||
                    line.startsWith('+++')) {
                  textColor = const Color(0xFF94A3B8);
                  weight = FontWeight.w600;
                }

                return Container(
                  width: double.infinity,
                  color: bg,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 1.5),
                  child: SelectableText(
                    line,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: textColor,
                      fontWeight: weight,
                      height: 1.35,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

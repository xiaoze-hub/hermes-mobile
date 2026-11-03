import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';

class AnsiTerminalView extends StatelessWidget {
  final String text;
  final double fontSize;
  final int? maxLines;

  const AnsiTerminalView({
    super.key,
    required this.text,
    this.fontSize = 11.5,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    final spans = _parseAnsi(text);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF090D16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: HermesTheme.borderSubtle, width: 0.8),
      ),
      child: SelectableText.rich(
        TextSpan(children: spans),
        maxLines: maxLines,
      ),
    );
  }

  List<TextSpan> _parseAnsi(String input) {
    if (!input.contains('\x1b[')) {
      return [
        TextSpan(
          text: input,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: fontSize,
            color: const Color(0xFFCAD1E0),
            height: 1.45,
          ),
        ),
      ];
    }

    final spans = <TextSpan>[];
    final regex = RegExp(r'\x1b\[([0-9;]*)m');
    int lastEnd = 0;
    Color currentColor = const Color(0xFFCAD1E0);
    FontWeight currentWeight = FontWeight.normal;

    for (final match in regex.allMatches(input)) {
      if (match.start > lastEnd) {
        final chunk = input.substring(lastEnd, match.start);
        spans.add(TextSpan(
          text: chunk,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: fontSize,
            color: currentColor,
            fontWeight: currentWeight,
            height: 1.45,
          ),
        ));
      }

      final codes = (match.group(1) ?? '')
          .split(';')
          .map((c) => int.tryParse(c) ?? 0)
          .toList();

      if (codes.isEmpty || codes.contains(0)) {
        currentColor = const Color(0xFFCAD1E0);
        currentWeight = FontWeight.normal;
      }
      if (codes.contains(1)) {
        currentWeight = FontWeight.bold;
      }
      for (final code in codes) {
        switch (code) {
          case 30:
            currentColor = const Color(0xFF4B5563);
            break; // Black/Gray
          case 31:
            currentColor = const Color(0xFFF87171);
            break; // Red
          case 32:
            currentColor = const Color(0xFF34D399);
            break; // Green
          case 33:
            currentColor = const Color(0xFFFBBF24);
            break; // Yellow
          case 34:
            currentColor = const Color(0xFF60A5FA);
            break; // Blue
          case 35:
            currentColor = const Color(0xFFC084FC);
            break; // Magenta
          case 36:
            currentColor = const Color(0xFF38BDF8);
            break; // Cyan
          case 37:
            currentColor = const Color(0xFFF3F4F6);
            break; // White
          case 90:
            currentColor = const Color(0xFF6B7280);
            break; // Bright Black
          case 91:
            currentColor = const Color(0xFFEF4444);
            break; // Bright Red
          case 92:
            currentColor = const Color(0xFF10B981);
            break; // Bright Green
          case 93:
            currentColor = const Color(0xFFF59E0B);
            break; // Bright Yellow
          case 94:
            currentColor = const Color(0xFF3B82F6);
            break; // Bright Blue
          case 95:
            currentColor = const Color(0xFFA855F7);
            break; // Bright Magenta
          case 96:
            currentColor = const Color(0xFF06B6D4);
            break; // Bright Cyan
          case 97:
            currentColor = Colors.white;
            break;
        }
      }

      lastEnd = match.end;
    }

    if (lastEnd < input.length) {
      spans.add(TextSpan(
        text: input.substring(lastEnd),
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: fontSize,
          color: currentColor,
          fontWeight: currentWeight,
          height: 1.45,
        ),
      ));
    }

    return spans;
  }
}

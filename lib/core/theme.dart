import 'package:flutter/material.dart';

/// Hermes Design System - Claude 优雅流体 × 特工中控台 (Cyber Command Deck)
class HermesTheme {
  // 深空黑曜石阶梯背景
  static const Color background = Color(0xFF090C15);     // 纯粹底色
  static const Color surface = Color(0xFF111625);        // 容器卡片底色
  static const Color surfaceLight = Color(0xFF192035);   // 高亮控制表面
  static const Color surfaceElevated = Color(0xFF202942);// 浮层与弹窗
  static const Color surfaceGlass = Color(0xDD111625);   // 毛玻璃半透底色

  // 先进品牌与功能状态色
  static const Color primary = Color(0xFF6366F1);        // Hermes 主题紫
  static const Color primaryLight = Color(0xFF818CF8);   // 高亮淡紫
  static const Color primaryDark = Color(0xFF4F46E5);    // 渐变深紫
  static const Color accent = Color(0xFF10B981);         // 翡翠终端绿 (Connected / Shell)
  static const Color warning = Color(0xFFF59E0B);        // 思考脉冲金 (Thinking / Running)
  static const Color danger = Color(0xFFEF4444);         // 告警绯红 (OOM / Error)
  static const Color cyan = Color(0xFF06B6D4);           // 遥测电光蓝 (Telemetry)

  // 文字分级系统
  static const Color textMain = Color(0xFFF8FAFC);       // 一级正文
  static const Color textMuted = Color(0xFF94A3B8);      // 二级描述
  static const Color textDim = Color(0xFF64748B);        // 三级注脚/时间戳

  // 极细边界线 (1px Fine Border)
  static const Color border = Color(0xFF1E273C);
  static const Color borderSubtle = Color(0xFF283450);
  static const Color borderHighlight = Color(0xFF38466B);

  // 氛围光效 (Atmospheric Glow)
  static const BoxShadow primaryGlow = BoxShadow(
    color: Color(0x336366F1),
    blurRadius: 16,
    spreadRadius: -2,
    offset: Offset(0, 4),
  );

  static const BoxShadow elevation1 = BoxShadow(
    color: Color(0x22000000),
    blurRadius: 8,
    offset: Offset(0, 2),
  );

  static const BoxShadow thinkingGlow = BoxShadow(
    color: Color(0x22F59E0B),
    blurRadius: 12,
    spreadRadius: -2,
  );

  static const LinearGradient userBubbleGradient = LinearGradient(
    colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient assistantBubbleGradient = LinearGradient(
    colors: [Color(0xFF1E273C), Color(0xFF161C2C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: accent,
        surface: surface,
        onSurface: textMain,
        error: danger,
      ),
      fontFamily: 'sans-serif',
      appBarTheme: const AppBarTheme(
        backgroundColor: surfaceGlass,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: textMain,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
      cardTheme: CardTheme(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        hintStyle: const TextStyle(color: textDim, fontSize: 13),
      ),
    );
  }
}

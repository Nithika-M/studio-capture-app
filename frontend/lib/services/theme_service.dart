import 'package:flutter/material.dart';

class AppColors {
  final BuildContext context;
  AppColors(this.context);

  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  Color get bg => isDark ? const Color(0xFF0F1117) : const Color(0xFFFAFAFC);
  Color get surface => isDark ? const Color(0xFF1A1D26) : Colors.white;
  Color get surfaceSecondary => isDark ? const Color(0xFF242836) : const Color(0xFFF3F4F6);
  Color get surfaceMuted => isDark ? const Color(0xFF1E222E) : const Color(0xFFF9FAFB);
  Color get border => isDark ? const Color(0xFF2E3342) : const Color(0xFFE5E7EB);
  Color get borderLight => isDark ? const Color(0xFF242836) : const Color(0xFFF3F4F6);
  Color get textPrimary => isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
  Color get textSecondary => isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
  Color get textTertiary => isDark ? const Color(0xFF6B7280) : const Color(0xFF9CA3AF);
  Color get primary => const Color(0xFFDC2626);
  Color get primaryBg => isDark ? const Color(0xFF381515) : const Color(0xFFFEF2F2);
  Color get primaryBorder => isDark ? const Color(0xFF5C1D1D) : const Color(0xFFFECACA);
  Color get iconColor => isDark ? const Color(0xFFD1D5DB) : const Color(0xFF374151);
}

extension AppThemeContext on BuildContext {
  AppColors get appColors => AppColors(this);
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

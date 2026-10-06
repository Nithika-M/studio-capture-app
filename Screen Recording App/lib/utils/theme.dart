import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color primary = Color(0xFFDC2626); // #dc2626 red
  static const Color primaryContainer = Color(0xFFDC2626);
  static const Color background = Color(0xFFF8F9FA); // #f8f9fa
  static const Color surface = Color(0xFFFFFFFF); // #ffffff
  static const Color textPrimary = Color(0xFF111827); // #111827 slate-900
  static const Color textSecondary = Color(0xFF64748B); // #64748b slate-500
  static const Color textMuted = Color(0xFF94A3B8); // slate-400
  static const Color border = Color(0xFFE2E8F0); // #e2e8f0 border-slate-200
  static const Color borderDark = Color(0xFFCBD5E1); // #cbd5e1 border-slate-300
  static const Color error = Color(0xFFEF4444); // #ef4444 red-500
  static const Color success = Color(0xFF10B981); // emerald-500
  static const Color cardBg = Color(0xFFFFFFFF);
  static const Color chipBg = Color(0xFFF1F5F9); // slate-100
}

class AppTheme {
  static ThemeData get lightTheme {
    final baseTextTheme = ThemeData.light().textTheme;
    
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        background: AppColors.background,
        onBackground: AppColors.textPrimary,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.error,
        onError: Colors.white,
        outline: AppColors.border,
      ),
      textTheme: GoogleFonts.hankenGroteskTextTheme(baseTextTheme).copyWith(
        displayLarge: GoogleFonts.manrope(
          fontSize: 40, fontWeight: FontWeight.w800, color: AppColors.textPrimary, height: 1.2,
        ),
        headlineLarge: GoogleFonts.manrope(
          fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.25,
        ),
        headlineMedium: GoogleFonts.manrope(
          fontSize: 24, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.3,
        ),
        headlineSmall: GoogleFonts.manrope(
          fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.4,
        ),
        titleLarge: GoogleFonts.manrope(
          fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.44,
        ),
        titleMedium: GoogleFonts.manrope(
          fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.5,
        ),
        bodyLarge: GoogleFonts.hankenGrotesk(
          fontSize: 16, fontWeight: FontWeight.w400, color: AppColors.textPrimary, height: 1.5,
        ),
        bodyMedium: GoogleFonts.hankenGrotesk(
          fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textSecondary, height: 1.43,
        ),
        bodySmall: GoogleFonts.hankenGrotesk(
          fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondary, height: 1.33,
        ),
        labelLarge: GoogleFonts.hankenGrotesk(
          fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.43,
        ),
        labelMedium: GoogleFonts.hankenGrotesk(
          fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary, height: 1.33,
        ),
        labelSmall: GoogleFonts.hankenGrotesk(
          fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary, height: 1.4,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
    );
  }
}

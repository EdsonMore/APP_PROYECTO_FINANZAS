import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_config.dart';

/// Tema oscuro global de SaldoClaro.
abstract final class AppTheme {
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: const Color(ColorConfig.background),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(ColorConfig.accent),
        brightness: Brightness.dark,
        surface: const Color(ColorConfig.surface),
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
        bodyColor: const Color(ColorConfig.textPrimary),
        displayColor: const Color(ColorConfig.textPrimary),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(ColorConfig.background),
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: const CardThemeData(
        color: Color(ColorConfig.surface),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(ColorConfig.surfaceAlt),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(ColorConfig.accent),
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(ColorConfig.surfaceAlt),
        contentTextStyle: TextStyle(color: Color(ColorConfig.textPrimary)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

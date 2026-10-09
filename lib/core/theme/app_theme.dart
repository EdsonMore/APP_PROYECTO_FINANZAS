import 'package:flutter/material.dart';

import 'tokens.dart';

/// ThemeData claro y oscuro construidos solo desde [Palette] y los tokens.
abstract final class AppTheme {
  static final light = _build(Palette.light, Brightness.light);
  static final dark = _build(Palette.dark, Brightness.dark);

  static ThemeData _build(Palette p, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: p.ink,
      onPrimary: p.canvas,
      secondary: p.inkMuted,
      onSecondary: p.canvas,
      error: p.expenseFg,
      onError: p.surface,
      surface: p.surface,
      onSurface: p.ink,
      onSurfaceVariant: p.inkMuted,
      outline: p.border,
      outlineVariant: p.border,
    );

    TextStyle c(TextStyle s, [Color? color]) => s.copyWith(color: color ?? p.ink);

    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.button));

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.canvas,
      fontFamily: AppType.sans,
      splashFactory: NoSplash.splashFactory,
      extensions: [p],
      textTheme: TextTheme(
        displayLarge: c(AppType.display),
        headlineMedium: c(AppType.title),
        titleMedium: c(AppType.heading),
        bodyLarge: c(AppType.body),
        bodyMedium: c(AppType.body),
        labelLarge: c(AppType.label),
        bodySmall: c(AppType.caption, p.inkMuted),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: p.canvas,
        foregroundColor: p.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: c(AppType.title),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: BorderSide(color: p.border),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.ink,
          foregroundColor: p.canvas,
          minimumSize: const Size.fromHeight(Space.ctaHeight),
          textStyle: AppType.button,
          shape: buttonShape,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.ink,
          minimumSize: const Size.fromHeight(Space.ctaHeight),
          textStyle: AppType.button,
          shape: buttonShape,
          side: BorderSide(color: p.border),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: p.ink, textStyle: AppType.label),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: p.ink,
        labelStyle: c(AppType.label),
        secondaryLabelStyle: c(AppType.label, p.canvas),
        side: BorderSide(color: p.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.chip)),
        showCheckmark: false,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        modalBackgroundColor: p.surface,
        elevation: 0,
        showDragHandle: true,
        dragHandleColor: p.border,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        hintStyle: c(AppType.body, p.inkMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.button),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.button),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.button),
          borderSide: BorderSide(color: p.ink),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.canvas,
        indicatorColor: p.border,
        elevation: 0,
        labelTextStyle: WidgetStatePropertyAll(c(AppType.caption)),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      }),
    );
  }
}

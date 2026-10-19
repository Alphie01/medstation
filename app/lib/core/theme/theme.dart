import 'package:flutter/material.dart';

import 'tokens.dart';

const display = 'Bricolage';
const body = 'InstrumentSans';

/// Variable fonts need the weight axis set explicitly on every platform.
TextStyle displayStyle(double size, {FontWeight weight = FontWeight.w700, Color? color, double height = 1.05}) =>
    TextStyle(
      fontFamily: display,
      fontSize: size,
      fontWeight: weight,
      fontVariations: [FontVariation.weight(weight.value.toDouble())],
      letterSpacing: size >= 30 ? -0.035 * size : -0.02 * size,
      height: height,
      color: color,
    );

TextStyle bodyStyle(double size, {FontWeight weight = FontWeight.w400, Color? color, double height = 1.4}) =>
    TextStyle(
      fontFamily: body,
      fontSize: size,
      fontWeight: weight,
      fontVariations: [FontVariation.weight(weight.value.toDouble())],
      height: height,
      color: color,
    );

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: EtkenColors.navy,
      primary: EtkenColors.navy,
      secondary: EtkenColors.coral,
      surface: EtkenColors.surface,
      onSurface: EtkenColors.ink,
      error: EtkenColors.riskCritical,
    ),
    scaffoldBackgroundColor: EtkenColors.bg,
    fontFamily: body,
  );
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineLarge: displayStyle(40, weight: FontWeight.w800, height: 0.98, color: EtkenColors.ink),
      headlineMedium: displayStyle(28, weight: FontWeight.w800, color: EtkenColors.ink),
      titleLarge: displayStyle(21, color: EtkenColors.ink),
      titleMedium: bodyStyle(16, color: EtkenColors.ink),
      bodyLarge: bodyStyle(17, color: EtkenColors.ink),
      bodyMedium: bodyStyle(15, color: EtkenColors.ink),
      bodySmall: bodyStyle(13, color: EtkenColors.muted),
      labelLarge: bodyStyle(16, weight: FontWeight.w700, color: EtkenColors.ink),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: EtkenColors.surface,
      hintStyle: bodyStyle(16, color: EtkenColors.placeholder),
      labelStyle: bodyStyle(15, color: EtkenColors.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: EtkenColors.lineStrong)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: EtkenColors.lineStrong)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: EtkenColors.coral, width: 2)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: EtkenColors.navy,
        foregroundColor: Colors.white,
        minimumSize: const Size(44, 54),
        textStyle: bodyStyle(17, weight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: EtkenColors.ink,
      contentTextStyle: bodyStyle(15, color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerColor: EtkenColors.lineSoft,
  );
}

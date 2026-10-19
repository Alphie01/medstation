import 'package:flutter/material.dart';

/// Colour and shape tokens from the MedStation reference design.
abstract final class EtkenColors {
  static const ink = Color(0xFF1B1340);
  static const navy = Color(0xFF2B1E6B);
  static const coral = Color(0xFFFF6B4A);
  static const bg = Color(0xFFF3F1FA);
  static const surface = Color(0xFFFFFFFF);
  static const muted = Color(0xFF5E5880);
  static const placeholder = Color(0xFF9A94B8);
  static const line = Color(0xFFE6E2F2);
  static const lineSoft = Color(0xFFEEEBF6);
  static const lineStrong = Color(0xFFDCD7EC);

  static const blue = Color(0xFF3F6BFF);
  static const amber = Color(0xFFFFB321);
  static const green = Color(0xFF1DBF8E);
  static const lavender = Color(0xFFA68CFF);

  // Risk levels: distinct in lightness as well as hue, always paired with an
  // icon and a text label.
  static const riskCritical = Color(0xFFB42318);
  static const riskCriticalTint = Color(0xFFFDE4E1);
  static const riskMajor = Color(0xFF8A5A00);
  static const riskMajorTint = Color(0xFFFFF0CC);
  static const riskInfo = Color(0xFF2546C7);
  static const riskInfoTint = Color(0xFFE2E8FF);
  static const riskUnknown = Color(0xFF5E5880);
  static const riskUnknownTint = Color(0xFFECEAF4);

  /// Commercial products are always shown in this separate colour.
  static const commercial = Color(0xFF0E7A5A);
  static const commercialTint = Color(0xFFD5F4E9);
}

/// Ingredient colour + tint pair, assigned deterministically by name.
class IngredientColor {
  const IngredientColor(this.color, this.tint, this.onColor);
  final Color color;
  final Color tint;
  final Color onColor;
}

const _palette = [
  IngredientColor(EtkenColors.coral, Color(0xFFFFE3DB), EtkenColors.ink),
  IngredientColor(EtkenColors.blue, Color(0xFFE2E8FF), Colors.white),
  IngredientColor(EtkenColors.amber, Color(0xFFFFF0CC), EtkenColors.ink),
  IngredientColor(EtkenColors.lavender, Color(0xFFECE6FF), EtkenColors.ink),
  IngredientColor(EtkenColors.green, Color(0xFFD5F4E9), EtkenColors.ink),
];

IngredientColor ingredientColor(String name) {
  var h = 0;
  for (final c in name.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return _palette[h % _palette.length];
}

abstract final class EtkenRadius {
  static const card = 26.0;
  static const tile = 20.0;
  static const cta = 22.0;
  static const button = 15.0;
  static const hero = 36.0;
}

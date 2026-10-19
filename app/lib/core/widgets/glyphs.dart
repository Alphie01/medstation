import 'dart:math' as math;

import 'package:medstation_core/medstation_core.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum GlyphShape { capsule, tablet, bottle }

GlyphShape shapeFor(Drug d) => switch (d.formGroup) {
      FormGroup.sivi => GlyphShape.bottle,
      _ when (d.form ?? '').toLowerCase().contains('kapl') || (d.form ?? '').toLowerCase().contains('kaps') =>
        GlyphShape.capsule,
      _ => GlyphShape.tablet,
    };

/// Two-tone pill glyphs from the reference design (rotated -32°).
class PillGlyph extends StatelessWidget {
  const PillGlyph({super.key, required this.a, Color? b, this.size = 50, this.shape = GlyphShape.capsule, this.shadow = true})
      : b = b ?? a;

  factory PillGlyph.forDrug(Drug d, {double size = 50, Key? key}) {
    final ings = d.ingredients;
    final a = ings.isEmpty ? EtkenColors.placeholder : ingredientColor(baseIngredient(ings[0].name)).color;
    final b = ings.length > 1 ? ingredientColor(baseIngredient(ings[1].name)).color : a;
    return PillGlyph(key: key, a: a, b: b, size: size, shape: shapeFor(d));
  }

  final Color a;
  final Color b;
  final double size;
  final GlyphShape shape;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    if (shape == GlyphShape.bottle) {
      return CustomPaint(size: Size(size * 0.6, size * 0.92), painter: _BottlePainter(a));
    }
    final isTab = shape == GlyphShape.tablet;
    final w = isTab ? size * 0.62 : size;
    final h = isTab ? size * 0.62 : size * 0.4;
    return Transform.rotate(
      angle: -32 * math.pi / 180,
      child: Container(
        width: w,
        height: h,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          boxShadow: shadow
              ? [BoxShadow(color: EtkenColors.ink.withValues(alpha: 0.22), blurRadius: size / 5, offset: Offset(0, size / 10))]
              : null,
        ),
        child: Stack(children: [
          Positioned.fill(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: ColoredBox(color: a)), Expanded(child: ColoredBox(color: b))])),
          Positioned(
            left: w * 0.15,
            top: h * 0.16,
            child: Container(
              width: w * 0.37,
              height: h * 0.2,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(99)),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(height: math.max(2, size / 16), color: Colors.black.withValues(alpha: 0.14)),
          ),
        ]),
      ),
    );
  }
}

class _BottlePainter extends CustomPainter {
  _BottlePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final sx = s.width / 40, sy = s.height / 64;
    RRect r(double x, double y, double w, double h, double rad) =>
        RRect.fromRectAndRadius(Rect.fromLTWH(x * sx, y * sy, w * sx, h * sy), Radius.circular(rad * sx));
    final p = Paint();
    canvas.drawRRect(r(13, 2, 14, 9, 2), p..color = EtkenColors.ink);
    canvas.drawRect(Rect.fromLTWH(15 * sx, 10 * sy, 10 * sx, 7 * sy), p..color = EtkenColors.ink.withValues(alpha: 0.75));
    canvas.drawRRect(r(6, 16, 28, 46, 9), p..color = color);
    canvas.drawRRect(r(10, 32, 20, 16, 3), p..color = Colors.white.withValues(alpha: 0.85));
    canvas.drawRRect(r(10, 20, 4, 36, 2), p..color = Colors.white.withValues(alpha: 0.35));
  }

  @override
  bool shouldRepaint(_BottlePainter old) => old.color != color;
}

/// Small rotated colour dash used beside ingredient names.
class IngredientDot extends StatelessWidget {
  const IngredientDot(this.color, {super.key, this.width = 18});
  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: -30 * math.pi / 180,
        child: Container(
          width: width,
          height: width / 2,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(99)),
        ),
      );
}

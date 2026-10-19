@Tags(['icon'])
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medstation/core/theme/tokens.dart';

/// Renders the MedStation app icon from code, so it stays in sync with the
/// brand tokens. Regenerate with:
///   flutter test tool/app_icon_test.dart && dart run flutter_launcher_icons
class AppIconPainter extends CustomPainter {
  const AppIconPainter({this.background = true, this.scale = 1});

  /// false: transparent background (Android adaptive foreground layer).
  final bool background;

  /// Artwork scale; the adaptive foreground must fit the 66 % safe zone.
  final double scale;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width;
    if (background) {
      canvas.drawRect(Offset.zero & s, Paint()..color = EtkenColors.navy);
      canvas.drawCircle(
        Offset(w * 0.5, w * 0.48),
        w * 0.46,
        Paint()
          ..shader = ui.Gradient.radial(Offset(w * 0.5, w * 0.48), w * 0.46, [
            Colors.white.withValues(alpha: 0.09),
            Colors.white.withValues(alpha: 0),
          ]),
      );
    }
    canvas.save();
    canvas.translate(w / 2, w / 2);
    canvas.scale(scale);
    canvas.translate(-w / 2, -w / 2);

    // Capsule.
    final cw = w * 0.66, ch = w * 0.27;
    final center = Offset(w * 0.5, w * 0.54);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-32 * math.pi / 180);
    final body = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: cw, height: ch), Radius.circular(ch / 2));
    // Soft drop shadow.
    canvas.drawRRect(
      body.shift(Offset(0, ch * 0.16)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, ch * 0.18),
    );
    canvas.save();
    canvas.clipRRect(body);
    canvas.drawRect(Rect.fromLTRB(-cw / 2, -ch / 2, 0, ch / 2), Paint()..color = EtkenColors.coral);
    canvas.drawRect(Rect.fromLTRB(0, -ch / 2, cw / 2, ch / 2), Paint()..color = EtkenColors.blue);
    // Bottom shade and seam.
    canvas.drawRect(Rect.fromLTRB(-cw / 2, ch * 0.30, cw / 2, ch / 2), Paint()..color = Colors.black.withValues(alpha: 0.16));
    canvas.drawRect(Rect.fromLTRB(-ch * 0.025, -ch / 2, ch * 0.025, ch / 2), Paint()..color = Colors.black.withValues(alpha: 0.10));
    canvas.restore();
    // Highlight.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(-cw * 0.36, -ch * 0.30, cw * 0.30, ch * 0.17), Radius.circular(ch)),
      Paint()..color = Colors.white.withValues(alpha: 0.5),
    );
    canvas.restore();

    // Scored amber tablet, apart from the capsule.
    final dot = Offset(w * 0.285, w * 0.295);
    final r = w * 0.092;
    canvas.drawCircle(dot.translate(0, r * 0.14), r,
        Paint()..color = Colors.black.withValues(alpha: 0.22)..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.22));
    canvas.drawCircle(dot, r, Paint()..color = EtkenColors.amber);
    canvas.save();
    canvas.translate(dot.dx, dot.dy);
    canvas.rotate(-32 * math.pi / 180);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: r * 1.25, height: r * 0.15), Radius.circular(r)),
      Paint()..color = EtkenColors.ink.withValues(alpha: 0.2),
    );
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(AppIconPainter old) => old.background != background || old.scale != scale;
}

Future<void> _render(WidgetTester t, String path, AppIconPainter painter) async {
  const size = 1024.0;
  final key = GlobalKey();
  await t.pumpWidget(Center(
    child: RepaintBoundary(
      key: key,
      child: CustomPaint(size: const Size.square(size), painter: painter),
    ),
  ));
  await t.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('render app icon', (t) async {
    t.view.physicalSize = const Size(1024, 1024);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await _render(t, 'assets/icon/app_icon.png', const AppIconPainter());
    await _render(t, 'assets/icon/app_icon_foreground.png', const AppIconPainter(background: false, scale: 0.72));
  });
}

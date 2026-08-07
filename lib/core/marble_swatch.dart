import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/palette_swatch.dart';

/// Soft marble overlays for the Standard palette.
///
/// Flat base color plus deterministic cloud highlights and wandering veins —
/// all soft-edged; underlying fill values stay unchanged.
abstract final class MarbleSwatch {
  static void paint(Canvas canvas, Rect rect, PaletteSwatch swatch) {
    if (!swatch.isMarble || rect.isEmpty) return;

    final color = swatch.start;
    canvas.drawRect(rect, Paint()..color = color);

    canvas.save();
    canvas.clipRect(rect);

    final rng = math.Random(_seedFor(color, swatch.swirlSeed));
    final highlight = _tint(color, 0.32);
    final lightVein = _tint(color, 0.35);
    final darkVein = _tint(color, -0.15);

    _paintClouds(canvas, rect, rng, highlight);
    _paintVeins(canvas, rect, rng, lightVein, darkVein);

    canvas.restore();
  }

  static void _paintClouds(
    Canvas canvas,
    Rect rect,
    math.Random rng,
    Color highlight,
  ) {
    final count = 1 + rng.nextInt(2); // 1–2
    for (var i = 0; i < count; i++) {
      final cx = rect.left + rng.nextDouble() * rect.width;
      final cy = rect.top + rng.nextDouble() * rect.height;
      final radius = rect.shortestSide * (0.22 + rng.nextDouble() * 0.18);
      final opacity = 0.08 + rng.nextDouble() * 0.04; // ~0.08–0.12
      canvas.drawCircle(
        Offset(cx, cy),
        radius,
        Paint()
          ..color = highlight.withValues(alpha: opacity)
          ..maskFilter = ui.MaskFilter.blur(
            ui.BlurStyle.normal,
            radius * 0.7,
          ),
      );
    }
  }

  static void _paintVeins(
    Canvas canvas,
    Rect rect,
    math.Random rng,
    Color lightVein,
    Color darkVein,
  ) {
    final count = 1 + rng.nextInt(2); // 1–2
    for (var i = 0; i < count; i++) {
      final isLight = i.isEven;
      final opacity = 0.10 + rng.nextDouble() * 0.02; // ~0.10–0.12
      final stroke = 1.0 + rng.nextDouble() * 0.5; // ~1.0–1.5
      final paint = Paint()
        ..color = (isLight ? lightVein : darkVein).withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = stroke
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 5.0);

      final path = Path();
      var x = rect.left + rng.nextDouble() * rect.width;
      var y = rect.top;
      path.moveTo(x, y);

      while (y < rect.bottom) {
        final nextX = (x + (rng.nextDouble() - 0.5) * rect.width * 0.25)
            .clamp(rect.left, rect.right);
        final nextY = (y + rect.height * (0.3 + rng.nextDouble() * 0.25))
            .clamp(rect.top, rect.bottom + 1);
        final ctrlX = ((x + nextX) / 2 + (rng.nextDouble() - 0.5) * 10)
            .clamp(rect.left, rect.right);
        final ctrlY = (y + nextY) / 2;
        path.quadraticBezierTo(ctrlX, ctrlY, nextX, nextY);
        x = nextX;
        y = nextY;
        if (nextY >= rect.bottom) break;
      }

      canvas.drawPath(path, paint);
    }
  }

  static Color _tint(Color base, double amount) {
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  /// Stable seed from fill color + slot so the pattern never drifts.
  static int _seedFor(Color color, int swirlSeed) {
    return Object.hash(color.toARGB32(), swirlSeed);
  }
}

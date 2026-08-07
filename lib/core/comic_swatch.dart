import 'package:flutter/material.dart';

import '../models/palette_swatch.dart';

/// Pop-art / comic cel fill for the Neon palette.
///
/// Flat base color, hard shadow wedge with Ben-Day dots, and a thin ink outline.
abstract final class ComicSwatch {
  static const double _dotSpacing = 4.5;
  static const double _dotRadius = 0.95;
  static const double _dotOpacity = 0.18;
  static const double _outlineWidth = 0.5;
  /// Diagonal shadow band starts around here (TL→BR parameter).
  static const double _shadowStart = 0.72;

  static void paint(Canvas canvas, Rect rect, PaletteSwatch swatch) {
    if (!swatch.isNeon || rect.isEmpty) return;

    final base = swatch.start;
    final shadow = Color.lerp(base, Colors.black, 0.30)!;
    final ink = Color.lerp(base, const Color(0xFF0A0A0D), 0.78)!;

    // 1) Flat local color — unchanged hue family, no shader.
    canvas.drawRect(rect, Paint()..color = base);

    canvas.save();
    canvas.clipRect(rect);

    // 2) Hard shadow wedge + Ben-Day dots (comic shading, not a soft gradient).
    canvas.save();
    canvas.clipPath(_shadowPath(rect));
    canvas.drawRect(rect, Paint()..color = shadow);
    _paintHalftone(canvas, rect);
    canvas.restore();

    canvas.restore();

    // 3) Thin ink outline.
    canvas.drawRect(
      rect.deflate(_outlineWidth / 2),
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = _outlineWidth,
    );
  }

  /// Staggered Ben-Day dots (Lichtenstein-style), clipped by caller.
  static void _paintHalftone(Canvas canvas, Rect rect) {
    final w = rect.width;
    final h = rect.height;
    if (w <= 0 || h <= 0) return;

    final paint = Paint()
      ..color = Colors.black.withValues(alpha: _dotOpacity)
      ..blendMode = BlendMode.multiply;

    var row = 0;
    for (var y = _dotSpacing * 0.5; y < h; y += _dotSpacing, row++) {
      final x0 = (row.isOdd ? _dotSpacing * 0.5 : 0.0) + _dotSpacing * 0.5;
      for (var x = x0; x < w; x += _dotSpacing) {
        canvas.drawCircle(
          Offset(rect.left + x, rect.top + y),
          _dotRadius,
          paint,
        );
      }
    }
  }

  /// Hard shadow where diagonal t >= [_shadowStart].
  static Path _shadowPath(Rect rect) {
    final w = rect.width;
    final h = rect.height;
    final k = _shadowStart * 2; // ~1.44
    final xOnBottom = (k - 1.0).clamp(0.0, 1.0) * w;
    final yOnRight = (k - 1.0).clamp(0.0, 1.0) * h;
    return Path()
      ..moveTo(rect.left + xOnBottom, rect.bottom)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.right, rect.top + yOnRight)
      ..close();
  }
}

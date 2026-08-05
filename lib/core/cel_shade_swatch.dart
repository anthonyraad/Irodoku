import 'package:flutter/material.dart';

import '../models/palette_swatch.dart';

/// Cell-shaded (toon) fill for the 1-1 palette: three hard diagonal bands.
///
/// Top-left highlight (~25%), middle base (~55%), bottom-right shadow (~20%).
/// Bands use angular clip paths - no gradient blending.
abstract final class CelShadeSwatch {
  static const double _highlightEnd = 0.25;
  static const double _shadowStart = 0.80;
  static const double _outlineWidth = 1.55;

  static void paint(Canvas canvas, Rect rect, PaletteSwatch swatch) {
    if (!swatch.isCelShade || rect.isEmpty) return;

    final base = swatch.start;
    final highlight = _adjustLightness(base, 0.0825);
    final shadow = _adjustLightness(base, -0.0825);
    final outline = Color.lerp(base, Colors.black, 0.42)!;

    // Base band first; hard clips paint highlight/shadow over it.
    canvas.drawRect(rect, Paint()..color = base);

    canvas.save();
    canvas.clipPath(_highlightPath(rect));
    canvas.drawRect(rect, Paint()..color = highlight);
    canvas.restore();

    canvas.save();
    canvas.clipPath(_shadowPath(rect));
    canvas.drawRect(rect, Paint()..color = shadow);
    canvas.restore();

    canvas.drawRect(
      rect.deflate(_outlineWidth / 2),
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = _outlineWidth,
    );
  }

  /// Diagonal parameter t = ((x-left)/w + (y-top)/h) / 2 along TL->BR.
  /// Highlight where t < [_highlightEnd] (x/w + y/h < 0.5).
  static Path _highlightPath(Rect rect) {
    final w = rect.width;
    final h = rect.height;
    final k = _highlightEnd * 2; // 0.5
    return Path()
      ..moveTo(rect.left, rect.top)
      ..lineTo(rect.left + k * w, rect.top)
      ..lineTo(rect.left, rect.top + k * h)
      ..close();
  }

  /// Shadow where t >= [_shadowStart] (x/w + y/h >= 1.6).
  static Path _shadowPath(Rect rect) {
    final w = rect.width;
    final h = rect.height;
    final k = _shadowStart * 2; // 1.6
    final xOnBottom = (k - 1.0).clamp(0.0, 1.0) * w;
    final yOnRight = (k - 1.0).clamp(0.0, 1.0) * h;
    return Path()
      ..moveTo(rect.left + xOnBottom, rect.bottom)
      ..lineTo(rect.right, rect.bottom)
      ..lineTo(rect.right, rect.top + yOnRight)
      ..close();
  }

  static Color _adjustLightness(Color color, double delta) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + delta).clamp(0.05, 0.95))
        .withSaturation((hsl.saturation * 0.98).clamp(0.0, 1.0))
        .toColor();
  }
}

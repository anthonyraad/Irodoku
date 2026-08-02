import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/palette_swatch.dart';

/// Stark diagonal gloss for Kanto swatches.
///
/// Hard cut along the top-left → bottom-right diagonal: flat lift above,
/// flat shade below — no soft gradient feathering.
abstract final class GlossSwatchShader {
  static Shader? forRect(Rect rect, PaletteSwatch swatch) {
    if (!swatch.isGloss) return null;

    final color = swatch.start;
    final highlight = Color.lerp(color, Colors.white, 0.07)!;
    final shade = Color.lerp(color, Colors.black, 0.06)!;

    // Duplicate stops at 0.5 create an abrupt seam (stark gloss, not a ramp).
    return ui.Gradient.linear(
      rect.topLeft,
      rect.bottomRight,
      [highlight, highlight, shade, shade],
      const [0.0, 0.5, 0.5, 1.0],
    );
  }
}

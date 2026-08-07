import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/palette_swatch.dart';
import 'organic_swatch_motion.dart';

/// GPU swirl fill for gradient palette swatches (Rainbow / Glass / Sky).
///
/// Reuses [FragmentShader] instances across frames. Creating a new shader on
/// every cell paint (especially while Glass/Sky animate) leaks GPU objects and
/// can leave occasional cells unfilled on web — showing the given-cell grey
/// underlay instead of the swatch.
abstract final class OrganicSwatchShader {
  static ui.FragmentProgram? _program;

  /// One shader per unique swatch + quantized paint size so simultaneous draws
  /// with different uniforms don't stomp each other.
  static final Map<int, ui.FragmentShader> _shaders = {};

  static bool get isReady => _program != null;

  static Future<void> ensureLoaded() async {
    _program ??=
        await ui.FragmentProgram.fromAsset('shaders/organic_swatch.frag');
  }

  static Shader? forRect(Rect rect, PaletteSwatch swatch) {
    final program = _program;
    if (program == null || !swatch.isOrganic) return null;

    final w = rect.width;
    final h = rect.height;
    if (w <= 0 || h <= 0) return null;

    final key = Object.hash(
      swatch.swirlSeed,
      swatch.start.toARGB32(),
      swatch.stop.toARGB32(),
      swatch.intensity,
      swatch.animated,
      swatch.motionSpeed,
      // Quantize so minor float noise doesn't explode the cache.
      (w * 4).round(),
      (h * 4).round(),
    );

    final shader = _shaders.putIfAbsent(key, program.fragmentShader);
    shader
      ..setFloat(0, w)
      ..setFloat(1, h)
      ..setFloat(2, swatch.swirlSeed.toDouble());

    _setColor(shader, 3, swatch.start);
    _setColor(shader, 7, swatch.stop);
    shader
      ..setFloat(
        11,
        swatch.animated
            ? OrganicSwatchMotion.timeSeconds * swatch.motionSpeed
            : 0,
      )
      ..setFloat(12, swatch.intensity);

    return shader;
  }

  static void _setColor(ui.FragmentShader shader, int index, Color color) {
    // Color.r/g/b/a are already 0–1 in current Flutter.
    shader
      ..setFloat(index, color.r)
      ..setFloat(index + 1, color.g)
      ..setFloat(index + 2, color.b)
      ..setFloat(index + 3, color.a);
  }
}

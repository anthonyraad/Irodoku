import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/palette_swatch.dart';
import 'organic_swatch_motion.dart';

/// GPU swirl fill for gradient palette swatches (Rainbow / Glass / Sunset).
abstract final class OrganicSwatchShader {
  static ui.FragmentProgram? _program;

  static bool get isReady => _program != null;

  static Future<void> ensureLoaded() async {
    _program ??=
        await ui.FragmentProgram.fromAsset('shaders/organic_swatch.frag');
  }

  static Shader? forRect(Rect rect, PaletteSwatch swatch) {
    final program = _program;
    if (program == null || !swatch.isOrganic) return null;

    final shader = program.fragmentShader()
      ..setFloat(0, rect.width)
      ..setFloat(1, rect.height)
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

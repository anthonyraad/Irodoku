import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/palette_swatch.dart';

/// GPU holographic foil fill for Neon palette swatches.
abstract final class NeonSwatchShader {
  static ui.FragmentProgram? _program;

  static bool get isReady => _program != null;

  static Future<void> ensureLoaded() async {
    _program ??= await ui.FragmentProgram.fromAsset('shaders/neon_swatch.frag');
  }

  static Shader? forRect(Rect rect, PaletteSwatch swatch) {
    final program = _program;
    if (program == null || !swatch.isNeon) return null;

    final shader = program.fragmentShader()
      ..setFloat(0, rect.width)
      ..setFloat(1, rect.height)
      ..setFloat(2, swatch.swirlSeed.toDouble());

    final color = swatch.start;
    shader
      ..setFloat(3, color.r)
      ..setFloat(4, color.g)
      ..setFloat(5, color.b)
      ..setFloat(6, color.a);

    return shader;
  }
}

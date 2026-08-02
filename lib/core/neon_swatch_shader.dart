import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/palette_swatch.dart';
import 'organic_swatch_motion.dart';

/// Soft center glow for Neon palette swatches, with a gentle per-slot breathe.
abstract final class NeonSwatchShader {
  /// Kept for call-site compatibility; glow uses a CPU gradient, not a frag.
  static bool get isReady => true;

  static Future<void> ensureLoaded() async {}

  static Shader? forRect(Rect rect, PaletteSwatch swatch) {
    if (!swatch.isNeon) return null;

    final color = swatch.start;
    final breathe = _breathe(swatch);

    // Soft lift with a clearer peak so the breathe reads without a hard disk.
    final hot = Color.lerp(color, Colors.white, 0.13 + 0.02 * breathe)!;
    final mid = Color.lerp(color, Colors.white, 0.044 + 0.016 * breathe)!;
    final edge = Color.lerp(color, Colors.black, 0.02)!;
    final radius = rect.shortestSide * (1.02 + 0.08 * breathe);

    return ui.Gradient.radial(
      rect.center,
      radius,
      [hot, mid, color, edge],
      const [0.0, 0.42, 0.78, 1.0],
    );
  }

  /// 0–1 oscillation unique per [swatch.swirlSeed] (phase + period desynced).
  static double _breathe(PaletteSwatch swatch) {
    final t = OrganicSwatchMotion.timeSeconds;
    final seed = swatch.swirlSeed;
    // Distinct phase / periods so neighboring slots never pulse in lockstep.
    final phase = seed * 2.3999632;
    // Primary breathe ~1.8–4.7s across slots (desynced via seed mods).
    final period = 1.8 + (seed % 9) * 0.29 + (seed % 5) * 0.145;
    final period2 = period * 1.41 + 0.9;
    final wave = 0.5 + 0.5 * math.sin(t * (math.pi * 2.0) / period + phase);
    final wave2 =
        0.5 + 0.5 * math.sin(t * (math.pi * 2.0) / period2 + phase * 1.31);
    return (wave * 0.72 + wave2 * 0.28).clamp(0.0, 1.0);
  }
}

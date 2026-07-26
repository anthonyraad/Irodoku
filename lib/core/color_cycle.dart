import 'package:flutter/material.dart';

import '../models/game_palette.dart';
import '../models/palette_swatch.dart';
import 'palette.dart';

/// Palette sweep used by the title-tap easter egg on filled cells.
abstract final class ColorCycle {
  static const double staggerSpread = 0.16;

  /// Maps board position to a 0–1 phase lag for a soft diagonal wave.
  static double staggeredPhase(double globalT, int row, int col) {
    if (globalT <= 0) return 0;
    if (globalT >= 1) return 1;

    final delay = ((row * 9 + col) / 81) * staggerSpread;
    if (globalT <= delay) return 0;
    return ((globalT - delay) / (1 - staggerSpread)).clamp(0.0, 1.0);
  }

  /// Cycles [colorValue] through [stepCount] palette steps and back (t=0/1 → original).
  static PaletteSwatch displaySwatch(
    int colorValue,
    double t, {
    required int stepCount,
    required GamePalette palette,
  }) {
    final swatches = IrodokuPalette.swatchesFor(palette);
    final original = IrodokuPalette.swatchForValue(colorValue, palette);
    if (original == null) return swatches.first;
    if (t <= 0 || t >= 1) return original;

    final steps = stepCount.clamp(1, swatches.length);
    final eased = Curves.easeInOutCubic.transform(t);
    // Out-and-back: sweep forward through [steps] colors, then return.
    final sweep = eased < 0.5 ? eased * 2 : (1 - eased) * 2;
    final offset = sweep * steps;

    final startIndex = colorValue - 1;
    final i0 = (startIndex + offset.floor()) % 9;
    final i1 = (startIndex + offset.ceil()) % 9;
    final frac = offset - offset.floor();
    return PaletteSwatch.lerp(swatches[i0], swatches[i1], frac);
  }
}

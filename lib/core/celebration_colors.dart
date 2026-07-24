import 'dart:ui';

import '../models/game_palette.dart';
import 'palette.dart';

abstract final class CelebrationColors {
  /// Smooth rainbow sweep through the palette, then settle to [original].
  ///
  /// [t] is 0–1 for this cell (after stagger). [stagger] offsets the wave.
  static Color colorFor({
    required double t,
    required int stagger,
    required Color original,
    required GamePalette palette,
  }) {
    const cycleEnd = 0.78;
    final clamped = t.clamp(0.0, 1.0);

    if (clamped < cycleEnd) {
      final cycleT = _easeInOutCubic(clamped / cycleEnd);
      return _rainbow(cycleT, stagger, palette);
    }

    final settleT = _easeOutCubic((clamped - cycleEnd) / (1 - cycleEnd));
    final from = _rainbow(1.0, stagger, palette);
    return Color.lerp(from, original, settleT)!;
  }

  static double scaleFor(double t) {
    final clamped = t.clamp(0.0, 1.0);
    // Soft pulse mid-celebration.
    if (clamped < 0.55) {
      final rise = _easeOutCubic(clamped / 0.55);
      return 1.0 + 0.07 * rise;
    }
    final fall = _easeInOutCubic((clamped - 0.55) / 0.45);
    return 1.07 - 0.07 * fall;
  }

  static double shimmerFor(double t) {
    final clamped = t.clamp(0.0, 1.0);
    if (clamped < 0.2) return clamped / 0.2 * 0.18;
    if (clamped < 0.75) return 0.18 * (1 - (clamped - 0.2) / 0.55 * 0.55);
    return 0.08 * (1 - (clamped - 0.75) / 0.25);
  }

  static Color _rainbow(double cycleT, int stagger, GamePalette palette) {
    final colors = IrodokuPalette.colorsFor(palette);
    final pos = (cycleT * colors.length + stagger * 0.45) % colors.length;
    final i = pos.floor();
    final f = _easeInOutCubic(pos - i);
    final a = colors[i % colors.length];
    final b = colors[(i + 1) % colors.length];
    return Color.lerp(a, b, f)!;
  }

  static double _easeInOutCubic(double t) {
    final x = t.clamp(0.0, 1.0);
    return x < 0.5 ? 4 * x * x * x : 1 - (((-2 * x + 2) * (-2 * x + 2) * (-2 * x + 2)) / 2);
  }

  static double _easeOutCubic(double t) {
    final x = 1 - t.clamp(0.0, 1.0);
    return 1 - x * x * x;
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/cell.dart';
import '../models/game_palette.dart';
import '../models/palette_swatch.dart';
import 'palette.dart';

/// Palette sweep used by the title-tap easter egg on filled cells.
abstract final class ColorCycle {
  static const double staggerSpread = 0.16;

  static const Duration oneShotDuration = Duration(milliseconds: 1500);

  /// Wait after press before a picker hold-sweep starts.
  static const Duration holdStartDelay = Duration(milliseconds: 360);

  /// Wait after release before mix-out.
  static const Duration holdReleaseDelay = Duration(milliseconds: 400);

  /// Quick mix-in so the hold sweep is visible right after [holdStartDelay].
  static const Duration holdMixIn = Duration(milliseconds: 50);

  /// Mix-out back to the real colors after [holdReleaseDelay].
  static const Duration holdRamp = Duration(milliseconds: 400);

  /// Hold loop period per out-and-back.
  static const Duration holdCycleDuration = Duration(milliseconds: 3826);

  /// Maps board position to a 0–1 phase lag for a soft diagonal wave.
  static double staggeredPhase(
    double globalT,
    int row,
    int col, {
    double spread = staggerSpread,
  }) {
    if (globalT <= 0) return 0;
    if (globalT >= 1) return 1;

    final lag = spread.clamp(0.0, 0.9);
    final delay = ((row * 9 + col) / 81) * lag;
    if (globalT <= delay) return 0;
    return ((globalT - delay) / (1 - lag)).clamp(0.0, 1.0);
  }

  /// True when a committed fill or a note matches [filter].
  static bool cellMatchesFilter(Cell cell, int filter) {
    if (cell.value == filter) return true;
    return cell.notes.contains(filter);
  }

  /// When [filter] is set, only that color value should cycle.
  static bool valueMatchesFilter(int value, int? filter) {
    return filter == null || value == filter;
  }

  /// Cycles [colorValue] through [stepCount] palette steps and back (t=0/1 → original).
  ///
  /// When [linear] is true (picker hold), ping-pongs along adjacent palette
  /// slots at a constant visual speed (no wrap, no hue-spin). [mix] fades
  /// between the real color (0) and the walking color (1).
  static PaletteSwatch displaySwatch(
    int colorValue,
    double t, {
    required int stepCount,
    required GamePalette palette,
    List<PaletteSwatch>? swatches,
    bool linear = false,
    double mix = 1,
  }) {
    final list = swatches ?? IrodokuPalette.swatchesFor(palette);
    final original = IrodokuPalette.swatchFromList(colorValue, list) ??
        IrodokuPalette.swatchForValue(colorValue, palette);
    if (original == null) return list.first;
    if (mix <= 0) return original;

    final walked = linear
        ? _holdWalk(original, colorValue, t, list)
        : _oneShotWalk(original, colorValue, t, list, stepCount);
    if (mix >= 1) return walked;
    return _holdLerp(original, walked, mix);
  }

  static PaletteSwatch _oneShotWalk(
    PaletteSwatch original,
    int colorValue,
    double t,
    List<PaletteSwatch> list,
    int stepCount,
  ) {
    if (t <= 0 || t >= 1) return original;

    final steps = stepCount.clamp(1, list.length);
    final eased = Curves.easeInOutCubic.transform(t);
    final sweep = eased < 0.5 ? eased * 2 : (1 - eased) * 2;
    final offset = sweep * steps;

    final n = list.length;
    if (n <= 0) return original;
    final startIndex = colorValue - 1;
    final i0 = (startIndex + offset.floor()) % n;
    final i1 = (startIndex + offset.ceil()) % n;
    final frac = offset - offset.floor();
    return PaletteSwatch.lerp(list[i0], list[i1], frac);
  }

  /// Out-and-back along adjacent slots only, paced by RGB distance so a large
  /// jump cannot race through while nearby slots crawl.
  static PaletteSwatch _holdWalk(
    PaletteSwatch original,
    int colorValue,
    double t,
    List<PaletteSwatch> list,
  ) {
    final n = list.length;
    if (n <= 1) return original;
    final u = t % 1.0;
    if (u <= 0) return original;

    final start = (colorValue - 1) % n;
    final segmentCount = n - 1;
    final dists = [
      for (var i = 0; i < segmentCount; i++)
        _stepDistance(
          list[(start + i) % n],
          list[(start + i + 1) % n],
        ),
    ];
    final totalOut = dists.fold<double>(0, (sum, d) => sum + d);
    if (totalOut <= 0) return original;

    // 0→1→0 over the cycle so t=0 and t=1 are the original color.
    final along = u <= 0.5 ? u * 2 * totalOut : (1 - u) * 2 * totalOut;

    var acc = 0.0;
    for (var i = 0; i < segmentCount; i++) {
      final next = acc + dists[i];
      if (along <= next || i == segmentCount - 1) {
        final span = dists[i];
        final frac =
            span <= 1e-9 ? 1.0 : ((along - acc) / span).clamp(0.0, 1.0);
        return _holdLerp(
          list[(start + i) % n],
          list[(start + i + 1) % n],
          frac,
          styleOf: original,
        );
      }
      acc = next;
    }
    return original;
  }

  static double _stepDistance(PaletteSwatch a, PaletteSwatch b) {
    final ca = a.representative;
    final cb = b.representative;
    final dr = ca.r - cb.r;
    final dg = ca.g - cb.g;
    final db = ca.b - cb.b;
    // Nearby slots still get a beat; huge jumps take longer, not faster.
    return math.sqrt(dr * dr + dg * dg + db * db).clamp(0.12, 1.8);
  }

  /// Straight RGB blend between two swatches, keeping [styleOf]'s shader identity.
  static PaletteSwatch _holdLerp(
    PaletteSwatch from,
    PaletteSwatch to,
    double t, {
    PaletteSwatch? styleOf,
  }) {
    final style = styleOf ?? from;
    return PaletteSwatch(
      start: Color.lerp(from.start, to.start, t)!,
      stop: Color.lerp(from.stop, to.stop, t)!,
      begin: style.begin,
      end: style.end,
      swirlSeed: style.swirlSeed,
      style: style.style,
      animated: style.animated,
      intensity: style.intensity,
      motionSpeed: style.motionSpeed,
      outlined: style.outlined,
    );
  }
}

/// Looping hold-sweep: mix 0–1 envelope plus a slow repeating cycle.
class PickerHoldSweep {
  PickerHoldSweep(TickerProvider vsync)
      : cycle = AnimationController(
          vsync: vsync,
          duration: ColorCycle.holdCycleDuration,
        ),
        mix = AnimationController(
          vsync: vsync,
          duration: ColorCycle.holdMixIn,
        );

  final AnimationController cycle;
  final AnimationController mix;
  Timer? _releaseTimer;
  bool _wasActive = false;

  Listenable get listenable => Listenable.merge([cycle, mix]);

  bool get isVisible => mix.value > 0;

  void sync({required bool active, bool immediateRelease = false}) {
    if (active && !_wasActive) {
      _releaseTimer?.cancel();
      _releaseTimer = null;
      mix.duration = ColorCycle.holdMixIn;
      cycle
        ..stop()
        ..repeat();
      mix.forward();
    } else if (!active && _wasActive) {
      _releaseTimer?.cancel();
      final delay =
          immediateRelease ? Duration.zero : ColorCycle.holdReleaseDelay;
      _releaseTimer = Timer(delay, () {
        mix.duration = ColorCycle.holdRamp;
        mix.reverse().whenComplete(() {
          if (!_wasActive && mix.value <= 0) {
            cycle.stop();
            cycle.value = 0;
          }
        });
      });
    }
    _wasActive = active;
  }

  double? phase({
    required int? filter,
    required bool Function(int filter) matches,
  }) {
    if (mix.value <= 0 || filter == null) return null;
    if (!matches(filter)) return null;
    return cycle.value;
  }

  void dispose() {
    _releaseTimer?.cancel();
    cycle.dispose();
    mix.dispose();
  }
}

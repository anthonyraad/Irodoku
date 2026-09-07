import 'dart:math';

import 'package:flutter/material.dart';

import '../models/game_palette.dart';
import '../models/iroen_mosaic.dart';
import '../models/palette_swatch.dart';
import 'palette.dart';

/// Title-tap easter egg: solved 9×9 board eases into a saved Iroen mosaic
/// (true 3×3 detail per cell, mosaic palette) and back.
abstract final class MosaicShimmer {
  static const Duration duration = Duration(milliseconds: 1720);
  static const double staggerSpread = 0.08;
  /// Sub-tiles in a cell stay in lockstep so the 27×27 doesn't crawl.
  static const double subStaggerSpread = 0;
  /// Fraction of the timeline spent fully on the mosaic (no motion).
  static const double holdFraction = 0.36;

  static double get _holdStart => (1 - holdFraction.clamp(0.0, 0.8)) / 2;

  static bool shouldAnimate({
    required bool isWon,
    required bool isPocket,
    required bool iroenUnlocked,
    required Iterable<IroenMosaic>? mosaics,
  }) {
    if (!isWon || isPocket || !iroenUnlocked) return false;
    if (mosaics == null) return false;
    return mosaics.any((mosaic) => !mosaic.isEmpty);
  }

  static IroenMosaic? pickRandom(
    Iterable<IroenMosaic> mosaics, {
    String? excludingId,
    Random? random,
  }) {
    final candidates = mosaics.where((mosaic) => !mosaic.isEmpty).toList();
    if (candidates.isEmpty) return null;
    if (candidates.length == 1) return candidates.first;
    final rng = random ?? Random();
    final pool = excludingId == null
        ? candidates
        : candidates.where((mosaic) => mosaic.id != excludingId).toList();
    final pickFrom = pool.isEmpty ? candidates : pool;
    return pickFrom[rng.nextInt(pickFrom.length)];
  }

  static double envelope(double globalT) {
    if (globalT <= 0 || globalT >= 1) return 0;
    final holdStart = _holdStart;
    final holdEnd = 1 - holdStart;
    if (globalT >= holdStart && globalT <= holdEnd) return 1;
    if (globalT < holdStart) {
      return Curves.easeOutCubic.transform(globalT / holdStart);
    }
    return Curves.easeInCubic.transform((1 - globalT) / holdStart);
  }

  /// Mix for one tile. Always 1 while [envelope] is 1 so the mosaic can sit still.
  static double amount(
    double globalT, {
    int row = 0,
    int col = 0,
    int subIndex = 0,
  }) {
    if (globalT <= 0 || globalT >= 1) return 0;
    final holdStart = _holdStart;
    final holdEnd = 1 - holdStart;
    if (globalT >= holdStart && globalT <= holdEnd) return 1;

    final maxDelay = holdStart * 0.4;
    final delay = (((row * 9 + col) / 81) * staggerSpread +
            (subIndex.clamp(0, 8) / 9) * subStaggerSpread)
        .clamp(0.0, maxDelay);

    if (globalT < holdStart) {
      final span = holdStart - delay;
      if (globalT <= delay || span <= 0) return 0;
      return Curves.easeOutCubic.transform(
        ((globalT - delay) / span).clamp(0.0, 1.0),
      );
    }

    final local = globalT - holdEnd;
    if (local <= delay) return 1;
    final span = holdStart - delay;
    if (span <= 0) return 0;
    final u = ((local - delay) / span).clamp(0.0, 1.0);
    return 1 - Curves.easeInCubic.transform(u);
  }

  /// Cell-level mix (no sub-tile stagger).
  static double mixAmount(double globalT, {int row = 0, int col = 0}) =>
      amount(globalT, row: row, col: col);

  /// Out-and-back mix for one of a cell's nine sub-tiles.
  static double tileAmount(
    double globalT,
    int subIndex, {
    int row = 0,
    int col = 0,
  }) =>
      amount(globalT, row: row, col: col, subIndex: subIndex);

  /// Kept at 0 so the 27×27 mosaic reads as a continuous painting.
  static double tileGap(double amount, double tileSize) => 0;

  static PaletteSwatch lerpSwatch(PaletteSwatch a, PaletteSwatch b, double t) {
    final clamped = t.clamp(0.0, 1.0);
    if (clamped <= 0) return a;
    if (clamped >= 1) return b;
    final style = clamped < 0.5 ? a.style : b.style;
    return PaletteSwatch(
      start: PaletteSwatch.blend(a.start, b.start, clamped),
      stop: PaletteSwatch.blend(a.stop, b.stop, clamped),
      begin: Alignment.lerp(a.begin, b.begin, clamped)!,
      end: Alignment.lerp(a.end, b.end, clamped)!,
      swirlSeed: (a.swirlSeed + (b.swirlSeed - a.swirlSeed) * clamped).round(),
      style: style,
      animated: clamped < 0.5 ? a.animated : b.animated,
      intensity: a.intensity + (b.intensity - a.intensity) * clamped,
      motionSpeed: a.motionSpeed + (b.motionSpeed - a.motionSpeed) * clamped,
    );
  }

  static PaletteSwatch? blendTile({
    required PaletteSwatch original,
    required int mosaicValue,
    required List<PaletteSwatch> mosaicSwatches,
    required PaletteSwatch empty,
    required double amount,
  }) {
    if (amount <= 0) return original;
    final target = mosaicValue <= 0
        ? empty
        : IrodokuPalette.swatchFromList(mosaicValue, mosaicSwatches) ?? empty;
    if (amount >= 1) return mosaicValue <= 0 ? null : target;
    return lerpSwatch(original, target, amount);
  }

  /// Nine tile fills (null = leave the empty cell showing) for [cellPhase].
  static List<PaletteSwatch?> tiles({
    required PaletteSwatch original,
    required List<int> subValues,
    required GamePalette mosaicPalette,
    required Color emptyFill,
    required double cellPhase,
    int row = 0,
    int col = 0,
  }) {
    final mosaicSwatches = IrodokuPalette.swatchesFor(mosaicPalette);
    final empty = PaletteSwatch.solid(emptyFill);
    return [
      for (var i = 0; i < 9; i++)
        blendTile(
          original: original,
          mosaicValue: i < subValues.length ? subValues[i] : 0,
          mosaicSwatches: mosaicSwatches,
          empty: empty,
          amount: tileAmount(cellPhase, i, row: row, col: col),
        ),
    ];
  }
}

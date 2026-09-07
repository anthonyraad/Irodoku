import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irodoku/core/mosaic_shimmer.dart';
import 'package:irodoku/models/game_palette.dart';
import 'package:irodoku/models/iroen_mosaic.dart';
import 'package:irodoku/models/iroen_state.dart';
import 'package:irodoku/models/palette_swatch.dart';

List<int> _detail({int at = 0, int value = 1, int length = 0}) {
  final size = IroenState.detailSize * IroenState.detailSize;
  final detail = List<int>.filled(size, 0);
  if (length <= 0) {
    detail[at] = value;
    return detail;
  }
  for (var i = 0; i < length && at + i < size; i++) {
    detail[at + i] = value;
  }
  return detail;
}

IroenMosaic _mosaic(String id, List<int> detail, {GamePalette? palette}) {
  return IroenMosaic(
    id: id,
    name: id,
    detail: detail,
    updatedAtMs: 1,
    palette: palette ?? GamePalette.standard,
  );
}

void main() {
  test('shouldAnimate requires a completed 9×9, unlocked Iroen, and a painted mosaic',
      () {
    final painted = _mosaic('a', _detail());
    final blank = _mosaic('b', List<int>.filled(729, 0));

    expect(
      MosaicShimmer.shouldAnimate(
        isWon: true,
        isPocket: false,
        iroenUnlocked: true,
        mosaics: [painted],
      ),
      isTrue,
    );
    expect(
      MosaicShimmer.shouldAnimate(
        isWon: false,
        isPocket: false,
        iroenUnlocked: true,
        mosaics: [painted],
      ),
      isFalse,
    );
    expect(
      MosaicShimmer.shouldAnimate(
        isWon: true,
        isPocket: true,
        iroenUnlocked: true,
        mosaics: [painted],
      ),
      isFalse,
    );
    expect(
      MosaicShimmer.shouldAnimate(
        isWon: true,
        isPocket: false,
        iroenUnlocked: false,
        mosaics: [painted],
      ),
      isFalse,
    );
    expect(
      MosaicShimmer.shouldAnimate(
        isWon: true,
        isPocket: false,
        iroenUnlocked: true,
        mosaics: [blank],
      ),
      isFalse,
    );
  });

  test('pickRandom skips empty mosaics and avoids repeating the last id', () {
    final a = _mosaic('a', _detail(at: 0));
    final b = _mosaic('b', _detail(at: 10));
    final empty = _mosaic('empty', List<int>.filled(729, 0));
    final rng = Random(4);

    expect(MosaicShimmer.pickRandom([empty]), isNull);
    expect(MosaicShimmer.pickRandom([a, empty], random: rng)?.id, 'a');

    final seen = <String>{};
    for (var i = 0; i < 12; i++) {
      seen.add(
        MosaicShimmer.pickRandom(
          [a, b],
          excludingId: 'a',
          random: Random(i),
        )!.id,
      );
    }
    expect(seen, {'b'});
  });

  test('subValuesAt returns the true 3×3 including blanks', () {
    final detail = List<int>.filled(729, 0);
    // Cell (0,0): top-left 3×3 of the 27×27 canvas.
    detail[0] = 3;
    detail[1] = 0;
    detail[2] = 7;
    detail[27] = 1;
    final mosaic = _mosaic('m', detail);

    expect(mosaic.subValuesAt(0, 0), [3, 0, 7, 1, 0, 0, 0, 0, 0]);
    expect(mosaic.subValuesAt(1, 1), everyElement(0));
  });

  test('tileAmount is out-and-back and blank tiles lerp to empty', () {
    expect(MosaicShimmer.tileAmount(0, 0), 0);
    expect(MosaicShimmer.tileAmount(1, 0), 0);
    expect(MosaicShimmer.envelope(0.35), 1);
    expect(MosaicShimmer.envelope(0.5), 1);
    expect(MosaicShimmer.envelope(0.65), 1);
    expect(MosaicShimmer.tileAmount(0.5, 0), 1);
    expect(MosaicShimmer.amount(0.4, row: 8, col: 8, subIndex: 8), 1);
    expect(MosaicShimmer.amount(0.6, row: 8, col: 8, subIndex: 8), 1);

    const original = Color(0xFFE53935);
    const empty = Color(0xFFFAFAFA);
    final peak = MosaicShimmer.tiles(
      original: PaletteSwatch.solid(original),
      subValues: const [2, 0, 0, 0, 0, 0, 0, 0, 0],
      mosaicPalette: GamePalette.neon,
      emptyFill: empty,
      cellPhase: 0.5,
    );
    expect(peak, hasLength(9));
    expect(peak[0], isNotNull);
    expect(peak[1], isNull);

    final rising = MosaicShimmer.tiles(
      original: PaletteSwatch.solid(original),
      subValues: const [2, 0, 0, 0, 0, 0, 0, 0, 0],
      mosaicPalette: GamePalette.neon,
      emptyFill: empty,
      cellPhase: 0.12,
    );
    final blank = rising[1];
    expect(blank, isNotNull);
    expect(blank!.start, isNot(original));
    expect(
      (blank.start.g - original.g).abs(),
      greaterThan(0.05),
    );
  });

  test('hold keeps every mosaic tile frozen at full mix', () {
    const t0 = 0.38;
    const t1 = 0.62;
    for (var row = 0; row < 9; row++) {
      for (var col = 0; col < 9; col++) {
        for (var sub = 0; sub < 9; sub++) {
          expect(
            MosaicShimmer.amount(t0, row: row, col: col, subIndex: sub),
            1,
          );
          expect(
            MosaicShimmer.amount(t1, row: row, col: col, subIndex: sub),
            MosaicShimmer.amount(t0, row: row, col: col, subIndex: sub),
          );
        }
      }
    }
  });
}

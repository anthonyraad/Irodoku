import 'package:flutter_test/flutter_test.dart';
import 'package:irodoku/core/color_cycle.dart';
import 'package:irodoku/core/palette.dart';
import 'package:irodoku/models/cell.dart';
import 'package:irodoku/models/difficulty.dart';
import 'package:irodoku/models/game_palette.dart';
import 'package:irodoku/models/paused_game.dart';

void main() {
  test('pocketWindow takes slots 1-6 or 4-9', () {
    final slots = [1, 2, 3, 4, 5, 6, 7, 8, 9];
    expect(IrodokuPalette.pocketWindow(slots, 0), [1, 2, 3, 4, 5, 6]);
    expect(
      IrodokuPalette.pocketWindow(slots, IrodokuPalette.pocketHighSwatchOffset),
      [4, 5, 6, 7, 8, 9],
    );
    expect(IrodokuPalette.normalizePocketSwatchOffset(3), 3);
    expect(IrodokuPalette.normalizePocketSwatchOffset(1), 0);
  });

  test('high window outlines use palette slots 4-9', () {
    const offset = IrodokuPalette.pocketHighSwatchOffset;
    expect(
      IrodokuPalette.outlineForSlot(1, GamePalette.sky, null, offset),
      isNull,
    );
    expect(
      IrodokuPalette.outlineForSlot(6, GamePalette.greyscale, null, offset),
      IrodokuPalette.lightFillOutline,
    );
  });

  test('color cycle on a 6-swatch pocket window stays in range', () {
    final six = IrodokuPalette.pocketWindow(
      IrodokuPalette.swatchesFor(GamePalette.standard),
      IrodokuPalette.pocketHighSwatchOffset,
    );
    expect(six, hasLength(6));
    final swatch = ColorCycle.displaySwatch(
      1,
      0.4,
      stepCount: 4,
      palette: GamePalette.standard,
      swatches: six,
    );
    expect(swatch.representative.a, greaterThan(0));
  });

  test('paused Pocket stores the 4-9 window', () {
    final paused = PausedGame(
      difficulty: Difficulty.easy,
      elapsed: Duration.zero,
      mistakes: 0,
      solution: List<int>.filled(36, 1),
      cells: List<Cell>.generate(36, (_) => const Cell()),
      isPocket: true,
      pocketSwatchOffset: IrodokuPalette.pocketHighSwatchOffset,
    );
    final restored = PausedGame.fromJson(paused.toJson());
    expect(restored.pocketSwatchOffset, 3);
    expect(PausedGame.fromJson(paused.toJson()..remove('pocketSwatchOffset'))
        .pocketSwatchOffset, 0);
  });
}

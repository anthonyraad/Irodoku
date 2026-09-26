import 'package:flutter_test/flutter_test.dart';
import 'package:irodoku/core/palette.dart';
import 'package:irodoku/models/achievements_progress.dart';
import 'package:irodoku/models/game_palette.dart';
import 'package:irodoku/models/game_stats.dart';
import 'package:irodoku/models/iro_mix.dart';
import 'package:irodoku/models/iroen_mosaic.dart';
import 'package:irodoku/models/iroen_state.dart';
import 'package:irodoku/models/player_xp.dart';
import 'package:irodoku/models/progress_backup.dart';

void main() {
  test('menu palettes unlock B-sides every 5 levels from 15', () {
    expect(GamePalette.standard.bSideUnlockLevel, 15);
    expect(GamePalette.rainbow.bSideUnlockLevel, 20);
    expect(GamePalette.world11.bSideUnlockLevel, 25);
    expect(GamePalette.neon.bSideUnlockLevel, 30);
    expect(GamePalette.pkmn.bSideUnlockLevel, 35);
    expect(GamePalette.pkmn2.bSideUnlockLevel, 40);
    expect(GamePalette.glass.bSideUnlockLevel, 45);
    expect(GamePalette.sky.bSideUnlockLevel, 50);
    expect(GamePalette.iro.hasBSide, isFalse);
    expect(GamePalette.greyscale.hasBSide, isFalse);
  });

  test('latest B-side for a level is the most recently unlocked palette', () {
    expect(GamePalette.latestBSideForLevel(14), isNull);
    expect(GamePalette.latestBSideForLevel(15), GamePalette.standard);
    expect(GamePalette.latestBSideForLevel(19), GamePalette.standard);
    expect(GamePalette.latestBSideForLevel(20), GamePalette.rainbow);
    expect(GamePalette.latestBSideForLevel(21), GamePalette.rainbow);
    expect(GamePalette.latestBSideForLevel(25), GamePalette.world11);
    expect(GamePalette.latestBSideForLevel(49), GamePalette.glass);
    expect(GamePalette.latestBSideForLevel(50), GamePalette.sky);
    expect(GamePalette.latestBSideForLevel(80), GamePalette.sky);
  });

  test('B-side swatches keep the A-side texture and change the colors', () {
    for (final palette in GamePalette.menuValues) {
      final a = IrodokuPalette.swatchesFor(palette);
      final b = IrodokuPalette.swatchesFor(palette, bSide: true);
      expect(b, hasLength(9));
      expect(
        b.map((s) => s.style),
        a.map((s) => s.style),
        reason: palette.label,
      );
      expect(
        b.map((s) => s.representative),
        isNot(a.map((s) => s.representative)),
        reason: palette.label,
      );
    }
  });

  test('only Sky A-side slot 1 keeps a near-white outline', () {
    expect(
      IrodokuPalette.outlineForValue(1, GamePalette.sky),
      IrodokuPalette.lightFillOutline,
    );
    expect(
      IrodokuPalette.outlineForValue(8, GamePalette.sky, bSide: true),
      isNull,
    );
    expect(
      IrodokuPalette.outlineForValue(9, GamePalette.sky, bSide: true),
      isNull,
    );
    expect(
      IrodokuPalette.outlineForValue(7, GamePalette.glass, bSide: true),
      isNull,
    );
    expect(
      IrodokuPalette.outlineForValue(9, GamePalette.greyscale),
      isNull,
    );

    final skyB = IrodokuPalette.swatchesFor(GamePalette.sky, bSide: true);
    expect(IrodokuPalette.outlineForSwatch(skyB[0]), isNull);
    expect(IrodokuPalette.outlineForSwatch(skyB[7]), isNull);
  });

  test('IroMix.withBSides remaps slots without changing sources', () {
    final mix = IroMix(
      List<GamePalette>.filled(9, GamePalette.standard),
    );
    final flipped = mix.withBSides((_) => true);
    expect(flipped.sources, mix.sources);
    expect(flipped.bSides, List<bool>.filled(9, true));
    expect(
      flipped.swatches[0].representative,
      IrodokuPalette.swatchesFor(GamePalette.standard, bSide: true)[0]
          .representative,
    );
  });

  test('IroMix persists B-sides on source keys', () {
    final mix = IroMix(
      List<GamePalette>.filled(9, GamePalette.rainbow),
      List<bool>.generate(9, (i) => i.isOdd),
    );
    final restored = IroMix.fromKeys(mix.toKeys());
    expect(restored, isNotNull);
    expect(restored!.sources, mix.sources);
    expect(restored.bSides, mix.bSides);
    expect(restored.swatches[0].representative,
        IrodokuPalette.swatchesFor(GamePalette.rainbow)[0].representative);
    expect(
      restored.swatches[1].representative,
      IrodokuPalette.swatchesFor(GamePalette.rainbow, bSide: true)[1]
          .representative,
    );
  });

  test('Iroen mosaic JSON keeps bSide and stays backward compatible', () {
    final detail = List<int>.filled(
      IroenState.detailSize * IroenState.detailSize,
      0,
    );
    final mosaic = IroenMosaic(
      id: 'm1',
      name: 'Test',
      detail: detail,
      updatedAtMs: 1,
      palette: GamePalette.glass,
      bSide: true,
    );
    final loaded = IroenMosaic.fromJson(mosaic.toJson());
    expect(loaded.bSide, isTrue);
    expect(loaded.palette, GamePalette.glass);

    final old = IroenMosaic.fromJson({
      'id': 'old',
      'name': 'Old',
      'detail': detail,
      'updatedAtMs': 1,
      'palette': GamePalette.neon.storageKey,
    });
    expect(old.bSide, isFalse);
  });

  test('B-side unlocks only when the level threshold is crossed', () {
    final unlocked = PlayerXp.bSidesUnlockedByLevelUp(
      fromXp: _xpToReachLevel(14),
      toXp: _xpToReachLevel(15),
      paletteUnlocked: (_) => true,
    );
    expect(unlocked, [GamePalette.standard]);

    final none = PlayerXp.bSidesUnlockedByLevelUp(
      fromXp: _xpToReachLevel(15),
      toXp: _xpToReachLevel(19),
      paletteUnlocked: (_) => true,
    );
    expect(none, isEmpty);
  });

  test('progress backup round-trips palette B-side choices', () {
    final backup = ProgressBackup(
      stats: const GameStats(totalXp: 8000),
      achievements: const AchievementsProgress(),
      paletteBSides: {GamePalette.rainbow, GamePalette.neon},
      iroMix: IroMix(
        List<GamePalette>.filled(9, GamePalette.glass),
        List<bool>.filled(9, true),
      ),
    );
    final copy = ProgressBackup.fromJson(backup.toJson());
    expect(copy.paletteBSides, {GamePalette.rainbow, GamePalette.neon});
    expect(copy.iroMix, isNotNull);
    expect(copy.iroMix!.sources, backup.iroMix!.sources);
    expect(copy.iroMix!.bSides, backup.iroMix!.bSides);
  });
}

int _xpToReachLevel(int level) {
  var xp = 0;
  for (var i = 1; i < level; i++) {
    xp += PlayerXp.xpToReach(i);
  }
  return xp;
}

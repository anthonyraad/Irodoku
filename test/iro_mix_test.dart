import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:irodoku/core/palette.dart';
import 'package:irodoku/models/game_palette.dart';
import 'package:irodoku/models/iro_mix.dart';

void main() {
  test('Iro is hidden from the Config menu until unlocked', () {
    expect(GamePalette.iro.visibleInMenu, isFalse);
    expect(GamePalette.iro.isLockedByDefault, isTrue);
    expect(GamePalette.iro.label, 'Iro');
    expect(GamePalette.iro.storageKey, 'iro');
    expect(GamePalette.menuValues, isNot(contains(GamePalette.iro)));
    expect(GamePalette.menuValues, isNot(contains(GamePalette.greyscale)));
    expect(GamePalette.menuValues, hasLength(8));
  });

  test('IroMix.random is deterministic for a seed', () {
    final a = IroMix.random(Random(42));
    final b = IroMix.random(Random(42));
    expect(a.sources, b.sources);
    expect(a.key, b.key);
  });

  test('each Iro slot is that index from a menu palette', () {
    final mix = IroMix.random(Random(7));
    expect(mix.sources, hasLength(9));
    for (var i = 0; i < 9; i++) {
      final source = mix.sources[i];
      expect(source.visibleInMenu, isTrue);
      expect(source, isNot(GamePalette.iro));
      expect(source, isNot(GamePalette.greyscale));
      expect(
        mix.swatches[i].representative,
        IrodokuPalette.swatchesFor(source)[i].representative,
      );
    }
  });

  test('IroMix round-trips through storage keys', () {
    final mix = IroMix.random(Random(99));
    final restored = IroMix.fromKeys(mix.toKeys());
    expect(restored, isNotNull);
    expect(restored!.sources, mix.sources);
  });

  test('fromKeys rejects greyscale and Iro sources', () {
    final keys = [
      for (var i = 0; i < 9; i++) GamePalette.standard.storageKey,
    ];
    keys[3] = GamePalette.iro.storageKey;
    expect(IroMix.fromKeys(keys), isNull);

    keys[3] = GamePalette.greyscale.storageKey;
    expect(IroMix.fromKeys(keys), isNull);
  });

  test('chromatic hop remixes Iro instead of switching palettes', () {
    // GameProvider keeps GamePalette.iro and assigns IroMix.random() on a hop.
    final start = IroMix.random(Random(1));
    final hop = IroMix.random(Random(2));
    expect(start.sources, isNot(equals(hop.sources)));
    expect(
      hop.sources.every((palette) => palette.visibleInMenu),
      isTrue,
    );
  });
}

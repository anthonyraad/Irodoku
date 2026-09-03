import 'dart:math';

import '../core/palette.dart';
import 'game_palette.dart';
import 'palette_swatch.dart';

/// Per-slot mashup: color *n* is taken from a randomly chosen menu palette.
class IroMix {
  final List<GamePalette> sources;

  const IroMix(this.sources)
      : assert(sources.length == 9, 'Iro mix must have 9 slot sources');

  static List<GamePalette> get sourcePalettes => GamePalette.menuValues;

  factory IroMix.random([Random? random]) {
    final r = random ?? Random();
    final palettes = sourcePalettes;
    return IroMix([
      for (var i = 0; i < 9; i++) palettes[r.nextInt(palettes.length)],
    ]);
  }

  /// Stable 9-slot preview used when no live mix is available.
  factory IroMix.showcase() {
    final palettes = sourcePalettes;
    return IroMix([
      for (var i = 0; i < 9; i++) palettes[i % palettes.length],
    ]);
  }

  List<PaletteSwatch> get swatches => [
        for (var i = 0; i < 9; i++)
          IrodokuPalette.swatchesFor(sources[i])[i],
      ];

  String get key => sources.map((p) => p.storageKey).join(',');

  List<String> toKeys() => [for (final p in sources) p.storageKey];

  static IroMix? fromKeys(List<dynamic>? keys) {
    if (keys == null || keys.length != 9) return null;
    final parsed = <GamePalette>[];
    for (final raw in keys) {
      final palette = GamePalette.fromStorageKey(raw?.toString());
      if (palette == GamePalette.iro || palette == GamePalette.greyscale) {
        return null;
      }
      parsed.add(palette);
    }
    return IroMix(parsed);
  }
}

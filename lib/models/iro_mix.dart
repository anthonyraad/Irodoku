import 'dart:math';

import '../core/palette.dart';
import 'game_palette.dart';
import 'palette_swatch.dart';

/// Per-slot mashup: color *n* is taken from a randomly chosen menu palette.
class IroMix {
  final List<GamePalette> sources;
  /// Parallel to [sources]; true when that slot uses the source's B-side.
  final List<bool> bSides;

  IroMix(this.sources, [List<bool>? bSides])
      : bSides = _normalizedBSides(sources.length, bSides),
        assert(sources.length == 9, 'Iro mix must have 9 slot sources');

  static List<bool> _normalizedBSides(int length, List<bool>? raw) {
    if (raw == null || raw.length != length) {
      return List<bool>.filled(length, false);
    }
    return List<bool>.from(raw);
  }

  static List<GamePalette> get sourcePalettes => GamePalette.menuValues;

  factory IroMix.random([
    Random? random,
    bool Function(GamePalette)? bSideOf,
  ]) {
    final r = random ?? Random();
    final palettes = sourcePalettes;
    final sources = [
      for (var i = 0; i < 9; i++) palettes[r.nextInt(palettes.length)],
    ];
    return IroMix(
      sources,
      [for (final source in sources) bSideOf?.call(source) ?? false],
    );
  }

  /// Stable 9-slot preview used when no live mix is available.
  factory IroMix.showcase([bool Function(GamePalette)? bSideOf]) {
    final palettes = sourcePalettes;
    final sources = [
      for (var i = 0; i < 9; i++) palettes[i % palettes.length],
    ];
    return IroMix(
      sources,
      [for (final source in sources) bSideOf?.call(source) ?? false],
    );
  }

  IroMix withBSides(bool Function(GamePalette) bSideOf) =>
      IroMix(sources, [for (final source in sources) bSideOf(source)]);

  List<PaletteSwatch> get swatches => [
        for (var i = 0; i < 9; i++)
          IrodokuPalette.swatchesFor(sources[i], bSide: bSides[i])[i],
      ];

  String get key => [
        for (var i = 0; i < sources.length; i++)
          '${sources[i].storageKey}${bSides[i] ? ':b' : ''}',
      ].join(',');

  List<String> toKeys() => [
        for (var i = 0; i < sources.length; i++)
          '${sources[i].storageKey}${bSides[i] ? ':b' : ''}',
      ];

  static IroMix? fromKeys(List<dynamic>? keys) {
    if (keys == null || keys.length != 9) return null;
    final parsed = <GamePalette>[];
    final sides = <bool>[];
    for (final raw in keys) {
      final token = raw?.toString() ?? '';
      final bSide = token.endsWith(':b');
      final key = bSide ? token.substring(0, token.length - 2) : token;
      final palette = GamePalette.fromStorageKey(key);
      if (palette == GamePalette.iro || palette == GamePalette.greyscale) {
        return null;
      }
      parsed.add(palette);
      sides.add(bSide && palette.hasBSide);
    }
    return IroMix(parsed, sides);
  }
}

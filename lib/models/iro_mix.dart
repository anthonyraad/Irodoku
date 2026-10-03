import 'dart:math';
import 'dart:ui' show Color;

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

  /// RGB distance at or below this counts as the same (or virtually the same)
  /// hex, so those two slots cannot share an Iro set.
  static const double nearDuplicateRgbDistance = 12;

  factory IroMix.random([
    Random? random,
    bool Function(GamePalette)? bSideOf,
  ]) {
    final r = random ?? Random();
    final palettes = sourcePalettes;
    return _assignSlots(
      candidatesFor: (_) => List<GamePalette>.of(palettes)..shuffle(r),
      sideOf: (_, palette) => bSideOf?.call(palette) ?? false,
    );
  }

  /// Stable 9-slot preview used when no live mix is available.
  factory IroMix.showcase([bool Function(GamePalette)? bSideOf]) {
    final palettes = sourcePalettes;
    return _assignSlots(
      candidatesFor: (slot) {
        final preferred = palettes[slot % palettes.length];
        return [
          preferred,
          ...palettes.where((palette) => palette != preferred),
        ];
      },
      sideOf: (_, palette) => bSideOf?.call(palette) ?? false,
    );
  }

  IroMix withBSides(bool Function(GamePalette) bSideOf) =>
      IroMix(sources, [for (final source in sources) bSideOf(source)]);

  /// True when two slots use the same, or virtually the same, fill hex.
  bool get hasNearDuplicateColors {
    final list = swatches;
    for (var i = 0; i < list.length; i++) {
      for (var j = i + 1; j < list.length; j++) {
        if (_swatchPairDistance(list[i], list[j]) <=
            nearDuplicateRgbDistance) {
          return true;
        }
      }
    }
    return false;
  }

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

  static IroMix _assignSlots({
    required List<GamePalette> Function(int slot) candidatesFor,
    required bool Function(int slot, GamePalette palette) sideOf,
  }) {
    final sources = <GamePalette>[];
    final sides = <bool>[];
    for (var slot = 0; slot < 9; slot++) {
      final palette = _firstNonClashing(
        slot: slot,
        candidates: candidatesFor(slot),
        existingSources: sources,
        existingSides: sides,
        sideOf: sideOf,
      );
      sources.add(palette);
      sides.add(sideOf(slot, palette));
    }
    return IroMix(sources, sides);
  }

  static GamePalette _firstNonClashing({
    required int slot,
    required List<GamePalette> candidates,
    required List<GamePalette> existingSources,
    required List<bool> existingSides,
    required bool Function(int slot, GamePalette palette) sideOf,
  }) {
    GamePalette? fallback;
    var fallbackScore = -1.0;
    for (final palette in candidates) {
      final swatch = IrodokuPalette.swatchesFor(
        palette,
        bSide: sideOf(slot, palette),
      )[slot];
      final score = _minDistanceToExisting(
        swatch,
        existingSources,
        existingSides,
      );
      if (score > nearDuplicateRgbDistance) return palette;
      if (score > fallbackScore) {
        fallbackScore = score;
        fallback = palette;
      }
    }
    return fallback ?? candidates.first;
  }

  static double _minDistanceToExisting(
    PaletteSwatch swatch,
    List<GamePalette> existingSources,
    List<bool> existingSides,
  ) {
    if (existingSources.isEmpty) return double.infinity;
    var best = double.infinity;
    for (var j = 0; j < existingSources.length; j++) {
      final other = IrodokuPalette.swatchesFor(
        existingSources[j],
        bSide: existingSides[j],
      )[j];
      final distance = _swatchPairDistance(swatch, other);
      if (distance < best) best = distance;
    }
    return best;
  }

  static double _swatchPairDistance(PaletteSwatch a, PaletteSwatch b) {
    var best = double.infinity;
    for (final left in [a.start, a.stop, a.representative]) {
      for (final right in [b.start, b.stop, b.representative]) {
        final distance = _rgbDistance(left, right);
        if (distance < best) best = distance;
      }
    }
    return best;
  }

  static double _rgbDistance(Color a, Color b) {
    final dr = (a.r - b.r) * 255.0;
    final dg = (a.g - b.g) * 255.0;
    final db = (a.b - b.b) * 255.0;
    return sqrt(dr * dr + dg * dg + db * db);
  }
}

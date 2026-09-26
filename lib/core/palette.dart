import 'package:flutter/material.dart';

import '../models/game_palette.dart';
import '../models/palette_swatch.dart';

/// The nine Sudoku colors. Indices 0–8 map to values 1–9 internally.
abstract final class IrodokuPalette {
  static const List<Color> defaultColors = [
    Color(0xFFE53935), // Red
    Color(0xFFFB8C00), // Orange
    Color(0xFFFDD835), // Yellow
    Color(0xFF2E7D32), // Forest green
    Color(0xFF42A5F5), // Light blue
    Color(0xFF3949AB), // Indigo
    Color(0xFF8E24AA), // Violet
    Color(0xFFF48FB1), // Light pink
    Color(0xFF757575), // Gray
  ];

  static const List<Color> neonColors = [
    Color(0xFF450693),
    Color(0xFF8C00FF),
    Color(0xFFFF5FCF),
    Color(0xFFFFC400),
    Color(0xFF4DEEEA),
    Color(0xFF0065F8),
    Color(0xFF06D001),
    Color(0xFFFC7135),
    Color(0xFFD12052),
  ];

  static const List<Color> greyscaleColors = [
    Color(0xFF000000),
    Color(0xFF222222),
    Color(0xFF444444),
    Color(0xFF666666),
    Color(0xFF888888),
    Color(0xFFAAAAAA),
    Color(0xFFCCCCCC),
    Color(0xFFE6E6E6),
    Color(0xFFFFFFFF),
  ];

  static const List<Color> pkmnColors = [
    Color(0xFFA8A77A), // Normal
    Color(0xFFEE8130), // Fire
    Color(0xFF6390F0), // Water
    Color(0xFFF7D02C), // Electric
    Color(0xFF7AC74C), // Grass
    Color(0xFF96D9D6), // Ice
    Color(0xFFC22E28), // Fighting
    Color(0xFFA33EA1), // Poison
    Color(0xFF6F35FC), // Ground
  ];

  static const List<Color> pkmn2Colors = [
    Color(0xFF96D9D6), // Ice
    Color(0xFFE2BF65), // Ground
    Color(0xFFA98FF3), // Flying
    Color(0xFFF95587), // Psychic
    Color(0xFFA6B91A), // Bug
    Color(0xFF735797), // Ghost
    Color(0xFF705746), // Dark
    Color(0xFFB7B7CE), // Steel
    Color(0xFFD685AD), // Fairy
  ];

  static const List<Color> glassColors = [
    Color(0xFF243D42),
    Color(0xFF0B3C8C), // Deep Navy
    Color(0xFF2563EB), // Royal Blue
    Color(0xFFCFD8DC), // Light grey
    Color(0xFF00D9B4), // Turquoise
    Color(0xFF009448), // Emerald
    Color(0xFFF4D1FF),
    Color(0xFFBE1FCC),
    Color(0xFF7B3FF2), // Purple
  ];

  static const List<Color> defaultBColors = [
    Color(0xFFFF5D8F),
    Color(0xFFFFB627),
    Color(0xFF4ECDC4),
    Color(0xFF6A4C93),
    Color(0xFFFF6B35),
    Color(0xFFD62839),
    Color(0xFFB14DFF),
    Color(0xFF468A64),
    Color(0xFF3A86FF),
  ];

  static const List<Color> rainbowBColors = [
    Color(0xFF33E69A),
    Color(0xFF229EC3),
    Color(0xFF455BED),
    Color(0xFF5B22A0),
    Color(0xFFE444CE),
    Color(0xFF931021),
    Color(0xFFDEB27C),
    Color(0xFFB6C610),
    Color(0xFF294570),
  ];

  static const List<Color> neonBColors = [
    Color(0xFF6239AC),
    Color(0xFF8697C6),
    Color(0xFF69ED45),
    Color(0xFF22A051),
    Color(0xFF44DBE4),
    Color(0xFF3B4BCE),
    Color(0xFFAA7CDE),
    Color(0xFFCF59B9),
    Color(0xFFD6295E),
  ];

  static const List<Color> pkmnBColors = [
    Color(0xFFB8860B),
    Color(0xFFFF6B35),
    Color(0xFF4A90E2),
    Color(0xFFF4C430),
    Color(0xFF2E8B57),
    Color(0xFF40E0D0),
    Color(0xFFC0392B),
    Color(0xFF6A0DAD),
    Color(0xFF2B2B2B),
  ];

  static const List<Color> pkmn2BColors = [
    Color(0xFFA8C8E8),
    Color(0xFF8B6F47),
    Color(0xFFC9A876),
    Color(0xFF6B4C93),
    Color(0xFFE85D75),
    Color(0xFF4A7A96),
    Color(0xFFB0B8C4),
    Color(0xFF4A9B6E),
    Color(0xFF7B68A6),
  ];

  static const List<Color> glassBColors = [
    Color(0xFFCFEAE3),
    Color(0xFFA3D4D9),
    Color(0xFF51B2D6),
    Color(0xFF1B5DAC),
    Color(0xFF98ACA9),
    Color(0xFFF9E1B4),
    Color(0xFFFFFDF7),
    Color(0xFFFCFCFC),
    Color(0xFFFCE8EC),
  ];

  static const List<Color> skyBColors = [
    Color(0xFF32104F),
    Color(0xFF54278F),
    Color(0xFF8E5EA2),
    Color(0xFFD45087),
    Color(0xFFD62828),
    Color(0xFFE85D04),
    Color(0xFFFFB703),
    Color(0xFFFFF77D),
    Color(0xFFFFFBEF),
  ];

  static const List<Color> world11BColors = [
    Color(0xFF1F5BFF),
    Color(0xFFF79A1E),
    Color(0xFFD7262E),
    Color(0xFFF58FB5),
    Color(0xFF2B2B3A),
    Color(0xFFFFD400),
    Color(0xFF37B24D),
    Color(0xFF8E5BD6),
    Color(0xFF9AA3AE),
  ];

  static const List<Color> skyColors = [
    Color(0xFFF5F3FF),
    Color(0xFF73726F),
    Color(0xFF282829),
    Color(0xFFFE6382),
    Color(0xFFF3D493),
    Color(0xFF60F0E1),
    Color(0xFF02B34E),
    Color(0xFF8232C7),
    Color(0xFF026468),
  ];

  static const List<Color> world11Colors = [
    Color(0xFFE52521), // Mario Red
    Color(0xFF8B4513), // Brick Brown
    Color(0xFFFFC400), // Coin Gold
    Color(0xFFF57C00), // Fire Flower Orange
    Color(0xFF1E9E3F), // Pipe Green
    Color(0xFF7AC943), // Yoshi Green
    Color(0xFF29B6F6), // Sky Blue
    Color(0xFF1565C0), // Water Blue
    Color(0xFF6A35B1), // Night Sky Purple
  ];

  /// Rainbow organic pairs stay within ~25° of hue so the amorphous HSL blend
  /// keeps each unit in its own family around the wheel.
  static const _rainbowStarts = <Color>[
    Color(0xFFC62828), // Red
    Color(0xFFEF6C00), // Orange
    Color(0xFFF9A825), // Gold
    Color(0xFF7CB342), // Lime
    Color(0xFF00897B), // Teal
    Color(0xFF0277BD), // Blue
    Color(0xFF3949AB), // Indigo
    Color(0xFF8E24AA), // Violet
    Color(0xFFD81B60), // Magenta
  ];

  static const _rainbowStops = <Color>[
    Color(0xFFFF8A80), // Light coral-red
    Color(0xFFFFB74D), // Light amber-orange
    Color(0xFFFFF176), // Light yellow
    Color(0xFFAED581), // Light leaf
    Color(0xFF4DB6AC), // Light teal
    Color(0xFF4FC3F7), // Sky blue
    Color(0xFF7986CB), // Soft indigo
    Color(0xFFCE93D8), // Soft lilac
    Color(0xFFF8BBD0), // Soft pink-magenta
  ];

  static final List<PaletteSwatch> rainbowSwatches = List.generate(9, (i) {
    // Softer stop + lower intensity so the organic texture stays understated.
    final stop = Color.lerp(_rainbowStarts[i], _rainbowStops[i], 0.62)!;
    return PaletteSwatch.organic(
      start: _rainbowStarts[i],
      stop: stop,
      swirlSeed: i + 1,
      intensity: 0.55,
    );
  });

  static final List<PaletteSwatch> rainbowBSwatches = _organicFromColors(
    rainbowBColors,
    seedBase: 21,
    intensity: 0.55,
  );

  /// Same-hue light/dark companion for organic palettes (Rainbow, Glass).
  static Color _organicCompanion(Color color) {
    final hsl = HSLColor.fromColor(color);
    final lightness = hsl.lightness;
    final target = lightness < 0.55
        ? (lightness + 0.22).clamp(0.0, 0.95)
        : (lightness - 0.22).clamp(0.05, 1.0);
    return hsl
        .withLightness(target)
        .withSaturation((hsl.saturation * 0.92).clamp(0.0, 1.0))
        .toColor();
  }

  static List<PaletteSwatch> _organicFromColors(
    List<Color> colors, {
    required int seedBase,
    bool animated = false,
    double intensity = 1.0,
    double motionSpeed = 1.0,
  }) {
    return List.generate(colors.length, (i) {
      final start = colors[i];
      var stop = _organicCompanion(start);
      if (stop == start) {
        stop = Color.lerp(start, Colors.white, 0.28)!;
      }
      return PaletteSwatch.organic(
        start: start,
        stop: stop,
        swirlSeed: seedBase + i,
        animated: animated,
        intensity: intensity,
        motionSpeed: motionSpeed,
      );
    });
  }

  static final List<PaletteSwatch> glassSwatches = _organicFromColors(
    glassColors,
    seedBase: 600,
    animated: true,
  );

  /// Same moving organic fill as Glass, with stronger warp and a slower drift.
  static final List<PaletteSwatch> skySwatches = [
    for (final (i, swatch) in _organicFromColors(
      skyColors,
      seedBase: 800,
      animated: true,
      intensity: 1.85,
      motionSpeed: 0.72,
    ).indexed)
      i == 0
          ? PaletteSwatch(
              start: swatch.start,
              stop: swatch.stop,
              swirlSeed: swatch.swirlSeed,
              style: swatch.style,
              animated: swatch.animated,
              intensity: swatch.intensity,
              motionSpeed: swatch.motionSpeed,
              outlined: true,
            )
          : swatch,
  ];

  static List<PaletteSwatch> _solidSwatches(List<Color> colors) =>
      colors.map(PaletteSwatch.solid).toList();

  static final List<PaletteSwatch> neonSwatches = List.generate(
    neonColors.length,
    (i) => PaletteSwatch.neon(neonColors[i], swirlSeed: 400 + i),
  );

  /// Kanto / Johto: stark diagonal gloss (subtle, static).
  static final List<PaletteSwatch> pkmnSwatches = List.generate(
    pkmnColors.length,
    (i) => PaletteSwatch.gloss(pkmnColors[i], swirlSeed: 500 + i),
  );

  static final List<PaletteSwatch> pkmn2Swatches = List.generate(
    pkmn2Colors.length,
    (i) => PaletteSwatch.gloss(pkmn2Colors[i], swirlSeed: 600 + i),
  );

  /// 1-1: cell-shaded bands derived from each base color at paint time.
  static final List<PaletteSwatch> world11Swatches = List.generate(
    world11Colors.length,
    (i) => PaletteSwatch.celShade(world11Colors[i], swirlSeed: 300 + i),
  );

  static final List<PaletteSwatch> glassBSwatches = _organicFromColors(
    glassBColors,
    seedBase: 1600,
    animated: true,
  );

  static final List<PaletteSwatch> skyBSwatches = _organicFromColors(
    skyBColors,
    seedBase: 1800,
    animated: true,
    intensity: 1.85,
    motionSpeed: 0.72,
  );

  static final List<PaletteSwatch> neonBSwatches = List.generate(
    neonBColors.length,
    (i) => PaletteSwatch.neon(neonBColors[i], swirlSeed: 1400 + i),
  );

  static final List<PaletteSwatch> pkmnBSwatches = List.generate(
    pkmnBColors.length,
    (i) => PaletteSwatch.gloss(pkmnBColors[i], swirlSeed: 1500 + i),
  );

  static final List<PaletteSwatch> pkmn2BSwatches = List.generate(
    pkmn2BColors.length,
    (i) => PaletteSwatch.gloss(pkmn2BColors[i], swirlSeed: 1600 + i),
  );

  static final List<PaletteSwatch> world11BSwatches = List.generate(
    world11BColors.length,
    (i) => PaletteSwatch.celShade(world11BColors[i], swirlSeed: 1300 + i),
  );

  static List<PaletteSwatch> swatchesFor(
    GamePalette palette, {
    bool bSide = false,
    Set<int> flatSlots = const {},
  }) {
    final useB = bSide && palette.hasBSide;
    final base = switch (palette) {
      GamePalette.standard =>
        _solidSwatches(useB ? defaultBColors : defaultColors),
      GamePalette.rainbow => useB ? rainbowBSwatches : rainbowSwatches,
      GamePalette.world11 => useB ? world11BSwatches : world11Swatches,
      GamePalette.neon => useB ? neonBSwatches : neonSwatches,
      GamePalette.pkmn => useB ? pkmnBSwatches : pkmnSwatches,
      GamePalette.pkmn2 => useB ? pkmn2BSwatches : pkmn2Swatches,
      GamePalette.glass => useB ? glassBSwatches : glassSwatches,
      GamePalette.sky => useB ? skyBSwatches : skySwatches,
      GamePalette.greyscale => _solidSwatches(greyscaleColors),
      GamePalette.iro => _iroShowcaseSwatches(),
    };
    return flattenSlots(base, flatSlots);
  }

  /// Replaces textured slots (values 1–9) with a solid representative color.
  static List<PaletteSwatch> flattenSlots(
    List<PaletteSwatch> swatches,
    Set<int> values,
  ) {
    if (values.isEmpty) return swatches;
    return [
      for (var i = 0; i < swatches.length; i++)
        values.contains(i + 1)
            ? PaletteSwatch.solid(
                swatches[i].representative,
                outlined: swatches[i].outlined,
              )
            : swatches[i],
    ];
  }

  static List<PaletteSwatch> _iroShowcaseSwatches() {
    final palettes = GamePalette.menuValues;
    return [
      for (var i = 0; i < 9; i++)
        swatchesFor(palettes[i % palettes.length])[i],
    ];
  }

  static List<Color> colorsFor(GamePalette palette, {bool bSide = false}) =>
      swatchesFor(palette, bSide: bSide)
          .map((swatch) => swatch.representative)
          .toList();

  /// Value is 1–9. Returns null for empty (0).
  static Color? colorForValue(
    int value,
    GamePalette palette, {
    bool bSide = false,
  }) {
    if (value < 1 || value > 9) return null;
    return swatchesFor(palette, bSide: bSide)[value - 1].representative;
  }

  static PaletteSwatch? swatchForValue(
    int value,
    GamePalette palette, {
    bool bSide = false,
  }) {
    if (value < 1 || value > 9) return null;
    return swatchesFor(palette, bSide: bSide)[value - 1];
  }

  /// Swatch for [value] from an explicit 9-slot display list, if valid.
  static PaletteSwatch? swatchFromList(int value, List<PaletteSwatch>? swatches) {
    if (swatches == null || value < 1 || value > swatches.length) return null;
    return swatches[value - 1];
  }

  /// Darker edge used only on Sky A-side slot 1.
  static const Color lightFillOutline = Color(0xFF444444);

  static Color? outlineForSwatch(PaletteSwatch swatch) =>
      swatch.outlined ? lightFillOutline : null;

  static Color? outlineForValue(
    int value,
    GamePalette palette, {
    bool bSide = false,
  }) {
    if (value < 1 || value > 9) return null;
    return outlineForSwatch(swatchesFor(palette, bSide: bSide)[value - 1]);
  }

  /// Pocket high window: board values 1–6 map to palette slots 4–9.
  static const int pocketHighSwatchOffset = 3;
  static const int pocketSwatchCount = 6;

  static int normalizePocketSwatchOffset(int offset) =>
      offset == pocketHighSwatchOffset ? pocketHighSwatchOffset : 0;

  /// Six consecutive entries starting at [offset] (0 or 3).
  static List<T> pocketWindow<T>(List<T> full, int offset) {
    final start = normalizePocketSwatchOffset(offset);
    if (full.length < start + pocketSwatchCount) return List<T>.from(full);
    return full.sublist(start, start + pocketSwatchCount);
  }

  /// Outline for slot [value] when each slot may come from a different palette.
  /// [slotOffset] is added to [value] for near-white outline checks (Pocket 4–9).
  static Color? outlineForSlot(
    int value,
    GamePalette palette, [
    List<GamePalette>? sources,
    int slotOffset = 0,
  ]) {
    final slot = value + slotOffset;
    if (sources != null && value >= 1 && value <= sources.length) {
      return outlineForValue(slot, sources[value - 1]);
    }
    return outlineForValue(slot, palette);
  }
}

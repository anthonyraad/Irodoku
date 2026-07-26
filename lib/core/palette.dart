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
    Color(0xFF00FF9C),
    Color(0xFF0065F8),
    Color(0xFF06D001),
    Color(0xFFF45B26),
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
    Color(0xFF0B3C8C), // Deep Navy
    Color(0xFF2563EB), // Royal Blue
    Color(0xFF4FC3F7), // Sky Blue
    Color(0xFFCFD8DC), // Light grey
    Color(0xFF00C9A7), // Turquoise
    Color(0xFF00A651), // Emerald
    Color(0xFF8BCF00), // Lime Green
    Color(0xFF7B3FF2), // Purple
    Color(0xFFC026D3), // Magenta-Violet
  ];

  static const List<Color> sunsetColors = [
    Color(0xFF32104F), // Deep purple
    Color(0xFF54278F), // Violet
    Color(0xFF8E5EA2), // Lavender
    Color(0xFFD45087), // Rose
    Color(0xFFD62828), // Sunset red
    Color(0xFFE85D04), // Burnt orange
    Color(0xFFFFB703), // Amber gold
    Color(0xFFFFD500), // Bright gold
    Color(0xFFFFF3B0), // Pale sand
  ];

  static const List<Color> world11Colors = [
    Color(0xFFE52521), // Mario Red
    Color(0xFFF57C00), // Fire Flower Orange
    Color(0xFFFFC400), // Coin Gold
    Color(0xFF1E9E3F), // Pipe Green
    Color(0xFF7AC943), // Yoshi Green
    Color(0xFF29B6F6), // Sky Blue
    Color(0xFF1565C0), // Water Blue
    Color(0xFF6A35B1), // Night Sky Purple
    Color(0xFF8B4513), // Brick Brown
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
    return PaletteSwatch.organic(
      start: _rainbowStarts[i],
      stop: _rainbowStops[i],
      swirlSeed: i + 1,
    );
  });

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

  /// Same moving organic fill as Glass, with stronger warp and faster drift.
  static final List<PaletteSwatch> sunsetSwatches = _organicFromColors(
    sunsetColors,
    seedBase: 800,
    animated: true,
    intensity: 1.85,
    motionSpeed: 1.0,
  );

  static List<PaletteSwatch> _solidSwatches(List<Color> colors) =>
      colors.map(PaletteSwatch.solid).toList();

  static List<PaletteSwatch> swatchesFor(GamePalette palette) => switch (palette) {
        GamePalette.standard => _solidSwatches(defaultColors),
        GamePalette.rainbow => rainbowSwatches,
        GamePalette.world11 => _solidSwatches(world11Colors),
        GamePalette.neon => _solidSwatches(neonColors),
        GamePalette.pkmn => _solidSwatches(pkmnColors),
        GamePalette.pkmn2 => _solidSwatches(pkmn2Colors),
        GamePalette.glass => glassSwatches,
        GamePalette.sunset => sunsetSwatches,
        GamePalette.greyscale => _solidSwatches(greyscaleColors),
      };

  static List<Color> colorsFor(GamePalette palette) =>
      swatchesFor(palette).map((swatch) => swatch.representative).toList();

  /// Value is 1–9. Returns null for empty (0).
  static Color? colorForValue(int value, GamePalette palette) {
    if (value < 1 || value > 9) return null;
    return swatchesFor(palette)[value - 1].representative;
  }

  static PaletteSwatch? swatchForValue(int value, GamePalette palette) {
    if (value < 1 || value > 9) return null;
    return swatchesFor(palette)[value - 1];
  }

  /// Greyscale white (#FFFFFF) needs an outline so it doesn't match empty cells.
  static const Color greyscaleWhiteOutline = Color(0xFF444444);

  static Color? outlineForValue(int value, GamePalette palette) {
    if (palette == GamePalette.greyscale && value == 9) {
      return greyscaleWhiteOutline;
    }
    return null;
  }
}

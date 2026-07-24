import 'package:flutter/material.dart';

import '../models/game_palette.dart';

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
    Color(0xFFFF1744), // Neon red
    Color(0xFFFF6A00), // Neon orange
    Color(0xFFFFEA00), // Laser yellow
    Color(0xFF00E676), // Neon green
    Color(0xFF006D5B), // Dark green
    Color(0xFF00E5FF), // Electric cyan
    Color(0xFF2979FF), // Electric blue
    Color(0xFF651FFF), // Neon indigo
    Color(0xFFFC79C3), // Hot pink
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
    Color(0xFF00E5FF), // Aqua
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
    Color(0xFFE76F51), // Coral
    Color(0xFFF9844A), // Orange coral
    Color(0xFFF8961E), // Orange
    Color(0xFFF9C74F), // Gold
    Color(0xFFFDE2A7), // Sand
  ];

  static const List<Color> rainbowColors = [
    Color(0xFFD7263D), // Red
    Color(0xFFF26B1D), // Orange
    Color(0xFFFFCA3A), // Yellow
    Color(0xFF8AC926), // Lime Green
    Color(0xFF06A77D), // Emerald Green
    Color(0xFF4361EE), // Blue
    Color(0xFF3A0CA3), // Indigo
    Color(0xFF7209B7), // Violet
    Color(0xFFF72585), // Pink/Magenta
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

  static List<Color> colorsFor(GamePalette palette) => switch (palette) {
        GamePalette.standard => defaultColors,
        GamePalette.rainbow => rainbowColors,
        GamePalette.world11 => world11Colors,
        GamePalette.neon => neonColors,
        GamePalette.pkmn => pkmnColors,
        GamePalette.pkmn2 => pkmn2Colors,
        GamePalette.glass => glassColors,
        GamePalette.sunset => sunsetColors,
        GamePalette.greyscale => greyscaleColors,
      };

  /// Value is 1–9. Returns null for empty (0).
  static Color? colorForValue(int value, GamePalette palette) {
    if (value < 1 || value > 9) return null;
    return colorsFor(palette)[value - 1];
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

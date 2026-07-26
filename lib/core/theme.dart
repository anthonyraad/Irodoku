import 'package:flutter/material.dart';

abstract final class IrodokuTheme {
  static const _seed = Color(0xFF42A5F5);
  static const settingsPrimaryLight = Color(0xFF424242);
  static const settingsPrimaryDark = Color(0xFF757575);

  /// Puzzle board always uses light-mode fills and grid lines.
  static const boardBrightness = Brightness.light;

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Balatro',
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF5F6F8),
      textTheme: ThemeData(brightness: Brightness.light).textTheme.apply(
            fontFamily: 'Balatro',
          ),
      primaryTextTheme: ThemeData(brightness: Brightness.light)
          .primaryTextTheme
          .apply(fontFamily: 'Balatro'),
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFFF5F6F8),
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: 'Balatro',
          color: colorScheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: const DividerThemeData(space: 1, thickness: 1),
    );
  }

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Balatro',
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF121418),
      textTheme: ThemeData(brightness: Brightness.dark).textTheme.apply(
            fontFamily: 'Balatro',
          ),
      primaryTextTheme: ThemeData(brightness: Brightness.dark)
          .primaryTextTheme
          .apply(fontFamily: 'Balatro'),
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF121418),
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: 'Balatro',
          color: colorScheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: const Color(0xFF1C1F26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: Colors.white.withValues(alpha: 0.12),
      ),
    );
  }

  /// Grid line colors that stay readable in both themes.
  static Color thinGridLine(Brightness brightness) =>
      brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.28)
          : Colors.black.withValues(alpha: 0.22);

  static Color thickGridLine(Brightness brightness) =>
      brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.72)
          : Colors.black.withValues(alpha: 0.65);

  static Color emptyCellFill(Brightness brightness) =>
      brightness == Brightness.dark
          ? const Color(0xFF1C1F26)
          : Colors.white;

  static Color givenCellFill(Brightness brightness) =>
      brightness == Brightness.dark
          ? const Color(0xFF2A2F38)
          : const Color(0xFFE8EAED);

  static const selectedCellBorderWidth = 3.0;

  /// Tint drawn above cell fills so selection stays visible on colored cells.
  static Color selectedCellHighlight(Brightness brightness, Color primary) =>
      primary.withValues(alpha: brightness == Brightness.dark ? 0.34 : 0.28);

  /// Powder blue for peer highlights — kept far from picker light-blue (#42A5F5).
  static const _peerAccentLight = Color(0xFFC5DDF0);

  /// Soft highlight for peers in the selected cell's row, column, or box.
  static Color relatedCellOverlay(Brightness brightness) =>
      brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.03)
          : _peerAccentLight.withValues(alpha: 0.08);

  /// Overlay on other cells that share the selected cell's confirmed color.
  static Color sameColorOverlay(Brightness brightness) =>
      brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.28)
          : Colors.black.withValues(alpha: 0.16);

  /// Outline color for the selected row, column, and 3×3 box borders.
  static Color relatedUnitBorder(Brightness brightness) =>
      brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.72)
          : const Color(0xFF6A9CC4);

  /// Pulses between [relatedUnitBorder] and a softer tint ([t] is 0–1).
  static Color relatedUnitBorderPulse(Brightness brightness, double t) {
    final base = relatedUnitBorder(brightness);
    final light = brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.95)
        : const Color(0xFFB8D8EE);
    return Color.lerp(base, light, t.clamp(0.0, 1.0))!;
  }

  static Color conflictBorder(Brightness brightness) =>
      brightness == Brightness.dark
          ? const Color(0xFFFF6B6B)
          : const Color(0xFFE53935);

  /// Soft animated sweep for bulk note-select peer borders.
  static List<Color> bulkNoteBorderRainbow(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return const [
        Color(0xA0FF8A9B),
        Color(0xA0FFB86A),
        Color(0xA0FFE97A),
        Color(0xA07AD99A),
        Color(0xA06EC5E8),
        Color(0xA0A894E8),
        Color(0xA0FF8A9B),
      ];
    }
    return const [
      Color(0xBFF06292),
      Color(0xBFF5A623),
      Color(0xBFE6C229),
      Color(0xBF5CB87A),
      Color(0xBF4BA3C7),
      Color(0xBF8E7CC3),
      Color(0xBFF06292),
    ];
  }

  /// Samples the bulk-note rainbow at [phase] (0–1) for UI accents.
  static Color bulkNoteRainbowColor(Brightness brightness, double phase) {
    final colors = bulkNoteBorderRainbow(brightness)
        .map((color) => color.withValues(alpha: 1))
        .toList();
    final wrapped = phase % 1.0;
    final pos = wrapped * (colors.length - 1);
    final i = pos.floor().clamp(0, colors.length - 2);
    final t = Curves.easeInOut.transform(pos - i);
    return Color.lerp(colors[i], colors[i + 1], t)!;
  }

  /// Dark grey accent for Settings section headers and toggles.
  static ThemeData settingsTheme(ThemeData base) {
    final grey =
        base.brightness == Brightness.dark ? settingsPrimaryDark : settingsPrimaryLight;
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: grey,
        onPrimary: Colors.white,
      ),
    );
  }
}

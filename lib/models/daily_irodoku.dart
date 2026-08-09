import 'difficulty.dart';
import 'game_palette.dart';

/// Deterministic daily challenge shared by all players on a local calendar day.
class DailyIrodoku {
  /// Difficulties used for the daily (equal long-run odds, non-sequential).
  static const scheduleDifficulties = <Difficulty>[
    Difficulty.easy,
    Difficulty.medium,
    Difficulty.hard,
  ];

  /// Palettes that rotate for the daily (menu palettes, including locked ones).
  static const schedulePalettes = <GamePalette>[
    GamePalette.standard,
    GamePalette.rainbow,
    GamePalette.world11,
    GamePalette.neon,
    GamePalette.pkmn,
    GamePalette.pkmn2,
    GamePalette.glass,
    GamePalette.sky,
  ];

  final String dayKey;
  final int seed;
  final Difficulty difficulty;
  final GamePalette palette;

  const DailyIrodoku({
    required this.dayKey,
    required this.seed,
    required this.difficulty,
    required this.palette,
  });

  /// Local-calendar challenge for [date] (defaults to now).
  factory DailyIrodoku.forDate([DateTime? date]) {
    final local = (date ?? DateTime.now()).toLocal();
    final key = dayKeyFor(local);
    final dayIndex = _utcDayIndex(key);
    // Stable across devices/isolates — do not use [Object.hash] / [hashCode].
    final seed = _stableHash('$key:seed');
    final difficultyIndex =
        _stableHash('$key:difficulty') % scheduleDifficulties.length;
    return DailyIrodoku(
      dayKey: key,
      seed: seed == 0 ? 1 : seed,
      difficulty: scheduleDifficulties[difficultyIndex],
      palette: schedulePalettes[dayIndex.abs() % schedulePalettes.length],
    );
  }

  static String dayKeyFor(DateTime date) {
    final local = date.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Calendar day before [dayKey] (`yyyy-MM-dd`).
  static String previousDayKey(String dayKey) {
    final parts = dayKey.split('-');
    final prev = DateTime.utc(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    ).subtract(const Duration(days: 1));
    final y = prev.year.toString().padLeft(4, '0');
    final m = prev.month.toString().padLeft(2, '0');
    final d = prev.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Short display date from `yyyy-MM-dd`, e.g. `8.9.26`.
  static String shortDateLabel(String dayKey) {
    final parts = dayKey.split('-');
    if (parts.length != 3) return dayKey;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return dayKey;
    final yy = (year % 100).toString().padLeft(2, '0');
    return '$month.$day.$yy';
  }

  /// Days since 2024-01-01 UTC for a `yyyy-MM-dd` key (timezone-independent).
  static int _utcDayIndex(String dayKey) {
    final parts = dayKey.split('-');
    final day = DateTime.utc(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
    return day.difference(DateTime.utc(2024, 1, 1)).inDays;
  }

  /// FNV-1a 32-bit — stable across platforms, isolates, and app restarts.
  static int _stableHash(String input) {
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash & 0x7fffffff;
  }
}

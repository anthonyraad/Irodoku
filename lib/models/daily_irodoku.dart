import 'difficulty.dart';
import 'game_palette.dart';

/// Deterministic daily challenge shared by all players.
///
/// Resets at midnight **PST** (fixed UTC−8, no daylight-saving shift) so every
/// device sees the same puzzle for the same `yyyy-MM-dd` day key.
class DailyIrodoku {
  /// Fixed Pacific Standard Time offset (UTC−8). Intentionally ignores PDT.
  static const pstOffsetFromUtc = Duration(hours: -8);

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

  /// Completed rows+cols+boxes required before the mid-game palette switch.
  static const paletteSwitchUnitThreshold = 11; // ~40% of 27 units

  final String dayKey;
  final int seed;
  final Difficulty difficulty;

  /// Opening palette for the day (everyone shares this).
  final GamePalette palette;

  /// Second palette after [paletteSwitchUnitThreshold] units (always ≠ [palette]).
  final GamePalette secondPalette;

  const DailyIrodoku({
    required this.dayKey,
    required this.seed,
    required this.difficulty,
    required this.palette,
    required this.secondPalette,
  });

  /// PST-calendar challenge for [date] (defaults to now).
  factory DailyIrodoku.forDate([DateTime? date]) {
    final key = dayKeyFor(date ?? DateTime.now());
    final dayIndex = _utcDayIndex(key);
    // Stable across devices/isolates — do not use [Object.hash] / [hashCode].
    final seed = _stableHash('$key:seed');
    final difficultyIndex =
        _stableHash('$key:difficulty') % scheduleDifficulties.length;
    final firstIndex = dayIndex.abs() % schedulePalettes.length;
    // Offset 1..(n-1) so second is never the same as first.
    final secondOffset =
        1 + (_stableHash('$key:secondPalette') % (schedulePalettes.length - 1));
    final secondIndex = (firstIndex + secondOffset) % schedulePalettes.length;
    return DailyIrodoku(
      dayKey: key,
      seed: seed == 0 ? 1 : seed,
      difficulty: scheduleDifficulties[difficultyIndex],
      palette: schedulePalettes[firstIndex],
      secondPalette: schedulePalettes[secondIndex],
    );
  }

  /// `yyyy-MM-dd` of the PST calendar day containing [date].
  static String dayKeyFor(DateTime date) {
    final pst = _pstWallClock(date);
    final y = pst.year.toString().padLeft(4, '0');
    final m = pst.month.toString().padLeft(2, '0');
    final d = pst.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Instant of the next PST midnight after [now] (defaults to now).
  static DateTime nextPstMidnight([DateTime? now]) {
    final utcNow = (now ?? DateTime.now()).toUtc();
    final pst = _pstWallClock(utcNow);
    // Carrier date for the current PST Y-M-D, then step to next midnight PST.
    final nextPstMidnightWall = DateTime.utc(pst.year, pst.month, pst.day)
        .add(const Duration(days: 1));
    // PST midnight wall clock → UTC (= wall + 8h).
    return nextPstMidnightWall.subtract(pstOffsetFromUtc);
  }

  /// Delay until the Daily resets (PST midnight), for UI refresh timers.
  static Duration timeUntilNextReset([DateTime? now]) {
    final n = (now ?? DateTime.now()).toUtc();
    final next = nextPstMidnight(n);
    final delta = next.difference(n);
    return delta.isNegative ? Duration.zero : delta;
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

  /// PST wall-clock components for [date] (DateTime is UTC-flagged; use Y/M/D/H only).
  static DateTime _pstWallClock(DateTime date) {
    return date.toUtc().add(pstOffsetFromUtc);
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

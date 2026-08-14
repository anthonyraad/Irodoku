import 'game_palette.dart';

/// Palette rows for the achievements grid (excludes Greyscale).
const List<GamePalette> achievementPaletteRows = [
  GamePalette.standard,
  GamePalette.rainbow,
  GamePalette.world11,
  GamePalette.neon,
  GamePalette.pkmn,
  GamePalette.pkmn2,
  GamePalette.glass,
  GamePalette.sky,
];

/// One cell in the 8×9 achievements grid (row/col are 0-based).
class Achievement {
  final int row;
  final int col;
  final String title;

  const Achievement({
    required this.row,
    required this.col,
    required this.title,
  });

  /// Stable prefs key, e.g. `r1c1`.
  String get id => 'r${row + 1}c${col + 1}';

  GamePalette get palette => achievementPaletteRows[row];

  /// Color value 1–9 for this column.
  int get colorValue => col + 1;

  static const int rowCount = 8;
  static const int columnCount = 9;

  /// XP for finishing a full Achievements-page row (row 1 → 1000, … row 8 → 8000).
  static int xpForCompletedRow(int rowIndex) => (rowIndex + 1) * 1000;

  static bool isRowComplete(Set<String> unlockedIds, int rowIndex) {
    for (var col = 0; col < columnCount; col++) {
      if (!unlockedIds.contains('r${rowIndex + 1}c${col + 1}')) {
        return false;
      }
    }
    return true;
  }

  static const List<Achievement> all = [
    // Row 1 — Default
    Achievement(row: 0, col: 0, title: 'Win 3 games with Default palette'),
    Achievement(row: 0, col: 1, title: 'Win 7 games with Default palette'),
    Achievement(row: 0, col: 2, title: 'Win 10 games with Default palette'),
    Achievement(row: 0, col: 3, title: 'Finish a game with the bottom-right cell'),
    Achievement(row: 0, col: 4, title: 'Finish a game with the top-left cell'),
    Achievement(row: 0, col: 5, title: 'Win a Hard game with Default palette'),
    Achievement(row: 0, col: 6, title: 'Finish a game with the center-middle cell'),
    Achievement(row: 0, col: 7, title: 'Win 1 game in Dark mode'),
    Achievement(row: 0, col: 8, title: 'Win an Easy game without taking notes'),
    // Row 2 — Rainbow
    Achievement(row: 1, col: 0, title: 'Win 3 games with Rainbow palette'),
    Achievement(row: 1, col: 1, title: 'Win 7 games with Rainbow palette'),
    Achievement(row: 1, col: 2, title: 'Win 10 games with Rainbow palette'),
    Achievement(row: 1, col: 3, title: 'Win a game without any undos'),
    Achievement(row: 1, col: 4, title: 'Win a game without any mistakes'),
    Achievement(row: 1, col: 5, title: 'Win a Master game with Rainbow palette'),
    Achievement(row: 1, col: 6, title: 'Erase 100 cells'),
    Achievement(row: 1, col: 7, title: 'Win a game 3 days in a row'),
    Achievement(
      row: 1,
      col: 8,
      title: 'Win 3 consecutive Hard games with no mistakes',
    ),
    // Row 3 — 1-1
    Achievement(row: 2, col: 0, title: 'Win 3 games with 1-1 palette'),
    Achievement(row: 2, col: 1, title: 'Win 7 games with 1-1 palette'),
    Achievement(row: 2, col: 2, title: 'Win 10 games with 1-1 palette'),
    Achievement(row: 2, col: 3, title: 'Win after making 2 mistakes'),
    Achievement(row: 2, col: 4, title: 'Win a Hard game without pausing'),
    Achievement(row: 2, col: 5, title: 'Win a Master game with 1-1 palette'),
    Achievement(row: 2, col: 6, title: 'Undo 100 times'),
    Achievement(row: 2, col: 7, title: 'Win an Expert game without pausing'),
    Achievement(
      row: 2,
      col: 8,
      title: 'Finish a game in exactly 4:54',
    ),
    // Row 4 — Neon
    Achievement(row: 3, col: 0, title: 'Win 3 games with Neon palette'),
    Achievement(row: 3, col: 1, title: 'Win 7 games with Neon palette'),
    Achievement(row: 3, col: 2, title: 'Win 10 games with Neon palette'),
    Achievement(row: 3, col: 3, title: 'Win an Easy game within 4 minutes'),
    Achievement(row: 3, col: 4, title: 'Win a Medium game within 8 minutes'),
    Achievement(row: 3, col: 5, title: 'Win a Master game with Neon palette'),
    Achievement(row: 3, col: 6, title: 'Win a Hard game within 12 minutes'),
    Achievement(row: 3, col: 7, title: 'Win an Expert game within 18 minutes'),
    Achievement(row: 3, col: 8, title: 'Win a Master game within 45 minutes'),
    // Row 5 — Kanto
    Achievement(row: 4, col: 0, title: 'Win 3 games with Kanto palette'),
    Achievement(row: 4, col: 1, title: 'Win 7 games with Kanto palette'),
    Achievement(row: 4, col: 2, title: 'Win 10 games with Kanto palette'),
    Achievement(
      row: 4,
      col: 3,
      title: 'Win the Daily Challenge 5 days in a row',
    ),
    Achievement(
      row: 4,
      col: 4,
      title: 'Start a game by filling in a Blue cell [Kanto]',
    ),
    Achievement(row: 4, col: 5, title: 'Win a Master game with Kanto palette'),
    Achievement(row: 4, col: 6, title: 'Take 1,000 notes'),
    Achievement(
      row: 4,
      col: 7,
      title: 'Complete a row, column, and box simultaneously',
    ),
    Achievement(
      row: 4,
      col: 8,
      title: 'Finish an Expert game by filling in a Orange cell [Kanto]',
    ),
    // Row 6 — Johto
    Achievement(row: 5, col: 0, title: 'Win 3 games with Johto palette'),
    Achievement(row: 5, col: 1, title: 'Win 7 games with Johto palette'),
    Achievement(row: 5, col: 2, title: 'Win 10 games with Johto palette'),
    Achievement(row: 5, col: 3, title: 'Finish 3 rows within 1:30'),
    Achievement(
      row: 5,
      col: 4,
      title: 'Finish 3 columns within 1:30',
    ),
    Achievement(row: 5, col: 5, title: 'Win a Master game with Johto palette'),
    Achievement(row: 5, col: 6, title: 'Finish 3 boxes within 1:30'),
    Achievement(
      row: 5,
      col: 7,
      title: 'Win back-to-back Expert games with Kanto and Johto',
    ),
    Achievement(
      row: 5,
      col: 8,
      title: 'Finish an Expert game by filling in a Silver cell [Johto]',
    ),
    // Row 7 — Glass
    Achievement(row: 6, col: 0, title: 'Win 3 games with Glass palette'),
    Achievement(row: 6, col: 1, title: 'Win 7 games with Glass palette'),
    Achievement(row: 6, col: 2, title: 'Win 10 games with Glass palette'),
    Achievement(row: 6, col: 3, title: 'Win a Medium game without taking notes'),
    Achievement(
      row: 6,
      col: 4,
      title: 'Win 3 consecutive Expert games with no mistakes',
    ),
    Achievement(row: 6, col: 5, title: 'Win a Master game with Glass palette'),
    Achievement(
      row: 6,
      col: 6,
      title: 'Win an Expert or Master game in exactly 44:44',
    ),
    Achievement(
      row: 6,
      col: 7,
      title: 'Complete 9 rows, columns, or boxes in 9 seconds.',
    ),
    Achievement(
      row: 6,
      col: 8,
      title: 'Fill in all 9 colors consecutively without repeating a color',
    ),
    // Row 8 — Sky
    Achievement(row: 7, col: 0, title: 'Win 3 games with Sky palette'),
    Achievement(row: 7, col: 1, title: 'Win 7 games with Sky palette'),
    Achievement(row: 7, col: 2, title: 'Win 10 games with Sky palette'),
    Achievement(
      row: 7,
      col: 3,
      title: 'Finish a Master game by filling in a Black cell [Sky]',
    ),
    Achievement(
      row: 7,
      col: 4,
      title: 'Win a Chromatic game without taking notes and with no mistakes',
    ),
    Achievement(
      row: 7,
      col: 5,
      title: 'Win back-to-back Master games with Glass and Sky',
    ),
    Achievement(
      row: 7,
      col: 6,
      title: 'Win the Daily Challenge 30 days in a row',
    ),
    Achievement(row: 7, col: 7, title: 'Win 30 Chromatic games'),
    Achievement(row: 7, col: 8, title: 'Win 30 Master games with no mistakes'),
  ];

  static Achievement? byId(String id) {
    for (final a in all) {
      if (a.id == id) return a;
    }
    return null;
  }
}

/// Per-game flags/counters used when evaluating win achievements.
class AchievementGameContext {
  final int? firstFillColor;
  final int? lastFillColor;
  final int? lastFillRow;
  final int? lastFillCol;
  final bool usedNotes;
  final bool usedUndo;
  final bool paused;
  final bool usedDarkMode;
  final bool chromatic;
  final bool completedRowColBoxSimultaneously;
  final bool completedNineUnitsInNineSeconds;
  final bool filledNineDistinctColorsConsecutively;
  /// Units completed while game timer was still under 1:30.
  final int rowsCompletedInFirst90Seconds;
  final int colsCompletedInFirst90Seconds;
  final int boxesCompletedInFirst90Seconds;

  const AchievementGameContext({
    this.firstFillColor,
    this.lastFillColor,
    this.lastFillRow,
    this.lastFillCol,
    this.usedNotes = false,
    this.usedUndo = false,
    this.paused = false,
    this.usedDarkMode = false,
    this.chromatic = false,
    this.completedRowColBoxSimultaneously = false,
    this.completedNineUnitsInNineSeconds = false,
    this.filledNineDistinctColorsConsecutively = false,
    this.rowsCompletedInFirst90Seconds = 0,
    this.colsCompletedInFirst90Seconds = 0,
    this.boxesCompletedInFirst90Seconds = 0,
  });
}

import 'cell.dart';
import 'difficulty.dart';
import 'game_palette.dart';
import '../sudoku/sudoku_board.dart';

class PausedGame {
  final Difficulty difficulty;
  final Duration elapsed;
  final int mistakes;
  final List<int> solution;
  final List<Cell> cells;
  final bool isDaily;
  final bool isPocket;
  final String? dailyDayKey;

  /// Live session palette (Chromatic hop / Daily), not the saved Config choice.
  final GamePalette? sessionPalette;
  /// Iro slot sources for this board; null when not using an Iro mix.
  final List<String>? iroSources;
  /// Pocket: 0 = palette slots 1–6, 3 = slots 4–9. Ignored on 9×9 / Daily.
  final int pocketSwatchOffset;
  final bool usedNotes;
  /// True when this board was restarted after a defeat (Classic / Chromatic / Pocket).
  final bool retriedAfterLoss;

  const PausedGame({
    required this.difficulty,
    required this.elapsed,
    required this.mistakes,
    required this.solution,
    required this.cells,
    this.isDaily = false,
    this.isPocket = false,
    this.dailyDayKey,
    this.sessionPalette,
    this.iroSources,
    this.pocketSwatchOffset = 0,
    this.usedNotes = false,
    this.retriedAfterLoss = false,
  });

  Map<String, Object?> toJson() {
    return {
      'difficulty': difficulty.storageKey,
      'elapsedMs': elapsed.inMilliseconds,
      'mistakes': mistakes,
      'solution': solution,
      'isDaily': isDaily,
      'isPocket': isPocket,
      'dailyDayKey': dailyDayKey,
      'sessionPalette': sessionPalette?.storageKey,
      'iroSources': iroSources,
      'pocketSwatchOffset': pocketSwatchOffset,
      'usedNotes': usedNotes,
      'retriedAfterLoss': retriedAfterLoss,
      'cells': [
        for (final cell in cells)
          {
            'v': cell.value,
            'n': cell.notes.toList()..sort(),
            'g': cell.isGiven,
            'l': cell.isLocked,
          },
      ],
    };
  }

  factory PausedGame.fromJson(Map<String, dynamic> json) {
    final cellMaps = (json['cells'] as List<dynamic>? ?? const []);
    final cells = <Cell>[];
    for (final raw in cellMaps) {
      final map = Map<String, dynamic>.from(raw as Map);
      cells.add(
        Cell(
          value: map['v'] as int? ?? 0,
          notes: _notesFromMap(map),
          isGiven: map['g'] as bool? ?? false,
          isLocked: map['l'] as bool? ?? false,
        ),
      );
    }

    final solutionRaw = (json['solution'] as List<dynamic>? ?? const [])
        .map((e) => e as int)
        .toList();

    final isPocket = json['isPocket'] as bool? ??
        cells.length == SudokuBoard.pocketSize * SudokuBoard.pocketSize;
    final expected = isPocket
        ? SudokuBoard.pocketSize * SudokuBoard.pocketSize
        : SudokuBoard.size * SudokuBoard.size;
    if (cells.length != expected || solutionRaw.length != expected) {
      throw const FormatException('Invalid paused game payload');
    }

    // Migrate older saves / repair lock flags from the solution.
    for (var i = 0; i < cells.length; i++) {
      final cell = cells[i];
      if (cell.isGiven || cell.value == 0) {
        if (cell.isLocked) cells[i] = cell.copyWith(isLocked: false);
        continue;
      }
      final correct = cell.value == solutionRaw[i];
      if (cell.isLocked != correct) {
        cells[i] = cell.copyWith(isLocked: correct);
      }
    }

    final sessionKey = json['sessionPalette'] as String?;
    final notesOnBoard = cells.any((cell) => cell.hasNotes);
    return PausedGame(
      difficulty: Difficulty.fromStorageKey(json['difficulty'] as String?),
      elapsed: Duration(milliseconds: json['elapsedMs'] as int? ?? 0),
      mistakes: json['mistakes'] as int? ?? 0,
      solution: solutionRaw,
      cells: cells,
      isDaily: json['isDaily'] as bool? ?? false,
      isPocket: isPocket,
      dailyDayKey: json['dailyDayKey'] as String?,
      sessionPalette:
          sessionKey == null ? null : GamePalette.fromStorageKey(sessionKey),
      iroSources: _stringList(json['iroSources']),
      pocketSwatchOffset: _pocketSwatchOffsetFromJson(json['pocketSwatchOffset']),
      usedNotes: json['usedNotes'] as bool? ?? notesOnBoard,
      retriedAfterLoss: json['retriedAfterLoss'] as bool? ?? false,
    );
  }

  static int _pocketSwatchOffsetFromJson(Object? raw) {
    final value = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
    return value == 3 ? 3 : 0;
  }

  static List<String>? _stringList(Object? raw) {
    if (raw is! List) return null;
    final keys = [for (final e in raw) e.toString()];
    if (keys.length != 9) return null;
    return keys;
  }

  static Set<int> _notesFromMap(Map<String, dynamic> map) {
    final rawNotes = map['n'];
    if (rawNotes is List) {
      return {
        for (final n in rawNotes)
          if (n is int && n >= 1 && n <= 9) n,
      };
    }

    // Legacy quadrant / half-note formats → collect any non-zero color values.
    final legacy = <int>{
      if (map['tl'] is int && (map['tl'] as int) > 0) map['tl'] as int,
      if (map['tr'] is int && (map['tr'] as int) > 0) map['tr'] as int,
      if (map['br'] is int && (map['br'] as int) > 0) map['br'] as int,
      if (map['bl'] is int && (map['bl'] as int) > 0) map['bl'] as int,
      if (map['t'] is int && (map['t'] as int) > 0) map['t'] as int,
      if (map['b'] is int && (map['b'] as int) > 0) map['b'] as int,
    };
    return {
      for (final n in legacy)
        if (n >= 1 && n <= 9) n,
    };
  }
}

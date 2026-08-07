import 'cell.dart';
import 'difficulty.dart';
import '../sudoku/sudoku_board.dart';

class PausedGame {
  final Difficulty difficulty;
  final Duration elapsed;
  final int mistakes;
  final List<int> solution;
  final List<Cell> cells;

  const PausedGame({
    required this.difficulty,
    required this.elapsed,
    required this.mistakes,
    required this.solution,
    required this.cells,
  });

  Map<String, Object?> toJson() {
    return {
      'difficulty': difficulty.storageKey,
      'elapsedMs': elapsed.inMilliseconds,
      'mistakes': mistakes,
      'solution': solution,
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

    if (cells.length != SudokuBoard.size * SudokuBoard.size ||
        solutionRaw.length != SudokuBoard.size * SudokuBoard.size) {
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

    return PausedGame(
      difficulty: Difficulty.fromStorageKey(json['difficulty'] as String?),
      elapsed: Duration(milliseconds: json['elapsedMs'] as int? ?? 0),
      mistakes: json['mistakes'] as int? ?? 0,
      solution: solutionRaw,
      cells: cells,
    );
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

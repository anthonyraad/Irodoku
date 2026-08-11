import 'dart:math';

import 'sudoku_board.dart';

class SudokuSolver {
  /// Fills [board] in-place using backtracking.
  /// When [random] is provided, candidate values are shuffled for variety.
  bool solve(SudokuBoard board, {Random? random}) {
    final empty = _findEmpty(board);
    if (empty == null) return true;

    final (row, col) = empty;
    final candidates = List<int>.generate(9, (i) => i + 1);
    if (random != null) {
      candidates.shuffle(random);
    }

    for (final value in candidates) {
      if (board.isValidPlacement(row, col, value)) {
        board.set(row, col, value);
        if (solve(board, random: random)) return true;
        board.set(row, col, 0);
      }
    }
    return false;
  }

  /// Counts solutions up to [limit] (typically 2 for uniqueness checks).
  ///
  /// Works on a copy so [board] is never mutated.
  int countSolutions(SudokuBoard board, {int limit = 2}) {
    return _countSolutions(board.copy(), limit);
  }

  /// True when [board] has exactly one solution.
  ///
  /// Mutates [board] only transiently; cells are restored before return.
  bool hasUniqueSolution(SudokuBoard board) {
    return _countSolutions(board, 2) == 1;
  }

  int _countSolutions(SudokuBoard board, int limit) {
    final empty = _findEmptyMrv(board);
    if (empty == null) return 1;

    final (row, col) = empty;
    var count = 0;
    for (var value = 1; value <= 9; value++) {
      if (board.isValidPlacement(row, col, value)) {
        board.set(row, col, value);
        count += _countSolutions(board, limit);
        board.set(row, col, 0);
        if (count >= limit) return count;
      }
    }
    return count;
  }

  (int, int)? _findEmpty(SudokuBoard board) {
    for (var r = 0; r < SudokuBoard.size; r++) {
      for (var c = 0; c < SudokuBoard.size; c++) {
        if (board.get(r, c) == 0) return (r, c);
      }
    }
    return null;
  }

  /// Most-constrained empty cell (fewest valid candidates). Speeds uniqueness.
  (int, int)? _findEmptyMrv(SudokuBoard board) {
    (int, int)? best;
    var bestCount = 10;

    for (var r = 0; r < SudokuBoard.size; r++) {
      for (var c = 0; c < SudokuBoard.size; c++) {
        if (board.get(r, c) != 0) continue;

        var candidates = 0;
        for (var value = 1; value <= 9; value++) {
          if (board.isValidPlacement(r, c, value)) candidates++;
        }
        if (candidates == 0) return (r, c);
        if (candidates < bestCount) {
          bestCount = candidates;
          best = (r, c);
          if (bestCount == 1) return best;
        }
      }
    }
    return best;
  }
}

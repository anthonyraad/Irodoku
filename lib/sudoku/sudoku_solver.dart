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
  int countSolutions(SudokuBoard board, {int limit = 2}) {
    final working = board.copy();
    return _countSolutions(working, limit);
  }

  bool hasUniqueSolution(SudokuBoard board) {
    return countSolutions(board, limit: 2) == 1;
  }

  int _countSolutions(SudokuBoard board, int limit) {
    final empty = _findEmpty(board);
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
}

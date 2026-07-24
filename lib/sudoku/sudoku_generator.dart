import 'dart:math';

import '../models/difficulty.dart';
import 'sudoku_board.dart';
import 'sudoku_solver.dart';

class GeneratedPuzzle {
  /// Puzzle with 0 for empty cells.
  final SudokuBoard puzzle;

  /// Complete valid solution.
  final SudokuBoard solution;

  const GeneratedPuzzle({
    required this.puzzle,
    required this.solution,
  });
}

class SudokuGenerator {
  final SudokuSolver _solver;
  final Random _random;

  SudokuGenerator({
    SudokuSolver? solver,
    Random? random,
  })  : _solver = solver ?? SudokuSolver(),
        _random = random ?? Random();

  /// Generates a fresh, uniquely solvable puzzle for [difficulty].
  GeneratedPuzzle generate(Difficulty difficulty) {
    final solution = _generateFullSolution();
    final puzzle = _carvePuzzle(solution, difficulty);
    return GeneratedPuzzle(puzzle: puzzle, solution: solution);
  }

  SudokuBoard _generateFullSolution() {
    final board = SudokuBoard.empty();
    final filled = _solver.solve(board, random: _random);
    if (!filled || !board.isValidSolution()) {
      throw StateError('Failed to generate a valid Sudoku solution');
    }
    return board;
  }

  SudokuBoard _carvePuzzle(SudokuBoard solution, Difficulty difficulty) {
    final puzzle = solution.copy();
    final (minGiven, maxGiven) = difficulty.givenCellRange;
    final targetGiven =
        minGiven + _random.nextInt(maxGiven - minGiven + 1);
    final targetRemovals = SudokuBoard.size * SudokuBoard.size - targetGiven;

    final positions = <(int, int)>[
      for (var r = 0; r < SudokuBoard.size; r++)
        for (var c = 0; c < SudokuBoard.size; c++) (r, c),
    ]..shuffle(_random);

    var removed = 0;
    for (final (row, col) in positions) {
      if (removed >= targetRemovals) break;

      final backup = puzzle.get(row, col);
      puzzle.set(row, col, 0);

      if (_solver.hasUniqueSolution(puzzle)) {
        removed++;
      } else {
        puzzle.set(row, col, backup);
      }
    }

    // If uniqueness constraints left too many givens, accept the unique board
    // (still a valid uniquely solvable puzzle, just slightly easier).
    return puzzle;
  }
}

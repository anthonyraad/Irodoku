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

  /// Solved grids to try before giving up.
  static const int _maxSolutions = 40;

  /// Dig-order shuffles per solved grid (cheap vs. regenerating a solution).
  static const int _digOrdersPerSolution = 8;

  /// Generates a fresh, uniquely solvable puzzle for [difficulty].
  GeneratedPuzzle generate(Difficulty difficulty) {
    if (difficulty == Difficulty.master) {
      return _generateMaster();
    }
    return _generateForBand(difficulty);
  }

  /// Master: progressive dig into 17–22 givens, then evaluate the threshold.
  ///
  /// 1. Generate a complete solved grid.
  /// 2. Progressively remove clues, keeping a unique solution.
  /// 3. Stop once givens are at most 22 (band ceiling).
  /// 4. Optionally deepen toward a random in-band target for variety.
  /// 5. Accept if the Master threshold (17–22 givens + unique) is met;
  ///    otherwise discard that carving and try another dig order / grid.
  ///
  /// Does not hunt for exact 17-clue puzzles — any unique 17–22 board passes.
  GeneratedPuzzle _generateMaster() {
    final (minGiven, maxGiven) = Difficulty.master.givenCellRange;

    for (var s = 0; s < _maxSolutions; s++) {
      final solution = _generateFullSolution();

      for (var d = 0; d < _digOrdersPerSolution; d++) {
        final puzzle = solution.copy();
        _progressiveRemove(puzzle, stopAtOrBelow: maxGiven);

        if (_countGivens(puzzle) > maxGiven) {
          // Uniqueness floor above the band — discard this carving.
          continue;
        }

        // In band at ≤22. Bounded deepen for variety (still stays ≤22).
        final deepenTarget =
            minGiven + _random.nextInt(maxGiven - minGiven + 1);
        if (_countGivens(puzzle) > deepenTarget) {
          _progressiveRemove(
            puzzle,
            stopAtOrBelow: deepenTarget,
            failBudget: 16,
          );
        }

        if (_meetsDifficultyThreshold(puzzle, Difficulty.master)) {
          return GeneratedPuzzle(puzzle: puzzle, solution: solution);
        }
      }
    }

    throw StateError(
      'Failed to generate a Master puzzle with $minGiven–$maxGiven givens',
    );
  }

  /// Non-Master: progressive dig into the difficulty's given-cell band.
  GeneratedPuzzle _generateForBand(Difficulty difficulty) {
    final (minGiven, maxGiven) = difficulty.givenCellRange;

    for (var s = 0; s < _maxSolutions; s++) {
      final solution = _generateFullSolution();
      for (var d = 0; d < _digOrdersPerSolution; d++) {
        final puzzle = solution.copy();
        _progressiveRemove(puzzle, stopAtOrBelow: maxGiven);

        if (_countGivens(puzzle) > maxGiven) continue;

        final deepenTarget =
            minGiven + _random.nextInt(maxGiven - minGiven + 1);
        if (_countGivens(puzzle) > deepenTarget) {
          _progressiveRemove(
            puzzle,
            stopAtOrBelow: deepenTarget,
            failBudget: 16,
          );
        }

        if (_meetsDifficultyThreshold(puzzle, difficulty)) {
          return GeneratedPuzzle(puzzle: puzzle, solution: solution);
        }
      }
    }

    throw StateError(
      'Failed to generate a ${difficulty.label} puzzle '
      'with $minGiven–$maxGiven givens',
    );
  }

  SudokuBoard _generateFullSolution({bool pocket = false}) {
    final board = SudokuBoard.empty(pocket: pocket);
    final filled = _solver.solve(board, random: _random);
    if (!filled || !board.isValidSolution()) {
      throw StateError('Failed to generate a valid Sudoku solution');
    }
    return board;
  }

  /// Removes clues in random order while the puzzle stays uniquely solvable,
  /// stopping once given count is at most [stopAtOrBelow].
  ///
  /// When [failBudget] is set, stops after that many rejected removals so
  /// optional deepening near the uniqueness floor cannot run unbounded.
  void _progressiveRemove(
    SudokuBoard puzzle, {
    required int stopAtOrBelow,
    int? failBudget,
  }) {
    final positions = <(int, int)>[
      for (var r = 0; r < puzzle.n; r++)
        for (var c = 0; c < puzzle.n; c++)
          if (puzzle.get(r, c) != 0) (r, c),
    ]..shuffle(_random);

    var givens = _countGivens(puzzle);
    var fails = 0;
    for (final (row, col) in positions) {
      if (givens <= stopAtOrBelow) return;
      if (failBudget != null && fails >= failBudget) return;

      final backup = puzzle.get(row, col);
      puzzle.set(row, col, 0);
      if (_solver.hasUniqueSolution(puzzle)) {
        givens--;
      } else {
        puzzle.set(row, col, backup);
        fails++;
      }
    }
  }

  /// Existing difficulty gate: given-cell band + uniqueness.
  bool _meetsDifficultyThreshold(SudokuBoard puzzle, Difficulty difficulty) {
    final (minGiven, maxGiven) = difficulty.givenCellRange;
    final givenCount = _countGivens(puzzle);
    if (givenCount < minGiven || givenCount > maxGiven) return false;
    return _solver.hasUniqueSolution(puzzle);
  }

  int _countGivens(SudokuBoard puzzle) {
    var count = 0;
    for (var r = 0; r < puzzle.n; r++) {
      for (var c = 0; c < puzzle.n; c++) {
        if (puzzle.get(r, c) != 0) count++;
      }
    }
    return count;
  }

  /// Unique 6×6 mini Sudoku (2×3 boxes) with 11–13 givens.
  GeneratedPuzzle generatePocket() {
    const minGiven = 11;
    const maxGiven = 13;
    for (var s = 0; s < _maxSolutions; s++) {
      final solution = _generateFullSolution(pocket: true);
      for (var d = 0; d < _digOrdersPerSolution; d++) {
        final puzzle = solution.copy();
        _progressiveRemove(puzzle, stopAtOrBelow: maxGiven);
        if (_countGivens(puzzle) > maxGiven) continue;

        final deepenTarget = minGiven + _random.nextInt(maxGiven - minGiven + 1);
        if (_countGivens(puzzle) > deepenTarget) {
          _progressiveRemove(
            puzzle,
            stopAtOrBelow: deepenTarget,
            failBudget: 16,
          );
        }

        final givenCount = _countGivens(puzzle);
        if (givenCount >= minGiven &&
            givenCount <= maxGiven &&
            _solver.hasUniqueSolution(puzzle)) {
          return GeneratedPuzzle(puzzle: puzzle, solution: solution);
        }
      }
    }
    throw StateError(
      'Failed to generate a Pocket puzzle with $minGiven–$maxGiven givens',
    );
  }
}

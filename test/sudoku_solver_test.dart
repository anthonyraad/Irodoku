import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:irodoku/models/difficulty.dart';
import 'package:irodoku/sudoku/sudoku_board.dart';
import 'package:irodoku/sudoku/sudoku_generator.dart';
import 'package:irodoku/sudoku/sudoku_solver.dart';

void main() {
  group('SudokuSolver', () {
    test('solves an empty board into a valid complete solution', () {
      final solver = SudokuSolver();
      final board = SudokuBoard.empty();

      final solved = solver.solve(board, random: Random(42));

      expect(solved, isTrue);
      expect(board.isComplete(), isTrue);
      expect(board.isValidSolution(), isTrue);
    });

    test('randomized fills produce different solutions', () {
      final solver = SudokuSolver();
      final a = SudokuBoard.empty();
      final b = SudokuBoard.empty();

      solver.solve(a, random: Random(1));
      solver.solve(b, random: Random(2));

      expect(a.toFlat(), isNot(equals(b.toFlat())));
    });

    test('countSolutions reports a unique solution for a carved puzzle', () {
      final generator = SudokuGenerator(random: Random(7));
      final puzzle = generator.generate(Difficulty.easy);
      final solver = SudokuSolver();

      expect(solver.countSolutions(puzzle.puzzle, limit: 2), 1);
      expect(solver.hasUniqueSolution(puzzle.puzzle), isTrue);
    });
  });

  group('SudokuGenerator', () {
    test('generates a valid solution and uniquely solvable puzzle', () {
      final generator = SudokuGenerator(random: Random(99));
      final result = generator.generate(Difficulty.medium);

      expect(result.solution.isValidSolution(), isTrue);
      expect(result.puzzle.isValidSolution(), isFalse);
      expect(SudokuSolver().hasUniqueSolution(result.puzzle), isTrue);

      // Puzzle cells that are filled must match the solution.
      for (var r = 0; r < SudokuBoard.size; r++) {
        for (var c = 0; c < SudokuBoard.size; c++) {
          final given = result.puzzle.get(r, c);
          if (given != 0) {
            expect(given, result.solution.get(r, c));
          }
        }
      }
    });

    test('given cell counts fall within difficulty ranges when possible', () {
      final generator = SudokuGenerator(random: Random(123));

      for (final difficulty in Difficulty.values) {
        final result = generator.generate(difficulty);
        final givenCount = result.puzzle
            .toFlat()
            .where((v) => v != 0)
            .length;
        final (minGiven, maxGiven) = difficulty.givenCellRange;

        expect(givenCount, greaterThanOrEqualTo(minGiven));
        expect(givenCount, lessThanOrEqualTo(maxGiven));
        expect(SudokuSolver().hasUniqueSolution(result.puzzle), isTrue);
      }
    });

    test('board conflictingCells detects row/column/box clashes', () {
      final board = SudokuBoard.empty();
      board.set(0, 0, 1);
      board.set(0, 1, 1);

      final conflicts = board.conflictingCells();
      expect(conflicts.contains((0, 0)), isTrue);
      expect(conflicts.contains((0, 1)), isTrue);
    });
  });
}

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:irodoku/models/difficulty.dart';
import 'package:irodoku/sudoku/sudoku_generator.dart';
import 'package:irodoku/sudoku/sudoku_solver.dart';

void main() {
  test('Master progressive dig stays in 17–22 and stays unique', () {
    final solver = SudokuSolver();
    final (minGiven, maxGiven) = Difficulty.master.givenCellRange;
    final sw = Stopwatch()..start();

    for (var seed = 0; seed < 20; seed++) {
      final result =
          SudokuGenerator(random: Random(seed)).generate(Difficulty.master);
      final givenCount = result.puzzle.toFlat().where((v) => v != 0).length;

      expect(givenCount, inInclusiveRange(minGiven, maxGiven),
          reason: 'seed=$seed');
      expect(solver.hasUniqueSolution(result.puzzle), isTrue);
      expect(result.solution.isValidSolution(), isTrue);

      for (var r = 0; r < 9; r++) {
        for (var c = 0; c < 9; c++) {
          final given = result.puzzle.get(r, c);
          if (given != 0) {
            expect(given, result.solution.get(r, c));
          }
        }
      }
    }

    // Progressive dig-to-band should keep Master New Game snappy.
    expect(sw.elapsedMilliseconds, lessThan(20000));
  });

  test('Expert band still holds with progressive dig', () {
    final (minGiven, maxGiven) = Difficulty.expert.givenCellRange;
    for (var seed = 0; seed < 10; seed++) {
      final result =
          SudokuGenerator(random: Random(seed)).generate(Difficulty.expert);
      final givenCount = result.puzzle.toFlat().where((v) => v != 0).length;
      expect(givenCount, inInclusiveRange(minGiven, maxGiven));
    }
  });
}

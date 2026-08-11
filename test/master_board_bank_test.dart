import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:irodoku/models/difficulty.dart';
import 'package:irodoku/sudoku/master_board_codec.dart';
import 'package:irodoku/sudoku/sudoku_generator.dart';

void main() {
  test('encode/decode round-trips Master boards', () {
    final boards = <(List<int>, List<int>)>[];
    for (final seed in [1, 2, 3]) {
      final g =
          SudokuGenerator(random: Random(seed)).generate(Difficulty.master);
      boards.add((g.puzzle.toFlat(), g.solution.toFlat()));
      expect(
        MasterBoardCodec.validateRecord(boards.last.$1, boards.last.$2),
        isTrue,
      );
    }

    final bytes = MasterBoardCodec.encode(boards);
    final bank = MasterBoardCodec.decode(Uint8List.fromList(bytes));
    expect(bank.count, 3);

    for (var i = 0; i < 3; i++) {
      final got = bank.boardAt(i);
      expect(got[0], boards[i].$1);
      expect(got[1], boards[i].$2);
    }

    final pick = bank.takeRandom();
    expect(pick[0].length, 81);
    expect(pick[1].length, 81);
    expect(MasterBoardCodec.validateRecord(pick[0], pick[1]), isTrue);
  });
}

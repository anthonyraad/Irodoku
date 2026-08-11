import 'dart:io';
import 'dart:typed_data';

import 'package:irodoku/sudoku/master_board_codec.dart';

void main() {
  final bytes = File('assets/sudoku/master_boards.bin').readAsBytesSync();
  final bank = MasterBoardCodec.decode(Uint8List.fromList(bytes));
  stdout.writeln('count=${bank.count} bytes=${bytes.length}');
  for (final i in [0, 100, 5000, bank.count - 1]) {
    final boards = bank.boardAt(i);
    final ok = MasterBoardCodec.validateRecord(boards[0], boards[1]);
    final givens = boards[0].where((v) => v != 0).length;
    stdout.writeln('board $i givens=$givens valid=$ok');
    if (!ok) exitCode = 1;
  }
}

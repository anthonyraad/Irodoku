import 'dart:math';

import 'package:flutter/services.dart';

import 'master_board_codec.dart';

/// Flutter asset loader for [MasterBoardCodec] precomputed Master puzzles.
class MasterBoardBank {
  static const assetPath = 'assets/sudoku/master_boards.bin';

  static MasterBoardCodec? _codec;

  static MasterBoardCodec? get instance => _codec;

  static bool get isLoaded => _codec != null && _codec!.count > 0;

  static int get count => _codec?.count ?? 0;

  /// Loads the shipped bank once. Safe to call repeatedly.
  static Future<MasterBoardCodec> load({Random? random}) async {
    if (_codec != null) return _codec!;
    final data = await rootBundle.load(assetPath);
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    _codec = MasterBoardCodec.decode(bytes, random: random);
    return _codec!;
  }

  /// Test helper to install a codec without loading from assets.
  static void debugInstall(MasterBoardCodec codec) {
    _codec = codec;
  }

  static void debugClear() {
    _codec = null;
  }

  static List<List<int>> takeRandom() {
    final codec = _codec;
    if (codec == null) {
      throw StateError('Master board bank is not loaded');
    }
    return codec.takeRandom();
  }

  // Re-export codec helpers for callers/tests.
  static MasterBoardCodec decode(Uint8List bytes, {Random? random}) =>
      MasterBoardCodec.decode(bytes, random: random);

  static Uint8List encode(List<(List<int>, List<int>)> boards) =>
      MasterBoardCodec.encode(boards);

  static bool validateRecord(List<int> puzzle, List<int> solution) =>
      MasterBoardCodec.validateRecord(puzzle, solution);
}

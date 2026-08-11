import 'dart:math';
import 'dart:typed_data';

import '../models/difficulty.dart';
import 'sudoku_board.dart';
import 'sudoku_solver.dart';

/// Binary codec for precomputed Master puzzles (no Flutter dependency).
///
/// File layout:
/// - magic `IMB1` (4 bytes)
/// - little-endian uint32 count
/// - [count] records of 162 bytes: 81 puzzle + 81 solution (cell values 0–9)
class MasterBoardCodec {
  static const magic = 'IMB1';
  static const cells = SudokuBoard.size * SudokuBoard.size; // 81
  static const recordBytes = cells * 2; // puzzle + solution
  static const headerBytes = 8; // magic + count

  final Uint8List bytes;
  final int count;
  final Random _random;
  final List<int> _recent = [];

  /// How many recent picks to avoid immediately repeating.
  static const recentWindow = 64;

  MasterBoardCodec._(this.bytes, this.count, this._random);

  static MasterBoardCodec decode(Uint8List bytes, {Random? random}) {
    if (bytes.length < headerBytes) {
      throw FormatException('Master board bank too short');
    }
    final magicBytes = String.fromCharCodes(bytes.sublist(0, 4));
    if (magicBytes != magic) {
      throw FormatException('Bad master board bank magic: $magicBytes');
    }
    final count =
        ByteData.sublistView(bytes, 4, 8).getUint32(0, Endian.little);
    final expected = headerBytes + count * recordBytes;
    if (bytes.length < expected) {
      throw FormatException(
        'Master board bank truncated: have ${bytes.length}, need $expected',
      );
    }
    if (count == 0) {
      throw FormatException('Master board bank is empty');
    }
    return MasterBoardCodec._(bytes, count, random ?? Random());
  }

  static Uint8List encode(List<(List<int>, List<int>)> boards) {
    final out = BytesBuilder(copy: false);
    out.add(magic.codeUnits);
    final header = ByteData(4)..setUint32(0, boards.length, Endian.little);
    out.add(header.buffer.asUint8List());
    for (final (puzzle, solution) in boards) {
      if (puzzle.length != cells || solution.length != cells) {
        throw ArgumentError('Each board must be $cells cells');
      }
      out.add(Uint8List.fromList(puzzle));
      out.add(Uint8List.fromList(solution));
    }
    return out.toBytes();
  }

  /// Returns `[puzzleFlat, solutionFlat]` as length-81 int lists.
  List<List<int>> takeRandom() {
    if (count <= 0) {
      throw StateError('Master board bank is empty');
    }

    var index = _random.nextInt(count);
    if (_recent.isNotEmpty && count > recentWindow) {
      var guard = 0;
      while (_recent.contains(index) && guard < 12) {
        index = _random.nextInt(count);
        guard++;
      }
    }
    _recent.add(index);
    if (_recent.length > recentWindow) {
      _recent.removeAt(0);
    }

    return boardAt(index);
  }

  List<List<int>> boardAt(int index) {
    if (index < 0 || index >= count) {
      throw RangeError.index(index, this, 'index', null, count);
    }
    final offset = headerBytes + index * recordBytes;
    final puzzle = List<int>.generate(
      cells,
      (i) => bytes[offset + i],
      growable: false,
    );
    final solution = List<int>.generate(
      cells,
      (i) => bytes[offset + cells + i],
      growable: false,
    );
    return [puzzle, solution];
  }

  static bool validateRecord(List<int> puzzle, List<int> solution) {
    final (minGiven, maxGiven) = Difficulty.master.givenCellRange;
    var givens = 0;
    for (var i = 0; i < cells; i++) {
      final p = puzzle[i];
      final s = solution[i];
      if (p < 0 || p > 9 || s < 1 || s > 9) return false;
      if (p != 0) {
        if (p != s) return false;
        givens++;
      }
    }
    if (givens < minGiven || givens > maxGiven) return false;
    final board = SudokuBoard.fromFlat(puzzle);
    final sol = SudokuBoard.fromFlat(solution);
    if (!sol.isValidSolution()) return false;
    return SudokuSolver().hasUniqueSolution(board);
  }
}

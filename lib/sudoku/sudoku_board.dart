/// Sudoku grid of values 0–[n] (0 = empty).
///
/// Classic is 9×9 with 3×3 boxes. Pocket is 6×6 with 2×3 boxes.
class SudokuBoard {
  static const int size = 9;
  static const int boxSize = 3;
  static const int pocketSize = 6;
  static const int pocketBoxWidth = 3;
  static const int pocketBoxHeight = 2;

  final int n;
  final int boxW;
  final int boxH;
  final List<List<int>> grid;

  bool get isPocket => n == pocketSize;

  SudokuBoard(
    List<List<int>> grid, {
    int? n,
    int? boxWidth,
    int? boxHeight,
  })  : n = n ?? grid.length,
        boxW = boxWidth ??
            (grid.length == pocketSize ? pocketBoxWidth : boxSize),
        boxH = boxHeight ??
            (grid.length == pocketSize ? pocketBoxHeight : boxSize),
        grid = List.generate(
          n ?? grid.length,
          (r) => List<int>.from(grid[r]),
        );

  factory SudokuBoard.empty({bool pocket = false}) {
    final n = pocket ? pocketSize : size;
    return SudokuBoard(
      List.generate(n, (_) => List.filled(n, 0)),
      n: n,
      boxWidth: pocket ? pocketBoxWidth : boxSize,
      boxHeight: pocket ? pocketBoxHeight : boxSize,
    );
  }

  factory SudokuBoard.fromFlat(List<int> values, {bool pocket = false}) {
    final n = pocket ? pocketSize : size;
    assert(values.length == n * n);
    final grid = List.generate(
      n,
      (r) => values.sublist(r * n, (r + 1) * n),
    );
    return SudokuBoard(
      grid,
      n: n,
      boxWidth: pocket ? pocketBoxWidth : boxSize,
      boxHeight: pocket ? pocketBoxHeight : boxSize,
    );
  }

  int get(int row, int col) => grid[row][col];

  void set(int row, int col, int value) {
    grid[row][col] = value;
  }

  SudokuBoard copy() => SudokuBoard(
        grid,
        n: n,
        boxWidth: boxW,
        boxHeight: boxH,
      );

  List<int> toFlat() => grid.expand((row) => row).toList();

  bool isComplete() {
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (grid[r][c] == 0) return false;
      }
    }
    return true;
  }

  /// Returns true if [value] can be placed at [row],[col] without conflicts.
  bool isValidPlacement(int row, int col, int value) {
    if (value < 1 || value > n) return false;

    for (var c = 0; c < n; c++) {
      if (c != col && grid[row][c] == value) return false;
    }
    for (var r = 0; r < n; r++) {
      if (r != row && grid[r][col] == value) return false;
    }

    final boxRow = (row ~/ boxH) * boxH;
    final boxCol = (col ~/ boxW) * boxW;
    for (var r = boxRow; r < boxRow + boxH; r++) {
      for (var c = boxCol; c < boxCol + boxW; c++) {
        if ((r != row || c != col) && grid[r][c] == value) return false;
      }
    }
    return true;
  }

  /// True when the board is fully filled and every placement is valid.
  bool isValidSolution() {
    if (!isComplete()) return false;
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        final v = grid[r][c];
        if (!isValidPlacement(r, c, v)) return false;
      }
    }
    return true;
  }

  int get boxCols => n ~/ boxW;
  int get boxRows => n ~/ boxH;

  /// Keys for fully filled, conflict-free units: `r0`…, `c0`…, `b0`….
  Set<String> completedUnitKeys() {
    final keys = <String>{};

    for (var r = 0; r < n; r++) {
      if (_isCompleteUnit([for (var c = 0; c < n; c++) (r, c)])) {
        keys.add('r$r');
      }
    }
    for (var c = 0; c < n; c++) {
      if (_isCompleteUnit([for (var r = 0; r < n; r++) (r, c)])) {
        keys.add('c$c');
      }
    }
    for (var br = 0; br < boxRows; br++) {
      for (var bc = 0; bc < boxCols; bc++) {
        final positions = <(int, int)>[
          for (var r = br * boxH; r < br * boxH + boxH; r++)
            for (var c = bc * boxW; c < bc * boxW + boxW; c++) (r, c),
        ];
        if (_isCompleteUnit(positions)) {
          keys.add('b${br * boxCols + bc}');
        }
      }
    }
    return keys;
  }

  /// Positions in a unit key, in wave order for celebration stagger.
  static List<(int, int)> positionsForUnitKey(
    String key, {
    int n = size,
    int boxW = boxSize,
    int boxH = boxSize,
  }) {
    final type = key[0];
    final index = int.parse(key.substring(1));
    final boxCols = n ~/ boxW;
    switch (type) {
      case 'r':
        return [for (var c = 0; c < n; c++) (index, c)];
      case 'c':
        return [for (var r = 0; r < n; r++) (r, index)];
      case 'b':
        final br = index ~/ boxCols;
        final bc = index % boxCols;
        return [
          for (var r = br * boxH; r < br * boxH + boxH; r++)
            for (var c = bc * boxW; c < bc * boxW + boxW; c++) (r, c),
        ];
      default:
        return const [];
    }
  }

  List<(int, int)> positionsForUnit(String key) => positionsForUnitKey(
        key,
        n: n,
        boxW: boxW,
        boxH: boxH,
      );

  bool _isCompleteUnit(List<(int, int)> positions) {
    final seen = <int>{};
    for (final (r, c) in positions) {
      final v = grid[r][c];
      if (v < 1 || v > n || !seen.add(v)) return false;
    }
    return seen.length == n;
  }

  /// Positions (row, col) that conflict with Sudoku rules for non-empty cells.
  Set<(int, int)> conflictingCells() {
    final conflicts = <(int, int)>{};

    void markDuplicates(List<(int, int)> positions) {
      final seen = <int, List<(int, int)>>{};
      for (final pos in positions) {
        final v = grid[pos.$1][pos.$2];
        if (v == 0) continue;
        seen.putIfAbsent(v, () => []).add(pos);
      }
      for (final group in seen.values) {
        if (group.length > 1) {
          conflicts.addAll(group);
        }
      }
    }

    for (var r = 0; r < n; r++) {
      markDuplicates(List.generate(n, (c) => (r, c)));
    }
    for (var c = 0; c < n; c++) {
      markDuplicates(List.generate(n, (r) => (r, c)));
    }
    for (var br = 0; br < boxRows; br++) {
      for (var bc = 0; bc < boxCols; bc++) {
        final positions = <(int, int)>[];
        for (var r = br * boxH; r < br * boxH + boxH; r++) {
          for (var c = bc * boxW; c < bc * boxW + boxW; c++) {
            positions.add((r, c));
          }
        }
        markDuplicates(positions);
      }
    }

    return conflicts;
  }
}

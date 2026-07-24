/// Immutable 9×9 grid of values 0–9 (0 = empty).
class SudokuBoard {
  static const int size = 9;
  static const int boxSize = 3;

  final List<List<int>> grid;

  SudokuBoard(List<List<int>> grid)
      : grid = List.generate(
          size,
          (r) => List<int>.from(grid[r]),
        );

  factory SudokuBoard.empty() {
    return SudokuBoard(
      List.generate(size, (_) => List.filled(size, 0)),
    );
  }

  factory SudokuBoard.fromFlat(List<int> values) {
    assert(values.length == size * size);
    final grid = List.generate(
      size,
      (r) => values.sublist(r * size, (r + 1) * size),
    );
    return SudokuBoard(grid);
  }

  int get(int row, int col) => grid[row][col];

  void set(int row, int col, int value) {
    grid[row][col] = value;
  }

  SudokuBoard copy() => SudokuBoard(grid);

  List<int> toFlat() => grid.expand((row) => row).toList();

  bool isComplete() {
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        if (grid[r][c] == 0) return false;
      }
    }
    return true;
  }

  /// Returns true if [value] can be placed at [row],[col] without conflicts.
  bool isValidPlacement(int row, int col, int value) {
    if (value < 1 || value > 9) return false;

    for (var c = 0; c < size; c++) {
      if (c != col && grid[row][c] == value) return false;
    }
    for (var r = 0; r < size; r++) {
      if (r != row && grid[r][col] == value) return false;
    }

    final boxRow = (row ~/ boxSize) * boxSize;
    final boxCol = (col ~/ boxSize) * boxSize;
    for (var r = boxRow; r < boxRow + boxSize; r++) {
      for (var c = boxCol; c < boxCol + boxSize; c++) {
        if ((r != row || c != col) && grid[r][c] == value) return false;
      }
    }
    return true;
  }

  /// True when the board is fully filled and every placement is valid.
  bool isValidSolution() {
    if (!isComplete()) return false;
    for (var r = 0; r < size; r++) {
      for (var c = 0; c < size; c++) {
        final v = grid[r][c];
        if (!isValidPlacement(r, c, v)) return false;
      }
    }
    return true;
  }

  /// Keys for fully filled, conflict-free units: `r0`…`r8`, `c0`…`c8`, `b0`…`b8`.
  Set<String> completedUnitKeys() {
    final keys = <String>{};

    for (var r = 0; r < size; r++) {
      if (_isCompleteUnit([for (var c = 0; c < size; c++) (r, c)])) {
        keys.add('r$r');
      }
    }
    for (var c = 0; c < size; c++) {
      if (_isCompleteUnit([for (var r = 0; r < size; r++) (r, c)])) {
        keys.add('c$c');
      }
    }
    for (var br = 0; br < boxSize; br++) {
      for (var bc = 0; bc < boxSize; bc++) {
        final positions = <(int, int)>[
          for (var r = br * boxSize; r < br * boxSize + boxSize; r++)
            for (var c = bc * boxSize; c < bc * boxSize + boxSize; c++) (r, c),
        ];
        if (_isCompleteUnit(positions)) {
          keys.add('b${br * boxSize + bc}');
        }
      }
    }
    return keys;
  }

  /// Positions in a unit key, in wave order for celebration stagger.
  static List<(int, int)> positionsForUnitKey(String key) {
    final type = key[0];
    final index = int.parse(key.substring(1));
    switch (type) {
      case 'r':
        return [for (var c = 0; c < size; c++) (index, c)];
      case 'c':
        return [for (var r = 0; r < size; r++) (r, index)];
      case 'b':
        final br = index ~/ boxSize;
        final bc = index % boxSize;
        return [
          for (var r = br * boxSize; r < br * boxSize + boxSize; r++)
            for (var c = bc * boxSize; c < bc * boxSize + boxSize; c++) (r, c),
        ];
      default:
        return const [];
    }
  }

  bool _isCompleteUnit(List<(int, int)> positions) {
    final seen = <int>{};
    for (final (r, c) in positions) {
      final v = grid[r][c];
      if (v < 1 || v > 9 || !seen.add(v)) return false;
    }
    return seen.length == size;
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

    for (var r = 0; r < size; r++) {
      markDuplicates(List.generate(size, (c) => (r, c)));
    }
    for (var c = 0; c < size; c++) {
      markDuplicates(List.generate(size, (r) => (r, c)));
    }
    for (var br = 0; br < boxSize; br++) {
      for (var bc = 0; bc < boxSize; bc++) {
        final positions = <(int, int)>[];
        for (var r = br * boxSize; r < br * boxSize + boxSize; r++) {
          for (var c = bc * boxSize; c < bc * boxSize + boxSize; c++) {
            positions.add((r, c));
          }
        }
        markDuplicates(positions);
      }
    }

    return conflicts;
  }
}

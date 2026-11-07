import 'dart:math';

/// Marks a peer-note clear so cells can stagger dismiss as an outward wave.
class NoteClearWave {
  final int row;
  final int col;
  final int value;
  final int seq;

  /// Milliseconds between Chebyshev distance rings.
  static const int ringStaggerMs = 26;

  const NoteClearWave({
    required this.row,
    required this.col,
    required this.value,
    required this.seq,
  });

  /// Delay before a cell at ([r], [c]) starts shrinking cleared notes.
  Duration delayFor(int r, int c) {
    final dist = max((r - row).abs(), (c - col).abs());
    return Duration(milliseconds: dist * ringStaggerMs);
  }
}

/// Sketch notes blooming out from the center of a box.
class NoteAppearWave {
  final int value;
  final int seq;
  final int centerRow;
  final int centerCol;

  /// Milliseconds of delay per cell of distance from the box center.
  static const ringStaggerMs = 46;

  /// Matches the committed-fill radial bloom.
  static const bloomMs = 280;

  const NoteAppearWave({
    required this.value,
    required this.seq,
    required this.centerRow,
    required this.centerCol,
  });

  Duration delayFor(int r, int c) {
    final dist = sqrt(
      pow(r - centerRow, 2) + pow(c - centerCol, 2),
    );
    return Duration(milliseconds: (dist * ringStaggerMs).round());
  }

  /// Longest start delay inside a 3×3 box (a corner, √2 from the center).
  static const delayForMax = Duration(milliseconds: 66);
}

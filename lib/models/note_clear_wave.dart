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

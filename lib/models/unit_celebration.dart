/// Visual pulse when a row, column, or box is completed.
class UnitCelebration {
  final int id;

  /// Cell positions participating in this celebration, with wave stagger 0–8.
  final Map<(int, int), int> cellStagger;

  /// Original committed color values (1–9) for settle-back.
  final Map<(int, int), int> originalValues;

  const UnitCelebration({
    required this.id,
    required this.cellStagger,
    required this.originalValues,
  });

  bool contains(int row, int col) => cellStagger.containsKey((row, col));

  int staggerFor(int row, int col) => cellStagger[(row, col)] ?? 0;

  int originalValueFor(int row, int col) => originalValues[(row, col)] ?? 1;
}

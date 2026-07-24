enum Difficulty {
  easy,
  medium,
  hard,
  expert,
  master;

  static const int unlockWinsRequired = 5;

  String get label => switch (this) {
        Difficulty.easy => 'Easy',
        Difficulty.medium => 'Medium',
        Difficulty.hard => 'Hard',
        Difficulty.expert => 'Expert',
        Difficulty.master => 'Master',
      };

  /// Target count of given (pre-filled) cells for puzzle generation.
  (int min, int max) get givenCellRange => switch (this) {
        Difficulty.easy => (36, 40),
        Difficulty.medium => (32, 35),
        Difficulty.hard => (28, 31),
        Difficulty.expert => (22, 27),
        Difficulty.master => (17, 17),
      };

  /// Difficulty whose wins gate this level. Null means always unlocked.
  Difficulty? get unlockPrerequisite => switch (this) {
        Difficulty.easy => null,
        Difficulty.medium => Difficulty.easy,
        Difficulty.hard => Difficulty.medium,
        Difficulty.expert => Difficulty.hard,
        Difficulty.master => Difficulty.expert,
      };

  String get storageKey => name;

  static Difficulty fromStorageKey(String? key) {
    // Hard was previously stored as "expert".
    if (key == 'expert') return Difficulty.hard;
    return Difficulty.values.firstWhere(
      (d) => d.storageKey == key,
      orElse: () => Difficulty.easy,
    );
  }
}

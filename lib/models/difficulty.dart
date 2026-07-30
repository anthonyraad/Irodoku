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

  /// Prefs / paused-game key. Expert is not `"expert"` — that legacy string
  /// meant today's Hard before the rename.
  String get storageKey => switch (this) {
        Difficulty.easy => 'easy',
        Difficulty.medium => 'medium',
        Difficulty.hard => 'hard',
        Difficulty.expert => 'expert_v2',
        Difficulty.master => 'master',
      };

  static Difficulty fromStorageKey(String? key) {
    // Pre-rename Hard was stored as "expert".
    if (key == 'expert') return Difficulty.hard;
    return Difficulty.values.firstWhere(
      (d) => d.storageKey == key,
      orElse: () => Difficulty.easy,
    );
  }
}

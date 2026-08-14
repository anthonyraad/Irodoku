import 'difficulty.dart';
import 'game_palette.dart';

class GameStats {
  static const int iroenUnlockWinsRequired = 100;

  /// Medium wins required before Daily Challenge unlocks.
  static const int dailyChallengeUnlockMediumWins = 1;

  /// Easy wins required before Graffiti unlocks.
  static const int graffitiUnlockEasyWins = 1;

  final int currentStreak;
  final int bestStreak;
  final int gamesPlayed;
  final int gamesWon;
  final Map<Difficulty, Duration?> bestTimes;
  final Map<Difficulty, int> winsByDifficulty;
  final int chromaticGamesWon;
  final Map<Difficulty, Duration?> chromaticBestTimes;
  final Map<Difficulty, int> chromaticWinsByDifficulty;
  final Set<GamePalette> unlockedPalettes;
  final Map<GamePalette, int> bestStreakByPalette;
  final Map<GamePalette, int> currentStreakByPalette;
  final int graffitiWins;
  final int graffitiLosses;
  final int graffitiDraws;
  /// Lifetime prestige XP. Level is derived from this (not stored).
  final int totalXp;

  const GameStats({
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.gamesPlayed = 0,
    this.gamesWon = 0,
    this.bestTimes = const {},
    this.winsByDifficulty = const {},
    this.chromaticGamesWon = 0,
    this.chromaticBestTimes = const {},
    this.chromaticWinsByDifficulty = const {},
    this.unlockedPalettes = const {},
    this.bestStreakByPalette = const {},
    this.currentStreakByPalette = const {},
    this.graffitiWins = 0,
    this.graffitiLosses = 0,
    this.graffitiDraws = 0,
    this.totalXp = 0,
  });

  Duration? bestTimeFor(Difficulty difficulty) => bestTimes[difficulty];

  int winsFor(Difficulty difficulty) => winsByDifficulty[difficulty] ?? 0;

  Duration? chromaticBestTimeFor(Difficulty difficulty) =>
      chromaticBestTimes[difficulty];

  int chromaticWinsFor(Difficulty difficulty) =>
      chromaticWinsByDifficulty[difficulty] ?? 0;

  /// Display form e.g. `15-17 (2)`.
  String get graffitiRecordLabel =>
      '$graffitiWins-$graffitiLosses ($graffitiDraws)';

  int bestStreakForPalette(GamePalette palette) =>
      bestStreakByPalette[palette] ?? 0;

  /// Palette with the highest recorded win streak, if any wins exist.
  GamePalette? get favoritePalette {
    GamePalette? favorite;
    var best = 0;
    for (final palette in GamePalette.values) {
      final streak = bestStreakForPalette(palette);
      if (streak > best) {
        best = streak;
        favorite = palette;
      }
    }
    return favorite;
  }

  bool isPaletteUnlocked(GamePalette palette) {
    if (!palette.isLockedByDefault) return true;
    return unlockedPalettes.contains(palette);
  }

  GamePalette get fallbackPalette {
    for (final palette in GamePalette.values) {
      if (isPaletteUnlocked(palette)) return palette;
    }
    return GamePalette.standard;
  }

  bool isUnlocked(Difficulty difficulty) {
    final prerequisite = difficulty.unlockPrerequisite;
    if (prerequisite == null) return true;
    return winsFor(prerequisite) >= Difficulty.unlockWinsRequired;
  }

  bool get isIroenUnlocked => gamesWon >= iroenUnlockWinsRequired;

  bool get isDailyChallengeUnlocked =>
      winsFor(Difficulty.medium) >= dailyChallengeUnlockMediumWins;

  bool get isGraffitiUnlocked =>
      winsFor(Difficulty.easy) >= graffitiUnlockEasyWins;

  Difficulty get highestUnlocked {
    Difficulty best = Difficulty.easy;
    for (final d in Difficulty.values) {
      if (isUnlocked(d)) best = d;
    }
    return best;
  }

  GameStats copyWith({
    int? currentStreak,
    int? bestStreak,
    int? gamesPlayed,
    int? gamesWon,
    Map<Difficulty, Duration?>? bestTimes,
    Map<Difficulty, int>? winsByDifficulty,
    int? chromaticGamesWon,
    Map<Difficulty, Duration?>? chromaticBestTimes,
    Map<Difficulty, int>? chromaticWinsByDifficulty,
    Set<GamePalette>? unlockedPalettes,
    Map<GamePalette, int>? bestStreakByPalette,
    Map<GamePalette, int>? currentStreakByPalette,
    int? graffitiWins,
    int? graffitiLosses,
    int? graffitiDraws,
    int? totalXp,
  }) {
    return GameStats(
      currentStreak: currentStreak ?? this.currentStreak,
      bestStreak: bestStreak ?? this.bestStreak,
      gamesPlayed: gamesPlayed ?? this.gamesPlayed,
      gamesWon: gamesWon ?? this.gamesWon,
      bestTimes: bestTimes ?? this.bestTimes,
      winsByDifficulty: winsByDifficulty ?? this.winsByDifficulty,
      chromaticGamesWon: chromaticGamesWon ?? this.chromaticGamesWon,
      chromaticBestTimes: chromaticBestTimes ?? this.chromaticBestTimes,
      chromaticWinsByDifficulty:
          chromaticWinsByDifficulty ?? this.chromaticWinsByDifficulty,
      unlockedPalettes: unlockedPalettes ?? this.unlockedPalettes,
      bestStreakByPalette: bestStreakByPalette ?? this.bestStreakByPalette,
      currentStreakByPalette:
          currentStreakByPalette ?? this.currentStreakByPalette,
      graffitiWins: graffitiWins ?? this.graffitiWins,
      graffitiLosses: graffitiLosses ?? this.graffitiLosses,
      graffitiDraws: graffitiDraws ?? this.graffitiDraws,
      totalXp: totalXp ?? this.totalXp,
    );
  }
}

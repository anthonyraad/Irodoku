import 'dart:math' as math;

import 'difficulty.dart';
import 'game_stats.dart';

/// Prestige XP: stored as [totalXp]; level / progress are derived.
abstract final class PlayerXp {
  static const firstWinOfDayBonus = 50;
  /// 9×9 Chromatic: 75% of that difficulty's finish XP, rounded down.
  static const chromaticModifier = 0.75;
  /// Pocket [Chromatic] unit-hop games grant a smaller Chromatic line.
  static const pocketChromaticBonus = 20;
  static const flawlessModifier = 0.25;
  static const fastModifier = 0.25;
  static const notelessModifier = 0.40;
  static const wetPaintModifier = 0.25;

  static int baseXp(Difficulty difficulty) => switch (difficulty) {
        Difficulty.easy => 50,
        Difficulty.medium => 100,
        Difficulty.hard => 175,
        Difficulty.expert => 275,
        Difficulty.master => 400,
      };

  static int chromaticBonusFor(Difficulty difficulty) =>
      (baseXp(difficulty) * chromaticModifier).floor();

  /// Daily Challenge is a flat base (that day's difficulty still gates Fast).
  static const dailyBaseXp = 150;
  static const dailyStreakBonusMin = 3;
  static const dailyStreakBonus = 25;
  static const dailyStreakBonus7Min = 7;
  static const dailyStreakBonus7 = 50;
  static const dailyStreakBonus10Min = 10;
  static const dailyStreakBonus10 = 75;
  static const dailyStreakBonus14Min = 14;
  static const dailyStreakBonus14 = 100;

  /// Highest flat Daily streak bonus for [dailyStreak] (0 if under 3 days).
  static int streakBonusFor(int dailyStreak) {
    if (dailyStreak >= dailyStreakBonus14Min) return dailyStreakBonus14;
    if (dailyStreak >= dailyStreakBonus10Min) return dailyStreakBonus10;
    if (dailyStreak >= dailyStreakBonus7Min) return dailyStreakBonus7;
    if (dailyStreak >= dailyStreakBonusMin) return dailyStreakBonus;
    return 0;
  }

  /// Flat jackpot; rolled independently on each eligible victory.
  static const luckyXp = 400;
  static const luckyChance = 0.04;
  /// Career wins that must already be finished before Lucky can roll.
  /// Graffiti is excluded from this count.
  static const luckyMinPriorWins = 3;

  /// Pocket is a flat base; Speedy is under 2:00. Lazy is over 3:00.
  static const pocketBaseXp = 25;
  static const pocketDailyBaseXp = 50;
  static const pocketFastThreshold = Duration(minutes: 2);
  static const pocketLazyThreshold = Duration(minutes: 3);
  static const pocketLazyXp = -6;

  /// [Daily] streak XP (Pocket Daily only).
  static const pocketDailyStreakBonusMin = 3;
  static const pocketDailyStreakBonus = 5;
  static const pocketDailyStreakBonus7Min = 7;
  static const pocketDailyStreakBonus7 = 10;
  static const pocketDailyStreakBonus10Min = 10;
  static const pocketDailyStreakBonus10 = 15;
  static const pocketDailyStreakBonus14Min = 14;
  static const pocketDailyStreakBonus14 = 20;

  static int pocketDailyStreakBonusFor(int dailyStreak) {
    if (dailyStreak >= pocketDailyStreakBonus14Min) {
      return pocketDailyStreakBonus14;
    }
    if (dailyStreak >= pocketDailyStreakBonus10Min) {
      return pocketDailyStreakBonus10;
    }
    if (dailyStreak >= pocketDailyStreakBonus7Min) {
      return pocketDailyStreakBonus7;
    }
    if (dailyStreak >= pocketDailyStreakBonusMin) {
      return pocketDailyStreakBonus;
    }
    return 0;
  }

  /// Classic / 9×9 Chromatic Easy: Lazy is over 15:00.
  static const easyLazyThreshold = Duration(minutes: 15);
  static const easyLazyXp = -12;

  /// Graffiti has no ladder tier — treated as Medium for base; Speedy is under 5:00.
  static const graffitiDifficulty = Difficulty.medium;
  static const graffitiFastThreshold = Duration(minutes: 5);

  static Duration fastThreshold(Difficulty difficulty) => switch (difficulty) {
        Difficulty.easy => const Duration(minutes: 5),
        Difficulty.medium => const Duration(minutes: 8),
        Difficulty.hard => const Duration(minutes: 12),
        Difficulty.expert => const Duration(minutes: 20),
        Difficulty.master => const Duration(minutes: 30),
      };

  /// XP to go from [level] to [level]+1 (not cumulative).
  static int xpToReach(int level) {
    if (level < 1) return 100;
    return (100 * math.pow(level, 1.1)).round();
  }

  static int levelFor(int totalXp) {
    var remaining = math.max(0, totalXp);
    var level = 1;
    while (true) {
      final need = xpToReach(level);
      if (remaining < need) return level;
      remaining -= need;
      level++;
    }
  }

  /// XP into the current level, and XP required to finish this level.
  /// Not lifetime / not cumulative to next level.
  static ({int intoLevel, int toNext}) progress(int totalXp) {
    var remaining = math.max(0, totalXp);
    var level = 1;
    while (true) {
      final need = xpToReach(level);
      if (remaining < need) {
        return (intoLevel: remaining, toNext: need);
      }
      remaining -= need;
      level++;
    }
  }

  static double progressFraction(int totalXp) {
    final p = progress(totalXp);
    if (p.toNext <= 0) return 1;
    return (p.intoLevel / p.toNext).clamp(0.0, 1.0);
  }

  /// One-time seed: wins × base XP (no bonuses) + Graffiti wins × Medium.
  static int backfillFrom(GameStats stats) {
    var xp = 0;
    for (final difficulty in Difficulty.values) {
      xp += stats.winsFor(difficulty) * baseXp(difficulty);
    }
    xp += stats.graffitiWins * baseXp(graffitiDifficulty);
    return xp;
  }

  static XpAward compute({
    required Difficulty difficulty,
    required int mistakes,
    required Duration elapsed,
    required bool firstWinOfDay,
    required int previousTotal,
    String? sourceLabel,
    bool daily = false,
    int dailyStreak = 0,
    bool chromatic = false,
    bool wetPaint = false,
    bool noteless = false,
    int achievedXp = 0,
    bool pocket = false,
    bool graffiti = false,
    bool lucky = false,
    bool suppressSpeedAndFlawless = false,
  }) {
    final pocketDaily = pocket && daily;
    final base = pocketDaily
        ? pocketDailyBaseXp
        : pocket
            ? pocketBaseXp
            : daily
                ? dailyBaseXp
                : baseXp(difficulty);
    final flawless = mistakes == 0 && !suppressSpeedAndFlawless;
    final sloppy = pocket ? mistakes == 1 : mistakes == 2;
    final fast = suppressSpeedAndFlawless
        ? false
        : pocket
            ? elapsed < pocketFastThreshold
            : graffiti
                ? elapsed < graffitiFastThreshold
                : elapsed < fastThreshold(difficulty);
    final lazyXp = pocket && !daily && elapsed > pocketLazyThreshold
        ? pocketLazyXp
        : !pocket &&
                !daily &&
                !graffiti &&
                difficulty == Difficulty.easy &&
                elapsed > easyLazyThreshold
            ? easyLazyXp
            : 0;
    final lazy = lazyXp != 0;
    final flawlessXp = flawless ? (base * flawlessModifier).floor() : 0;
    final sloppyXp = sloppy ? -(base * flawlessModifier).floor() : 0;
    final fastXp = fast ? (base * fastModifier).floor() : 0;
    final notelessXp =
        !pocket && noteless ? (base * notelessModifier).floor() : 0;
    final wetPaintXp = !daily && !chromatic && !pocket && wetPaint
        ? (base * wetPaintModifier).floor()
        : 0;
    final firstOfDay = firstWinOfDay ? firstWinOfDayBonus : 0;
    final streak = daily
        ? (pocket
            ? pocketDailyStreakBonusFor(dailyStreak)
            : streakBonusFor(dailyStreak))
        : 0;
    final chromaticXp = !chromatic
        ? 0
        : pocket
            ? pocketChromaticBonus
            : chromaticBonusFor(difficulty);
    final artistryXp = pocket ? 0 : achievedXp;
    final luckyBonus = lucky ? luckyXp : 0;
    final earned = base +
        flawlessXp +
        sloppyXp +
        fastXp +
        lazyXp +
        notelessXp +
        wetPaintXp +
        firstOfDay +
        streak +
        chromaticXp +
        artistryXp +
        luckyBonus;
    return XpAward(
      baseXp: base,
      difficulty: difficulty,
      sourceLabel: sourceLabel ??
          (pocket && daily
              ? '[Daily]'
              : pocket
                  ? 'Pocket'
                  : daily
                      ? 'Daily'
                      : difficulty.label),
      flawless: flawless,
      sloppy: sloppy,
      fast: fast,
      lazy: lazy,
      firstWinOfDay: firstWinOfDay,
      streak: streak > 0,
      streakXp: streak,
      streakLabel: pocket && daily ? '[Streak]' : 'Streak',
      chromatic: chromaticXp > 0,
      chromaticXp: chromaticXp,
      chromaticLabel: pocket ? '[Chromatic]' : 'Chromatic',
      wetPaint: wetPaintXp > 0,
      noteless: notelessXp > 0,
      achievedXp: artistryXp,
      flawlessXp: flawlessXp,
      sloppyXp: sloppyXp,
      fastXp: fastXp,
      lazyXp: lazyXp,
      wetPaintXp: wetPaintXp,
      notelessXp: notelessXp,
      earned: earned,
      previousTotal: previousTotal,
      newTotal: previousTotal + earned,
      lucky: luckyBonus > 0,
    );
  }

  /// True [luckyChance] of the time after [luckyMinPriorWins] non-Graffiti wins.
  static bool rollLucky(int careerWinsBefore, {double? roll}) {
    if (careerWinsBefore < luckyMinPriorWins) return false;
    return (roll ?? math.Random().nextDouble()) < luckyChance;
  }
}

class XpAward {
  final int baseXp;
  final Difficulty difficulty;
  final String sourceLabel;
  final bool flawless;
  final bool sloppy;
  final bool fast;
  final bool lazy;
  final bool firstWinOfDay;
  final bool streak;
  final int streakXp;
  final String streakLabel;
  final bool chromatic;
  final int chromaticXp;
  final String chromaticLabel;
  final bool wetPaint;
  final bool noteless;
  final int achievedXp;
  final int flawlessXp;
  final int sloppyXp;
  final int fastXp;
  final int lazyXp;
  final int wetPaintXp;
  final int notelessXp;
  final int earned;
  final int previousTotal;
  final int newTotal;
  final bool lucky;

  const XpAward({
    required this.baseXp,
    required this.difficulty,
    required this.sourceLabel,
    required this.flawless,
    this.sloppy = false,
    required this.fast,
    this.lazy = false,
    required this.firstWinOfDay,
    required this.streak,
    this.streakXp = 0,
    this.streakLabel = 'Streak',
    required this.chromatic,
    this.chromaticXp = 0,
    this.chromaticLabel = 'Chromatic',
    this.wetPaint = false,
    this.noteless = false,
    this.achievedXp = 0,
    required this.flawlessXp,
    this.sloppyXp = 0,
    required this.fastXp,
    this.lazyXp = 0,
    this.wetPaintXp = 0,
    this.notelessXp = 0,
    required this.earned,
    required this.previousTotal,
    required this.newTotal,
    this.lucky = false,
  });

  int get previousLevel => PlayerXp.levelFor(previousTotal);
  int get newLevel => PlayerXp.levelFor(newTotal);
  bool get leveledUp => newLevel > previousLevel;

  /// Receipt lines that sum to [earned].
  List<({String label, int xp})> get breakdown => [
        (label: '$sourceLabel finish', xp: baseXp),
        if (flawless) (label: 'Flawless', xp: flawlessXp),
        if (sloppy) (label: 'Sloppy', xp: sloppyXp),
        if (fast) (label: 'Speedy', xp: fastXp),
        if (lazy) (label: 'Lazy', xp: lazyXp),
        if (noteless) (label: 'Freestyle', xp: notelessXp),
        if (wetPaint) (label: 'Wet paint', xp: wetPaintXp),
        if (chromatic) (label: chromaticLabel, xp: chromaticXp),
        if (achievedXp > 0) (label: 'Artistry', xp: achievedXp),
        if (firstWinOfDay)
          (label: 'First of day', xp: PlayerXp.firstWinOfDayBonus),
        if (streak) (label: streakLabel, xp: streakXp),
        if (lucky) (label: 'Lucky', xp: PlayerXp.luckyXp),
      ];
}

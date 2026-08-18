import 'package:flutter_test/flutter_test.dart';
import 'package:irodoku/models/achievement.dart';
import 'package:irodoku/models/difficulty.dart';
import 'package:irodoku/models/game_stats.dart';
import 'package:irodoku/models/player_xp.dart';

void main() {
  test('xpToReach follows 100 * level^1.3', () {
    expect(PlayerXp.xpToReach(1), 100);
    expect(PlayerXp.xpToReach(2), 246);
    expect(PlayerXp.xpToReach(5), 810);
    expect(PlayerXp.xpToReach(10), 1995);
    expect(PlayerXp.xpToReach(20), 4913);
    expect(PlayerXp.xpToReach(50), 16168);
  });

  test('level and progress are derived from total XP', () {
    expect(PlayerXp.levelFor(0), 1);
    expect(PlayerXp.progress(0), (intoLevel: 0, toNext: 100));

    expect(PlayerXp.levelFor(99), 1);
    expect(PlayerXp.levelFor(100), 2);
    expect(PlayerXp.progress(100), (intoLevel: 0, toNext: 246));

    expect(PlayerXp.levelFor(345), 2);
    expect(PlayerXp.levelFor(346), 3);
    expect(PlayerXp.progress(150), (intoLevel: 50, toNext: 246));
  });

  test('flawless fast Hard first-of-day floors each 25% bonus', () {
    final award = PlayerXp.compute(
      difficulty: Difficulty.hard,
      mistakes: 0,
      elapsed: const Duration(minutes: 11, seconds: 59),
      firstWinOfDay: true,
      previousTotal: 0,
    );
    expect(award.baseXp, 175);
    expect(award.flawless, isTrue);
    expect(award.fast, isTrue);
    expect(award.flawlessXp, 43);
    expect(award.fastXp, 43);
    expect(award.earned, 311);
    expect(award.newTotal, 311);
    expect(award.leveledUp, isTrue);
    expect(award.newLevel, 2);
    expect(
      award.breakdown,
      [
        (label: 'Hard finish', xp: 175),
        (label: 'Flawless', xp: 43),
        (label: 'Speedy', xp: 43),
        (label: 'First of day', xp: 50),
      ],
    );
    expect(
      award.breakdown.fold<int>(0, (sum, line) => sum + line.xp),
      award.earned,
    );
  });

  test('Easy win with 3 mistakes is base XP only', () {
    final award = PlayerXp.compute(
      difficulty: Difficulty.easy,
      mistakes: 3,
      elapsed: const Duration(minutes: 15),
      firstWinOfDay: false,
      previousTotal: 40,
    );
    expect(award.earned, 50);
    expect(award.newTotal, 90);
    expect(award.leveledUp, isFalse);
  });

  test('Sloppy is minus Flawless at exactly 2 mistakes', () {
    final easy = PlayerXp.compute(
      difficulty: Difficulty.easy,
      mistakes: 2,
      elapsed: const Duration(minutes: 15),
      firstWinOfDay: false,
      previousTotal: 0,
    );
    final hard = PlayerXp.compute(
      difficulty: Difficulty.hard,
      mistakes: 2,
      elapsed: const Duration(minutes: 20),
      firstWinOfDay: false,
      previousTotal: 0,
    );
    final oneMistake = PlayerXp.compute(
      difficulty: Difficulty.easy,
      mistakes: 1,
      elapsed: const Duration(minutes: 15),
      firstWinOfDay: false,
      previousTotal: 0,
    );
    expect(easy.sloppy, isTrue);
    expect(easy.sloppyXp, -12);
    expect(easy.earned, 38);
    expect(
      easy.breakdown,
      [
        (label: 'Easy finish', xp: 50),
        (label: 'Sloppy', xp: -12),
      ],
    );
    expect(hard.sloppyXp, -43);
    expect(hard.earned, 132);
    expect(oneMistake.sloppy, isFalse);
    expect(oneMistake.earned, 50);
  });

  test('Pocket Sloppy is 1 mistake; Daily stays at 2', () {
    final pocket = PlayerXp.compute(
      difficulty: Difficulty.easy,
      mistakes: 1,
      elapsed: const Duration(minutes: 3),
      firstWinOfDay: false,
      previousTotal: 0,
      pocket: true,
    );
    final pocketTwo = PlayerXp.compute(
      difficulty: Difficulty.easy,
      mistakes: 2,
      elapsed: const Duration(minutes: 3),
      firstWinOfDay: false,
      previousTotal: 0,
      pocket: true,
    );
    final daily = PlayerXp.compute(
      difficulty: Difficulty.easy,
      mistakes: 2,
      elapsed: const Duration(minutes: 20),
      firstWinOfDay: false,
      previousTotal: 0,
      daily: true,
    );
    expect(pocket.sloppy, isTrue);
    expect(pocket.sloppyXp, -6);
    expect(pocket.earned, 19);
    expect(pocketTwo.sloppy, isFalse);
    expect(daily.sloppyXp, -37);
    expect(daily.earned, 113);
  });

  test('fast bonus is strict under the threshold', () {
    final under = PlayerXp.compute(
      difficulty: Difficulty.easy,
      mistakes: 1,
      elapsed: const Duration(minutes: 4, seconds: 59),
      firstWinOfDay: false,
      previousTotal: 0,
    );
    final onThreshold = PlayerXp.compute(
      difficulty: Difficulty.easy,
      mistakes: 1,
      elapsed: const Duration(minutes: 5),
      firstWinOfDay: false,
      previousTotal: 0,
    );
    expect(under.fast, isTrue);
    expect(under.earned, 62);
    expect(onThreshold.fast, isFalse);
    expect(onThreshold.earned, 50);
  });

  test('Daily Challenge is a flat 150 base XP', () {
    final award = PlayerXp.compute(
      difficulty: Difficulty.easy,
      mistakes: 1,
      elapsed: const Duration(minutes: 20),
      firstWinOfDay: false,
      previousTotal: 0,
      daily: true,
    );
    expect(award.baseXp, 150);
    expect(award.sourceLabel, 'Daily');
    expect(award.lazy, isFalse);
    expect(award.earned, 150);
  });

  test('Daily still applies Fast using that day\'s difficulty', () {
    final award = PlayerXp.compute(
      difficulty: Difficulty.easy,
      mistakes: 1,
      elapsed: const Duration(minutes: 4),
      firstWinOfDay: false,
      previousTotal: 0,
      daily: true,
    );
    expect(award.fast, isTrue);
    expect(award.earned, 187);
  });

  test('Daily streak of 3+ adds a flat 25 XP', () {
    final two = PlayerXp.compute(
      difficulty: Difficulty.medium,
      mistakes: 1,
      elapsed: const Duration(minutes: 30),
      firstWinOfDay: false,
      previousTotal: 0,
      daily: true,
      dailyStreak: 2,
    );
    final three = PlayerXp.compute(
      difficulty: Difficulty.medium,
      mistakes: 1,
      elapsed: const Duration(minutes: 30),
      firstWinOfDay: false,
      previousTotal: 0,
      daily: true,
      dailyStreak: 3,
    );
    expect(two.streak, isFalse);
    expect(two.earned, 150);
    expect(three.streak, isTrue);
    expect(three.earned, 175);
  });

  test('Wet paint adds 25% of base, rounded down', () {
    final samePalette = PlayerXp.compute(
      difficulty: Difficulty.hard,
      mistakes: 1,
      elapsed: const Duration(minutes: 20),
      firstWinOfDay: false,
      previousTotal: 0,
    );
    final switched = PlayerXp.compute(
      difficulty: Difficulty.hard,
      mistakes: 1,
      elapsed: const Duration(minutes: 20),
      firstWinOfDay: false,
      previousTotal: 0,
      wetPaint: true,
    );
    expect(samePalette.wetPaint, isFalse);
    expect(samePalette.wetPaintXp, 0);
    expect(samePalette.earned, 175);
    expect(switched.wetPaint, isTrue);
    expect(switched.wetPaintXp, 43);
    expect(switched.earned, 218);
    expect(
      switched.breakdown,
      [
        (label: 'Hard finish', xp: 175),
        (label: 'Wet paint', xp: 43),
      ],
    );
  });

  test('Freestyle adds 40% of base, rounded down', () {
    final withNotes = PlayerXp.compute(
      difficulty: Difficulty.hard,
      mistakes: 1,
      elapsed: const Duration(minutes: 20),
      firstWinOfDay: false,
      previousTotal: 0,
    );
    final noteless = PlayerXp.compute(
      difficulty: Difficulty.hard,
      mistakes: 1,
      elapsed: const Duration(minutes: 20),
      firstWinOfDay: false,
      previousTotal: 0,
      noteless: true,
    );
    expect(withNotes.noteless, isFalse);
    expect(withNotes.notelessXp, 0);
    expect(withNotes.earned, 175);
    expect(noteless.noteless, isTrue);
    expect(noteless.notelessXp, 70);
    expect(noteless.earned, 245);
    expect(
      noteless.breakdown,
      [
        (label: 'Hard finish', xp: 175),
        (label: 'Freestyle', xp: 70),
      ],
    );
  });

  test('Freestyle applies to Daily Challenge', () {
    final award = PlayerXp.compute(
      difficulty: Difficulty.easy,
      mistakes: 1,
      elapsed: const Duration(minutes: 20),
      firstWinOfDay: false,
      previousTotal: 0,
      daily: true,
      noteless: true,
    );
    expect(award.notelessXp, 60);
    expect(award.earned, 210);
  });

  test('Wet paint never applies to Daily Challenge', () {
    final award = PlayerXp.compute(
      difficulty: Difficulty.hard,
      mistakes: 1,
      elapsed: const Duration(minutes: 20),
      firstWinOfDay: false,
      previousTotal: 0,
      daily: true,
      wetPaint: true,
    );
    expect(award.wetPaint, isFalse);
    expect(award.wetPaintXp, 0);
    expect(award.earned, 150);
    expect(award.breakdown, [(label: 'Daily finish', xp: 150)]);
  });

  test('Wet paint never applies to Chromatic', () {
    final award = PlayerXp.compute(
      difficulty: Difficulty.hard,
      mistakes: 1,
      elapsed: const Duration(minutes: 20),
      firstWinOfDay: false,
      previousTotal: 0,
      chromatic: true,
      wetPaint: true,
    );
    expect(award.wetPaint, isFalse);
    expect(award.wetPaintXp, 0);
    expect(award.earned, 306);
    expect(
      award.breakdown,
      [
        (label: 'Hard finish', xp: 175),
        (label: 'Chromatic', xp: 131),
      ],
    );
  });

  test('Chromatic is 75% of difficulty base, rounded down', () {
    final classic = PlayerXp.compute(
      difficulty: Difficulty.easy,
      mistakes: 1,
      elapsed: const Duration(minutes: 15),
      firstWinOfDay: false,
      previousTotal: 0,
    );
    final chromatic = PlayerXp.compute(
      difficulty: Difficulty.easy,
      mistakes: 1,
      elapsed: const Duration(minutes: 15),
      firstWinOfDay: false,
      previousTotal: 0,
      chromatic: true,
    );
    expect(classic.chromatic, isFalse);
    expect(classic.earned, 50);
    expect(chromatic.chromatic, isTrue);
    expect(chromatic.chromaticXp, 37);
    expect(chromatic.earned, 87);
    expect(
      chromatic.breakdown,
      [
        (label: 'Easy finish', xp: 50),
        (label: 'Chromatic', xp: 37),
      ],
    );
    expect(PlayerXp.chromaticBonusFor(Difficulty.medium), 75);
    expect(PlayerXp.chromaticBonusFor(Difficulty.hard), 131);
    expect(PlayerXp.chromaticBonusFor(Difficulty.expert), 206);
    expect(PlayerXp.chromaticBonusFor(Difficulty.master), 300);
  });

  test('completing an achievement row adds Artistry XP', () {
    expect(Achievement.xpForCompletedRow(0), 1000);
    expect(Achievement.xpForCompletedRow(7), 8000);
    final almost = {
      for (var c = 0; c < 8; c++) 'r1c${c + 1}',
    };
    expect(Achievement.isRowComplete(almost, 0), isFalse);
    expect(Achievement.isRowComplete({...almost, 'r1c9'}, 0), isTrue);

    final award = PlayerXp.compute(
      difficulty: Difficulty.easy,
      mistakes: 1,
      elapsed: const Duration(minutes: 15),
      firstWinOfDay: false,
      previousTotal: 0,
      achievedXp: Achievement.xpForCompletedRow(0),
    );
    expect(award.earned, 1050);
    expect(
      award.breakdown,
      [
        (label: 'Easy finish', xp: 50),
        (label: 'Artistry', xp: 1000),
      ],
    );
  });

  test('Pocket is a flat 25 base XP', () {
    final award = PlayerXp.compute(
      difficulty: Difficulty.master,
      mistakes: 0,
      elapsed: const Duration(minutes: 3),
      firstWinOfDay: false,
      previousTotal: 0,
      pocket: true,
    );
    expect(award.baseXp, 25);
    expect(award.sourceLabel, 'Pocket');
    expect(award.earned, 31);
    expect(
      award.breakdown,
      [
        (label: 'Pocket finish', xp: 25),
        (label: 'Flawless', xp: 6),
      ],
    );
  });

  test('Pocket Speedy is under 2:00', () {
    final under = PlayerXp.compute(
      difficulty: Difficulty.easy,
      mistakes: 0,
      elapsed: const Duration(minutes: 1, seconds: 59),
      firstWinOfDay: false,
      previousTotal: 0,
      pocket: true,
    );
    final onThreshold = PlayerXp.compute(
      difficulty: Difficulty.easy,
      mistakes: 0,
      elapsed: const Duration(minutes: 2),
      firstWinOfDay: false,
      previousTotal: 0,
      pocket: true,
    );
    expect(under.fast, isTrue);
    expect(under.fastXp, 6);
    expect(under.earned, 37);
    expect(onThreshold.fast, isFalse);
    expect(onThreshold.earned, 31);
  });

  test('Graffiti Speedy is under 5:00', () {
    final under = PlayerXp.compute(
      difficulty: PlayerXp.graffitiDifficulty,
      mistakes: 1,
      elapsed: const Duration(minutes: 4, seconds: 59),
      firstWinOfDay: false,
      previousTotal: 0,
      sourceLabel: 'Graffiti',
      graffiti: true,
    );
    final onThreshold = PlayerXp.compute(
      difficulty: PlayerXp.graffitiDifficulty,
      mistakes: 1,
      elapsed: const Duration(minutes: 5),
      firstWinOfDay: false,
      previousTotal: 0,
      sourceLabel: 'Graffiti',
      graffiti: true,
    );
    expect(under.baseXp, 100);
    expect(under.fast, isTrue);
    expect(under.fastXp, 25);
    expect(under.earned, 125);
    expect(onThreshold.fast, isFalse);
    expect(onThreshold.earned, 100);
  });

  test('Pocket Flawless and First of day apply; extras do not', () {
    final award = PlayerXp.compute(
      difficulty: Difficulty.hard,
      mistakes: 0,
      elapsed: const Duration(minutes: 1),
      firstWinOfDay: true,
      previousTotal: 0,
      pocket: true,
      wetPaint: true,
      noteless: true,
      daily: true,
      dailyStreak: 5,
      achievedXp: 1000,
    );
    expect(award.baseXp, 25);
    expect(award.flawless, isTrue);
    expect(award.flawlessXp, 6);
    expect(award.fast, isTrue);
    expect(award.fastXp, 6);
    expect(award.firstWinOfDay, isTrue);
    expect(award.wetPaint, isFalse);
    expect(award.noteless, isFalse);
    expect(award.chromatic, isFalse);
    expect(award.streak, isFalse);
    expect(award.achievedXp, 0);
    expect(award.earned, 87);
    expect(
      award.breakdown,
      [
        (label: 'Pocket finish', xp: 25),
        (label: 'Flawless', xp: 6),
        (label: 'Speedy', xp: 6),
        (label: 'First of day', xp: 50),
      ],
    );
  });

  test('Pocket Chromatic adds a flat 20 XP labeled [Chromatic]', () {
    final award = PlayerXp.compute(
      difficulty: Difficulty.easy,
      mistakes: 0,
      elapsed: const Duration(minutes: 3),
      firstWinOfDay: false,
      previousTotal: 0,
      pocket: true,
      chromatic: true,
    );
    expect(award.baseXp, 25);
    expect(award.chromatic, isTrue);
    expect(award.chromaticXp, 20);
    expect(award.earned, 51);
    expect(
      award.breakdown,
      [
        (label: 'Pocket finish', xp: 25),
        (label: 'Flawless', xp: 6),
        (label: '[Chromatic]', xp: 20),
      ],
    );
  });

  test('Pocket Lazy is over 3:00 and subtracts 6 XP', () {
    final onThreshold = PlayerXp.compute(
      difficulty: Difficulty.easy,
      mistakes: 0,
      elapsed: const Duration(minutes: 3),
      firstWinOfDay: false,
      previousTotal: 0,
      pocket: true,
    );
    final over = PlayerXp.compute(
      difficulty: Difficulty.easy,
      mistakes: 0,
      elapsed: const Duration(minutes: 3, seconds: 1),
      firstWinOfDay: false,
      previousTotal: 0,
      pocket: true,
    );
    expect(onThreshold.lazy, isFalse);
    expect(onThreshold.earned, 31);
    expect(over.lazy, isTrue);
    expect(over.lazyXp, -6);
    expect(over.earned, 25);
    expect(
      over.breakdown,
      [
        (label: 'Pocket finish', xp: 25),
        (label: 'Flawless', xp: 6),
        (label: 'Lazy', xp: -6),
      ],
    );
  });

  test('Pocket Chromatic Lazy still subtracts 6 XP', () {
    final award = PlayerXp.compute(
      difficulty: Difficulty.easy,
      mistakes: 0,
      elapsed: const Duration(minutes: 4),
      firstWinOfDay: false,
      previousTotal: 0,
      pocket: true,
      chromatic: true,
    );
    expect(award.lazy, isTrue);
    expect(award.lazyXp, -6);
    expect(award.earned, 45);
    expect(
      award.breakdown,
      [
        (label: 'Pocket finish', xp: 25),
        (label: 'Flawless', xp: 6),
        (label: 'Lazy', xp: -6),
        (label: '[Chromatic]', xp: 20),
      ],
    );
  });

  test('Easy Lazy is over 15:00 and subtracts 12 XP', () {
    final onThreshold = PlayerXp.compute(
      difficulty: Difficulty.easy,
      mistakes: 1,
      elapsed: const Duration(minutes: 15),
      firstWinOfDay: false,
      previousTotal: 0,
    );
    final over = PlayerXp.compute(
      difficulty: Difficulty.easy,
      mistakes: 1,
      elapsed: const Duration(minutes: 15, seconds: 1),
      firstWinOfDay: false,
      previousTotal: 0,
    );
    final medium = PlayerXp.compute(
      difficulty: Difficulty.medium,
      mistakes: 1,
      elapsed: const Duration(minutes: 20),
      firstWinOfDay: false,
      previousTotal: 0,
    );
    expect(onThreshold.lazy, isFalse);
    expect(onThreshold.earned, 50);
    expect(over.lazy, isTrue);
    expect(over.lazyXp, -12);
    expect(over.earned, 38);
    expect(
      over.breakdown,
      [
        (label: 'Easy finish', xp: 50),
        (label: 'Lazy', xp: -12),
      ],
    );
    expect(medium.lazy, isFalse);
    expect(medium.earned, 100);
  });

  test('Easy Chromatic Lazy still subtracts 12 XP', () {
    final award = PlayerXp.compute(
      difficulty: Difficulty.easy,
      mistakes: 1,
      elapsed: const Duration(minutes: 16),
      firstWinOfDay: false,
      previousTotal: 0,
      chromatic: true,
    );
    expect(award.lazy, isTrue);
    expect(award.lazyXp, -12);
    expect(award.earned, 75);
    expect(
      award.breakdown,
      [
        (label: 'Easy finish', xp: 50),
        (label: 'Lazy', xp: -12),
        (label: 'Chromatic', xp: 37),
      ],
    );
  });

  test('backfill uses winsByDifficulty plus Graffiti, not chromatic twice', () {
    const stats = GameStats(
      winsByDifficulty: {
        Difficulty.easy: 2,
        Difficulty.medium: 1,
      },
      chromaticWinsByDifficulty: {
        Difficulty.easy: 2,
      },
      graffitiWins: 3,
    );
    expect(PlayerXp.backfillFrom(stats), 2 * 50 + 100 + 3 * 100);
  });
}

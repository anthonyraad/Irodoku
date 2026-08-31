import 'package:flutter_test/flutter_test.dart';
import 'package:irodoku/models/achievement.dart';
import 'package:irodoku/models/difficulty.dart';
import 'package:irodoku/models/game_stats.dart';
import 'package:irodoku/models/player_xp.dart';

void main() {
  test('xpToReach follows 100 * level^1.1', () {
    expect(PlayerXp.xpToReach(1), 100);
    expect(PlayerXp.xpToReach(2), 214);
    expect(PlayerXp.xpToReach(5), 587);
    expect(PlayerXp.xpToReach(10), 1259);
    expect(PlayerXp.xpToReach(20), 2699);
    expect(PlayerXp.xpToReach(50), 7394);
  });

  test('level and progress are derived from total XP', () {
    expect(PlayerXp.levelFor(0), 1);
    expect(PlayerXp.progress(0), (intoLevel: 0, toNext: 100));

    expect(PlayerXp.levelFor(99), 1);
    expect(PlayerXp.levelFor(100), 2);
    expect(PlayerXp.progress(100), (intoLevel: 0, toNext: 214));

    expect(PlayerXp.levelFor(313), 2);
    expect(PlayerXp.levelFor(314), 3);
    expect(PlayerXp.progress(150), (intoLevel: 50, toNext: 214));
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

  test('Daily streak XP is a flat tier: 25 / 50 / 75 / 100', () {
    XpAward daily(int streak) => PlayerXp.compute(
          difficulty: Difficulty.medium,
          mistakes: 1,
          elapsed: const Duration(minutes: 30),
          firstWinOfDay: false,
          previousTotal: 0,
          daily: true,
          dailyStreak: streak,
        );

    final two = daily(2);
    expect(two.streak, isFalse);
    expect(two.streakXp, 0);
    expect(two.earned, 150);

    final three = daily(3);
    expect(three.streak, isTrue);
    expect(three.streakXp, 25);
    expect(three.earned, 175);
    expect(three.breakdown.last, (label: 'Streak', xp: 25));

    expect(daily(6).streakXp, 25);
    expect(daily(7).streakXp, 50);
    expect(daily(7).earned, 200);
    expect(daily(9).streakXp, 50);
    expect(daily(10).streakXp, 75);
    expect(daily(10).earned, 225);
    expect(daily(13).streakXp, 75);
    expect(daily(14).streakXp, 100);
    expect(daily(14).earned, 250);
    expect(daily(30).streakXp, 100);
  });

  test('Pocket Daily is a flat 50 base with [Daily] receipt', () {
    final award = PlayerXp.compute(
      difficulty: Difficulty.hard,
      mistakes: 0,
      elapsed: const Duration(minutes: 2, seconds: 30),
      firstWinOfDay: false,
      previousTotal: 0,
      pocket: true,
      daily: true,
    );
    expect(award.baseXp, 50);
    expect(award.sourceLabel, '[Daily]');
    expect(award.fast, isFalse);
    expect(award.lazy, isFalse);
    expect(award.earned, 62);
    expect(
      award.breakdown,
      [
        (label: '[Daily] finish', xp: 50),
        (label: 'Flawless', xp: 12),
      ],
    );
  });

  test('Pocket Daily uses Pocket Speedy and Sloppy; not Lazy', () {
    final speedy = PlayerXp.compute(
      difficulty: Difficulty.easy,
      mistakes: 0,
      elapsed: const Duration(minutes: 1, seconds: 59),
      firstWinOfDay: false,
      previousTotal: 0,
      pocket: true,
      daily: true,
    );
    final lazy = PlayerXp.compute(
      difficulty: Difficulty.easy,
      mistakes: 0,
      elapsed: const Duration(minutes: 3, seconds: 1),
      firstWinOfDay: false,
      previousTotal: 0,
      pocket: true,
      daily: true,
    );
    final sloppy = PlayerXp.compute(
      difficulty: Difficulty.easy,
      mistakes: 1,
      elapsed: const Duration(minutes: 2, seconds: 30),
      firstWinOfDay: false,
      previousTotal: 0,
      pocket: true,
      daily: true,
    );
    expect(speedy.fast, isTrue);
    expect(speedy.fastXp, 12);
    expect(lazy.lazy, isFalse);
    expect(lazy.lazyXp, 0);
    expect(sloppy.sloppy, isTrue);
    expect(sloppy.sloppyXp, -12);
    expect(sloppy.flawless, isFalse);
  });

  test('Pocket Daily streak XP is a flat tier: 5 / 10 / 15 / 20', () {
    XpAward daily(int streak) => PlayerXp.compute(
          difficulty: Difficulty.easy,
          mistakes: 1,
          elapsed: const Duration(minutes: 2, seconds: 30),
          firstWinOfDay: false,
          previousTotal: 0,
          pocket: true,
          daily: true,
          dailyStreak: streak,
        );

    final two = daily(2);
    expect(two.streak, isFalse);
    expect(two.streakXp, 0);
    expect(two.streakLabel, '[Streak]');

    final three = daily(3);
    expect(three.streak, isTrue);
    expect(three.streakXp, 5);
    expect(three.breakdown.last, (label: '[Streak]', xp: 5));

    expect(daily(6).streakXp, 5);
    expect(daily(7).streakXp, 10);
    expect(daily(9).streakXp, 10);
    expect(daily(10).streakXp, 15);
    expect(daily(13).streakXp, 15);
    expect(daily(14).streakXp, 20);
    expect(daily(30).streakXp, 20);
  });

  test('Pocket Daily can take First of day and Lucky; not Freestyle', () {
    final first = PlayerXp.compute(
      difficulty: Difficulty.easy,
      mistakes: 1,
      elapsed: const Duration(minutes: 2, seconds: 30),
      firstWinOfDay: true,
      previousTotal: 0,
      pocket: true,
      daily: true,
      noteless: true,
      achievedXp: 40,
      lucky: true,
    );
    expect(first.noteless, isFalse);
    expect(first.achievedXp, 0);
    expect(first.lucky, isTrue);
    expect(first.firstWinOfDay, isTrue);
    expect(
      first.breakdown,
      [
        (label: '[Daily] finish', xp: 50),
        (label: 'Sloppy', xp: -12),
        (label: 'First of day', xp: 50),
        (label: 'Lucky', xp: 400),
      ],
    );
  });

  test('Pocket Daily unlocks after a Pocket win', () {
    expect(const GameStats().isPocketDailyUnlocked, isFalse);
    expect(
      const GameStats(
        winsByDifficulty: {Difficulty.medium: 1},
      ).isPocketDailyUnlocked,
      isFalse,
    );
    expect(
      const GameStats(pocketWins: 1).isPocketDailyUnlocked,
      isTrue,
    );
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

  test('Wet paint never applies to Graffiti or [Graffiti]', () {
    final graffiti = PlayerXp.compute(
      difficulty: PlayerXp.graffitiDifficulty,
      mistakes: 1,
      elapsed: const Duration(minutes: 10),
      firstWinOfDay: false,
      previousTotal: 0,
      sourceLabel: 'Graffiti',
      graffiti: true,
      wetPaint: true,
    );
    final pocketGraffiti = PlayerXp.compute(
      difficulty: PlayerXp.graffitiDifficulty,
      mistakes: 1,
      elapsed: const Duration(minutes: 10),
      firstWinOfDay: false,
      previousTotal: 0,
      sourceLabel: '[Graffiti]',
      graffiti: true,
      pocket: true,
      wetPaint: true,
    );
    expect(graffiti.wetPaint, isFalse);
    expect(graffiti.wetPaintXp, 0);
    expect(graffiti.earned, 100);
    expect(graffiti.breakdown, [(label: 'Graffiti finish', xp: 100)]);
    expect(pocketGraffiti.wetPaint, isFalse);
    expect(pocketGraffiti.wetPaintXp, 0);
    expect(pocketGraffiti.earned, 50);
    expect(pocketGraffiti.breakdown, [(label: '[Graffiti] finish', xp: 50)]);
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

  test('Pocket [Graffiti] is a flat 50 base with Graffiti Speedy and Freestyle', () {
    final award = PlayerXp.compute(
      difficulty: PlayerXp.graffitiDifficulty,
      mistakes: 0,
      elapsed: const Duration(minutes: 4, seconds: 59),
      firstWinOfDay: false,
      previousTotal: 0,
      sourceLabel: '[Graffiti]',
      graffiti: true,
      pocket: true,
      noteless: true,
    );
    expect(award.baseXp, 50);
    expect(award.sourceLabel, '[Graffiti]');
    expect(award.fast, isTrue);
    expect(award.fastXp, 12);
    expect(award.noteless, isTrue);
    expect(award.notelessXp, 20);
    expect(award.sloppy, isFalse);
    expect(award.lazy, isFalse);
    expect(
      award.breakdown,
      [
        (label: '[Graffiti] finish', xp: 50),
        (label: 'Flawless', xp: 12),
        (label: 'Speedy', xp: 12),
        (label: 'Freestyle', xp: 20),
      ],
    );
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

  test('Lucky adds 400 as the last receipt line', () {
    final award = PlayerXp.compute(
      difficulty: Difficulty.easy,
      mistakes: 3,
      elapsed: const Duration(minutes: 15),
      firstWinOfDay: false,
      previousTotal: 0,
      lucky: true,
    );
    expect(award.lucky, isTrue);
    expect(award.earned, 50 + PlayerXp.luckyXp);
    expect(award.breakdown.last, (label: 'Lucky', xp: 400));
    expect(
      award.breakdown.fold<int>(0, (sum, line) => sum + line.xp),
      award.earned,
    );
  });

  test('Lucky does not roll on the first 3 career wins', () {
    expect(PlayerXp.rollLucky(0, roll: 0), isFalse);
    expect(PlayerXp.rollLucky(2, roll: 0), isFalse);
    expect(PlayerXp.rollLucky(3, roll: 0), isTrue);
  });

  test('Lucky is 4% after the career lockout', () {
    expect(PlayerXp.rollLucky(3, roll: 0.039999), isTrue);
    expect(PlayerXp.rollLucky(3, roll: 0.04), isFalse);
    expect(PlayerXp.rollLucky(10, roll: 0.5), isFalse);
  });

  test('retry wins omit Speedy and Flawless XP', () {
    final award = PlayerXp.compute(
      difficulty: Difficulty.hard,
      mistakes: 0,
      elapsed: const Duration(minutes: 11, seconds: 59),
      firstWinOfDay: false,
      previousTotal: 0,
      suppressSpeedAndFlawless: true,
    );
    expect(award.flawless, isFalse);
    expect(award.fast, isFalse);
    expect(award.flawlessXp, 0);
    expect(award.fastXp, 0);
    expect(award.earned, 175);
    expect(award.breakdown, [(label: 'Hard finish', xp: 175)]);
  });
}

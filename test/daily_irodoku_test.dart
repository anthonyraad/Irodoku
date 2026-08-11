import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:irodoku/models/daily_irodoku.dart';
import 'package:irodoku/models/difficulty.dart';
import 'package:irodoku/sudoku/sudoku_generator.dart';

void main() {
  test('same PST calendar day yields identical challenge', () {
    // PST day 2026-08-09 runs 08:00 UTC Aug 9 → 08:00 UTC Aug 10.
    final a = DailyIrodoku.forDate(DateTime.utc(2026, 8, 9, 8));
    final b = DailyIrodoku.forDate(DateTime.utc(2026, 8, 10, 7, 59));
    expect(a.dayKey, '2026-08-09');
    expect(a.dayKey, b.dayKey);
    expect(a.seed, b.seed);
    expect(a.difficulty, b.difficulty);
    expect(a.palette, b.palette);
    expect(a.secondPalette, b.secondPalette);
  });

  test('second palette differs from first and is stable for the day', () {
    final a = DailyIrodoku.forDate(DateTime.utc(2026, 8, 9, 12));
    final b = DailyIrodoku.forDate(DateTime.utc(2026, 8, 9, 20));
    expect(a.secondPalette, isNot(a.palette));
    expect(a.secondPalette, b.secondPalette);
    expect(
      DailyIrodoku.schedulePalettes,
      contains(a.secondPalette),
    );
  });

  test('day key ignores device local timezone', () {
    // Same instant expressed as local-looking constructors still maps via UTC→PST.
    final utc = DateTime.utc(2026, 8, 9, 15); // 07:00 PST → Aug 9
    expect(DailyIrodoku.dayKeyFor(utc), '2026-08-09');
    expect(DailyIrodoku.dayKeyFor(utc.toLocal()), '2026-08-09');
  });

  test('rolls at PST midnight (08:00 UTC)', () {
    final before = DailyIrodoku.forDate(DateTime.utc(2026, 8, 9, 7, 59));
    final after = DailyIrodoku.forDate(DateTime.utc(2026, 8, 9, 8));
    expect(before.dayKey, '2026-08-08');
    expect(after.dayKey, '2026-08-09');
  });

  test('seed is stable (not Object.hash)', () {
    // Pin expected FNV-1a so a regression to Object.hash fails loudly.
    final challenge = DailyIrodoku.forDate(DateTime.utc(2026, 8, 9, 12));
    expect(challenge.dayKey, '2026-08-09');
    expect(challenge.seed, 1798384309);
  });

  test('adjacent PST days differ', () {
    final a = DailyIrodoku.forDate(DateTime.utc(2026, 8, 9, 12));
    final b = DailyIrodoku.forDate(DateTime.utc(2026, 8, 10, 12));
    expect(a.dayKey, isNot(b.dayKey));
    expect(a.seed, isNot(b.seed));
  });

  test('previousDayKey steps back one calendar day', () {
    expect(
      DailyIrodoku.previousDayKey('2026-08-09'),
      '2026-08-08',
    );
    expect(
      DailyIrodoku.previousDayKey('2026-03-01'),
      '2026-02-28',
    );
  });

  test('shortDateLabel formats M.d.yy', () {
    expect(DailyIrodoku.shortDateLabel('2026-08-09'), '8.9.26');
    expect(DailyIrodoku.shortDateLabel('2026-12-01'), '12.1.26');
  });

  test('nextPstMidnight lands on 08:00 UTC', () {
    final now = DateTime.utc(2026, 8, 9, 12);
    final next = DailyIrodoku.nextPstMidnight(now);
    expect(next, DateTime.utc(2026, 8, 10, 8));
    expect(DailyIrodoku.timeUntilNextReset(now), const Duration(hours: 20));
  });

  test('seeded generator is deterministic', () {
    final challenge = DailyIrodoku.forDate(DateTime.utc(2026, 8, 9, 12));
    final a = SudokuGenerator(random: Random(challenge.seed))
        .generate(Difficulty.easy);
    final b = SudokuGenerator(random: Random(challenge.seed))
        .generate(Difficulty.easy);
    expect(a.puzzle.toFlat(), b.puzzle.toFlat());
    expect(a.solution.toFlat(), b.solution.toFlat());
  });

  test('difficulty stays in easy/medium/hard with mixed consecutive days', () {
    final counts = <Difficulty, int>{
      Difficulty.easy: 0,
      Difficulty.medium: 0,
      Difficulty.hard: 0,
    };
    var sequentialSteps = 0;
    Difficulty? prev;
    // Noon UTC is always the same PST calendar morning (04:00 PST).
    final start = DateTime.utc(2026, 1, 1, 12);
    for (var i = 0; i < 300; i++) {
      final day = start.add(Duration(days: i));
      final challenge = DailyIrodoku.forDate(day);
      expect(
        DailyIrodoku.scheduleDifficulties,
        contains(challenge.difficulty),
      );
      expect(challenge.difficulty, isNot(Difficulty.expert));
      counts[challenge.difficulty] = counts[challenge.difficulty]! + 1;
      if (prev != null) {
        final prevIdx =
            DailyIrodoku.scheduleDifficulties.indexOf(prev);
        final nextIdx =
            DailyIrodoku.scheduleDifficulties.indexOf(challenge.difficulty);
        if (nextIdx == (prevIdx + 1) % 3) sequentialSteps++;
      }
      prev = challenge.difficulty;
    }
    // Roughly equal (~100 each over 300 days).
    for (final count in counts.values) {
      expect(count, greaterThan(70));
      expect(count, lessThan(130));
    }
    // Not a pure Easy→Medium→Hard cycle (~299 sequential steps).
    expect(sequentialSteps, lessThan(150));
  });
}

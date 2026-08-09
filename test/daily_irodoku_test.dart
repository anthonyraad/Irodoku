import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:irodoku/models/daily_irodoku.dart';
import 'package:irodoku/models/difficulty.dart';
import 'package:irodoku/sudoku/sudoku_generator.dart';

void main() {
  test('same calendar day yields identical challenge', () {
    final a = DailyIrodoku.forDate(DateTime(2026, 8, 9, 9));
    final b = DailyIrodoku.forDate(DateTime(2026, 8, 9, 23, 59));
    expect(a.dayKey, '2026-08-09');
    expect(a.dayKey, b.dayKey);
    expect(a.seed, b.seed);
    expect(a.difficulty, b.difficulty);
    expect(a.palette, b.palette);
  });

  test('seed is stable (not Object.hash)', () {
    // Pin expected FNV-1a so a regression to Object.hash fails loudly.
    final challenge = DailyIrodoku.forDate(DateTime(2026, 8, 9));
    expect(challenge.seed, 1798384309);
  });

  test('adjacent days differ', () {
    final a = DailyIrodoku.forDate(DateTime(2026, 8, 9));
    final b = DailyIrodoku.forDate(DateTime(2026, 8, 10));
    expect(a.dayKey, isNot(b.dayKey));
    expect(a.seed, isNot(b.seed));
  });

  test('previousDayKey steps back one local day', () {
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

  test('seeded generator is deterministic', () {
    final challenge = DailyIrodoku.forDate(DateTime(2026, 8, 9));
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
    final start = DateTime(2026, 1, 1);
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

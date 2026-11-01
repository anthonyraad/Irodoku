// Discord Activity scores share irodoku_daily/{day}/pocket with the app.
// They are keyed by Discord user IDs (snowflakes) and carry src:'discord'.
import 'package:flutter_test/flutter_test.dart';
import 'package:irodoku/models/daily_leaderboard.dart';

void main() {
  test('parses Discord-sourced entries next to app entries', () {
    final raw = <Object?, Object?>{
      // App (Firebase Auth uid).
      'Xk3pQ9aZ1bC2dE3fG4hI5jK6lM7n': {'name': 'Anthony', 'ms': 61000, 'at': 1},
      // Discord snowflake ids with the extra src field.
      '123456789012345678': {
        'name': 'iro_fan',
        'ms': 52000,
        'at': 2,
        'src': 'discord',
      },
      '987654321098765432': {
        'name': 'Player',
        'ms': '70000', // tolerate stringly-typed numbers
        'at': 3,
        'src': 'discord',
      },
      'bad': {'name': 'x', 'src': 'discord'}, // no ms -> skipped
    };
    final entries = <DailyLeaderboardEntry>[];
    for (final e in raw.entries) {
      final parsed = DailyLeaderboardEntry.fromSnapshot(e.key.toString(), e.value);
      if (parsed != null) entries.add(parsed);
    }
    expect(entries, hasLength(3));
    final board = DailyLeaderboardBoard.fromEntries(
      entries: entries,
      youUid: '123456789012345678',
    );
    expect(board.top.map((e) => e.uid).toList(), [
      '123456789012345678',
      'Xk3pQ9aZ1bC2dE3fG4hI5jK6lM7n',
      '987654321098765432',
    ]);
    expect(board.top.first.name, 'iro_fan');
    expect(board.youRank, 1);
  });

  test('worker-sanitized Discord names pass DisplayName rules', () {
    // discord/worker/src/names.js produces <=10 chars of [A-Za-z0-9 ._-].
    for (final n in ['iro_fan', 'Anthony.R', 'a-b c']) {
      expect(DisplayName.trySanitize(n), n);
    }
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:irodoku/services/daily_leaderboard_service.dart';
import 'package:irodoku/services/discord_link_service.dart';

void main() {
  group('DailyLeaderboardService.entryMs', () {
    test('reads a saved Pocket time', () {
      expect(
        DailyLeaderboardService.entryMs({'name': 'Stars', 'ms': 61000, 'at': 1}),
        61000,
      );
      expect(DailyLeaderboardService.entryMs({'ms': 61000.0}), 61000);
      expect(DailyLeaderboardService.entryMs({'ms': '72000'}), 72000);
    });

    test('no entry or invalid time is not done', () {
      expect(DailyLeaderboardService.entryMs(null), isNull);
      expect(DailyLeaderboardService.entryMs({'name': 'x'}), isNull);
      expect(DailyLeaderboardService.entryMs({'ms': 100}), isNull);
      expect(DailyLeaderboardService.entryMs({'ms': 25 * 3600000}), isNull);
      expect(DailyLeaderboardService.entryMs('garbage'), isNull);
    });
  });

  test('unlinked: no remote read, local behavior unchanged', () async {
    expect(DiscordLinkService.instance.linked, isFalse);
    expect(
      await DailyLeaderboardService.linkedPocketDoneMs('2026-11-01'),
      isNull,
    );
    expect(DiscordLinkService.instance.pocketKey('anon'), 'anon');
  });
}

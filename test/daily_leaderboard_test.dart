import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:irodoku/models/daily_leaderboard.dart';
import 'package:irodoku/providers/achievements_provider.dart';
import 'package:irodoku/providers/settings_provider.dart';
import 'package:irodoku/providers/stats_provider.dart';
import 'package:irodoku/services/preferences_service.dart';
import 'package:irodoku/screens/daily_leaderboard_screen.dart';
import 'package:irodoku/widgets/win_dialog.dart';

void main() {
  test('DisplayName accepts short public names', () {
    expect(DisplayName.trySanitize('Alex'), 'Alex');
    expect(DisplayName.trySanitize('  ink_42  '), 'ink_42');
    expect(DisplayName.trySanitize('A'), isNull);
    expect(DisplayName.trySanitize('this name is way too long'), isNull);
    expect(DisplayName.trySanitize('1234567890'), '1234567890');
    expect(DisplayName.trySanitize('12345678901'), isNull);
    expect(DisplayName.trySanitize('bad!name'), isNull);
    expect(DisplayName.orFallback(''), DisplayName.fallback);
  });

  test('leaderboard ranks by time then submit order', () {
    const you = DailyLeaderboardEntry(
      uid: 'me',
      name: 'Me',
      ms: 120000,
      atMs: 9,
    );
    final board = DailyLeaderboardBoard.fromEntries(
      youUid: 'me',
      topN: 2,
      entries: [
        you,
        const DailyLeaderboardEntry(
          uid: 'a',
          name: 'Ada',
          ms: 60000,
          atMs: 1,
        ),
        const DailyLeaderboardEntry(
          uid: 'b',
          name: 'Bea',
          ms: 90000,
          atMs: 2,
        ),
      ],
    );
    expect(board.top, hasLength(2));
    expect(board.top.first.uid, 'a');
    expect(board.you?.uid, 'me');
    expect(board.youRank, 3);
  });

  test('formatLeaderboardTime is mm:ss', () {
    expect(formatLeaderboardTime(0), '00:00');
    expect(formatLeaderboardTime(54000), '00:54');
    expect(formatLeaderboardTime(125000), '02:05');
  });

  testWidgets('Daily Victory shows Rankings and Close, not Set name',
      (tester) async {
    SharedPreferences.setMockInitialValues({'sound_enabled': false});
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () {
                  showWinDialog(
                    context,
                    time: '01:23',
                    onNewGame: () {},
                    showNewGame: false,
                    leaderboardLabel: 'Rankings',
                    onLeaderboard: () {},
                  );
                },
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Victory'), findsOneWidget);
    expect(find.text('Rankings'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Set Name'), findsNothing);
  });

  testWidgets('Leaderboard asks for a name only when none is saved',
      (tester) async {
    SharedPreferences.setMockInitialValues({'sound_enabled': false});
    final prefs = await PreferencesService.create();
    final stats = StatsProvider(prefs);
    final achievements = AchievementsProvider(prefs);
    final settings = SettingsProvider(
      prefs,
      stats: stats,
      achievements: achievements,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<StatsProvider>.value(value: stats),
          ChangeNotifierProvider<AchievementsProvider>.value(
            value: achievements,
          ),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ],
        child: const MaterialApp(
          home: DailyLeaderboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Set Name'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);
    expect(find.text('Be the first today.'), findsNothing);
    expect(find.byTooltip('Main Menu'), findsOneWidget);
  });
}

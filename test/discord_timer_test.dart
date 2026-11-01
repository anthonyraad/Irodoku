import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:irodoku/discord/discord_leaderboard.dart';
import 'package:irodoku/discord/discord_mode.dart';
import 'package:irodoku/discord/discord_shell.dart';
import 'package:irodoku/providers/game_provider.dart';
import 'package:irodoku/screens/game_screen.dart';
import 'package:irodoku/services/preferences_service.dart';
import 'package:irodoku/widgets/first_run_tutorial.dart';

Future<void> _boot(WidgetTester tester, PreferencesService prefs) async {
  await tester.pumpWidget(DiscordIrodokuApp(preferences: prefs));
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _solve(GameProvider game) {
  final n = game.gridSize;
  for (var r = 0; r < n; r++) {
    for (var c = 0; c < n; c++) {
      if (!game.cells[r][c].isEditable) continue;
      game.selectCell(r, c);
      game.setSelectedColor(game.debugSolutionAt(r, c)!);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DiscordMode.enabled = true;
    DiscordMode.showLeaderboard.value = false;
    DiscordMode.myMs = null;
  });
  tearDown(() => DiscordMode.enabled = false);

  test('parseStartResponse', () {
    expect(parseStartResponse(null).done, isFalse);
    expect(parseStartResponse('{"ok":true,"start":1}').done, isFalse);
    final r = parseStartResponse('{"ok":true,"done":true,"ms":131000}');
    expect(r.done, isTrue);
    expect(r.ms, 131000);
    expect(parseStartResponse('garbage').done, isFalse);
  });

  testWidgets('Discord Pocket Daily timer counts on fresh storage', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'sound_enabled': false});
    final preferences = await PreferencesService.create();
    expect(preferences.firstRunTutorialCompleted, isFalse);

    await _boot(tester, preferences);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(FirstRunTutorialOverlay), findsNothing);
    expect(preferences.firstRunTutorialCompleted, isTrue);

    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('00:00'), findsNothing);
    expect(find.textContaining(RegExp(r'^00:0[1-9]$')), findsOneWidget);
  });

  testWidgets(
    'finishing offers "See today\'s leaderboard" (no replay) and reopening '
    'shows the leaderboard instead of the puzzle',
    (tester) async {
      SharedPreferences.setMockInitialValues({'sound_enabled': false});
      final preferences = await PreferencesService.create();
      await _boot(tester, preferences);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }

      final game = Provider.of<GameProvider>(
        tester.element(find.byType(GameScreen)),
        listen: false,
      );
      _solve(game);
      await _settle(tester);
      expect(game.isWon, isTrue);

      expect(find.text("See today's leaderboard"), findsOneWidget);
      expect(find.text('Next game'), findsNothing);
      await tester.tap(find.text("See today's leaderboard"));
      await _settle(tester);
      expect(find.byType(DiscordLeaderboardScreen), findsOneWidget);
      expect(find.byType(GameScreen), findsNothing);
      expect(find.byKey(const Key('discord-my-time')), findsOneWidget);

      // Reopen the Activity with the same storage: straight to the board.
      DiscordMode.showLeaderboard.value = false;
      DiscordMode.myMs = null;
      await tester.pumpWidget(const SizedBox());
      await _boot(tester, preferences);
      await _settle(tester);
      expect(find.byType(DiscordLeaderboardScreen), findsOneWidget);
      expect(find.byType(GameScreen), findsNothing);
    },
  );
}

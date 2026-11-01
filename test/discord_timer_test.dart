import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:irodoku/discord/discord_mode.dart';
import 'package:irodoku/discord/discord_shell.dart';
import 'package:irodoku/services/preferences_service.dart';
import 'package:irodoku/widgets/first_run_tutorial.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => DiscordMode.enabled = false);

  testWidgets('Discord Pocket Daily timer counts on fresh storage',
      (tester) async {
    DiscordMode.enabled = true;
    SharedPreferences.setMockInitialValues({});
    final preferences = await PreferencesService.create();
    expect(preferences.firstRunTutorialCompleted, isFalse);

    await tester.pumpWidget(DiscordIrodokuApp(preferences: preferences));
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(FirstRunTutorialOverlay), findsNothing);
    expect(preferences.firstRunTutorialCompleted, isTrue);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('00:00'), findsNothing);
    expect(find.textContaining(RegExp(r'^00:0[1-9]$')), findsOneWidget);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:irodoku/app.dart';
import 'package:irodoku/services/preferences_service.dart';
import 'package:irodoku/widgets/first_run_tutorial.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fresh prefs have not completed the first-run tutorial', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await PreferencesService.create();
    expect(prefs.firstRunTutorialCompleted, isFalse);
  });

  test('returning players with games played skip the overlay', () async {
    SharedPreferences.setMockInitialValues({'stats_games_played': 4});
    final prefs = await PreferencesService.create();
    expect(prefs.firstRunTutorialCompleted, isTrue);
  });

  test('explicit incomplete flag still shows after a started game', () async {
    SharedPreferences.setMockInitialValues({
      'first_run_tutorial_completed': false,
      'stats_games_played': 1,
    });
    final prefs = await PreferencesService.create();
    expect(prefs.firstRunTutorialCompleted, isFalse);
  });

  testWidgets('first-time launch shows typed tutorial over the game screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await PreferencesService.create();

    await tester.pumpWidget(IrodokuApp(preferences: preferences));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.byType(FirstRunTutorialOverlay), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    expect(
      find.text(FirstRunTutorialOverlay.steps.first),
      findsWidgets,
    );
    expect(find.text('00:00'), findsOneWidget);
  });

  testWidgets('tapping completes typing then advances through three steps',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await PreferencesService.create();

    await tester.pumpWidget(IrodokuApp(preferences: preferences));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    Future<void> tapAdvance() async {
      await tester.tap(find.byType(FirstRunTutorialOverlay));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
    }

    await tapAdvance();
    expect(find.text(FirstRunTutorialOverlay.steps[0]), findsWidgets);
    await tapAdvance();
    await tapAdvance();
    expect(find.text(FirstRunTutorialOverlay.steps[1]), findsWidgets);
    await tapAdvance();
    await tapAdvance();
    expect(find.textContaining("let's get started!"), findsWidgets);
    await tapAdvance();
    await tester.pump(const Duration(milliseconds: 280));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(FirstRunTutorialOverlay), findsNothing);
    expect(preferences.firstRunTutorialCompleted, isTrue);
  });
}

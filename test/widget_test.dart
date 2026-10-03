import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:irodoku/app.dart';
import 'package:irodoku/services/preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Irodoku app shows title and game chrome', (tester) async {
    SharedPreferences.setMockInitialValues({
      'first_run_tutorial_completed': true,
    });
    final preferences = await PreferencesService.create();

    await tester.pumpWidget(IrodokuApp(preferences: preferences));
    await tester.pump();
    // TypingTitle waits a frame then types "Irodoku" at 30ms/char.
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Irodoku'), findsOneWidget);
    expect(find.byTooltip('Main Menu'), findsOneWidget);
    expect(find.byTooltip('New game'), findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);

    // Allow background generation isolate to settle without failing the test.
    await tester.pump(const Duration(milliseconds: 100));
  });
}

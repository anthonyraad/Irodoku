import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irodoku/widgets/age_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime(2026, 11, 1);

class _Harness extends StatelessWidget {
  const _Harness(this.results, {this.feature = AgeGateFeature.discordSync});
  final List<bool> results;
  final AgeGateFeature feature;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  results.add(await ensureAgeOk(context, feature, now: _now)),
              child: const Text('go'),
            ),
          ),
        ),
      );
}

FilledButton _continue(WidgetTester t) => t.widget<FilledButton>(
    find.ancestor(of: find.text('Continue'), matching: find.byType(FilledButton)));

Future<void> _pick(WidgetTester t, int year) async {
  await t.tap(find.text('Select year'));
  await t.pumpAndSettle();
  final item = find.descendant(
      of: find.byType(Scrollable).last, matching: find.text('$year'));
  await t.scrollUntilVisible(item, 48, scrollable: find.byType(Scrollable).last);
  await t.pumpAndSettle();
  await t.tap(item, warnIfMissed: false);
  await t.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('rule: currentYear - birthYear >= 13', () {
    expect(AgeGate.isOldEnough(2013, now: _now), isTrue);
    expect(AgeGate.isOldEnough(2014, now: _now), isFalse);
  });

  testWidgets('no preselect; Continue disabled until a year is picked',
      (t) async {
    final r = <bool>[];
    await t.pumpWidget(_Harness(r));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text('What year were you born?'), findsOneWidget);
    expect(find.text('Select year'), findsOneWidget);
    final dd = t.widget<DropdownButton<int>>(find.byType(DropdownButton<int>));
    expect(dd.value, isNull);
    expect(dd.items!.first.value, 2026);
    expect(dd.items!.last.value, 1926);
    expect(_continue(t).onPressed, isNull);
    await _pick(t, 2013);
    expect(_continue(t).onPressed, isNotNull);
  });

  testWidgets('2013 passes and is saved; never asked again', (t) async {
    final r = <bool>[];
    await t.pumpWidget(_Harness(r));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    await _pick(t, 2013);
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    expect(r, [true]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(AgeGate.prefBirthYear), 2013);
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text('What year were you born?'), findsNothing);
    expect(r, [true, true]);
  });

  testWidgets('2014 blocked with exact message; not re-asked', (t) async {
    final r = <bool>[];
    await t.pumpWidget(_Harness(r));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    await _pick(t, 2014);
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    expect(
        find.text('No worries! Discord sync is intended for players that are '
            '13+, but you can keep enjoying the rest of Irodoku.'),
        findsOneWidget);
    await t.tap(find.text('Got it'));
    await t.pumpAndSettle();
    expect(r, [false]);
    expect((await SharedPreferences.getInstance()).getInt(AgeGate.prefBirthYear),
        2014);
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text('What year were you born?'), findsNothing);
    expect(find.textContaining('No worries!'), findsOneWidget);
  });

  testWidgets('graffiti variant message', (t) async {
    SharedPreferences.setMockInitialValues({AgeGate.prefBirthYear: 2014});
    await t.pumpWidget(_Harness(<bool>[], feature: AgeGateFeature.graffitiRooms));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(
        find.text('No worries! Graffiti online rooms are intended for players '
            'that are 13+, but you can keep enjoying the rest of Irodoku.'),
        findsOneWidget);
  });

  testWidgets('Not now saves nothing and asks again next time', (t) async {
    final r = <bool>[];
    await t.pumpWidget(_Harness(r));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    await _pick(t, 2000);
    await t.tap(find.text('Not now'));
    await t.pumpAndSettle();
    expect(r, [false]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(AgeGate.prefBirthYear), isFalse);
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text('What year were you born?'), findsOneWidget);
  });

  group('Discord Activity (Graffiti / Pocket Daily Iro)', () {
    tearDown(() => AgeGate.inDiscordActivity = false);

    test('default off (Android/web app still gated)', () {
      expect(AgeGate.inDiscordActivity, isFalse);
    });

    for (final f in AgeGateFeature.values) {
      testWidgets('skips the age step for ${f.name}, saves nothing', (t) async {
        AgeGate.inDiscordActivity = true;
        final r = <bool>[];
        await t.pumpWidget(_Harness(r, feature: f));
        await t.tap(find.text('go'));
        await t.pumpAndSettle();
        expect(find.text('What year were you born?'), findsNothing);
        expect(r, [true]);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getInt(AgeGate.prefBirthYear), isNull);
      });
    }

    testWidgets('skip also wins over a stored under-13 year', (t) async {
      SharedPreferences.setMockInitialValues({AgeGate.prefBirthYear: 2014});
      AgeGate.inDiscordActivity = true;
      final r = <bool>[];
      await t.pumpWidget(_Harness(r, feature: AgeGateFeature.graffitiRooms));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(r, [true]);
    });
  });
}

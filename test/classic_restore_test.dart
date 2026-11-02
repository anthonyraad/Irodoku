import 'package:flutter_test/flutter_test.dart';
import 'package:irodoku/models/daily_irodoku.dart';
import 'package:irodoku/models/difficulty.dart';
import 'package:irodoku/providers/achievements_provider.dart';
import 'package:irodoku/providers/game_provider.dart';
import 'package:irodoku/providers/settings_provider.dart';
import 'package:irodoku/providers/stats_provider.dart';
import 'package:irodoku/services/preferences_service.dart';
import 'package:irodoku/services/sound_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fresh provider over the current mock SharedPreferences ("cold start").
Future<GameProvider> _coldProvider() async {
  final prefs = await PreferencesService.create();
  final stats = StatsProvider(prefs);
  final achievements = AchievementsProvider(prefs);
  final settings = SettingsProvider(
    prefs,
    stats: stats,
    achievements: achievements,
  );
  return GameProvider(
    settings: settings,
    stats: stats,
    achievements: achievements,
    preferences: prefs,
    sounds: SoundService(),
  );
}

List<(int, int)> _editable(GameProvider g) => [
  for (var r = 0; r < g.gridSize; r++)
    for (var c = 0; c < g.gridSize; c++)
      if (g.cellAt(r, c).isEditable) (r, c),
];

List<List<int>> _classicBoards() =>
    generatePuzzleIsolate(<Object>[Difficulty.easy.storageKey, 42]);

String _snapshot(GameProvider g) => [
  for (var r = 0; r < g.gridSize; r++)
    for (var c = 0; c < g.gridSize; c++)
      '${g.cellAt(r, c).value}:${(g.cellAt(r, c).notes.toList()..sort()).join(',')}',
].join('|');

/// Live Classic board with a fill, a mistake, two notes and 0:95 on the clock.
Future<(GameProvider, String)> _playClassic({String? dailyDayKey}) async {
  final a = await _coldProvider();
  a.debugLoadBoards(_classicBoards(), pocket: false, dailyDayKey: dailyDayKey);
  final cells = _editable(a);
  final (r0, c0) = cells[0];
  final (r1, c1) = cells[1];
  final (r2, c2) = cells[2];
  a.selectCell(r0, c0);
  a.applyPickerColor(a.debugSolutionAt(r0, c0)!);
  final wrong = a.debugSolutionAt(r1, c1) == 1 ? 2 : 1;
  a.selectCell(r1, c1);
  a.applyPickerColor(wrong);
  a.selectCell(r2, c2);
  a.toggleNoteMode();
  a.applyPickerColor(4);
  a.applyPickerColor(7);
  a.toggleNoteMode();
  a.debugSetElapsed(const Duration(seconds: 95));
  expect(a.mistakes, 1);
  expect(a.cellAt(r2, c2).notes, containsAll(<int>[4, 7]));
  return (a, _snapshot(a));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'sound_enabled': false});
  });

  test('live Classic survives a cold restart without pausing', () async {
    final (a, before) = await _playClassic();
    await a.persistLiveGameForBackground(); // backgrounded, then killed

    final b = await _coldProvider();
    await b.bootstrap();
    expect(b.isPocket, isFalse);
    expect(_snapshot(b), before);
    expect(b.mistakes, 1);
    expect(b.elapsed, const Duration(seconds: 95));
  });

  test('Classic and Pocket both survive one kill', () async {
    final (c, classic) = await _playClassic();
    await c.persistLiveGameForBackground();
    // Pocket written by a second session (Classic parked in the slot above).
    final p = await _coldProvider();
    p.debugLoadBoards(generatePocketIsolate(7), pocket: true);
    final (r, col) = _editable(p).first;
    p.selectCell(r, col);
    p.toggleNoteMode();
    p.applyPickerColor(2);
    final pocket = _snapshot(p);
    await p.persistLiveGameForBackground();

    final b = await _coldProvider();
    await b.bootstrap();
    expect(_snapshot(b), classic);
    await b.openPocketGame();
    expect(b.isPocket, isTrue);
    expect(_snapshot(b), pocket);
  });

  test('foreground again drops the Classic background copy', () async {
    final (a, _) = await _playClassic();
    await a.persistLiveGameForBackground();
    expect(
      (await PreferencesService.create()).loadParkedRegularGame(),
      isNotNull,
    );
    await a.onAppForeground();
    expect((await PreferencesService.create()).loadParkedRegularGame(), isNull);
  });

  test('paused Classic is not duplicated into the parked slot', () async {
    final (a, _) = await _playClassic();
    await a.pauseGame();
    await a.persistLiveGameForBackground();
    final p = await PreferencesService.create();
    expect(p.loadPausedGame(), isNotNull);
    expect(p.loadParkedRegularGame(), isNull);
  });

  test('in-progress Daily is saved to the Daily slot only', () async {
    final today = DailyIrodoku.forDate().dayKey;
    final (a, _) = await _playClassic(dailyDayKey: today);
    await a.persistLiveGameForBackground();
    final p = await PreferencesService.create();
    expect(p.loadParkedDailyGame()?.dailyDayKey, today);
    expect(p.loadParkedRegularGame(), isNull);
  });

  test('Daily already completed today is never written back', () async {
    final today = DailyIrodoku.forDate().dayKey;
    final raw = await SharedPreferences.getInstance();
    await raw.setString('daily_last_completed_day', today);
    final (a, _) = await _playClassic(dailyDayKey: today);
    await a.persistLiveGameForBackground();
    expect((await PreferencesService.create()).loadParkedDailyGame(), isNull);
  });

  test('finished (lost) Classic is not saved', () async {
    final a = await _coldProvider();
    a.debugLoadBoards(_classicBoards(), pocket: false);
    final cells = _editable(a);
    for (var i = 0; i < 6 && !a.isGameOver; i++) {
      final (r, c) = cells[i];
      a.selectCell(r, c);
      a.applyPickerColor(a.debugSolutionAt(r, c) == 1 ? 2 : 1);
    }
    expect(a.isGameOver, isTrue);
    await a.persistLiveGameForBackground();
    expect((await PreferencesService.create()).loadParkedRegularGame(), isNull);
  });

  for (final corrupt in <bool>[false, true]) {
    test(
      '${corrupt ? 'corrupt' : 'missing'} Classic save starts fresh',
      () async {
        if (corrupt) {
          final raw = await SharedPreferences.getInstance();
          await raw.setString('parked_regular_game', '{oops');
        }
        final b = await _coldProvider();
        await b.bootstrap();
        expect(b.isPocket, isFalse);
        expect(b.hasActiveGame, isTrue);
        expect(b.mistakes, 0);
        expect(b.elapsed, Duration.zero);
        expect(
          _editable(b).every((rc) => b.cellAt(rc.$1, rc.$2).value == 0),
          isTrue,
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}

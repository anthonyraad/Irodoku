import 'package:flutter_test/flutter_test.dart';
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

List<List<int>> _pocketBoards() => generatePocketIsolate(42);
List<List<int>> _classicBoards() =>
    generatePuzzleIsolate(<Object>[Difficulty.easy.storageKey, 42]);

String _snapshot(GameProvider g) => [
  for (var r = 0; r < g.gridSize; r++)
    for (var c = 0; c < g.gridSize; c++)
      '${g.cellAt(r, c).value}:${(g.cellAt(r, c).notes.toList()..sort()).join(',')}',
].join('|');

/// Paused Classic in paused_game so bootstrap restores it without generating.
Future<String> _seedPausedClassic() async {
  final c = await _coldProvider();
  c.debugLoadBoards(_classicBoards(), pocket: false);
  final (r, col) = _editable(c).first;
  c.selectCell(r, col);
  c.applyPickerColor(c.debugSolutionAt(r, col)!);
  c.debugSetElapsed(const Duration(seconds: 77));
  await c.pauseGame();
  return _snapshot(c);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'sound_enabled': false});
  });

  test(
    'Pocket fills, notes, mistakes and timer survive a cold restart',
    () async {
      final classic = await _seedPausedClassic();

      final a = await _coldProvider();
      a.debugLoadBoards(_pocketBoards(), pocket: true);
      final cells = _editable(a);
      final (r0, c0) = cells[0];
      final (r1, c1) = cells[1];
      final (r2, c2) = cells[2];
      a.selectCell(r0, c0);
      a.applyPickerColor(a.debugSolutionAt(r0, c0)!); // correct fill
      final wrong = a.debugSolutionAt(r1, c1)! == 1 ? 2 : 1;
      a.selectCell(r1, c1);
      a.applyPickerColor(wrong); // mistake
      a.selectCell(r2, c2);
      a.toggleNoteMode();
      a.applyPickerColor(3);
      a.applyPickerColor(5);
      a.toggleNoteMode();
      a.debugSetElapsed(const Duration(seconds: 123));
      expect(a.mistakes, 1);
      final before = _snapshot(a);
      expect(a.cellAt(r2, c2).notes, containsAll(<int>[3, 5]));

      await a.persistLivePocketForBackground(); // app backgrounded, then killed

      final b = await _coldProvider();
      await b.bootstrap();
      expect(b.isPocket, isFalse, reason: 'cold start still lands on Classic');
      expect(_snapshot(b), classic, reason: 'Classic restore unaffected');
      expect(b.elapsed, const Duration(seconds: 77));

      await b.openPocketGame();
      expect(b.isPocket, isTrue);
      expect(_snapshot(b), before);
      expect(b.mistakes, 1);
      expect(b.elapsed, const Duration(seconds: 123));
    },
  );

  test(
    'foreground again drops the background copy (no resurrection)',
    () async {
      final a = await _coldProvider();
      a.debugLoadBoards(_pocketBoards(), pocket: true);
      await a.persistLivePocketForBackground();
      final prefs = await PreferencesService.create();
      expect(prefs.loadParkedPocketGame(), isNotNull);
      await a.onAppForeground();
      expect(
        (await PreferencesService.create()).loadParkedPocketGame(),
        isNull,
      );
    },
  );

  test('Classic live game does not write any Pocket key', () async {
    final a = await _coldProvider();
    a.debugLoadBoards(_classicBoards(), pocket: false);
    await a.persistLivePocketForBackground();
    final p = await PreferencesService.create();
    expect(p.loadParkedPocketGame(), isNull);
    expect(p.loadParkedPocketDailyGame(), isNull);
    expect(p.loadParkedPocketChromaticGame(), isNull);
    expect(p.loadPausedGame(), isNull);
  });

  for (final corrupt in <bool>[false, true]) {
    test(
      '${corrupt ? 'corrupt' : 'missing'} Pocket save starts a new game',
      () async {
        final classic = await _seedPausedClassic();
        if (corrupt) {
          final raw = await SharedPreferences.getInstance();
          await raw.setString('parked_pocket_game', '{not json');
        }
        final b = await _coldProvider();
        await b.bootstrap();
        expect(_snapshot(b), classic);
        await b.openPocketGame();
        expect(b.isPocket, isTrue);
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

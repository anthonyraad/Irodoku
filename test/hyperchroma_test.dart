import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irodoku/models/difficulty.dart';
import 'package:irodoku/models/game_palette.dart';
import 'package:irodoku/models/hyperchroma.dart';
import 'package:irodoku/models/player_xp.dart';
import 'package:irodoku/providers/achievements_provider.dart';
import 'package:irodoku/providers/game_provider.dart';
import 'package:irodoku/providers/settings_provider.dart';
import 'package:irodoku/providers/stats_provider.dart';
import 'package:irodoku/services/preferences_service.dart';
import 'package:irodoku/services/sound_service.dart';
import 'package:irodoku/widgets/hyperchroma_menu_button.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'sound_enabled': false});
  });

  test('every correct fill banks the same time, and a mistake costs more', () {
    expect(HyperchromaRules.startSeconds, 60);
    expect(HyperchromaRules.gainSeconds, 10);
    expect(
      HyperchromaRules.mistakePenaltySeconds,
      greaterThan(HyperchromaRules.gainSeconds),
    );
  });

  test('difficulty climbs to Master and then repeats it', () {
    expect(HyperchromaRules.difficultyForBoard(0), Difficulty.easy);
    expect(HyperchromaRules.difficultyForBoard(1), Difficulty.medium);
    expect(HyperchromaRules.difficultyForBoard(4), Difficulty.master);
    expect(HyperchromaRules.difficultyForBoard(5), Difficulty.master);
    expect(HyperchromaRules.victoryLabel(1), 'Easy');
    expect(HyperchromaRules.victoryLabel(4), 'Expert');
    expect(HyperchromaRules.victoryLabel(5), 'Master');
    expect(HyperchromaRules.victoryLabel(7), 'Master ×3');
  });

  test('XP is cleared-board base plus a fraction of the board in progress', () {
    final earned = HyperchromaRules.xp(
      boardsCleared: 2,
      filledOnCurrent: 10,
      emptyOnCurrent: 40,
    );
    // Easy 100 + Medium 200 + 10/40 of Hard 350.
    expect(earned, 100 + 200 + (350 * 10 ~/ 40));

    final award = PlayerXp.hyperchroma(earned: earned, previousTotal: 20);
    expect(award.breakdown, [(label: 'Hyperchroma', xp: earned)]);
    expect(award.newTotal, 20 + earned);
    expect(award.chromatic, isFalse);
    expect(award.lucky, isFalse);
  });

  test(
    'a correct fill hops the palette and banks time; a mistake only costs time',
    () async {
      final game = await _game();
      addTearDown(game.dispose);
      game.debugQueueHyperchromaBoards([
        generatePuzzleIsolate(<Object>[Difficulty.easy.storageKey, 3]),
      ]);
      await game.debugBeginHyperchroma();

      expect(game.isHyperchroma, isTrue);
      expect(game.formatElapsed(), '01:00');
      expect(game.mistakes, 0);
      expect(game.activePalette, GamePalette.standard);

      final (row, col) = _editable(game).first;
      game.selectCell(row, col);
      game.toggleNoteMode();
      game.applyPickerColor(4);
      expect(game.hyperchromaSeconds, HyperchromaRules.startSeconds);
      game.toggleNoteMode();

      final wrong = _otherColor(game.debugSolutionAt(row, col)!);
      game.applyPickerColor(wrong);
      expect(game.mistakes, 0);
      expect(game.isLost, isFalse);
      expect(game.hyperchromaSeconds, HyperchromaRules.startSeconds - 12);
      expect(game.activePalette, GamePalette.standard);
      expect(game.hyperchromaPulse, -12);

      game.undo();
      expect(game.cellAt(row, col).value, 0);
      expect(game.hyperchromaSeconds, HyperchromaRules.startSeconds - 12);

      game.applyPickerColor(game.debugSolutionAt(row, col)!);
      expect(game.activePalette, isNot(GamePalette.standard));
      expect(game.hyperchromaPulse, HyperchromaRules.gainSeconds);
      expect(
        game.hyperchromaSeconds,
        HyperchromaRules.startSeconds - 12 + HyperchromaRules.gainSeconds,
      );

      game.debugTickClock();
      expect(game.hyperchromaPulse, 0);
      expect(
        game.hyperchromaSeconds,
        HyperchromaRules.startSeconds -
            12 +
            HyperchromaRules.gainSeconds -
            1,
      );
    },
  );

  test('the clock can absorb several mistakes before the run ends', () async {
    final game = await _game();
    addTearDown(game.dispose);
    game.debugQueueHyperchromaBoards([
      generatePuzzleIsolate(<Object>[Difficulty.easy.storageKey, 4]),
    ]);
    await game.debugBeginHyperchroma();

    final cells = _editable(game);
    for (var i = 0; i < 4; i++) {
      final (row, col) = cells[i];
      game.selectCell(row, col);
      game.applyPickerColor(_otherColor(game.debugSolutionAt(row, col)!));
    }
    expect(game.isGameOver, isFalse);
    expect(game.mistakes, 0);
    expect(game.hyperchromaSeconds, HyperchromaRules.startSeconds - 12 * 4);

    final (row, col) = cells[4];
    game.selectCell(row, col);
    game.applyPickerColor(_otherColor(game.debugSolutionAt(row, col)!));
    expect(game.isLost, isTrue);
    expect(game.isWon, isFalse);
    expect(game.hyperchromaSeconds, 0);
  });

  test(
    'time running out before the first clear is a defeat with no XP',
    () async {
      final stats = StatsProvider(await PreferencesService.create());
      final game = await _game(stats: stats);
      addTearDown(game.dispose);
      game.debugQueueHyperchromaBoards([
        generatePuzzleIsolate(<Object>[Difficulty.easy.storageKey, 5]),
      ]);
      await game.debugBeginHyperchroma();
      for (var i = 0; i < HyperchromaRules.startSeconds; i++) {
        game.debugTickClock();
      }
      expect(game.isLost, isTrue);
      expect(stats.stats.totalXp, 0);
      expect(stats.lastXpAward, isNull);
    },
  );

  test(
    'clearing a board keeps the bank and raises the next difficulty',
    () async {
      final game = await _game();
      addTearDown(game.dispose);
      final first = generatePuzzleIsolate(<Object>[
        Difficulty.easy.storageKey,
        8,
      ]);
      final second = generatePuzzleIsolate(<Object>[
        Difficulty.medium.storageKey,
        9,
      ]);
      game.debugQueueHyperchromaBoards([first, second]);
      await game.debugBeginHyperchroma();
      final empty = _editable(game).length;

      _solve(game);
      await game.debugSettleHyperchroma();

      expect(game.difficulty, Difficulty.medium);
      expect(game.hyperchromaBoardsCleared, 1);
      expect(game.isGameOver, isFalse);
      expect(
        game.hyperchromaSeconds,
        HyperchromaRules.startSeconds + HyperchromaRules.gainSeconds * empty,
      );

      final (row, col) = _editable(game).first;
      final before = game.hyperchromaSeconds;
      game.selectCell(row, col);
      game.applyPickerColor(game.debugSolutionAt(row, col)!);
      expect(game.hyperchromaSeconds, before + HyperchromaRules.gainSeconds);
    },
  );

  test('a cleared board turns a timeout into Hyperchroma XP', () async {
    final stats = StatsProvider(await PreferencesService.create());
    final game = await _game(stats: stats);
    addTearDown(game.dispose);
    game.debugQueueHyperchromaBoards([
      generatePuzzleIsolate(<Object>[Difficulty.easy.storageKey, 11]),
    ]);
    await game.debugBeginHyperchroma();
    game.debugSetHyperchromaProgress(
      boardsCleared: 1,
      filledOnCurrent: 10,
      emptyOnCurrent: 40,
    );
    for (var i = 0; i < HyperchromaRules.startSeconds; i++) {
      game.debugTickClock();
    }

    expect(game.isWon, isTrue);
    expect(game.isLost, isFalse);
    final earned = HyperchromaRules.xp(
      boardsCleared: 1,
      filledOnCurrent: 10,
      emptyOnCurrent: 40,
    );
    expect(stats.stats.totalXp, earned);
    expect(stats.lastXpAward?.breakdown, [(label: 'Hyperchroma', xp: earned)]);
    expect(game.hyperchromaProgressLabel, 'Easy');
  });

  test('Hyperchroma parks the live puzzle and does not overwrite it', () async {
    SharedPreferences.setMockInitialValues({
      'sound_enabled': false,
      'dev_mode': true,
    });
    final game = await _game();
    addTearDown(game.dispose);
    game.debugLoadBoards(
      generatePuzzleIsolate(<Object>[Difficulty.easy.storageKey, 15]),
      pocket: false,
    );
    final cells = _editable(game);
    final (r0, c0) = cells[0];
    final (r1, c1) = cells[1];
    game.selectCell(r0, c0);
    game.applyPickerColor(game.debugSolutionAt(r0, c0)!);
    game.selectCell(r1, c1);
    game.applyPickerColor(_otherColor(game.debugSolutionAt(r1, c1)!));
    game.debugSetElapsed(const Duration(seconds: 40));
    final snapshot = _snapshot(game);
    await game.persistLiveGameForBackground();

    game.debugQueueHyperchromaBoards([
      generatePuzzleIsolate(<Object>[Difficulty.easy.storageKey, 16]),
    ]);
    final started = await game.openHyperchromaGame();
    expect(started, isTrue);
    expect(game.isHyperchroma, isTrue);
    await game.persistLiveGameForBackground();

    final restored = await _game();
    addTearDown(restored.dispose);
    await restored.bootstrap();
    expect(restored.isHyperchroma, isFalse);
    expect(_snapshot(restored), snapshot);
    expect(restored.mistakes, 1);
    expect(restored.elapsed, const Duration(seconds: 40));

    await game.openClassicGame();
    expect(game.isHyperchroma, isFalse);
    expect(_snapshot(game), snapshot);
    expect(game.mistakes, 1);
  });

  testWidgets('holding Chromatic morphs it into Hyperchroma', (tester) async {
    final taps = <String>[];
    await _pumpButton(
      tester,
      onChromatic: () => taps.add('chromatic'),
      onHyperchroma: () => taps.add('hyper'),
    );

    await tester.tap(find.text('Chromatic'));
    await tester.pump();
    expect(taps, ['chromatic']);

    taps.clear();
    final held = await tester.startGesture(
      tester.getCenter(find.text('Chromatic')),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await held.up();
    await tester.pump();
    expect(find.text('Chromatic'), findsOneWidget);
    expect(taps, isEmpty);

    final arm = await tester.startGesture(
      tester.getCenter(find.text('Chromatic')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pump();
    expect(find.text('Hyperchroma'), findsOneWidget);
    await arm.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(taps, isEmpty);

    await tester.tap(find.text('Hyperchroma'));
    await tester.pump();
    expect(taps, ['hyper']);
  });

  testWidgets('leaving the button host restores Chromatic', (tester) async {
    final hold = ValueNotifier(true);
    addTearDown(hold.dispose);
    await _pumpButton(tester, hold: hold);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Chromatic')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pump();
    expect(find.text('Hyperchroma'), findsOneWidget);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 200));

    hold.value = false;
    await tester.pump();
    expect(find.text('Chromatic'), findsOneWidget);
    expect(find.text('Hyperchroma'), findsNothing);
  });
}

Future<GameProvider> _game({StatsProvider? stats}) async {
  final prefs = await PreferencesService.create();
  final statsProvider = stats ?? StatsProvider(prefs);
  final achievements = AchievementsProvider(prefs);
  final settings = SettingsProvider(
    prefs,
    stats: statsProvider,
    achievements: achievements,
  );
  return GameProvider(
    settings: settings,
    stats: statsProvider,
    achievements: achievements,
    preferences: prefs,
    sounds: SoundService(),
  );
}

List<(int, int)> _editable(GameProvider game) => [
  for (var r = 0; r < game.gridSize; r++)
    for (var c = 0; c < game.gridSize; c++)
      if (game.cellAt(r, c).isEditable) (r, c),
];

int _otherColor(int solution) => (solution % 9) + 1;

void _solve(GameProvider game) {
  for (final (row, col) in _editable(game)) {
    game.selectCell(row, col);
    game.applyPickerColor(game.debugSolutionAt(row, col)!);
  }
}

String _snapshot(GameProvider game) => [
  for (var r = 0; r < game.gridSize; r++)
    for (var c = 0; c < game.gridSize; c++) game.cellAt(r, c).value,
].join(',');

Future<void> _pumpButton(
  WidgetTester tester, {
  VoidCallback? onChromatic,
  VoidCallback? onHyperchroma,
  ValueNotifier<bool>? hold,
}) async {
  SharedPreferences.setMockInitialValues({'sound_enabled': false});
  final prefs = await PreferencesService.create();
  final stats = StatsProvider(prefs);
  final settings = SettingsProvider(
    prefs,
    stats: stats,
    achievements: AchievementsProvider(prefs),
  );
  final holdListenable = hold;
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: stats),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: holdListenable == null
              ? HyperchromaMenuButton(
                  label: 'Chromatic',
                  holdEnabled: true,
                  onPressed: onChromatic ?? () {},
                  onHyperchroma: onHyperchroma ?? () {},
                )
              : ValueListenableBuilder<bool>(
                  valueListenable: holdListenable,
                  builder: (context, enabled, _) {
                    return HyperchromaMenuButton(
                      label: 'Chromatic',
                      holdEnabled: enabled,
                      onPressed: onChromatic ?? () {},
                      onHyperchroma: onHyperchroma ?? () {},
                    );
                  },
                ),
        ),
      ),
    ),
  );
}

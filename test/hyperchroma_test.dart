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
      expect(game.hyperchromaLevelLabel, 'Level 1');
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
      expect(game.hyperchromaScore, 0);
      expect(game.hyperchromaSeconds, HyperchromaRules.startSeconds - 12);
      expect(game.activePalette, GamePalette.standard);
      expect(game.hyperchromaPulse, -12);

      game.undo();
      expect(game.cellAt(row, col).value, 0);
      expect(game.hyperchromaSeconds, HyperchromaRules.startSeconds - 12);

      game.applyPickerColor(game.debugSolutionAt(row, col)!);
      expect(game.hyperchromaScore, 1);
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
      expect(game.hyperchromaLevelLabel, 'Level 2');
      expect(game.hyperchromaScore, empty);
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
      expect(game.hyperchromaScore, empty + 1);
    },
  );

  test('a finished box grants a sketch that carries onto the next board', () async {
    final game = await _game();
    addTearDown(game.dispose);
    game.debugQueueHyperchromaBoards([
      generatePuzzleIsolate(<Object>[Difficulty.easy.storageKey, 21]),
      generatePuzzleIsolate(<Object>[Difficulty.medium.storageKey, 22]),
    ]);
    await game.debugBeginHyperchroma();

    expect(game.hyperchromaSketches, 0);
    expect(game.useSketch(0, 1), isFalse);
    expect(game.hyperchromaSketches, 0);

    final openAtStart = _openBoxes(game).length;
    _fillBox(game, _openBoxes(game).first);
    expect(game.hyperchromaSketches, 1);

    _solve(game);
    await game.debugSettleHyperchroma();
    expect(game.hyperchromaLevelLabel, 'Level 2');
    expect(game.hyperchromaSketches, openAtStart);
  });

  test('a sketch fills every candidate cell of that color in the box', () async {
    final game = await _game();
    addTearDown(game.dispose);
    game.debugQueueHyperchromaBoards([
      generatePuzzleIsolate(<Object>[Difficulty.easy.storageKey, 23]),
    ]);
    await game.debugBeginHyperchroma();

    _fillBox(game, _openBoxes(game).first);
    expect(game.hyperchromaSketches, 1);
    final box = _openBoxes(game).first;

    (int, List<(int, int)>)? pick;
    for (var value = 1; value <= game.gridSize; value++) {
      final cells = _sketchCandidates(game, box, value);
      if (cells.isEmpty) continue;
      if (pick == null || cells.length < pick.$2.length) {
        pick = (value, cells);
      }
    }
    expect(pick, isNotNull);
    final value = pick!.$1;
    final cells = pick.$2;
    final before = game.hyperchromaSeconds;
    final score = game.hyperchromaScore;
    final outside = <(int, int), int>{
      for (var r = 0; r < game.gridSize; r++)
        for (var c = 0; c < game.gridSize; c++)
          if (!_boxCells(game, box).contains((r, c)))
            (r, c): game.cellAt(r, c).value,
    };

    expect(game.useSketch(box, value), isTrue);

    for (final (row, col) in cells) {
      final cell = game.cellAt(row, col);
      expect(cell.value, 0);
      expect(cell.hasNote(value), isTrue);
      expect(cell.isLocked, isFalse);
    }
    expect(game.hyperchromaScore, score);
    expect(game.hyperchromaSeconds, before);
    expect(game.hyperchromaSketches, 0);
    for (final entry in outside.entries) {
      expect(game.cellAt(entry.key.$1, entry.key.$2).value, entry.value);
      expect(game.cellAt(entry.key.$1, entry.key.$2).hasNote(value), isFalse);
    }

    game.undo();
    for (final (row, col) in cells) {
      expect(game.cellAt(row, col).hasNote(value), isFalse);
    }
    expect(game.hyperchromaSketches, 0);
  });

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
    expect(game.hyperchromaScore, 0);
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

  test('the shop keeps the clock running and sells Steadfast', () async {
    final game = await _game();
    addTearDown(game.dispose);
    game.debugQueueHyperchromaBoards([
      generatePuzzleIsolate(<Object>[Difficulty.easy.storageKey, 11]),
    ]);
    await game.debugBeginHyperchroma();
    game.debugGrantSketches(3);
    final before = game.hyperchromaSeconds;
    await game.pauseGame();
    expect(game.isPaused, isTrue);
    game.debugTickClock();
    expect(game.isPaused, isTrue);
    expect(game.hyperchromaSeconds, before - 1);

    expect(
      game.buyHyperchromaEffect(HyperchromaEffect.telepathy),
      isFalse,
    );
    expect(game.isPaused, isTrue);
    expect(game.hyperchromaSketches, 3);

    final palette = game.activePalette;
    expect(game.buyHyperchromaEffect(HyperchromaEffect.steadfast), isTrue);
    expect(game.isPaused, isFalse);
    expect(game.hyperchromaSketches, 0);
    expect(game.activePalette, palette);

    for (var i = 0; i < HyperchromaRules.steadfastFills; i++) {
      final cell = _safeEmpty(game);
      expect(cell, isNotNull);
      game.selectCell(cell!.$1, cell.$2);
      game.applyPickerColor(game.debugSolutionAt(cell.$1, cell.$2)!);
      expect(game.activePalette, palette);
    }
    final next = _safeEmpty(game);
    expect(next, isNotNull);
    game.selectCell(next!.$1, next.$2);
    game.applyPickerColor(game.debugSolutionAt(next.$1, next.$2)!);
    expect(game.activePalette, isNot(palette));
  });

  test('completing a unit ends Steadfast on that fill', () async {
    final game = await _game();
    addTearDown(game.dispose);
    game.debugQueueHyperchromaBoards([
      generatePuzzleIsolate(<Object>[Difficulty.easy.storageKey, 5]),
    ]);
    await game.debugBeginHyperchroma();
    final box = _openBoxes(game).first;
    final cells = _boxCells(game, box)
        .where((cell) => game.cellAt(cell.$1, cell.$2).value == 0)
        .toList();
    expect(cells.length, greaterThan(1));
    for (final (row, col) in cells.skip(1)) {
      game.selectCell(row, col);
      game.applyPickerColor(game.debugSolutionAt(row, col)!);
    }
    game.debugGrantSketches(3);
    await game.pauseGame();
    final palette = game.activePalette;
    expect(game.buyHyperchromaEffect(HyperchromaEffect.steadfast), isTrue);
    final (row, col) = cells.first;
    game.selectCell(row, col);
    game.applyPickerColor(game.debugSolutionAt(row, col)!);
    expect(game.activePalette, palette);

    final after = _safeEmpty(game);
    expect(after, isNotNull);
    game.selectCell(after!.$1, after.$2);
    game.applyPickerColor(game.debugSolutionAt(after.$1, after.$2)!);
    expect(game.activePalette, isNot(palette));
  });

  test('Trace notes one box and Telepathy locks the right cell', () async {
    final game = await _game();
    addTearDown(game.dispose);
    game.debugQueueHyperchromaBoards([
      generatePuzzleIsolate(<Object>[Difficulty.easy.storageKey, 8]),
    ]);
    await game.debugBeginHyperchroma();
    final box = _openBoxes(game).first;
    final (row, col) = _boxCells(game, box).firstWhere(
      (cell) => game.cellAt(cell.$1, cell.$2).value == 0,
    );
    game.debugGrantSketches(HyperchromaEffect.trace.cost);
    await game.pauseGame();
    expect(game.buyHyperchromaEffect(HyperchromaEffect.trace), isTrue);
    game.selectCell(row, col);
    expect(game.cellAt(row, col).notes, isNotEmpty);
    for (final (r, c) in _boxCells(game, box)) {
      if ((r, c) == (row, col)) continue;
      if (game.cellAt(r, c).value != 0) continue;
      expect(game.cellAt(r, c).notes, isNotEmpty);
    }
    expect(game.hyperchromaSketches, 0);

    game.debugGrantSketches(HyperchromaEffect.telepathy.cost);
    final value = game.debugSolutionAt(row, col)!;
    await game.pauseGame();
    final score = game.hyperchromaScore;
    final seconds = game.hyperchromaSeconds;
    expect(game.buyHyperchromaEffect(HyperchromaEffect.telepathy), isTrue);
    expect(game.useSketch(box, value), isTrue);
    expect(game.cellAt(row, col).value, value);
    expect(game.cellAt(row, col).isLocked, isTrue);
    expect(game.hyperchromaSketches, 0);
    expect(game.hyperchromaScore, score + 1);
    expect(game.hyperchromaSeconds, seconds);
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
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();
    expect(find.text('Hyperchroma'), findsOneWidget);
    await arm.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(taps, isEmpty);

    await tester.tap(find.text('Hyperchroma'));
    await tester.pump();
    expect(taps, ['hyper']);
  });

  testWidgets('entering Hyperchroma keeps its label while the hold turns off', (
    tester,
  ) async {
    final hold = ValueNotifier(true);
    addTearDown(hold.dispose);
    var entered = false;
    await _pumpButton(
      tester,
      hold: hold,
      onHyperchroma: () {
        entered = true;
        hold.value = false;
      },
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Chromatic')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();
    expect(find.text('Hyperchroma'), findsOneWidget);
    await gesture.up();
    await tester.pump();

    await tester.tap(find.text('Hyperchroma'));
    await tester.pump();
    expect(entered, isTrue);
    expect(find.text('Hyperchroma'), findsOneWidget);
    expect(find.text('Chromatic'), findsNothing);
  });

  testWidgets('leaving the button host restores Chromatic', (tester) async {
    final hold = ValueNotifier(true);
    addTearDown(hold.dispose);
    await _pumpButton(tester, hold: hold);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Chromatic')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1600));
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

int _remainingInUnit(
  GameProvider game,
  bool Function(int row, int col) inUnit,
) {
  var count = 0;
  for (var row = 0; row < game.gridSize; row++) {
    for (var col = 0; col < game.gridSize; col++) {
      if (!inUnit(row, col)) continue;
      if (game.cellAt(row, col).value != game.debugSolutionAt(row, col)) {
        count++;
      }
    }
  }
  return count;
}

(int, int)? _safeEmpty(GameProvider game) {
  for (final (row, col) in _editable(game)) {
    if (game.cellAt(row, col).value != 0) continue;
    final boxCols = game.gridSize ~/ game.boxW;
    final box = (row ~/ game.boxH) * boxCols + (col ~/ game.boxW);
    if (_remainingInUnit(game, (r, c) => r == row) < 2) continue;
    if (_remainingInUnit(game, (r, c) => c == col) < 2) continue;
    if (_remainingInUnit(
          game,
          (r, c) => _boxCells(game, box).contains((r, c)),
        ) <
        2) {
      continue;
    }
    return (row, col);
  }
  return null;
}

int _otherColor(int solution) => (solution % 9) + 1;

List<(int, int)> _boxCells(GameProvider game, int box) {
  final boxCols = game.gridSize ~/ game.boxW;
  final br = box ~/ boxCols;
  final bc = box % boxCols;
  return [
    for (var r = br * game.boxH; r < (br + 1) * game.boxH; r++)
      for (var c = bc * game.boxW; c < (bc + 1) * game.boxW; c++) (r, c),
  ];
}

bool _boxComplete(GameProvider game, int box) {
  for (final (row, col) in _boxCells(game, box)) {
    if (game.cellAt(row, col).value != game.debugSolutionAt(row, col)) {
      return false;
    }
  }
  return true;
}

List<int> _openBoxes(GameProvider game) {
  final boxes = (game.gridSize ~/ game.boxH) * (game.gridSize ~/ game.boxW);
  return [
    for (var box = 0; box < boxes; box++)
      if (!_boxComplete(game, box)) box,
  ];
}

void _fillBox(GameProvider game, int box) {
  for (final (row, col) in _boxCells(game, box)) {
    final cell = game.cellAt(row, col);
    if (!cell.isEditable || cell.value != 0) continue;
    game.selectCell(row, col);
    game.applyPickerColor(game.debugSolutionAt(row, col)!);
  }
}

bool _unitHas(GameProvider game, int value, bool Function(int row, int col) inUnit) {
  for (var row = 0; row < game.gridSize; row++) {
    for (var col = 0; col < game.gridSize; col++) {
      if (inUnit(row, col) && game.cellAt(row, col).value == value) return true;
    }
  }
  return false;
}

List<(int, int)> _sketchCandidates(GameProvider game, int box, int value) {
  final cells = _boxCells(game, box);
  return [
    for (final (row, col) in cells)
      if (game.cellAt(row, col).isEditable &&
          game.cellAt(row, col).value == 0 &&
          !_unitHas(game, value, (r, c) => r == row) &&
          !_unitHas(game, value, (r, c) => c == col) &&
          !_unitHas(game, value, (r, c) => cells.contains((r, c))))
        (row, col),
  ];
}

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

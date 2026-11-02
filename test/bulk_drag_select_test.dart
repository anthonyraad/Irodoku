import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irodoku/models/difficulty.dart';
import 'package:irodoku/models/game_palette.dart';
import 'package:irodoku/providers/achievements_provider.dart';
import 'package:irodoku/providers/game_provider.dart';
import 'package:irodoku/providers/iroen_provider.dart';
import 'package:irodoku/providers/settings_provider.dart';
import 'package:irodoku/providers/stats_provider.dart';
import 'package:irodoku/services/preferences_service.dart';
import 'package:irodoku/services/sound_service.dart';
import 'package:irodoku/widgets/iroen_grid.dart';
import 'package:irodoku/widgets/sudoku_grid.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _boardSize = 360.0;

class _Env {
  _Env(this.prefs, this.settings, this.sounds, this.stats, this.achievements);
  final PreferencesService prefs;
  final SettingsProvider settings;
  final SoundService sounds;
  final StatsProvider stats;
  final AchievementsProvider achievements;
}

Future<_Env> _env() async {
  SharedPreferences.setMockInitialValues({'sound_enabled': false});
  final prefs = await PreferencesService.create();
  final stats = StatsProvider(prefs);
  final achievements = AchievementsProvider(prefs);
  final settings = SettingsProvider(
    prefs,
    stats: stats,
    achievements: achievements,
  );
  return _Env(prefs, settings, SoundService(), stats, achievements);
}

Future<GameProvider> _game(WidgetTester tester, {required bool pocket}) async {
  final env = await _env();
  final game = GameProvider(
    settings: env.settings,
    stats: env.stats,
    achievements: env.achievements,
    preferences: env.prefs,
    sounds: env.sounds,
  );
  game.debugLoadBoards(
    pocket
        ? generatePocketIsolate(42)
        : generatePuzzleIsolate(<Object>[Difficulty.easy.storageKey, 42]),
    pocket: pocket,
  );
  return game;
}

Future<void> _pumpGrid(WidgetTester tester, Widget grid) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: _boardSize, height: _boardSize, child: grid),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Editable cells in row-major order.
List<(int, int)> _editable(GameProvider g) => [
  for (var r = 0; r < g.gridSize; r++)
    for (var c = 0; c < g.gridSize; c++)
      if (g.cellAt(r, c).isEditable) (r, c),
];

Offset _center(int row, int col, int n) {
  // Grid has a 2.5px outer border; cells are an even split of the rest.
  final cell = (_boardSize - 5) / n;
  return Offset(2.5 + cell * (col + .5), 2.5 + cell * (row + .5));
}

/// A run of three horizontally adjacent editable cells.
(int, int) _editableRun(GameProvider g) {
  for (var r = 0; r < g.gridSize; r++) {
    for (var c = 0; c + 2 < g.gridSize; c++) {
      if (g.cellAt(r, c).isEditable &&
          g.cellAt(r, c + 1).isEditable &&
          g.cellAt(r, c + 2).isEditable) {
        return (r, c);
      }
    }
  }
  fail('no editable run');
}

Future<void> _holdAndDrag(
  WidgetTester tester,
  List<(int, int)> path,
  int n,
) async {
  final g = await tester.startGesture(_center(path.first.$1, path.first.$2, n));
  await tester.pump(const Duration(milliseconds: 500)); // past hold threshold
  for (final (r, c) in path.skip(1)) {
    await g.moveTo(_center(r, c, n));
    await tester.pump();
  }
  await g.up();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  for (final pocket in [false, true]) {
    final mode = pocket ? 'Pocket' : 'Classic';

    testWidgets('$mode: hold + drag selects multiple cells for notes', (
      tester,
    ) async {
      final game = await _game(tester, pocket: pocket);
      final n = game.gridSize;
      expect(n, pocket ? 6 : 9);
      await _pumpGrid(
        tester,
        SudokuGrid(game: game, palette: GamePalette.values.first),
      );

      final (r, c) = _editableRun(game);
      await _holdAndDrag(tester, [(r, c), (r, c + 1), (r, c + 2)], n);

      expect(game.bulkNoteSelect, isTrue);
      expect(game.noteMode, isTrue);
      for (var i = 0; i < 3; i++) {
        expect(game.isCellSelected(r, c + i), isTrue, reason: 'cell $i');
      }

      game.applyPickerColor(1);
      for (var i = 0; i < 3; i++) {
        expect(game.cellAt(r, c + i).notes, contains(1));
        expect(game.cellAt(r, c + i).value, 0);
      }

      game.undo();
      for (var i = 0; i < 3; i++) {
        expect(game.cellAt(r, c + i).hasNotes, isFalse);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('$mode: quick drag (no hold) also paints a selection', (
      tester,
    ) async {
      final game = await _game(tester, pocket: pocket);
      final n = game.gridSize;
      await _pumpGrid(
        tester,
        SudokuGrid(game: game, palette: GamePalette.values.first),
      );
      final (r, c) = _editableRun(game);
      final g = await tester.startGesture(_center(r, c, n));
      await tester.pump(const Duration(milliseconds: 50));
      await g.moveTo(_center(r, c + 1, n));
      await tester.pump();
      await g.up();
      await tester.pump(const Duration(milliseconds: 600));
      expect(game.bulkNoteSelect, isTrue);
      expect(game.isCellSelected(r, c), isTrue);
      expect(game.isCellSelected(r, c + 1), isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('$mode: plain tap single-selects and enters a color', (
      tester,
    ) async {
      final game = await _game(tester, pocket: pocket);
      final n = game.gridSize;
      await _pumpGrid(
        tester,
        SudokuGrid(game: game, palette: GamePalette.values.first),
      );
      final cells = _editable(game);
      final (r, c) = cells.first;
      await tester.tapAt(_center(r, c, n));
      await tester.pump(const Duration(milliseconds: 400));
      expect(game.bulkNoteSelect, isFalse);
      expect(game.selected, (r, c));
      final (r2, c2) = cells[1];
      await tester.tapAt(_center(r2, c2, n));
      await tester.pump(const Duration(milliseconds: 400));
      expect(game.selected, (r2, c2));
      expect(game.isCellSelected(r, c), isFalse);

      final v = game.debugSolutionAt(r2, c2)!;
      game.applyPickerColor(v);
      expect(game.cellAt(r2, c2).value, v);
      expect(game.cellAt(r2, c2).hasNotes, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('$mode: stationary hold in bulk still exits to single note', (
      tester,
    ) async {
      final game = await _game(tester, pocket: pocket);
      final n = game.gridSize;
      await _pumpGrid(
        tester,
        SudokuGrid(game: game, palette: GamePalette.values.first),
      );
      final (r, c) = _editableRun(game);
      await _holdAndDrag(tester, [(r, c), (r, c + 1)], n);
      expect(game.bulkNoteSelect, isTrue);
      // Hold again without moving: exit to single-cell note mode on lift.
      final g = await tester.startGesture(_center(r, c + 2, n));
      await tester.pump(const Duration(milliseconds: 500));
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(game.bulkNoteSelect, isFalse);
      expect(game.noteMode, isTrue);
      expect(game.selected, (r, c + 2));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  }

  testWidgets('Iroen: hold + drag still multi-selects (unchanged)', (
    tester,
  ) async {
    final env = await _env();
    final iroen = IroenProvider(
      preferences: env.prefs,
      settings: env.settings,
      sounds: env.sounds,
    );
    await _pumpGrid(
      tester,
      IroenGrid(iroen: iroen, palette: GamePalette.values.first),
    );
    await _holdAndDrag(tester, [(0, 0), (0, 1), (0, 2)], 9);
    expect(iroen.bulkNoteSelect, isTrue);
    for (var c = 0; c < 3; c++) {
      expect(iroen.isCellSelected(0, c), isTrue);
    }
    expect(iroen.isCellSelected(0, 3), isFalse);
    // Selecting a painted cell toggles it off, as before.
    iroen.prepareBulkPaintGesture(); // pointer-down, as a real tap does
    iroen.selectCell(0, 1);
    await tester.pump();
    expect(iroen.isCellSelected(0, 1), isFalse);
    expect(iroen.isCellSelected(0, 0), isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}

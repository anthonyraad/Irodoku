import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/palette.dart';
import '../models/achievement.dart';
import '../models/cell.dart';
import '../models/difficulty.dart';
import '../models/game_palette.dart';
import '../models/paused_game.dart';
import '../models/unit_celebration.dart';
import '../services/preferences_service.dart';
import '../services/sound_service.dart';
import '../sudoku/sudoku_board.dart';
import '../sudoku/sudoku_generator.dart';
import 'achievements_provider.dart';
import 'settings_provider.dart';
import 'stats_provider.dart';

/// Top-level entry for isolate-friendly puzzle generation.
/// Returns `[puzzleFlat, solutionFlat]` as length-81 int lists.
List<List<int>> generatePuzzleIsolate(String difficultyKey) {
  final difficulty = Difficulty.fromStorageKey(difficultyKey);
  final generated = SudokuGenerator().generate(difficulty);
  return [generated.puzzle.toFlat(), generated.solution.toFlat()];
}

class GameProvider extends ChangeNotifier {
  static const int maxMistakes = 3;

  final SettingsProvider _settings;
  final StatsProvider _stats;
  final AchievementsProvider _achievements;
  final PreferencesService _prefs;
  final SoundService _sounds;

  late List<List<Cell>> _cells;
  SudokuBoard? _solution;
  (int, int)? _selected;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  bool _isWon = false;
  bool _isLost = false;
  bool _isPaused = false;
  bool _isGenerating = false;
  bool _hasActiveGame = false;
  bool _winRecorded = false;
  bool _lossRecorded = false;
  /// True after the player taps/edits any cell this game.
  bool _hasInteracted = false;
  int _generationToken = 0;
  int _mistakes = 0;
  late Difficulty _gameDifficulty;
  Set<String> _completedUnits = {};
  UnitCelebration? _celebration;
  int _celebrationSeq = 0;
  int _colorCycleSeq = 0;
  int _colorCycleSteps = 4;
  /// When non-null, only cells with this committed value join the sweep.
  int? _colorCycleFilterValue;
  bool _noteMode = false;
  bool _bulkNoteSelect = false;
  final Set<int> _bulkSelected = {};
  List<GamePalette> _pendingPaletteUnlocks = [];
  final List<_UndoSnapshot> _undoStack = [];
  static const int _maxUndo = 60;

  // Per-game achievement tracking (not persisted across pause restore).
  int? _firstFillColor;
  int? _lastFillColor;
  int? _lastFillRow;
  int? _lastFillCol;
  bool _usedNotes = false;
  bool _usedUndo = false;
  bool _pausedThisGame = false;
  bool _completedRowColBoxSimultaneously = false;
  bool _completedNineUnitsInNineSeconds = false;
  bool _filledNineDistinctColorsConsecutively = false;
  int _rowsCompletedInFirst90Seconds = 0;
  int _colsCompletedInFirst90Seconds = 0;
  int _boxesCompletedInFirst90Seconds = 0;
  final List<int> _consecutiveDistinctFillColors = [];
  final List<DateTime> _unitCompletionTimes = [];

  GameProvider({
    required SettingsProvider settings,
    required StatsProvider stats,
    required AchievementsProvider achievements,
    required PreferencesService preferences,
    SoundService? sounds,
  })  : _settings = settings,
        _stats = stats,
        _achievements = achievements,
        _prefs = preferences,
        _sounds = sounds ?? SoundService() {
    _gameDifficulty = settings.difficulty;
    _cells = List.generate(
      SudokuBoard.size,
      (_) => List.generate(SudokuBoard.size, (_) => const Cell()),
    );
    _achievements.bindAudio(settings: settings, sounds: _sounds);
  }

  List<List<Cell>> get cells => _cells;
  (int, int)? get selected => _selected;
  Duration get elapsed => _elapsed;
  bool get isWon => _isWon;
  bool get isLost => _isLost;
  bool get isPaused => _isPaused;
  bool get isGameOver => _isWon || _isLost;
  bool get isGenerating => _isGenerating;
  bool get hasActiveGame => _hasActiveGame;
  /// Whether the player has interacted with any cell this game.
  bool get hasInteracted => _hasInteracted;
  int get mistakes => _mistakes;
  Difficulty get difficulty => _gameDifficulty;
  UnitCelebration? get celebration => _celebration;
  int get colorCycleSeq => _colorCycleSeq;
  int get colorCycleSteps => _colorCycleSteps;
  /// `null` = all filled cells (title tap); otherwise only that color value.
  int? get colorCycleFilterValue => _colorCycleFilterValue;
  bool get noteMode => _noteMode;
  bool get bulkNoteSelect => _bulkNoteSelect;

  List<GamePalette> consumePendingPaletteUnlocks() {
    final pending = List<GamePalette>.from(_pendingPaletteUnlocks);
    _pendingPaletteUnlocks = [];
    return pending;
  }
  bool get canUndo => _undoStack.isNotEmpty && !_isGenerating;

  bool isCellSelected(int row, int col) {
    if (_bulkNoteSelect) {
      return _bulkSelected.contains(_cellKey(row, col));
    }
    return _selected?.$1 == row && _selected?.$2 == col;
  }

  bool get hasCellSelection => _selected != null || _bulkNoteSelect;

  bool get canEraseSelection {
    if (isGameOver || _isGenerating || _isPaused) return false;
    if (_bulkNoteSelect && _bulkSelected.length >= 2) {
      return _bulkEditableCells().any((rc) => _cells[rc.$1][rc.$2].hasNotes);
    }
    final sel = _selected;
    if (sel == null) return false;
    final cell = _cells[sel.$1][sel.$2];
    return !cell.isGiven && !cell.isEmpty;
  }

  static int _cellKey(int row, int col) => row * SudokuBoard.size + col;

  Cell cellAt(int row, int col) => _cells[row][col];

  void clearCelebration() {
    if (_celebration == null) return;
    _celebration = null;
    notifyListeners();
  }

  /// Palette sweep on filled cells. Title tap uses all colors; cell tap can
  /// limit to [onlyValue] (1–9).
  void triggerColorCycle({int? onlyValue}) {
    if (_isGenerating || _isPaused || _isLost) return;
    if (!_hasActiveGame && !_isWon) return;
    if (_celebration != null) return;
    final half = IrodokuPalette.colorsFor(_settings.palette).length ~/ 2;
    _colorCycleSteps = half + Random().nextInt(2); // 4 or 5 of 9 colors
    _colorCycleFilterValue = onlyValue;
    _colorCycleSeq++;
    notifyListeners();
  }

  /// Restores a paused game if one exists; otherwise starts a new puzzle.
  Future<void> bootstrap() async {
    final restored = await restorePausedGame();
    if (!restored) {
      await startNewGame();
    }
  }

  Future<bool> restorePausedGame() async {
    final paused = _prefs.loadPausedGame();
    if (paused == null) return false;

    _timer?.cancel();
    _isGenerating = false;
    _isWon = false;
    _isLost = false;
    _isPaused = true;
    _hasActiveGame = true;
    _hasInteracted = true;
    _winRecorded = false;
    _lossRecorded = false;
    _pendingPaletteUnlocks = [];
    _selected = null;
    _exitBulkNoteSelect();
    _mistakes = paused.mistakes;
    _elapsed = paused.elapsed;
    _gameDifficulty = paused.difficulty;
    _solution = SudokuBoard.fromFlat(paused.solution);
    _noteMode = false;
    _undoStack.clear();

    _cells = List.generate(SudokuBoard.size, (r) {
      return List.generate(SudokuBoard.size, (c) {
        return paused.cells[r * SudokuBoard.size + c];
      });
    });
    _refreshConflicts();
    _completedUnits = _successfullyCompletedUnits();
    _celebration = null;
    _resetAchievementSession();
    notifyListeners();
    return true;
  }

  Future<void> startNewGame() async {
    _timer?.cancel();
    final token = ++_generationToken;
    _isGenerating = true;
    _isWon = false;
    _isLost = false;
    _isPaused = false;
    _hasActiveGame = false;
    _winRecorded = false;
    _lossRecorded = false;
    _hasInteracted = false;
    _mistakes = 0;
    _pendingPaletteUnlocks = [];
    _selected = null;
    _exitBulkNoteSelect();
    _elapsed = Duration.zero;
    _solution = null;
    _gameDifficulty = _settings.difficulty;
    _completedUnits = {};
    _celebration = null;
    _noteMode = false;
    _undoStack.clear();
    _resetAchievementSession();
    await _prefs.clearPausedGame();
    notifyListeners();

    final boards = await compute(
      generatePuzzleIsolate,
      _gameDifficulty.storageKey,
    );

    if (token != _generationToken) return;

    final puzzle = SudokuBoard.fromFlat(boards[0]);
    _solution = SudokuBoard.fromFlat(boards[1]);
    _cells = List.generate(SudokuBoard.size, (r) {
      return List.generate(SudokuBoard.size, (c) {
        final value = puzzle.get(r, c);
        return Cell(
          value: value,
          isGiven: value != 0,
        );
      });
    });

    _isGenerating = false;
    _hasActiveGame = true;
    _completedUnits = _successfullyCompletedUnits();
    await _stats.recordGameStarted();
    _startTimer();
    notifyListeners();
  }

  Future<void> pauseGame() async {
    if (!_hasActiveGame || isGameOver || _isGenerating || _isPaused) return;
    _isPaused = true;
    _pausedThisGame = true;
    _selected = null;
    _exitBulkNoteSelect();
    _timer?.cancel();
    await _savePausedGame();
    notifyListeners();
  }

  Future<void> resumeGame() async {
    if (!_isPaused || isGameOver) return;
    _isPaused = false;
    await _prefs.clearPausedGame();
    _startTimer();
    notifyListeners();
  }

  Future<void> togglePause() async {
    if (_isPaused) {
      await resumeGame();
    } else {
      await pauseGame();
    }
  }

  Future<void> _savePausedGame() async {
    final solution = _solution;
    if (solution == null || !_hasActiveGame || isGameOver) return;

    final flatCells = <Cell>[
      for (var r = 0; r < SudokuBoard.size; r++)
        for (var c = 0; c < SudokuBoard.size; c++)
          _cells[r][c].copyWith(hasConflict: false),
    ];

    await _prefs.savePausedGame(
      PausedGame(
        difficulty: _gameDifficulty,
        elapsed: _elapsed,
        mistakes: _mistakes,
        solution: solution.toFlat(),
        cells: flatCells,
      ),
    );
  }

  void selectCell(int row, int col) {
    if (isGameOver || _isGenerating || _isPaused) return;
    final cell = _cells[row][col];

    // Givens aren't selectable, but tapping one still pulses matching colors.
    if (cell.isGiven) {
      if (cell.value != 0) triggerColorCycle(onlyValue: cell.value);
      return;
    }

    if (_bulkNoteSelect) {
      final key = _cellKey(row, col);
      if (_bulkSelected.contains(key) && _bulkSelectionHasNotes()) {
        _exitBulkNoteSelect();
        _noteMode = false;
        _selected = (row, col);
        _hasInteracted = true;
        notifyListeners();
        if (cell.value != 0) triggerColorCycle(onlyValue: cell.value);
        return;
      }
      _hasInteracted = true;
      _toggleBulkCell(row, col);
      return;
    }

    // Tapping the already-selected cell dismisses selection.
    if (_selected != null && _selected!.$1 == row && _selected!.$2 == col) {
      _selected = null;
      notifyListeners();
      return;
    }
    _selected = (row, col);
    _hasInteracted = true;
    notifyListeners();
    if (cell.value != 0) triggerColorCycle(onlyValue: cell.value);
  }

  /// Hold on a cell: enter bulk note select, or exit bulk to single-cell note mode.
  void handleCellLongPress(int row, int col) {
    if (isGameOver || _isGenerating || _isPaused) return;
    if (_cells[row][col].isGiven) return;

    _hasInteracted = true;
    if (_bulkNoteSelect) {
      _exitBulkNoteSelect();
      _noteMode = true;
      _selected = (row, col);
      notifyListeners();
      return;
    }

    enterBulkNoteSelect(row, col);
  }

  /// Hold-to-enter: multi-cell note selection with note mode enabled.
  void enterBulkNoteSelect(int row, int col) {
    if (isGameOver || _isGenerating || _isPaused) return;
    if (_cells[row][col].isGiven) return;

    _bulkNoteSelect = true;
    if (!_noteMode) _noteMode = true;
    _bulkSelected.add(_cellKey(row, col));
    _selected = (row, col);
    notifyListeners();
  }

  bool get canEnterBulkNoteSelectFromToolbar {
    if (isGameOver || _isGenerating || _isPaused) return false;
    return !_bulkNoteSelect;
  }

  void enterBulkNoteSelectFromToolbar() {
    if (!canEnterBulkNoteSelectFromToolbar) return;
    final sel = _selected;
    if (sel != null && !_cells[sel.$1][sel.$2].isGiven) {
      enterBulkNoteSelect(sel.$1, sel.$2);
      return;
    }
    _bulkNoteSelect = true;
    if (!_noteMode) _noteMode = true;
    _selected = null;
    notifyListeners();
  }

  void _toggleBulkCell(int row, int col) {
    final key = _cellKey(row, col);
    if (_bulkSelected.contains(key)) {
      _bulkSelected.remove(key);
      if (_bulkSelected.isEmpty) {
        _exitBulkNoteSelect();
        _selected = null;
      } else if (_selected?.$1 == row && _selected?.$2 == col) {
        final last = _bulkSelected.last;
        _selected = (last ~/ SudokuBoard.size, last % SudokuBoard.size);
      }
    } else {
      _bulkSelected.add(key);
      _selected = (row, col);
    }
    notifyListeners();
  }

  void _exitBulkNoteSelect() {
    _bulkNoteSelect = false;
    _bulkSelected.clear();
  }

  bool _bulkSelectionHasNotes() {
    for (final key in _bulkSelected) {
      final row = key ~/ SudokuBoard.size;
      final col = key % SudokuBoard.size;
      if (_cells[row][col].hasNotes) return true;
    }
    return false;
  }

  void clearSelection() {
    if (_selected == null && !_bulkNoteSelect) return;
    _exitBulkNoteSelect();
    _selected = null;
    notifyListeners();
  }

  void toggleNoteMode() {
    if (isGameOver || _isGenerating || _isPaused) return;
    final turningOn = !_noteMode;
    if (turningOn || _bulkNoteSelect) {
      _exitBulkNoteSelect();
    }
    _noteMode = turningOn;
    notifyListeners();
  }

  /// Tap on a picker color: commit fill, toggle a note when note mode is on,
  /// or glimmer matching filled cells when nothing is selected.
  void applyPickerColor(int value) {
    if (_noteMode) {
      toggleSelectedNote(value);
      return;
    }
    if (_selected == null) {
      if (!_bulkNoteSelect) {
        triggerColorCycle(onlyValue: value);
      }
      return;
    }
    setSelectedColor(value);
  }

  void undo() {
    if (!canUndo) return;
    final snap = _undoStack.removeLast();
    _cells = snap.cells;
    _isWon = snap.isWon;
    _isLost = snap.isLost;
    _hasActiveGame = snap.hasActiveGame;
    _completedUnits = snap.completedUnits;
    _selected = snap.selected;
    _exitBulkNoteSelect();
    _celebration = null;
    _usedUndo = true;
    _consecutiveDistinctFillColors.clear();
    if (_hasActiveGame && !isGameOver && !_isPaused) {
      _startTimer();
    } else {
      _timer?.cancel();
    }
    _refreshConflicts();
    notifyListeners();
    unawaited(_achievements.recordUndo());
  }

  void setSelectedColor(int value) {
    final sel = _selected;
    if (sel == null || isGameOver || _isGenerating || _isPaused) return;
    final (row, col) = sel;
    final cell = _cells[row][col];
    if (cell.isGiven) return;

    _pushUndo();

    // Toggle off if same committed color tapped again — not a mistake.
    if (cell.value == value) {
      _cells[row][col] = cell.copyWith(clearValue: true, clearNotes: true);
      _selected = null;
      _refreshConflicts();
      _syncCompletedUnits(celebrate: false);
      _consecutiveDistinctFillColors.clear();
      notifyListeners();
      unawaited(_achievements.recordErase());
      return;
    }

    final solution = _solution;
    final isMistake =
        solution != null && value != solution.get(row, col);

    // Committing a full color clears any notes on this cell.
    _cells[row][col] = cell.copyWith(value: value, clearNotes: true);
    _selected = null;
    // Drop that color from notes in the same row, column, and box.
    _clearPeerNotes(row, col, value);

    if (isMistake) {
      _mistakes++;
      _consecutiveDistinctFillColors.clear();
      if (_mistakes >= maxMistakes) {
        _playSound(_sounds.playGameLoss);
        _handleLoss();
        notifyListeners();
        return;
      }
      _playSound(_sounds.playMistake);
    } else {
      _recordSuccessfulFill(row, col, value);
    }

    _refreshConflicts();
    final unitCompleted = _syncCompletedUnits(celebrate: true);
    if (!isMistake) {
      if (_toBoard().isValidSolution()) {
        _playSound(_sounds.playGameWin);
      } else {
        _playSound(unitCompleted ? _sounds.playComplete : _sounds.playConfirm);
      }
    }
    _checkWin();
    notifyListeners();
  }

  /// Removes [value] from notes in peer cells of (row, col).
  void _clearPeerNotes(int row, int col, int value) {
    final boxRow = row ~/ 3;
    final boxCol = col ~/ 3;
    for (var r = 0; r < SudokuBoard.size; r++) {
      for (var c = 0; c < SudokuBoard.size; c++) {
        if (r == row && c == col) continue;
        final sameUnit = r == row ||
            c == col ||
            (r ~/ 3 == boxRow && c ~/ 3 == boxCol);
        if (!sameUnit) continue;

        final peer = _cells[r][c];
        if (peer.isGiven || !peer.hasNote(value)) continue;
        _cells[r][c] = peer.withNoteRemoved(value);
      }
    }
  }

  /// Adds a color note in its fixed 3×3 slot. Does not count as a mistake.
  void addSelectedNote(int value) {
    if (_bulkNoteSelect && _bulkSelected.isNotEmpty) {
      _applyNoteToBulk(value, add: true);
      return;
    }
    final sel = _selected;
    if (sel == null || isGameOver || _isGenerating || _isPaused) return;
    final (row, col) = sel;
    final cell = _cells[row][col];
    if (cell.isGiven) return;

    final next = cell.withNoteAdded(value);
    if (identical(next, cell)) return;

    _pushUndo();
    _cells[row][col] = next;
    _markNoteTaken();
    _playSound(_sounds.playNote);
    // Keep selection so multiple notes can be added.
    notifyListeners();
  }

  /// Removes a color note from the selected cell. Does not count as a mistake.
  void removeSelectedNote(int value) {
    if (_bulkNoteSelect && _bulkSelected.isNotEmpty) {
      _applyNoteToBulk(value, add: false);
      return;
    }
    final sel = _selected;
    if (sel == null || isGameOver || _isGenerating || _isPaused) return;
    final (row, col) = sel;
    final cell = _cells[row][col];
    if (cell.isGiven) return;

    final next = cell.withNoteRemoved(value);
    if (identical(next, cell)) return;

    _pushUndo();
    _cells[row][col] = next;
    _playSound(_sounds.playNoteDeselect);
    notifyListeners();
  }

  /// Toggles a note on the selected cell (used by note-mode picker taps).
  void toggleSelectedNote(int value) {
    if (_bulkNoteSelect && _bulkSelected.isNotEmpty) {
      final targets = _bulkEditableCells();
      if (targets.isEmpty) return;
      final allHave = targets.every(
        (rc) => _cells[rc.$1][rc.$2].hasNote(value),
      );
      _applyNoteToBulk(value, add: !allHave);
      return;
    }
    final sel = _selected;
    if (sel == null || isGameOver || _isGenerating || _isPaused) return;
    final (row, col) = sel;
    final cell = _cells[row][col];
    if (cell.isGiven) return;

    final adding = !cell.hasNote(value);
    final next = adding
        ? cell.withNoteAdded(value)
        : cell.withNoteRemoved(value);
    if (identical(next, cell)) return;

    _pushUndo();
    _cells[row][col] = next;
    if (adding) _markNoteTaken();
    _playSound(adding ? _sounds.playNote : _sounds.playNoteDeselect);
    notifyListeners();
  }

  Iterable<(int, int)> _bulkEditableCells() sync* {
    for (final key in _bulkSelected) {
      final row = key ~/ SudokuBoard.size;
      final col = key % SudokuBoard.size;
      if (!_cells[row][col].isGiven) yield (row, col);
    }
  }

  void _applyNoteToBulk(int value, {required bool add}) {
    final targets = _bulkEditableCells().toList();
    if (targets.isEmpty) return;

    _pushUndo();
    var changed = false;
    for (final (row, col) in targets) {
      final cell = _cells[row][col];
      final next =
          add ? cell.withNoteAdded(value) : cell.withNoteRemoved(value);
      if (!identical(next, cell)) {
        _cells[row][col] = next;
        changed = true;
      }
    }
    if (changed) {
      if (add) _markNoteTaken();
      _playSound(add ? _sounds.playNote : _sounds.playNoteDeselect);
      notifyListeners();
    }
  }

  void _playSound(Future<void> Function() play) {
    if (!_settings.soundEnabled) return;
    unawaited(play());
  }

  void clearSelectedCell() {
    if (_bulkNoteSelect && _bulkSelected.length >= 2) {
      _clearNotesInBulkSelection();
      return;
    }
    final sel = _selected;
    if (sel == null) return;
    // Keep selection so the picker stays open after erase.
    clearCell(sel.$1, sel.$2, clearSelection: false);
  }

  void _clearNotesInBulkSelection() {
    if (isGameOver || _isGenerating || _isPaused) return;
    final targets = _bulkEditableCells()
        .where((rc) => _cells[rc.$1][rc.$2].hasNotes)
        .toList();
    if (targets.isEmpty) return;

    _pushUndo();
    for (final (row, col) in targets) {
      _cells[row][col] = _cells[row][col].copyWith(clearNotes: true);
    }
    notifyListeners();
  }

  /// Clears committed color and notes from an editable cell.
  void clearCell(int row, int col, {bool clearSelection = true}) {
    if (isGameOver || _isGenerating || _isPaused) return;
    final cell = _cells[row][col];
    if (cell.isGiven || cell.isEmpty) return;

    final hadValue = cell.value != 0;
    _pushUndo();
    _cells[row][col] = cell.copyWith(clearValue: true, clearNotes: true);
    if (clearSelection &&
        _selected != null &&
        _selected!.$1 == row &&
        _selected!.$2 == col) {
      _selected = null;
    }
    _refreshConflicts();
    _syncCompletedUnits(celebrate: false);
    // Only a committed-color erase breaks the 9-color consecutive chain.
    if (hadValue) {
      _consecutiveDistinctFillColors.clear();
      unawaited(_achievements.recordErase());
    }
    notifyListeners();
  }

  void _pushUndo() {
    _hasInteracted = true;
    _undoStack.add(
      _UndoSnapshot(
        cells: _cloneCells(),
        isWon: _isWon,
        isLost: _isLost,
        hasActiveGame: _hasActiveGame,
        completedUnits: {..._completedUnits},
        selected: _selected,
      ),
    );
    if (_undoStack.length > _maxUndo) {
      _undoStack.removeAt(0);
    }
  }

  List<List<Cell>> _cloneCells() {
    return List.generate(
      SudokuBoard.size,
      (r) => List.generate(SudokuBoard.size, (c) {
        final cell = _cells[r][c];
        return Cell(
          value: cell.value,
          notes: {...cell.notes},
          isGiven: cell.isGiven,
          hasConflict: cell.hasConflict,
        );
      }),
    );
  }

  bool _syncCompletedUnits({required bool celebrate}) {
    final now = _successfullyCompletedUnits();
    var newlyCompleted = false;
    final newly = now.difference(_completedUnits);
    if (celebrate && newly.isNotEmpty) {
      newlyCompleted = true;
      _celebration = _buildCelebration(newly);
      _trackNewlyCompletedUnits(newly);
      _maybeChromaticShift();
    }
    _completedUnits = now;
    return newlyCompleted;
  }

  /// Chromatic mode: after completing any unit, hop to a different menu palette.
  void _maybeChromaticShift() {
    if (!_settings.chromatic) return;
    final options = GamePalette.menuValues
        .where((palette) => palette != _settings.palette)
        .toList();
    if (options.isEmpty) return;
    final next = options[Random().nextInt(options.length)];
    unawaited(_settings.setPalette(next));
  }

  void _trackNewlyCompletedUnits(Set<String> newly) {
    final stamp = DateTime.now();
    var newRows = 0;
    var newCols = 0;
    var newBoxes = 0;
    for (final key in newly) {
      _unitCompletionTimes.add(stamp);
      if (key.startsWith('r')) {
        newRows++;
      } else if (key.startsWith('c')) {
        newCols++;
      } else if (key.startsWith('b')) {
        newBoxes++;
      }
    }

    // R6C4/C5/C7: count only units finished in the first 1:30 of game time.
    if (_elapsed < const Duration(minutes: 1, seconds: 30)) {
      _rowsCompletedInFirst90Seconds += newRows;
      _colsCompletedInFirst90Seconds += newCols;
      _boxesCompletedInFirst90Seconds += newBoxes;
    }

    if (newRows > 0 && newCols > 0 && newBoxes > 0) {
      _completedRowColBoxSimultaneously = true;
    }

    final cutoff = stamp.subtract(const Duration(seconds: 9));
    _unitCompletionTimes.removeWhere((t) => t.isBefore(cutoff));
    if (_unitCompletionTimes.length >= 9) {
      _completedNineUnitsInNineSeconds = true;
    }

    if (_completedRowColBoxSimultaneously ||
        _completedNineUnitsInNineSeconds ||
        _filledNineDistinctColorsConsecutively) {
      unawaited(
        _achievements.recordSessionFlags(
          completedRowColBoxSimultaneously:
              _completedRowColBoxSimultaneously,
          completedNineUnitsInNineSeconds:
              _completedNineUnitsInNineSeconds,
          filledNineDistinctColorsConsecutively:
              _filledNineDistinctColorsConsecutively,
        ),
      );
    }
  }

  void _recordSuccessfulFill(int row, int col, int value) {
    final isFirstFill = _firstFillColor == null;
    _firstFillColor ??= value;
    if (isFirstFill &&
        _settings.palette == GamePalette.pkmn &&
        value == 3) {
      unawaited(
        _achievements.recordFirstFill(
          palette: _settings.palette,
          colorValue: value,
        ),
      );
    }

    _lastFillColor = value;
    _lastFillRow = row;
    _lastFillCol = col;

    if (_consecutiveDistinctFillColors.contains(value)) {
      _consecutiveDistinctFillColors
        ..clear()
        ..add(value);
    } else {
      _consecutiveDistinctFillColors.add(value);
    }
    if (_consecutiveDistinctFillColors.length >= 9) {
      _filledNineDistinctColorsConsecutively = true;
      unawaited(
        _achievements.recordSessionFlags(
          completedRowColBoxSimultaneously:
              _completedRowColBoxSimultaneously,
          completedNineUnitsInNineSeconds:
              _completedNineUnitsInNineSeconds,
          filledNineDistinctColorsConsecutively: true,
        ),
      );
    }
  }

  void _markNoteTaken() {
    if (!_usedNotes) _usedNotes = true;
    unawaited(_achievements.recordNoteTaken());
  }

  void _resetAchievementSession() {
    _firstFillColor = null;
    _lastFillColor = null;
    _lastFillRow = null;
    _lastFillCol = null;
    _usedNotes = false;
    _usedUndo = false;
    _pausedThisGame = false;
    _completedRowColBoxSimultaneously = false;
    _completedNineUnitsInNineSeconds = false;
    _filledNineDistinctColorsConsecutively = false;
    _rowsCompletedInFirst90Seconds = 0;
    _colsCompletedInFirst90Seconds = 0;
    _boxesCompletedInFirst90Seconds = 0;
    _consecutiveDistinctFillColors.clear();
    _unitCompletionTimes.clear();
  }

  AchievementGameContext _achievementGameContext() {
    return AchievementGameContext(
      firstFillColor: _firstFillColor,
      lastFillColor: _lastFillColor,
      lastFillRow: _lastFillRow,
      lastFillCol: _lastFillCol,
      usedNotes: _usedNotes,
      usedUndo: _usedUndo,
      paused: _pausedThisGame,
      usedDarkMode: _settings.darkMode,
      chromatic: _settings.chromatic,
      completedRowColBoxSimultaneously: _completedRowColBoxSimultaneously,
      completedNineUnitsInNineSeconds: _completedNineUnitsInNineSeconds,
      filledNineDistinctColorsConsecutively:
          _filledNineDistinctColorsConsecutively,
      rowsCompletedInFirst90Seconds: _rowsCompletedInFirst90Seconds,
      colsCompletedInFirst90Seconds: _colsCompletedInFirst90Seconds,
      boxesCompletedInFirst90Seconds: _boxesCompletedInFirst90Seconds,
    );
  }

  /// Units that are fully filled with the correct solution colors.
  Set<String> _successfullyCompletedUnits() {
    final board = _toBoard();
    final solution = _solution;
    final keys = board.completedUnitKeys();
    if (solution == null) return keys;

    return keys.where((key) {
      final positions = SudokuBoard.positionsForUnitKey(key);
      return positions.every(
        (pos) => board.get(pos.$1, pos.$2) == solution.get(pos.$1, pos.$2),
      );
    }).toSet();
  }

  UnitCelebration _buildCelebration(Set<String> unitKeys) {
    final cellStagger = <(int, int), int>{};
    final originalValues = <(int, int), int>{};

    for (final key in unitKeys) {
      final positions = SudokuBoard.positionsForUnitKey(key);
      for (var i = 0; i < positions.length; i++) {
        final pos = positions[i];
        final existing = cellStagger[pos];
        if (existing == null || i < existing) {
          cellStagger[pos] = i;
        }
        originalValues[pos] = _cells[pos.$1][pos.$2].value;
      }
    }

    return UnitCelebration(
      id: ++_celebrationSeq,
      cellStagger: cellStagger,
      originalValues: originalValues,
    );
  }

  void _handleLoss() {
    _isLost = true;
    _hasActiveGame = false;
    _timer?.cancel();
    _selected = null;
    _exitBulkNoteSelect();
    _isPaused = false;
    _prefs.clearPausedGame();
    _refreshConflicts();
    if (!_lossRecorded) {
      _lossRecorded = true;
      _stats.resetStreakSync(palette: _settings.palette);
      unawaited(_stats.persist());
    }
  }

  void _refreshConflicts() {
    final board = _toBoard();
    final conflicts = board.conflictingCells();
    for (var r = 0; r < SudokuBoard.size; r++) {
      for (var c = 0; c < SudokuBoard.size; c++) {
        final hasConflict = conflicts.contains((r, c));
        final cell = _cells[r][c];
        if (cell.hasConflict != hasConflict) {
          _cells[r][c] = cell.copyWith(hasConflict: hasConflict);
        }
      }
    }
  }

  void _checkWin() {
    if (_isLost) return;
    final board = _toBoard();
    if (!board.isValidSolution()) return;

    _isWon = true;
    _hasActiveGame = false;
    _isPaused = false;
    _timer?.cancel();
    _selected = null;
    _exitBulkNoteSelect();
    _prefs.clearPausedGame();

    if (!_winRecorded) {
      _winRecorded = true;
      _pendingPaletteUnlocks = _stats.recordWinSync(
        difficulty: _gameDifficulty,
        elapsed: _elapsed,
        mistakes: _mistakes,
        palette: _settings.palette,
        chromatic: _settings.chromatic,
      );
      _settings.ensurePaletteUnlocked(_stats.stats);
      unawaited(_stats.persist());
      unawaited(
        _achievements.evaluateWin(
          difficulty: _gameDifficulty,
          elapsed: _elapsed,
          mistakes: _mistakes,
          palette: _settings.palette,
          ctx: _achievementGameContext(),
        ),
      );
    }
  }

  SudokuBoard _toBoard() {
    return SudokuBoard(
      List.generate(
        SudokuBoard.size,
        (r) => List.generate(SudokuBoard.size, (c) => _cells[r][c].value),
      ),
    );
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isGameOver || _isGenerating || _isPaused) return;
      _elapsed += const Duration(seconds: 1);
      notifyListeners();
    });
  }

  String formatElapsed() {
    final totalSeconds = _elapsed.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_sounds.dispose());
    super.dispose();
  }
}

class _UndoSnapshot {
  final List<List<Cell>> cells;
  final bool isWon;
  final bool isLost;
  final bool hasActiveGame;
  final Set<String> completedUnits;
  final (int, int)? selected;

  const _UndoSnapshot({
    required this.cells,
    required this.isWon,
    required this.isLost,
    required this.hasActiveGame,
    required this.completedUnits,
    required this.selected,
  });
}

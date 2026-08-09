import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/palette.dart';
import '../models/achievement.dart';
import '../models/cell.dart';
import '../models/daily_irodoku.dart';
import '../models/difficulty.dart';
import '../models/game_palette.dart';
import '../models/note_clear_wave.dart';
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
///
/// Args: `[difficultyKey, seed]` where [seed] `< 0` means unseeded [Random].
/// Returns `[puzzleFlat, solutionFlat]` as length-81 int lists.
List<List<int>> generatePuzzleIsolate(List<Object> args) {
  final difficultyKey = args[0] as String;
  final seed = args[1] as int;
  final difficulty = Difficulty.fromStorageKey(difficultyKey);
  final random = seed < 0 ? Random() : Random(seed);
  final generated = SudokuGenerator(random: random).generate(difficulty);
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

  /// Origin of the latest peer-note clear, for outward dismiss stagger.
  NoteClearWave? _noteClearWave;
  int _noteClearWaveSeq = 0;
  int _noteClearWaveClearToken = 0;

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

  bool _isDaily = false;
  String? _dailyDayKey;

  /// Daily-only display palette — never written to [SettingsProvider].
  GamePalette? _sessionPalette;

  /// Regular puzzle parked while Daily Irodoku is nested under Main Menu.
  _HeldGameSession? _heldRegular;

  /// In-progress Daily parked while browsing Main Menu.
  _HeldGameSession? _heldDaily;

  /// After cold restore of a paused Daily, home should open Main Menu → Daily.
  bool _openDailyRoutePending = false;

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
  /// Bumps when a new puzzle generation starts; use to reset per-cell UI state.
  int get boardEpoch => _generationToken;
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
  NoteClearWave? get noteClearWave => _noteClearWave;
  bool get isDaily => _isDaily;

  /// Palette for the live board (daily session override or settings).
  GamePalette get activePalette => _sessionPalette ?? _settings.palette;

  /// Short date for the active daily (`8.9.26`), or null when not daily.
  String? get dailyDateLabel {
    final key = _dailyDayKey;
    if (key == null) return null;
    return DailyIrodoku.shortDateLabel(key);
  }

  /// Whether today's Daily Irodoku has already been won (local calendar).
  bool get isDailyCompletedToday {
    final today = DailyIrodoku.forDate().dayKey;
    return _prefs.getDailyLastCompletedDay() == today;
  }

  /// True when today's daily is live or parked for resume from Main Menu.
  bool get hasResumableDaily {
    final today = DailyIrodoku.forDate().dayKey;
    if (isDailyCompletedToday) return false;
    if (_heldDaily?.dailyDayKey == today) return true;
    return _isDaily && _dailyDayKey == today && !isGameOver;
  }

  /// Consumes the cold-start flag to auto-open the Daily route once.
  bool consumeOpenDailyRoutePending() {
    final pending = _openDailyRoutePending;
    _openDailyRoutePending = false;
    return pending;
  }

  /// Streak shown on the Daily button; 0 if broken by a missed day.
  int get dailyStreakDisplay {
    final today = DailyIrodoku.forDate().dayKey;
    final last = _prefs.getDailyLastCompletedDay();
    if (last == null) return 0;
    if (last != today && last != DailyIrodoku.previousDayKey(today)) {
      return 0;
    }
    return _prefs.getDailyStreak();
  }

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

  bool get hasCellSelection =>
      _selected != null || _bulkNoteSelect || _noteMode;

  bool get canEraseSelection {
    if (isGameOver || _isGenerating || _isPaused) return false;
    if (_bulkNoteSelect && _bulkSelected.length >= 2) {
      return _bulkEditableCells().any((rc) => _cells[rc.$1][rc.$2].hasNotes);
    }
    final sel = _selected;
    if (sel == null) return false;
    final cell = _cells[sel.$1][sel.$2];
    return cell.isEditable && !cell.isEmpty;
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
    final half = IrodokuPalette.colorsFor(activePalette).length ~/ 2;
    _colorCycleSteps = half + Random().nextInt(2); // 4 or 5 of 9 colors
    _colorCycleFilterValue = onlyValue;
    _colorCycleSeq++;
    notifyListeners();
  }

  /// Restores a paused / parked game if one exists; otherwise starts a new puzzle.
  Future<void> bootstrap() async {
    await _hydrateParkedHoldsFromDisk();

    final paused = _prefs.loadPausedGame();
    if (paused != null && paused.isDaily) {
      final today = DailyIrodoku.forDate().dayKey;
      if (paused.dailyDayKey != today) {
        await _prefs.clearPausedGame();
      } else {
        // Don't put Daily on the home route — park it and reopen nested.
        _heldDaily = _heldFromPaused(paused);
        await _persistParkedDaily();
        await _prefs.clearPausedGame();
        _openDailyRoutePending = true;

        if (_heldRegular != null) {
          _applyHeld(_heldRegular!);
          _heldRegular = null;
          await _prefs.clearParkedRegularGame();
          notifyListeners();
          return;
        }
        await startNewGame(preserveHeldDaily: true);
        return;
      }
    }

    final restored = await restorePausedGame();
    if (restored) return;

    // Killed on Main Menu: both puzzles may exist only as parked holds.
    if (_heldRegular != null) {
      _applyHeld(_heldRegular!);
      _heldRegular = null;
      await _prefs.clearParkedRegularGame();
      notifyListeners();
      return;
    }

    await startNewGame();
  }

  Future<bool> restorePausedGame() async {
    final paused = _prefs.loadPausedGame();
    if (paused == null) return false;

    // Stale / unexpected daily — bootstrap handles today's paused Daily.
    if (paused.isDaily) {
      await _prefs.clearPausedGame();
      return false;
    }

    _applyPausedBoard(paused, sessionPalette: null);
    notifyListeners();
    return true;
  }

  /// Starts or resumes today's seeded Daily Irodoku.
  ///
  /// Parks the regular puzzle first so Main Menu back can restore it.
  Future<bool> startDailyGame() async {
    final challenge = DailyIrodoku.forDate();
    if (_prefs.getDailyLastCompletedDay() == challenge.dayKey) return false;
    if (_isGenerating) return false;

    // Resume a daily parked while browsing Main Menu.
    if (_heldDaily != null && _heldDaily!.dailyDayKey == challenge.dayKey) {
      if (!_isDaily) {
        await _parkRegularFromLive();
      }
      _applyHeld(_heldDaily!);
      _heldDaily = null;
      await _prefs.clearParkedDailyGame();
      _sessionPalette = challenge.palette;
      notifyListeners();
      return true;
    }

    // Already on today's live daily board (still in progress).
    if (_isDaily && _dailyDayKey == challenge.dayKey && !isGameOver) {
      _sessionPalette = challenge.palette;
      notifyListeners();
      return true;
    }

    // Park the regular puzzle before replacing the live board with daily.
    if (!_isDaily) {
      await _parkRegularFromLive();
    } else {
      // Lost/won leftover daily on the live board — drop it.
      _heldDaily = null;
      await _prefs.clearParkedDailyGame();
    }

    _sessionPalette = challenge.palette;
    await startNewGame(
      difficulty: challenge.difficulty,
      seed: challenge.seed,
      dailyDayKey: challenge.dayKey,
    );
    return true;
  }

  /// Park the live Daily when leaving its screen for Main Menu.
  void parkDailyForMenu() {
    if (!_isDaily) return;
    _timer?.cancel();
    if (!isGameOver) {
      _heldDaily = _captureHeld();
      unawaited(_persistParkedDaily());
    } else {
      _heldDaily = null;
      unawaited(_prefs.clearParkedDailyGame());
    }
    // Main Menu should reflect the user's real palette, not the daily's.
    _sessionPalette = null;
    notifyListeners();
  }

  /// Restore the parked regular puzzle when leaving Main Menu.
  Future<void> leaveMenuToRegular() async {
    var held = _heldRegular;
    if (held == null) {
      final parked = _prefs.loadParkedRegularGame();
      if (parked != null && !parked.isDaily) {
        held = _heldFromPaused(parked);
      }
    }
    if (held == null) {
      _sessionPalette = null;
      // Clear any legacy prefs from older daily palette forcing.
      await _prefs.clearPaletteBeforeDaily();
      // Live board may still be Daily after browsing the menu — park it.
      if (_isDaily) {
        if (!isGameOver) {
          _heldDaily = _captureHeld();
          await _persistParkedDaily();
        } else {
          _heldDaily = null;
          await _prefs.clearParkedDailyGame();
        }
        // Home must not keep Daily as the live board.
        await startNewGame(preserveHeldDaily: true);
        return;
      }
      notifyListeners();
      return;
    }
    if (_isDaily && !isGameOver) {
      _heldDaily = _captureHeld();
      await _persistParkedDaily();
    } else if (_isDaily && isGameOver) {
      _heldDaily = null;
      await _prefs.clearParkedDailyGame();
    }
    _sessionPalette = null;
    await _prefs.clearPaletteBeforeDaily();
    _applyHeld(held);
    _heldRegular = null;
    await _prefs.clearParkedRegularGame();
    notifyListeners();
  }

  Future<void> startNewGame({
    Difficulty? difficulty,
    int? seed,
    String? dailyDayKey,
    bool preserveHeldDaily = false,
  }) async {
    final startingDaily = dailyDayKey != null;
    if (startingDaily) {
      // Fresh Daily replaces any parked Daily; keep parked regular.
      _heldDaily = null;
      await _prefs.clearParkedDailyGame();
    } else if (preserveHeldDaily) {
      // Main Menu difficulty/palette: regenerate regular without wiping Daily.
      if (_isDaily && !isGameOver) {
        _heldDaily = _captureHeld();
        await _persistParkedDaily();
      }
      _heldRegular = null;
      await _prefs.clearParkedRegularGame();
      _sessionPalette = null;
      await _prefs.clearPaletteBeforeDaily();
    } else {
      // Starting a fresh regular game abandons nested daily/regular holds.
      _heldDaily = null;
      _heldRegular = null;
      _sessionPalette = null;
      await _prefs.clearParkedDailyGame();
      await _prefs.clearParkedRegularGame();
      await _prefs.clearPaletteBeforeDaily();
    }

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
    _gameDifficulty = difficulty ?? _settings.difficulty;
    _isDaily = startingDaily;
    _dailyDayKey = dailyDayKey;
    if (startingDaily && _sessionPalette == null) {
      _sessionPalette = DailyIrodoku.forDate().palette;
    }
    _completedUnits = {};
    _celebration = null;
    _noteMode = false;
    _undoStack.clear();
    _resetAchievementSession();
    await _prefs.clearPausedGame();
    notifyListeners();

    final boards = await compute(
      generatePuzzleIsolate,
      <Object>[_gameDifficulty.storageKey, seed ?? -1],
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
        isDaily: _isDaily,
        dailyDayKey: _dailyDayKey,
      ),
    );
  }

  void selectCell(int row, int col) {
    if (isGameOver || _isGenerating || _isPaused) return;
    final cell = _cells[row][col];

    // Givens and locked correct fills aren't selectable — tap pulses matches.
    if (!cell.isEditable) {
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
    if (!_cells[row][col].isEditable) return;

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
    if (!_cells[row][col].isEditable) return;

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
    if (sel != null && _cells[sel.$1][sel.$2].isEditable) {
      enterBulkNoteSelect(sel.$1, sel.$2);
      return;
    }
    _bulkNoteSelect = true;
    if (!_noteMode) _noteMode = true;
    _selected = null;
    notifyListeners();
  }

  void _toggleBulkCell(int row, int col) {
    if (!_cells[row][col].isEditable) return;
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
    if (_selected == null && !_bulkNoteSelect && !_noteMode) return;
    _exitBulkNoteSelect();
    _selected = null;
    // Empty-space tap clears selection and fully exits note mode (single or bulk).
    _noteMode = false;
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
    // Correct locks are permanent — keep them across earlier undo snapshots.
    final locked = _snapshotLockedCells();
    final snap = _undoStack.removeLast();
    _cells = snap.cells;
    _restoreLockedCells(locked);
    _isWon = snap.isWon;
    _isLost = snap.isLost;
    _hasActiveGame = snap.hasActiveGame;
    _completedUnits = snap.completedUnits;
    final sel = snap.selected;
    _selected = sel != null && _cells[sel.$1][sel.$2].isEditable ? sel : null;
    _exitBulkNoteSelect();
    _celebration = null;
    _usedUndo = true;
    _consecutiveDistinctFillColors.clear();
    if (_hasActiveGame && !isGameOver && !_isPaused) {
      _startTimer();
    } else {
      _timer?.cancel();
    }
    _syncCompletedUnits(celebrate: false);
    _refreshConflicts();
    notifyListeners();
    unawaited(_achievements.recordUndo());
  }

  void setSelectedColor(int value) {
    final sel = _selected;
    if (sel == null || isGameOver || _isGenerating || _isPaused) return;
    final (row, col) = sel;
    final cell = _cells[row][col];
    if (!cell.isEditable) return;

    _hasInteracted = true;

    // Toggle off if same committed color tapped again — not a mistake.
    // (Locked correct fills never reach here.)
    if (cell.value == value) {
      _pushUndo();
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

    // Correct confirms aren't undoable; mistakes / edits still are.
    if (isMistake) {
      _pushUndo();
    }

    // Committing a full color clears any notes on this cell.
    // Correct fills lock so they can't be overwritten or erased.
    _cells[row][col] = cell.copyWith(
      value: value,
      clearNotes: true,
      isLocked: !isMistake,
    );
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
        _playSound(
          unitCompleted ? _sounds.playComplete : _placementConfirmSound(),
        );
      }
    }
    _checkWin();
    notifyListeners();
  }

  Future<void> Function() _placementConfirmSound() {
    final palette = activePalette;
    if (palette == GamePalette.world11) return _sounds.playCoin;
    if (palette == GamePalette.pkmn || palette == GamePalette.pkmn2) {
      return _sounds.playPlink;
    }
    if (palette == GamePalette.neon) return _sounds.playSlide;
    if (palette == GamePalette.rainbow) return _sounds.playRainbowConfirm;
    if (palette == GamePalette.glass) return _sounds.playGlassConfirm;
    if (palette == GamePalette.sky) return _sounds.playSkyConfirm;
    return _sounds.playConfirm;
  }

  /// Removes [value] from notes in peer cells of (row, col).
  void _clearPeerNotes(
    int row,
    int col,
    int value, {
    bool emitWave = true,
  }) {
    if (emitWave) {
      final seq = ++_noteClearWaveSeq;
      _noteClearWave = NoteClearWave(
        row: row,
        col: col,
        value: value,
        seq: seq,
      );
      // Drop the wave after the farthest ring can finish animating.
      final clearToken = ++_noteClearWaveClearToken;
      Future<void>.delayed(const Duration(milliseconds: 520), () {
        if (_noteClearWaveClearToken != clearToken) return;
        if (_noteClearWave?.seq == seq) {
          _noteClearWave = null;
        }
      });
    }

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
        if (!peer.isEditable || !peer.hasNote(value)) continue;
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
    if (!cell.isEditable) return;

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
    if (!cell.isEditable) return;

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
    if (!cell.isEditable) return;

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
      if (_cells[row][col].isEditable) yield (row, col);
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
    if (!cell.isEditable || cell.isEmpty) return;

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

  Map<(int, int), Cell> _snapshotLockedCells() {
    final locked = <(int, int), Cell>{};
    for (var r = 0; r < SudokuBoard.size; r++) {
      for (var c = 0; c < SudokuBoard.size; c++) {
        final cell = _cells[r][c];
        if (cell.isLocked) {
          locked[(r, c)] = Cell(
            value: cell.value,
            notes: {...cell.notes},
            isGiven: cell.isGiven,
            isLocked: true,
            hasConflict: cell.hasConflict,
          );
        }
      }
    }
    return locked;
  }

  void _restoreLockedCells(Map<(int, int), Cell> locked) {
    for (final entry in locked.entries) {
      final (row, col) = entry.key;
      final cell = entry.value;
      _cells[row][col] = cell;
      if (cell.value != 0) {
        _clearPeerNotes(row, col, cell.value, emitWave: false);
      }
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
          isLocked: cell.isLocked,
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
    if (_isDaily) return;
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

    // On the winning fill, skip — evaluateWin unlocks these from ctx and
    // owns the delayed achievement sting (avoids a double play).
    if (!_toBoard().isValidSolution() &&
        (_completedRowColBoxSimultaneously ||
            _completedNineUnitsInNineSeconds ||
            _filledNineDistinctColorsConsecutively)) {
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
    // Winning fill: evaluateWin records r5c5 from firstFillColor + delay SFX.
    if (isFirstFill &&
        !_toBoard().isValidSolution() &&
        activePalette == GamePalette.pkmn &&
        value == 3) {
      unawaited(
        _achievements.recordFirstFill(
          palette: activePalette,
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
      if (!_toBoard().isValidSolution()) {
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
      chromatic: _settings.chromatic && !_isDaily,
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
      // Daily losses don't touch the regular palette streak.
      if (!_isDaily) {
        _stats.resetStreakSync(palette: _settings.palette);
        unawaited(_stats.persist());
      }
    }
    if (_isDaily) {
      _heldDaily = null;
      unawaited(_prefs.clearParkedDailyGame());
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
      final winPalette = activePalette;
      _pendingPaletteUnlocks = _stats.recordWinSync(
        difficulty: _gameDifficulty,
        elapsed: _elapsed,
        mistakes: _mistakes,
        palette: winPalette,
        chromatic: _settings.chromatic && !_isDaily,
      );
      _settings.ensurePaletteUnlocked(_stats.stats);
      unawaited(_stats.persist());
      unawaited(
        _achievements.evaluateWin(
          difficulty: _gameDifficulty,
          elapsed: _elapsed,
          mistakes: _mistakes,
          palette: winPalette,
          ctx: _achievementGameContext(),
        ),
      );
      if (_isDaily) {
        _heldDaily = null;
        unawaited(_prefs.clearParkedDailyGame());
        unawaited(_recordDailyCompletion());
      }
    }
  }

  Future<void> _recordDailyCompletion() async {
    final dayKey = _dailyDayKey ?? DailyIrodoku.forDate().dayKey;
    final last = _prefs.getDailyLastCompletedDay();
    if (last == dayKey) return;

    final yesterday = DailyIrodoku.previousDayKey(dayKey);
    final streak = last == yesterday ? _prefs.getDailyStreak() + 1 : 1;
    await _prefs.setDailyProgress(
      lastCompletedDay: dayKey,
      streak: streak,
    );
    notifyListeners();
  }

  Future<void> _hydrateParkedHoldsFromDisk() async {
    final today = DailyIrodoku.forDate().dayKey;

    final parkedRegular = _prefs.loadParkedRegularGame();
    if (parkedRegular != null && !parkedRegular.isDaily) {
      _heldRegular = _heldFromPaused(parkedRegular);
    } else if (parkedRegular != null) {
      await _prefs.clearParkedRegularGame();
    }

    final parkedDaily = _prefs.loadParkedDailyGame();
    if (parkedDaily != null &&
        parkedDaily.isDaily &&
        parkedDaily.dailyDayKey == today) {
      _heldDaily = _heldFromPaused(parkedDaily);
    } else if (parkedDaily != null) {
      await _prefs.clearParkedDailyGame();
    }
  }

  Future<void> _parkRegularFromLive() async {
    if (!_hasActiveGame && !isGameOver && _solution == null) return;
    _heldRegular = _captureHeld();
    await _persistParkedRegular();
  }

  Future<void> _persistParkedRegular() async {
    final held = _heldRegular;
    if (held == null) {
      await _prefs.clearParkedRegularGame();
      return;
    }
    final paused = _pausedFromHeld(held);
    if (paused == null) {
      await _prefs.clearParkedRegularGame();
      return;
    }
    await _prefs.saveParkedRegularGame(paused);
  }

  Future<void> _persistParkedDaily() async {
    final held = _heldDaily;
    if (held == null) {
      await _prefs.clearParkedDailyGame();
      return;
    }
    final paused = _pausedFromHeld(held);
    if (paused == null) {
      await _prefs.clearParkedDailyGame();
      return;
    }
    await _prefs.saveParkedDailyGame(paused);
  }

  PausedGame? _pausedFromHeld(_HeldGameSession held) {
    final solution = held.solution;
    if (solution == null) return null;
    final flatCells = <Cell>[
      for (final row in held.cells)
        for (final cell in row) cell.copyWith(hasConflict: false),
    ];
    return PausedGame(
      difficulty: held.gameDifficulty,
      elapsed: held.elapsed,
      mistakes: held.mistakes,
      solution: solution,
      cells: flatCells,
      isDaily: held.isDaily,
      dailyDayKey: held.dailyDayKey,
    );
  }

  _HeldGameSession _heldFromPaused(PausedGame paused) {
    final cells = List.generate(SudokuBoard.size, (r) {
      return List.generate(SudokuBoard.size, (c) {
        return paused.cells[r * SudokuBoard.size + c].copyWith();
      });
    });
    final sessionPalette = paused.isDaily
        ? DailyIrodoku.forDate().palette
        : null;
    return _HeldGameSession(
      cells: cells,
      solution: paused.solution,
      selected: null,
      elapsed: paused.elapsed,
      mistakes: paused.mistakes,
      isWon: false,
      isLost: false,
      isPaused: true,
      hasActiveGame: true,
      hasInteracted: true,
      winRecorded: false,
      lossRecorded: false,
      gameDifficulty: paused.difficulty,
      completedUnits: {},
      noteMode: false,
      bulkNoteSelect: false,
      bulkSelected: {},
      undoStack: const [],
      isDaily: paused.isDaily,
      dailyDayKey: paused.dailyDayKey,
      sessionPalette: sessionPalette,
      firstFillColor: null,
      lastFillColor: null,
      lastFillRow: null,
      lastFillCol: null,
      usedNotes: false,
      usedUndo: false,
      pausedThisGame: true,
      completedRowColBoxSimultaneously: false,
      completedNineUnitsInNineSeconds: false,
      filledNineDistinctColorsConsecutively: false,
      rowsCompletedInFirst90Seconds: 0,
      colsCompletedInFirst90Seconds: 0,
      boxesCompletedInFirst90Seconds: 0,
      consecutiveDistinctFillColors: const [],
      unitCompletionTimes: const [],
    );
  }

  void _applyPausedBoard(PausedGame paused, {GamePalette? sessionPalette}) {
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
    _isDaily = paused.isDaily;
    _dailyDayKey = paused.dailyDayKey;
    _sessionPalette = sessionPalette;
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
  }

  _HeldGameSession _captureHeld() {
    return _HeldGameSession(
      cells: _cloneCells(),
      solution: _solution?.toFlat(),
      selected: _selected,
      elapsed: _elapsed,
      mistakes: _mistakes,
      isWon: _isWon,
      isLost: _isLost,
      isPaused: _isPaused,
      hasActiveGame: _hasActiveGame,
      hasInteracted: _hasInteracted,
      winRecorded: _winRecorded,
      lossRecorded: _lossRecorded,
      gameDifficulty: _gameDifficulty,
      completedUnits: {..._completedUnits},
      noteMode: _noteMode,
      bulkNoteSelect: _bulkNoteSelect,
      bulkSelected: {..._bulkSelected},
      undoStack: [
        for (final snap in _undoStack)
          _UndoSnapshot(
            cells: [
              for (final row in snap.cells)
                [for (final cell in row) cell.copyWith()],
            ],
            isWon: snap.isWon,
            isLost: snap.isLost,
            hasActiveGame: snap.hasActiveGame,
            completedUnits: {...snap.completedUnits},
            selected: snap.selected,
          ),
      ],
      isDaily: _isDaily,
      dailyDayKey: _dailyDayKey,
      sessionPalette: _sessionPalette,
      firstFillColor: _firstFillColor,
      lastFillColor: _lastFillColor,
      lastFillRow: _lastFillRow,
      lastFillCol: _lastFillCol,
      usedNotes: _usedNotes,
      usedUndo: _usedUndo,
      pausedThisGame: _pausedThisGame,
      completedRowColBoxSimultaneously: _completedRowColBoxSimultaneously,
      completedNineUnitsInNineSeconds: _completedNineUnitsInNineSeconds,
      filledNineDistinctColorsConsecutively:
          _filledNineDistinctColorsConsecutively,
      rowsCompletedInFirst90Seconds: _rowsCompletedInFirst90Seconds,
      colsCompletedInFirst90Seconds: _colsCompletedInFirst90Seconds,
      boxesCompletedInFirst90Seconds: _boxesCompletedInFirst90Seconds,
      consecutiveDistinctFillColors: [..._consecutiveDistinctFillColors],
      unitCompletionTimes: [..._unitCompletionTimes],
    );
  }

  void _applyHeld(_HeldGameSession held) {
    _timer?.cancel();
    _generationToken++;
    _cells = [
      for (final row in held.cells) [for (final cell in row) cell.copyWith()],
    ];
    _solution =
        held.solution == null ? null : SudokuBoard.fromFlat(held.solution!);
    _selected = held.selected;
    _elapsed = held.elapsed;
    _mistakes = held.mistakes;
    _isWon = held.isWon;
    _isLost = held.isLost;
    _isPaused = held.isPaused;
    _hasActiveGame = held.hasActiveGame;
    _hasInteracted = held.hasInteracted;
    _winRecorded = held.winRecorded;
    _lossRecorded = held.lossRecorded;
    _gameDifficulty = held.gameDifficulty;
    _celebration = null;
    _noteMode = held.noteMode;
    _bulkNoteSelect = held.bulkNoteSelect;
    _bulkSelected
      ..clear()
      ..addAll(held.bulkSelected);
    _undoStack
      ..clear()
      ..addAll(held.undoStack);
    _isDaily = held.isDaily;
    _dailyDayKey = held.dailyDayKey;
    _sessionPalette = held.sessionPalette;
    _isGenerating = false;
    _pendingPaletteUnlocks = [];
    _noteClearWave = null;
    _firstFillColor = held.firstFillColor;
    _lastFillColor = held.lastFillColor;
    _lastFillRow = held.lastFillRow;
    _lastFillCol = held.lastFillCol;
    _usedNotes = held.usedNotes;
    _usedUndo = held.usedUndo;
    _pausedThisGame = held.pausedThisGame;
    _completedRowColBoxSimultaneously = held.completedRowColBoxSimultaneously;
    _completedNineUnitsInNineSeconds = held.completedNineUnitsInNineSeconds;
    _filledNineDistinctColorsConsecutively =
        held.filledNineDistinctColorsConsecutively;
    _rowsCompletedInFirst90Seconds = held.rowsCompletedInFirst90Seconds;
    _colsCompletedInFirst90Seconds = held.colsCompletedInFirst90Seconds;
    _boxesCompletedInFirst90Seconds = held.boxesCompletedInFirst90Seconds;
    _consecutiveDistinctFillColors
      ..clear()
      ..addAll(held.consecutiveDistinctFillColors);
    _unitCompletionTimes
      ..clear()
      ..addAll(held.unitCompletionTimes);
    _completedUnits = _successfullyCompletedUnits();
    if (_hasActiveGame && !isGameOver && !_isPaused) {
      _startTimer();
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

/// In-memory puzzle session for nesting Daily under Main Menu.
class _HeldGameSession {
  final List<List<Cell>> cells;
  final List<int>? solution;
  final (int, int)? selected;
  final Duration elapsed;
  final int mistakes;
  final bool isWon;
  final bool isLost;
  final bool isPaused;
  final bool hasActiveGame;
  final bool hasInteracted;
  final bool winRecorded;
  final bool lossRecorded;
  final Difficulty gameDifficulty;
  final Set<String> completedUnits;
  final bool noteMode;
  final bool bulkNoteSelect;
  final Set<int> bulkSelected;
  final List<_UndoSnapshot> undoStack;
  final bool isDaily;
  final String? dailyDayKey;
  final GamePalette? sessionPalette;
  final int? firstFillColor;
  final int? lastFillColor;
  final int? lastFillRow;
  final int? lastFillCol;
  final bool usedNotes;
  final bool usedUndo;
  final bool pausedThisGame;
  final bool completedRowColBoxSimultaneously;
  final bool completedNineUnitsInNineSeconds;
  final bool filledNineDistinctColorsConsecutively;
  final int rowsCompletedInFirst90Seconds;
  final int colsCompletedInFirst90Seconds;
  final int boxesCompletedInFirst90Seconds;
  final List<int> consecutiveDistinctFillColors;
  final List<DateTime> unitCompletionTimes;

  const _HeldGameSession({
    required this.cells,
    required this.solution,
    required this.selected,
    required this.elapsed,
    required this.mistakes,
    required this.isWon,
    required this.isLost,
    required this.isPaused,
    required this.hasActiveGame,
    required this.hasInteracted,
    required this.winRecorded,
    required this.lossRecorded,
    required this.gameDifficulty,
    required this.completedUnits,
    required this.noteMode,
    required this.bulkNoteSelect,
    required this.bulkSelected,
    required this.undoStack,
    required this.isDaily,
    required this.dailyDayKey,
    required this.sessionPalette,
    required this.firstFillColor,
    required this.lastFillColor,
    required this.lastFillRow,
    required this.lastFillCol,
    required this.usedNotes,
    required this.usedUndo,
    required this.pausedThisGame,
    required this.completedRowColBoxSimultaneously,
    required this.completedNineUnitsInNineSeconds,
    required this.filledNineDistinctColorsConsecutively,
    required this.rowsCompletedInFirst90Seconds,
    required this.colsCompletedInFirst90Seconds,
    required this.boxesCompletedInFirst90Seconds,
    required this.consecutiveDistinctFillColors,
    required this.unitCompletionTimes,
  });
}

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/palette.dart';
import '../models/achievement.dart';
import '../models/cell.dart';
import '../models/daily_irodoku.dart';
import '../models/difficulty.dart';
import '../models/game_palette.dart';
import '../models/iro_mix.dart';
import '../models/palette_swatch.dart';
import '../models/note_clear_wave.dart';
import '../models/paused_game.dart';
import '../models/unit_celebration.dart';
import '../services/preferences_service.dart';
import '../services/sound_service.dart';
import '../sudoku/master_board_bank.dart';
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

/// Top-level entry for isolate-friendly Pocket puzzle generation.
///
/// [seed] `< 0` means unseeded [Random].
/// Returns `[puzzleFlat, solutionFlat]` as length-36 int lists.
List<List<int>> generatePocketIsolate(int seed) {
  final random = seed < 0 ? Random() : Random(seed);
  final generated = SudokuGenerator(random: random).generatePocket();
  return [generated.puzzle.toFlat(), generated.solution.toFlat()];
}

class GameProvider extends ChangeNotifier {
  static const int maxMistakes = 3;
  static const int pocketMaxMistakes = 2;

  /// TEMP: fake Main Menu Daily streak for pill-sweep testing.
  /// Does not write to prefs. Set to `null` when done.
  static const int? debugDailyStreakOverride = null;

  final SettingsProvider _settings;
  final StatsProvider _stats;
  final AchievementsProvider _achievements;
  final PreferencesService _prefs;
  final SoundService _sounds;
  final bool _ownsSounds;

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
  /// Classic / Chromatic / Pocket: this board was restarted after a defeat.
  bool _retriedAfterLoss = false;
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
  bool _isPocket = false;

  /// Daily-only display palette — never written to [SettingsProvider].
  GamePalette? _sessionPalette;

  /// Compiled Iro mashup for this board (Classic / Pocket / Chromatic hops).
  IroMix? _iroMix;

  /// Pocket: 0 = slots 1–6, 3 = slots 4–9. Always 0 on 9×9, Daily, and Graffiti.
  int _pocketSwatchOffset = 0;

  /// Classic (non-chromatic) puzzle parked while Daily/Chromatic is active.
  _HeldGameSession? _heldRegular;

  /// Chromatic puzzle parked while Classic/Daily is active.
  _HeldGameSession? _heldChromatic;

  /// In-progress Daily parked while browsing Main Menu.
  _HeldGameSession? _heldDaily;

  /// Pocket puzzle parked while Classic/Chromatic/Daily is active.
  _HeldGameSession? _heldPocket;

  /// 6×6 Chromatic Pocket parked while Classic / 9×9 Chromatic / Pocket / Daily is active.
  _HeldGameSession? _heldPocketChromatic;

  /// In-progress 6×6 [Daily] parked while browsing Main Menu.
  _HeldGameSession? _heldPocketDaily;

  /// After cold restore of a paused Daily, home should open Main Menu → Daily.
  bool _openDailyRoutePending = false;

  /// Viewing today's already-won Daily (frozen board; no result dialog).
  bool _dailyReviewMode = false;

  /// Warm Master puzzle: `[puzzleFlat, solutionFlat]` ready for instant start.
  List<List<int>>? _cachedMasterBoards;

  /// In-flight Master prefetch so New Game can await instead of double-generating.
  Future<void>? _masterPrefetchFuture;

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
        _ownsSounds = sounds == null,
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
  bool get isPocket => _isPocket;
  bool get isPocketDaily => _isDaily && _isPocket;
  int get mistakeLimit =>
      _isPocket ? pocketMaxMistakes : maxMistakes;
  int get gridSize =>
      _isPocket ? SudokuBoard.pocketSize : SudokuBoard.size;
  int get boxW =>
      _isPocket ? SudokuBoard.pocketBoxWidth : SudokuBoard.boxSize;
  int get boxH =>
      _isPocket ? SudokuBoard.pocketBoxHeight : SudokuBoard.boxSize;

  /// True when reopening today's completed Daily for viewing only.
  bool get isDailyReview => _dailyReviewMode;

  /// Palette for the live board (daily session override or settings).
  /// A live Iro mix keeps the board on Iro even if Config is changed mid-game
  /// (Chromatic hops leave [_sessionPalette] unset).
  GamePalette get activePalette =>
      _iroMix != null ? GamePalette.iro : (_sessionPalette ?? _settings.palette);

  List<PaletteSwatch>? get displaySwatches {
    final full = _iroMix?.swatches;
    if (!_isPocket) return full;
    final source = full ?? IrodokuPalette.swatchesFor(activePalette);
    return IrodokuPalette.pocketWindow(source, pocketSwatchOffset);
  }

  String? get iroMixKey {
    final mix = _iroMix?.key;
    final offset = pocketSwatchOffset;
    if (offset == 0) return mix;
    return '${mix ?? activePalette.storageKey}:w$offset';
  }

  List<GamePalette>? get iroSources {
    final full = _iroMix?.sources;
    if (full == null) return null;
    if (!_isPocket) return full;
    return IrodokuPalette.pocketWindow(full, pocketSwatchOffset);
  }

  /// 0 or 3. Always 0 outside eligible Pocket (not Daily).
  int get pocketSwatchOffset =>
      (_isPocket && !_isDaily) ? _pocketSwatchOffset : 0;

  /// Short date for the active daily (`8.9.26`), or null when not daily.
  String? get dailyDateLabel {
    final key = _dailyDayKey;
    if (key == null) return null;
    return DailyIrodoku.shortDateLabel(key);
  }

  /// Whether today's Daily Irodoku has already been won (PST day).
  bool get isDailyCompletedToday {
    final today = DailyIrodoku.forDate().dayKey;
    return _prefs.getDailyLastCompletedDay() == today;
  }

  bool get isPocketDailyCompletedToday {
    final today = DailyIrodoku.forDate().dayKey;
    return _prefs.getPocketDailyLastCompletedDay() == today;
  }

  void notifyProgressReloaded() => notifyListeners();

  /// Won today's Daily — review only; losses can still be retried.
  bool get isDailyFinishedToday => isDailyCompletedToday;

  bool get isPocketDailyFinishedToday => isPocketDailyCompletedToday;

  /// Whether today's Daily Irodoku has already been lost (PST day).
  bool get isDailyFailedToday {
    final today = DailyIrodoku.forDate().dayKey;
    return _prefs.getDailyLastFailedDay() == today;
  }

  /// True when today's daily is live or parked for resume from Main Menu.
  bool get hasResumableDaily {
    final today = DailyIrodoku.forDate().dayKey;
    if (isDailyFinishedToday) return false;
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
    if (debugDailyStreakOverride != null) return debugDailyStreakOverride!;
    final today = DailyIrodoku.forDate().dayKey;
    final last = _prefs.getDailyLastCompletedDay();
    if (last == null) return 0;
    if (last != today && last != DailyIrodoku.previousDayKey(today)) {
      return 0;
    }
    return _prefs.getDailyStreak();
  }

  int get pocketDailyStreakDisplay {
    final today = DailyIrodoku.forDate().dayKey;
    final last = _prefs.getPocketDailyLastCompletedDay();
    if (last == null) return 0;
    if (last != today && last != DailyIrodoku.previousDayKey(today)) {
      return 0;
    }
    return _prefs.getPocketDailyStreak();
  }

  /// Streak after today's Daily win: continues from yesterday, else resets to 1.
  int _dailyStreakAfterThisWin({required bool pocket}) {
    final dayKey = _dailyDayKey ?? DailyIrodoku.forDate().dayKey;
    final last = pocket
        ? _prefs.getPocketDailyLastCompletedDay()
        : _prefs.getDailyLastCompletedDay();
    if (last == dayKey) {
      return pocket
          ? _prefs.getPocketDailyStreak()
          : _prefs.getDailyStreak();
    }
    final yesterday = DailyIrodoku.previousDayKey(dayKey);
    if (pocket) {
      return last == yesterday ? _prefs.getPocketDailyStreak() + 1 : 1;
    }
    return last == yesterday ? _prefs.getDailyStreak() + 1 : 1;
  }

  /// All-time highest Daily Iro win streak (survives missed days).
  int get dailyBestStreak => _prefs.getDailyBestStreak();

  int get pocketDailyBestStreak => _prefs.getPocketDailyBestStreak();

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

  int _cellKey(int row, int col) => row * gridSize + col;

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
    final half = gridSize ~/ 2;
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
      } else if (paused.isPocket) {
        // Pocket [Daily] stays nested; cold-start never auto-opens it.
        _heldPocketDaily = _heldFromPaused(paused);
        await _persistParkedPocketDaily();
        await _prefs.clearPausedGame();
        await _restoreHomeFromParkedHolds(preserveDaily: true);
        unawaited(prefetchMasterPuzzle());
        return;
      } else {
        // Don't put Daily on the home route — park it and reopen nested.
        _heldDaily = _heldFromPaused(paused);
        await _persistParkedDaily();
        await _prefs.clearPausedGame();
        _openDailyRoutePending = true;
        await _restoreHomeFromParkedHolds(preserveDaily: true);
        unawaited(prefetchMasterPuzzle());
        return;
      }
    }

    final restored = await restorePausedGame();
    if (restored) {
      unawaited(prefetchMasterPuzzle());
      return;
    }

    // Killed on Main Menu: puzzles may exist only as parked holds.
    await _restoreHomeFromParkedHolds(
      preserveDaily: _heldDaily != null || _heldPocketDaily != null,
    );
    unawaited(prefetchMasterPuzzle());
  }

  /// Pre-generates one Master puzzle when the shipped bank is unavailable.
  Future<void> prefetchMasterPuzzle() async {
    if (MasterBoardBank.isLoaded) return;
    if (!_stats.isUnlocked(Difficulty.master)) return;
    if (_cachedMasterBoards != null) return;
    if (_masterPrefetchFuture != null) {
      await _masterPrefetchFuture;
      return;
    }

    final future = _runMasterPrefetch();
    _masterPrefetchFuture = future;
    try {
      await future;
    } finally {
      if (identical(_masterPrefetchFuture, future)) {
        _masterPrefetchFuture = null;
      }
    }
  }

  Future<void> _runMasterPrefetch() async {
    try {
      final boards = await compute(
        generatePuzzleIsolate,
        <Object>[Difficulty.master.storageKey, -1],
      );
      _cachedMasterBoards ??= boards;
    } catch (_) {
      // Prefetch is best-effort; New Game can still generate on demand.
    }
  }

  /// Prefers the shipped Master board bank; falls back to warm cache / generate.
  Future<List<List<int>>> _obtainMasterBoards({required int? seed}) async {
    if (seed != null) {
      return compute(
        generatePuzzleIsolate,
        <Object>[Difficulty.master.storageKey, seed],
      );
    }

    // Instant path: precomputed Master puzzles.
    if (MasterBoardBank.isLoaded) {
      return MasterBoardBank.takeRandom();
    }

    final cached = _cachedMasterBoards;
    if (cached != null) {
      _cachedMasterBoards = null;
      unawaited(prefetchMasterPuzzle());
      return cached;
    }

    if (_masterPrefetchFuture != null) {
      await _masterPrefetchFuture;
      final warmed = _cachedMasterBoards;
      if (warmed != null) {
        _cachedMasterBoards = null;
        unawaited(prefetchMasterPuzzle());
        return warmed;
      }
    }

    final boards = await compute(
      generatePuzzleIsolate,
      <Object>[Difficulty.master.storageKey, -1],
    );
    unawaited(prefetchMasterPuzzle());
    return boards;
  }

  /// Prefer Classic hold, then Chromatic; otherwise start a new home game.
  Future<void> _restoreHomeFromParkedHolds({required bool preserveDaily}) async {
    if (_heldRegular != null) {
      await _settings.setChromatic(false);
      _applyHeld(_heldRegular!);
      _heldRegular = null;
      await _prefs.clearParkedRegularGame();
      notifyListeners();
      return;
    }
    if (_heldChromatic != null) {
      await _settings.setChromatic(true);
      _applyHeld(_heldChromatic!);
      _heldChromatic = null;
      await _prefs.clearParkedChromaticGame();
      notifyListeners();
      return;
    }
    await startNewGame(preserveHeldDaily: preserveDaily);
  }

  Future<bool> restorePausedGame() async {
    final paused = _prefs.loadPausedGame();
    if (paused == null) return false;

    // Stale / unexpected daily — bootstrap handles today's paused Daily.
    if (paused.isDaily) {
      await _prefs.clearPausedGame();
      return false;
    }

    _applyPausedBoard(paused, sessionPalette: paused.sessionPalette);
    notifyListeners();
    return true;
  }

  /// Starts or resumes today's seeded Daily Irodoku.
  ///
  /// Parks the regular puzzle first so Main Menu back can restore it.
  /// If today's Daily is already won, opens the frozen board.
  Future<bool> startDailyGame() async {
    final challenge = DailyIrodoku.forDate();
    if (_isGenerating) return false;
    if (!_stats.devMode && !_stats.stats.isDailyChallengeUnlocked) {
      return false;
    }

    // Reopen today's completed Daily (frozen win, same as post-victory board).
    if (_prefs.getDailyLastCompletedDay() == challenge.dayKey) {
      final completed = _prefs.loadCompletedDailyGame();
      if (completed == null || completed.dailyDayKey != challenge.dayKey) {
        return false;
      }
      if (!(_isDaily && !_isPocket)) {
        await _parkHomeLive();
      }
      _applyFinishedDailyReview(completed, won: true);
      notifyListeners();
      return true;
    }

    // Older builds locked the day after a loss. Retries are allowed now.
    if (_prefs.getDailyLastFailedDay() == challenge.dayKey) {
      await _prefs.clearDailyFailedDay();
      await _prefs.clearFailedDailyGame();
    }

    _dailyReviewMode = false;

    // Resume a daily parked while browsing Main Menu.
    if (_heldDaily != null && _heldDaily!.dailyDayKey == challenge.dayKey) {
      if (!(_isDaily && !_isPocket)) {
        await _parkHomeLive();
      }
      _applyHeld(_heldDaily!);
      _heldDaily = null;
      await _prefs.clearParkedDailyGame();
      // Keep parked session palette (may already be the second hop).
      _sessionPalette ??= challenge.palette;
      _ensureDailyPaletteForProgress();
      notifyListeners();
      return true;
    }

    // Already on today's live 9×9 daily board (still in progress).
    if (_isDaily &&
        !_isPocket &&
        _dailyDayKey == challenge.dayKey &&
        !isGameOver) {
      _sessionPalette ??= challenge.palette;
      _ensureDailyPaletteForProgress();
      notifyListeners();
      return true;
    }

    // Park whatever is live if it isn't this 9×9 Daily.
    if (_isDaily && _isPocket) {
      await _parkLiveDailyToHold();
    } else if (!_isDaily) {
      await _parkHomeLive();
    } else {
      _heldDaily = null;
      await _prefs.clearParkedDailyGame();
    }

    _sessionPalette = challenge.palette;
    await startNewGame(
      difficulty: challenge.difficulty,
      seed: challenge.seed,
      dailyDayKey: challenge.dayKey,
      pocket: false,
    );
    return true;
  }

  /// Starts or resumes today's seeded 6×6 [Daily Challenge].
  Future<bool> startPocketDailyGame() async {
    final challenge = DailyIrodoku.pocketForDate();
    if (_isGenerating) return false;
    if (!_stats.devMode && !_stats.stats.isPocketDailyUnlocked) {
      return false;
    }

    if (_prefs.getPocketDailyLastCompletedDay() == challenge.dayKey) {
      final completed = _prefs.loadCompletedPocketDailyGame();
      if (completed == null || completed.dailyDayKey != challenge.dayKey) {
        return false;
      }
      if (!isPocketDaily) {
        await _parkHomeLive();
      }
      _applyFinishedDailyReview(completed, won: true);
      notifyListeners();
      return true;
    }

    _dailyReviewMode = false;

    if (_heldPocketDaily != null &&
        _heldPocketDaily!.dailyDayKey == challenge.dayKey) {
      if (!isPocketDaily) {
        await _parkHomeLive();
      }
      _applyHeld(_heldPocketDaily!);
      _heldPocketDaily = null;
      await _prefs.clearParkedPocketDailyGame();
      _sessionPalette ??= challenge.palette;
      _ensureDailyPaletteForProgress();
      notifyListeners();
      return true;
    }

    if (isPocketDaily &&
        _dailyDayKey == challenge.dayKey &&
        !isGameOver) {
      _sessionPalette ??= challenge.palette;
      _ensureDailyPaletteForProgress();
      notifyListeners();
      return true;
    }

    if (_isDaily && !_isPocket) {
      await _parkLiveDailyToHold();
    } else if (!isPocketDaily) {
      await _parkHomeLive();
    } else {
      _heldPocketDaily = null;
      await _prefs.clearParkedPocketDailyGame();
    }

    _sessionPalette = challenge.palette;
    await startNewGame(
      difficulty: challenge.difficulty,
      seed: challenge.seed,
      dailyDayKey: challenge.dayKey,
      pocket: true,
    );
    return true;
  }

  /// Restart today's Daily from the given cells after a defeat.
  Future<void> retryDailyGame() async {
    if (!_isDaily || _isGenerating) return;
    if (_isPocket) {
      if (isPocketDailyCompletedToday) return;
    } else if (isDailyCompletedToday) {
      return;
    }
    final challenge =
        _isPocket ? DailyIrodoku.pocketForDate() : DailyIrodoku.forDate();
    if (!_isPocket) {
      await _prefs.clearDailyFailedDay();
      await _prefs.clearFailedDailyGame();
    }
    _sessionPalette = challenge.palette;
    await startNewGame(
      difficulty: challenge.difficulty,
      seed: challenge.seed,
      dailyDayKey: challenge.dayKey,
      pocket: _isPocket,
    );
    if (_isPocket) {
      _retriedAfterLoss = true;
      notifyListeners();
    }
  }

  /// Restart the current Classic / Chromatic / Pocket board after a defeat.
  Future<void> retryFromDefeat() async {
    if (_isGenerating || !isLost) return;
    if (_isDaily) {
      await retryDailyGame();
      return;
    }
    _retryCurrentPuzzle();
  }

  void _retryCurrentPuzzle() {
    if (_solution == null) return;
    _timer?.cancel();
    _retriedAfterLoss = true;
    _isWon = false;
    _isLost = false;
    _isPaused = false;
    _hasActiveGame = true;
    _winRecorded = false;
    _lossRecorded = false;
    _hasInteracted = false;
    _mistakes = 0;
    _pendingPaletteUnlocks = [];
    _selected = null;
    _exitBulkNoteSelect();
    _elapsed = Duration.zero;
    _sessionPalette = _iroMix != null ? GamePalette.iro : null;
    _celebration = null;
    _noteClearWave = null;
    _noteMode = false;
    _undoStack.clear();
    _colorCycleFilterValue = null;
    for (var r = 0; r < gridSize; r++) {
      for (var c = 0; c < gridSize; c++) {
        final cell = _cells[r][c];
        _cells[r][c] = cell.isGiven
            ? Cell(value: cell.value, isGiven: true)
            : const Cell();
      }
    }
    _completedUnits = _successfullyCompletedUnits();
    _resetAchievementSession();
    unawaited(_prefs.clearPausedGame());
    _startTimer();
    notifyListeners();
  }

  /// Park the live Daily when leaving its screen for Main Menu.
  void parkDailyForMenu() {
    if (!_isDaily) return;
    unawaited(_parkLiveDailyToHold());
    _dailyReviewMode = false;
    _sessionPalette = null;
    notifyListeners();
  }

  /// Restore the parked Classic/Chromatic/Pocket puzzle when leaving Main Menu.
  Future<void> leaveMenuToRegular({bool pocket = false}) async {
    // Clear any legacy prefs from older daily palette forcing.
    await _prefs.clearPaletteBeforeDaily();

    // Classic / Chromatic / Pocket buttons already swapped the live board
    // before pop. Don't restore a parked hold on top of that.
    // Keep [_sessionPalette] when returning to a live Chromatic game so hops
    // survive a Main Menu visit (Config still shows the saved palette).
    if (!_isDaily) {
      notifyListeners();
      return;
    }

    if (pocket) {
      await _leaveMenuToPocketHome();
      return;
    }

    final preferChromatic = _settings.chromatic;
    var held = preferChromatic ? _heldChromatic : _heldRegular;
    var heldIsChromatic = preferChromatic && held != null;
    if (held == null) {
      held = _heldRegular ?? _heldChromatic;
      heldIsChromatic = held != null && identical(held, _heldChromatic);
    }
    if (held == null) {
      final parked = preferChromatic
          ? _prefs.loadParkedChromaticGame()
          : _prefs.loadParkedRegularGame();
      if (parked != null && !parked.isDaily && !parked.isPocket) {
        held = _heldFromPaused(parked);
        heldIsChromatic = preferChromatic;
      }
    }
    if (held == null) {
      final parkedAlt = preferChromatic
          ? _prefs.loadParkedRegularGame()
          : _prefs.loadParkedChromaticGame();
      if (parkedAlt != null && !parkedAlt.isDaily && !parkedAlt.isPocket) {
        held = _heldFromPaused(parkedAlt);
        heldIsChromatic = !preferChromatic;
      }
    }
    if (held == null) {
      // Live board is still Daily — park it and start a fresh home game.
      await _parkLiveDailyToHold();
      await startNewGame(preserveHeldDaily: true);
      return;
    }

    await _parkLiveDailyToHold();
    await _settings.setChromatic(heldIsChromatic);
    _applyHeld(held);
    if (heldIsChromatic) {
      _heldChromatic = null;
      await _prefs.clearParkedChromaticGame();
    } else {
      _heldRegular = null;
      await _prefs.clearParkedRegularGame();
    }
    notifyListeners();
  }

  Future<void> _leaveMenuToPocketHome() async {
    final preferChromatic = _settings.chromatic;
    var held = preferChromatic ? _heldPocketChromatic : _heldPocket;
    var heldIsChromatic = preferChromatic && held != null;
    if (held == null) {
      held = _heldPocket ?? _heldPocketChromatic;
      heldIsChromatic = held != null && identical(held, _heldPocketChromatic);
    }
    if (held == null) {
      final parked = preferChromatic
          ? _prefs.loadParkedPocketChromaticGame()
          : _prefs.loadParkedPocketGame();
      if (parked != null && parked.isPocket && !parked.isDaily) {
        held = _heldFromPaused(parked);
        heldIsChromatic = preferChromatic;
      }
    }
    if (held == null) {
      final parkedAlt = preferChromatic
          ? _prefs.loadParkedPocketGame()
          : _prefs.loadParkedPocketChromaticGame();
      if (parkedAlt != null && parkedAlt.isPocket && !parkedAlt.isDaily) {
        held = _heldFromPaused(parkedAlt);
        heldIsChromatic = !preferChromatic;
      }
    }
    if (held == null) {
      await _parkLiveDailyToHold();
      await startNewGame(preserveHeldDaily: true, pocket: true);
      return;
    }

    await _parkLiveDailyToHold();
    await _settings.setChromatic(heldIsChromatic);
    _applyHeld(held);
    if (heldIsChromatic) {
      _heldPocketChromatic = null;
      await _prefs.clearParkedPocketChromaticGame();
    } else {
      _heldPocket = null;
      await _prefs.clearParkedPocketGame();
    }
    notifyListeners();
  }

  Future<void> startNewGame({
    Difficulty? difficulty,
    int? seed,
    String? dailyDayKey,
    bool preserveHeldDaily = false,
    bool? pocket,
  }) async {
    final startingDaily = dailyDayKey != null;
    final startingPocket = pocket ?? (!startingDaily && _isPocket);
    _dailyReviewMode = false;
    if (startingDaily) {
      if (startingPocket) {
        _heldPocketDaily = null;
        await _prefs.clearParkedPocketDailyGame();
      } else {
        _heldDaily = null;
        await _prefs.clearParkedDailyGame();
      }
    } else if (startingPocket) {
      // New Pocket keeps parked Classic/Chromatic/Daily and the other Pocket flavor.
      if (_settings.chromatic) {
        _heldPocketChromatic = null;
        await _prefs.clearParkedPocketChromaticGame();
      } else {
        _heldPocket = null;
        await _prefs.clearParkedPocketGame();
      }
      _sessionPalette = null;
    } else if (preserveHeldDaily) {
      // Regenerate the live Classic/Chromatic board without wiping Daily.
      // When Daily is still the live board (under Main Menu), only re-park it —
      // do not clear parked Classic/Chromatic and do not replace the Daily board.
      if (_isDaily) {
        await _parkLiveDailyToHold();
        _sessionPalette = null;
        await _prefs.clearPaletteBeforeDaily();
        notifyListeners();
        return;
      }
      if (_isPocket) {
        await _parkLivePocket();
      }
      if (_settings.chromatic) {
        _heldChromatic = null;
        await _prefs.clearParkedChromaticGame();
      } else {
        _heldRegular = null;
        await _prefs.clearParkedRegularGame();
      }
      _sessionPalette = null;
      await _prefs.clearPaletteBeforeDaily();
    } else {
      // Starting a fresh regular game abandons nested holds.
      _heldDaily = null;
      _heldRegular = null;
      _heldChromatic = null;
      _heldPocket = null;
      _heldPocketChromatic = null;
      _heldPocketDaily = null;
      _sessionPalette = null;
      await _prefs.clearParkedDailyGame();
      await _prefs.clearParkedRegularGame();
      await _prefs.clearParkedChromaticGame();
      await _prefs.clearParkedPocketGame();
      await _prefs.clearParkedPocketChromaticGame();
      await _prefs.clearParkedPocketDailyGame();
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
    _retriedAfterLoss = false;
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
    _isPocket = startingPocket;
    _prepareIroMix(daily: startingDaily);
    _rollPocketSwatchOffset();
    final n = gridSize;
    _cells = List.generate(n, (_) => List.generate(n, (_) => const Cell()));
    if (startingDaily && _sessionPalette == null) {
      _sessionPalette = startingPocket
          ? DailyIrodoku.pocketForDate().palette
          : DailyIrodoku.forDate().palette;
    }
    _completedUnits = {};
    _celebration = null;
    _noteMode = false;
    _undoStack.clear();
    _resetAchievementSession();
    await _prefs.clearPausedGame();
    notifyListeners();

    final List<List<int>> boards;
    final usedMasterWarmPath = !startingDaily &&
        !startingPocket &&
        _gameDifficulty == Difficulty.master &&
        seed == null;
    if (startingPocket) {
      boards = await compute(generatePocketIsolate, seed ?? -1);
    } else if (!startingDaily && _gameDifficulty == Difficulty.master) {
      boards = await _obtainMasterBoards(seed: seed);
    } else {
      boards = await compute(
        generatePuzzleIsolate,
        <Object>[_gameDifficulty.storageKey, seed ?? -1],
      );
      unawaited(prefetchMasterPuzzle());
    }

    if (token != _generationToken) {
      // Generation was superseded (mode switch / rapid New Game). Put an
      // unused unseeded Master board back so the warm cache isn't burned.
      if (usedMasterWarmPath) {
        _cachedMasterBoards ??= boards;
      }
      return;
    }

    final puzzle = SudokuBoard.fromFlat(boards[0], pocket: startingPocket);
    _solution = SudokuBoard.fromFlat(boards[1], pocket: startingPocket);
    _cells = List.generate(n, (r) {
      return List.generate(n, (c) {
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
    if (!startingPocket) {
      await _stats.recordGameStarted();
    }
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
    _playSound(_sounds.playIgMenu);
  }

  Future<void> resumeGame() async {
    if (!_isPaused || isGameOver) return;
    _isPaused = false;
    await _prefs.clearPausedGame();
    _startTimer();
    notifyListeners();
    _playSound(_sounds.playIgMenu);
  }

  Future<void> togglePause() async {
    if (_isPaused) {
      await resumeGame();
    } else {
      await pauseGame();
    }
  }

  Future<void> _savePausedGame() async {
    if (!_hasActiveGame || isGameOver) return;
    final snapshot = _snapshotLiveGame();
    if (snapshot == null) return;
    await _prefs.savePausedGame(snapshot);
  }

  PausedGame? _snapshotLiveGame() {
    final solution = _solution;
    if (solution == null) return null;

    final flatCells = <Cell>[
      for (var r = 0; r < gridSize; r++)
        for (var c = 0; c < gridSize; c++)
          _cells[r][c].copyWith(hasConflict: false),
    ];

    return PausedGame(
      difficulty: _gameDifficulty,
      elapsed: _elapsed,
      mistakes: _mistakes,
      solution: solution.toFlat(),
      cells: flatCells,
      isDaily: _isDaily,
      isPocket: _isPocket,
      dailyDayKey: _dailyDayKey,
      sessionPalette: _sessionPalette,
      iroSources: _iroMix?.toKeys(),
      pocketSwatchOffset: pocketSwatchOffset,
      usedNotes: _usedNotes,
      retriedAfterLoss: _retriedAfterLoss,
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
        _selected = (last ~/ gridSize, last % gridSize);
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
      final row = key ~/ gridSize;
      final col = key % gridSize;
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
    if (!_isPocket) unawaited(_achievements.recordUndo());
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
      if (!_isPocket) unawaited(_achievements.recordErase());
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
      if (_mistakes >= mistakeLimit) {
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
          unitCompleted
              ? _sounds.playComplete
              : _placementConfirmSound(value),
        );
      }
    }
    _checkWin();
    notifyListeners();
  }

  Future<void> Function() _placementConfirmSound(int value) {
    final slot = value + pocketSwatchOffset;
    final mix = _iroMix;
    final palette = mix != null && slot >= 1 && slot <= mix.sources.length
        ? mix.sources[slot - 1]
        : activePalette;
    if (palette == GamePalette.world11) return _sounds.playCoin;
    if (palette == GamePalette.pkmn || palette == GamePalette.pkmn2) {
      return _sounds.playPlink;
    }
    if (palette == GamePalette.neon) return _sounds.playSlide;
    if (palette == GamePalette.rainbow) return _sounds.playRainbowConfirm;
    if (palette == GamePalette.glass || palette == GamePalette.sky) {
      return () => _sounds.playNoteConfirm(slot);
    }
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

    final boxRow = row ~/ boxH;
    final boxCol = col ~/ boxW;
    for (var r = 0; r < gridSize; r++) {
      for (var c = 0; c < gridSize; c++) {
        if (r == row && c == col) continue;
        final sameUnit = r == row ||
            c == col ||
            (r ~/ boxH == boxRow && c ~/ boxW == boxCol);
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
      final row = key ~/ gridSize;
      final col = key % gridSize;
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
    if (!_isPocket) unawaited(_achievements.recordErase(targets.length));
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
    }
    if (!_isPocket) unawaited(_achievements.recordErase());
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
    for (var r = 0; r < gridSize; r++) {
      for (var c = 0; c < gridSize; c++) {
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
      gridSize,
      (r) => List.generate(gridSize, (c) {
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
      _maybeDailyPaletteShift(now);
    }
    _completedUnits = now;
    return newlyCompleted;
  }

  /// Daily: after ~½ of units (14/27), switch to the day's second palette.
  void _maybeDailyPaletteShift(Set<String> completedUnits) {
    if (!_isDaily) return;
    final challenge = _isPocket
        ? DailyIrodoku.pocketForDate()
        : DailyIrodoku.forDate();
    final threshold = _isPocket
        ? DailyIrodoku.pocketPaletteSwitchUnitThreshold
        : DailyIrodoku.paletteSwitchUnitThreshold;
    if (completedUnits.length < threshold) {
      return;
    }
    if (_dailyDayKey != null && _dailyDayKey != challenge.dayKey) return;
    if (_sessionPalette == challenge.secondPalette) return;
    _sessionPalette = challenge.secondPalette;
    notifyListeners();
  }

  /// Align session palette with unit progress (restore / review / resume).
  void _ensureDailyPaletteForProgress() {
    if (!_isDaily) return;
    final challenge = _isPocket
        ? DailyIrodoku.pocketForDate()
        : DailyIrodoku.forDate();
    final threshold = _isPocket
        ? DailyIrodoku.pocketPaletteSwitchUnitThreshold
        : DailyIrodoku.paletteSwitchUnitThreshold;
    final units = _successfullyCompletedUnits();
    if (units.length >= threshold) {
      _sessionPalette = challenge.secondPalette;
    } else {
      _sessionPalette ??= challenge.palette;
    }
  }

  /// Chromatic mode: after completing any unit, hop to a different menu palette.
  ///
  /// Includes 6×6 [Chromatic] Pocket. Hops use [_sessionPalette] only — the
  /// user's saved Config palette is left unchanged. Iro stays Iro and remixes.
  /// Eligible Pocket also re-rolls the 1–6 vs 4–9 swatch window.
  void _maybeChromaticShift() {
    if (_isDaily) return;
    if (!_settings.chromatic) return;
    if (_settings.palette == GamePalette.iro) {
      _sessionPalette = GamePalette.iro;
      _iroMix = IroMix.random();
      _rollPocketSwatchOffset();
      notifyListeners();
      return;
    }
    final current = activePalette;
    final options = GamePalette.menuValues
        .where((palette) => palette != current)
        .toList();
    if (options.isEmpty) return;
    _sessionPalette = options[Random().nextInt(options.length)];
    _iroMix = null;
    _rollPocketSwatchOffset();
    notifyListeners();
  }

  bool get _pocketHighWindowUnlocked =>
      _stats.devMode ||
      (_achievements.isUnlocked('r3c7') &&
          _achievements.isUnlocked('r4c9') &&
          _achievements.isUnlocked('r7c7'));

  /// Eligible Pocket (not Daily): 50/50 first six vs last six palette slots.
  void _rollPocketSwatchOffset() {
    if (!_isPocket || _isDaily || !_pocketHighWindowUnlocked) {
      _pocketSwatchOffset = 0;
      return;
    }
    _pocketSwatchOffset =
        Random().nextBool() ? IrodokuPalette.pocketHighSwatchOffset : 0;
  }

  void _prepareIroMix({required bool daily}) {
    if (daily) {
      _iroMix = null;
      return;
    }
    if (_settings.palette == GamePalette.iro) {
      _iroMix = IroMix.random();
      if (_settings.chromatic) {
        _sessionPalette = GamePalette.iro;
      }
    } else {
      _iroMix = null;
    }
  }

  /// After a Config palette change with no live board, drop a stale Iro mix.
  void syncIroMixToConfigPalette() {
    if (_hasActiveGame && !isGameOver) return;
    if (_isDaily) return;
    if (_settings.palette == GamePalette.iro) return;
    if (_iroMix == null) return;
    _iroMix = null;
    notifyListeners();
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
        !_isPocket &&
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
        !_isPocket &&
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
      if (!_isPocket && !_toBoard().isValidSolution()) {
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
    if (!_isPocket) unawaited(_achievements.recordNoteTaken());
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
      chromatic: _settings.chromatic && !_isDaily && !_isPocket,
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
      final positions = board.positionsForUnit(key);
      return positions.every(
        (pos) => board.get(pos.$1, pos.$2) == solution.get(pos.$1, pos.$2),
      );
    }).toSet();
  }

  UnitCelebration _buildCelebration(Set<String> unitKeys) {
    final cellStagger = <(int, int), int>{};
    final originalValues = <(int, int), int>{};
    final board = _toBoard();

    for (final key in unitKeys) {
      final positions = board.positionsForUnit(key);
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
      // Pocket losses only break Pocket palette streaks (favorite palette).
      if (!_isDaily && !_isPocket) {
        _stats.resetStreakSync(palette: _settings.palette);
        unawaited(_stats.persist());
      } else if (_isPocket && !_isDaily) {
        _stats.resetPocketStreakSync(
          palette: activePalette,
          chromatic: _settings.chromatic,
        );
        unawaited(_achievements.onPocketLoss());
        unawaited(_stats.persist());
      }
    }
    if (_isDaily) {
      if (_isPocket) {
        _heldPocketDaily = null;
        unawaited(_prefs.clearParkedPocketDailyGame());
      } else {
        _heldDaily = null;
        unawaited(_prefs.clearParkedDailyGame());
        unawaited(_prefs.clearDailyFailedDay());
        unawaited(_prefs.clearFailedDailyGame());
      }
    }
  }

  void _refreshConflicts() {
    final board = _toBoard();
    final conflicts = board.conflictingCells();
    for (var r = 0; r < gridSize; r++) {
      for (var c = 0; c < gridSize; c++) {
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
      if (_isPocket) {
        if (_isDaily) {
          final streak = _dailyStreakAfterThisWin(pocket: true);
          _stats.awardPocketDailyWin(
            elapsed: _elapsed,
            mistakes: _mistakes,
            palette: winPalette,
            dailyStreak: streak,
            suppressSpeedAndFlawless: _retriedAfterLoss,
          );
          unawaited(
            _achievements.onPocketGamesWon(
              pocketGamesWon: _stats.stats.pocketGamesWon,
              elapsed: _elapsed,
              mistakes: _mistakes,
              suppressSpeedAndFlawless: _retriedAfterLoss,
            ),
          );
          unawaited(_stats.persist());
          _heldPocketDaily = null;
          unawaited(_prefs.clearParkedPocketDailyGame());
          final completed = _snapshotLiveGame();
          unawaited(
            _recordPocketDailyCompletion(completedBoard: completed),
          );
        } else {
          _stats.awardPocketWin(
            elapsed: _elapsed,
            mistakes: _mistakes,
            palette: winPalette,
            chromatic: _settings.chromatic,
            suppressSpeedAndFlawless: _retriedAfterLoss,
          );
          unawaited(
            _achievements.onPocketGamesWon(
              pocketGamesWon: _stats.stats.pocketGamesWon,
              elapsed: _elapsed,
              mistakes: _mistakes,
              suppressSpeedAndFlawless: _retriedAfterLoss,
            ),
          );
          unawaited(_stats.persist());
        }
      } else {
        unawaited(
          _achievements.evaluateWin(
            difficulty: _gameDifficulty,
            elapsed: _elapsed,
            mistakes: _mistakes,
            palette: winPalette,
            ctx: _achievementGameContext(),
            suppressSpeedAndFlawless: _retriedAfterLoss && !_isDaily,
          ),
        );
        if (_isDaily) {
          unawaited(
            _achievements.onDailyChallengeWon(
              streak: _dailyStreakAfterThisWin(pocket: false),
            ),
          );
        }
        _pendingPaletteUnlocks = _stats.recordWinSync(
          difficulty: _gameDifficulty,
          elapsed: _elapsed,
          mistakes: _mistakes,
          palette: winPalette,
          chromatic: _settings.chromatic && !_isDaily,
          daily: _isDaily,
          dailyStreak: _isDaily ? _dailyStreakAfterThisWin(pocket: false) : 0,
          achievedXp: _achievements.consumeAchievedXp(),
          noteless: !_usedNotes,
          suppressSpeedAndFlawless: _retriedAfterLoss && !_isDaily,
        );
        _settings.ensurePaletteUnlocked(_stats.stats);
        unawaited(_stats.persist());
        // Expert wins may unlock Master — start warming a board immediately.
        unawaited(prefetchMasterPuzzle());
        if (_isDaily) {
          _heldDaily = null;
          unawaited(_prefs.clearParkedDailyGame());
          final completed = _snapshotLiveGame();
          unawaited(_recordDailyCompletion(completedBoard: completed));
        }
      }
    }
  }

  Future<void> _recordDailyCompletion({PausedGame? completedBoard}) async {
    final dayKey = _dailyDayKey ?? DailyIrodoku.forDate().dayKey;
    final last = _prefs.getDailyLastCompletedDay();
    if (last == dayKey) {
      if (completedBoard != null) {
        await _prefs.saveCompletedDailyGame(completedBoard);
      }
      await _prefs.clearFailedDailyGame();
      await _prefs.clearDailyFailedDay();
      return;
    }

    final streak = _dailyStreakAfterThisWin(pocket: false);
    await _prefs.setDailyProgress(
      lastCompletedDay: dayKey,
      streak: streak,
    );
    if (completedBoard != null) {
      await _prefs.saveCompletedDailyGame(completedBoard);
    }
    await _prefs.clearFailedDailyGame();
    await _prefs.clearDailyFailedDay();
    unawaited(_achievements.onDailyChallengeWon(streak: streak));
    notifyListeners();
  }

  Future<void> _recordPocketDailyCompletion({PausedGame? completedBoard}) async {
    final dayKey = _dailyDayKey ?? DailyIrodoku.forDate().dayKey;
    final last = _prefs.getPocketDailyLastCompletedDay();
    if (last == dayKey) {
      if (completedBoard != null) {
        await _prefs.saveCompletedPocketDailyGame(completedBoard);
      }
      return;
    }

    final streak = _dailyStreakAfterThisWin(pocket: true);
    await _prefs.setPocketDailyProgress(
      lastCompletedDay: dayKey,
      streak: streak,
    );
    if (completedBoard != null) {
      await _prefs.saveCompletedPocketDailyGame(completedBoard);
    }
    unawaited(_achievements.onDailyChallengeWon(streak: streak));
    notifyListeners();
  }

  void _applyFinishedDailyReview(PausedGame finished, {required bool won}) {
    final challenge = finished.isPocket
        ? DailyIrodoku.pocketForDate()
        : DailyIrodoku.forDate();
    _applyPausedBoard(
      finished,
      sessionPalette: finished.sessionPalette ?? challenge.palette,
    );
    _timer?.cancel();
    _isWon = won;
    _isLost = !won;
    _isPaused = false;
    _hasActiveGame = false;
    _winRecorded = won;
    _lossRecorded = !won;
    _dailyReviewMode = true;
    _isDaily = true;
    _dailyDayKey = finished.dailyDayKey ?? challenge.dayKey;
    // Prefer stored end-state palette; infer from unit progress for older saves.
    if (finished.sessionPalette != null) {
      _sessionPalette = finished.sessionPalette;
    } else {
      _ensureDailyPaletteForProgress();
    }
    _pendingPaletteUnlocks = [];
  }

  Future<void> _hydrateParkedHoldsFromDisk() async {
    final today = DailyIrodoku.forDate().dayKey;

    final completedDaily = _prefs.loadCompletedDailyGame();
    if (completedDaily != null && completedDaily.dailyDayKey != today) {
      await _prefs.clearCompletedDailyGame();
    }

    final failedDaily = _prefs.loadFailedDailyGame();
    if (failedDaily != null && failedDaily.dailyDayKey != today) {
      await _prefs.clearFailedDailyGame();
    }

    final completedPocketDaily = _prefs.loadCompletedPocketDailyGame();
    if (completedPocketDaily != null &&
        completedPocketDaily.dailyDayKey != today) {
      await _prefs.clearCompletedPocketDailyGame();
    }

    final parkedRegular = _prefs.loadParkedRegularGame();
    if (parkedRegular != null &&
        !parkedRegular.isDaily &&
        !parkedRegular.isPocket) {
      _heldRegular = _heldFromPaused(parkedRegular);
    } else if (parkedRegular != null) {
      await _prefs.clearParkedRegularGame();
    }

    final parkedChromatic = _prefs.loadParkedChromaticGame();
    if (parkedChromatic != null &&
        !parkedChromatic.isDaily &&
        !parkedChromatic.isPocket) {
      _heldChromatic = _heldFromPaused(parkedChromatic);
    } else if (parkedChromatic != null) {
      await _prefs.clearParkedChromaticGame();
    }

    final parkedDaily = _prefs.loadParkedDailyGame();
    if (parkedDaily != null &&
        parkedDaily.isDaily &&
        !parkedDaily.isPocket &&
        parkedDaily.dailyDayKey == today) {
      _heldDaily = _heldFromPaused(parkedDaily);
    } else if (parkedDaily != null) {
      await _prefs.clearParkedDailyGame();
    }

    final parkedPocket = _prefs.loadParkedPocketGame();
    if (parkedPocket != null &&
        parkedPocket.isPocket &&
        !parkedPocket.isDaily) {
      _heldPocket = _heldFromPaused(parkedPocket);
    } else if (parkedPocket != null) {
      await _prefs.clearParkedPocketGame();
    }

    final parkedPocketChromatic = _prefs.loadParkedPocketChromaticGame();
    if (parkedPocketChromatic != null &&
        parkedPocketChromatic.isPocket &&
        !parkedPocketChromatic.isDaily) {
      _heldPocketChromatic = _heldFromPaused(parkedPocketChromatic);
    } else if (parkedPocketChromatic != null) {
      await _prefs.clearParkedPocketChromaticGame();
    }

    final parkedPocketDaily = _prefs.loadParkedPocketDailyGame();
    if (parkedPocketDaily != null &&
        parkedPocketDaily.isDaily &&
        parkedPocketDaily.isPocket &&
        parkedPocketDaily.dailyDayKey == today) {
      _heldPocketDaily = _heldFromPaused(parkedPocketDaily);
    } else if (parkedPocketDaily != null) {
      await _prefs.clearParkedPocketDailyGame();
    }
  }

  /// Park Classic, Chromatic, Pocket, or Daily so another mode can replace live.
  Future<void> _parkHomeLive() async {
    if (_isDaily) {
      await _parkLiveDailyToHold();
    } else if (_isPocket) {
      await _parkLivePocket();
    } else {
      await _parkRegularFromLive();
    }
  }

  Future<void> _parkLivePocket() async {
    if (!_isPocket || _isDaily) return;
    if (_settings.chromatic) {
      await _parkPocketChromaticFromLive();
    } else {
      await _parkPocketFromLive();
    }
  }

  /// Park the live non-daily board into Classic or Chromatic hold.
  Future<void> _parkRegularFromLive() async {
    if (_isDaily || _isPocket) return;
    if (!_hasActiveGame && !isGameOver && _solution == null) return;
    final held = _captureHeld();
    if (_settings.chromatic) {
      _heldChromatic = held;
      await _persistParkedChromatic();
    } else {
      _heldRegular = held;
      await _persistParkedRegular();
    }
  }

  Future<void> _parkPocketFromLive() async {
    if (!_isPocket || _isDaily || _settings.chromatic) return;
    if (!_hasActiveGame && !isGameOver && _solution == null) return;
    _timer?.cancel();
    _heldPocket = _captureHeld();
    await _persistParkedPocket();
  }

  Future<void> _parkPocketChromaticFromLive() async {
    if (!_isPocket || _isDaily || !_settings.chromatic) return;
    if (!_hasActiveGame && !isGameOver && _solution == null) return;
    _timer?.cancel();
    _heldPocketChromatic = _captureHeld();
    await _persistParkedPocketChromatic();
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

  Future<void> _persistParkedChromatic() async {
    final held = _heldChromatic;
    if (held == null) {
      await _prefs.clearParkedChromaticGame();
      return;
    }
    final paused = _pausedFromHeld(held);
    if (paused == null) {
      await _prefs.clearParkedChromaticGame();
      return;
    }
    await _prefs.saveParkedChromaticGame(paused);
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

  Future<void> _persistParkedPocket() async {
    final held = _heldPocket;
    if (held == null) {
      await _prefs.clearParkedPocketGame();
      return;
    }
    final paused = _pausedFromHeld(held);
    if (paused == null) {
      await _prefs.clearParkedPocketGame();
      return;
    }
    await _prefs.saveParkedPocketGame(paused);
  }

  Future<void> _persistParkedPocketChromatic() async {
    final held = _heldPocketChromatic;
    if (held == null) {
      await _prefs.clearParkedPocketChromaticGame();
      return;
    }
    final paused = _pausedFromHeld(held);
    if (paused == null) {
      await _prefs.clearParkedPocketChromaticGame();
      return;
    }
    await _prefs.saveParkedPocketChromaticGame(paused);
  }

  Future<void> _persistParkedPocketDaily() async {
    final held = _heldPocketDaily;
    if (held == null) {
      await _prefs.clearParkedPocketDailyGame();
      return;
    }
    final paused = _pausedFromHeld(held);
    if (paused == null) {
      await _prefs.clearParkedPocketDailyGame();
      return;
    }
    await _prefs.saveParkedPocketDailyGame(paused);
  }

  Future<void> _parkLiveDailyToHold() async {
    if (!_isDaily) return;
    _timer?.cancel();
    if (!isGameOver && !_dailyReviewMode) {
      if (_isPocket) {
        _heldPocketDaily = _captureHeld();
        await _persistParkedPocketDaily();
      } else {
        _heldDaily = _captureHeld();
        await _persistParkedDaily();
      }
    } else if (_isPocket) {
      _heldPocketDaily = null;
      await _prefs.clearParkedPocketDailyGame();
    } else {
      _heldDaily = null;
      await _prefs.clearParkedDailyGame();
    }
    _dailyReviewMode = false;
    _sessionPalette = null;
  }

  Future<void> _parkDailyIfLive() async {
    await _parkLiveDailyToHold();
  }

  /// Switch to Classic mode for Main Menu → resume or start.
  Future<void> openClassicGame() async {
    if (_isGenerating) return;

    if (_isDaily) {
      await _parkDailyIfLive();
    } else if (_isPocket) {
      await _parkLivePocket();
    } else if (_settings.chromatic) {
      await _parkRegularFromLive();
    } else {
      // Already on Classic — resume as-is.
      notifyListeners();
      return;
    }

    await _settings.setChromatic(false);
    if (_heldRegular != null) {
      _applyHeld(_heldRegular!);
      _heldRegular = null;
      await _prefs.clearParkedRegularGame();
    } else {
      await startNewGame(preserveHeldDaily: true, pocket: false);
    }
    notifyListeners();
  }

  /// Switch to Chromatic mode for Main Menu → resume or start.
  /// Returns false if Chromatic is still locked.
  Future<bool> openChromaticGame() async {
    if (_isGenerating) return false;
    if (!_stats.areAllMenuPalettesUnlocked) return false;

    if (_isDaily) {
      await _parkDailyIfLive();
    } else if (_isPocket) {
      await _parkLivePocket();
    } else if (!_settings.chromatic) {
      await _parkRegularFromLive();
    } else {
      // Already on 9×9 Chromatic — resume as-is.
      notifyListeners();
      return true;
    }

    await _settings.setChromatic(true);
    if (_heldChromatic != null) {
      _applyHeld(_heldChromatic!);
      _heldChromatic = null;
      await _prefs.clearParkedChromaticGame();
    } else {
      await startNewGame(preserveHeldDaily: true, pocket: false);
    }
    notifyListeners();
    return true;
  }

  /// Switch to Pocket mode for Main Menu → resume or start.
  Future<void> openPocketGame() async {
    if (_isGenerating) return;

    if (_isPocket && !_isDaily && !_settings.chromatic) {
      notifyListeners();
      return;
    }

    if (_isDaily) {
      await _parkDailyIfLive();
    } else if (_isPocket) {
      await _parkLivePocket();
    } else {
      await _parkRegularFromLive();
    }

    await _settings.setChromatic(false);
    if (_heldPocket != null) {
      _applyHeld(_heldPocket!);
      _heldPocket = null;
      await _prefs.clearParkedPocketGame();
    } else {
      await startNewGame(pocket: true, preserveHeldDaily: true);
    }
    notifyListeners();
  }

  /// Switch to 6×6 Chromatic Pocket for Main Menu → resume or start.
  /// Returns false if Chromatic is still locked.
  Future<bool> openPocketChromaticGame() async {
    if (_isGenerating) return false;
    if (!_stats.areAllMenuPalettesUnlocked) return false;

    if (_isPocket && !_isDaily && _settings.chromatic) {
      notifyListeners();
      return true;
    }

    if (_isDaily) {
      await _parkDailyIfLive();
    } else if (_isPocket) {
      await _parkLivePocket();
    } else {
      await _parkRegularFromLive();
    }

    await _settings.setChromatic(true);
    if (_heldPocketChromatic != null) {
      _applyHeld(_heldPocketChromatic!);
      _heldPocketChromatic = null;
      await _prefs.clearParkedPocketChromaticGame();
    } else {
      await startNewGame(pocket: true, preserveHeldDaily: true);
    }
    notifyListeners();
    return true;
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
      isPocket: held.isPocket,
      dailyDayKey: held.dailyDayKey,
      sessionPalette: held.sessionPalette,
      iroSources: held.iroMix?.toKeys(),
      pocketSwatchOffset: held.pocketSwatchOffset,
      usedNotes: held.usedNotes,
      retriedAfterLoss: held.retriedAfterLoss,
    );
  }

  _HeldGameSession _heldFromPaused(PausedGame paused) {
    final n = paused.isPocket ? SudokuBoard.pocketSize : SudokuBoard.size;
    final cells = List.generate(n, (r) {
      return List.generate(n, (c) {
        return paused.cells[r * n + c].copyWith();
      });
    });
    final sessionPalette = paused.isDaily
        ? (paused.sessionPalette ??
            (paused.isPocket
                ? DailyIrodoku.pocketForDate().palette
                : DailyIrodoku.forDate().palette))
        : paused.sessionPalette;
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
      isPocket: paused.isPocket,
      dailyDayKey: paused.dailyDayKey,
      sessionPalette: sessionPalette,
      iroMix: IroMix.fromKeys(paused.iroSources),
      pocketSwatchOffset: paused.pocketSwatchOffset,
      firstFillColor: null,
      lastFillColor: null,
      lastFillRow: null,
      lastFillCol: null,
      usedNotes: paused.usedNotes,
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
      retriedAfterLoss: paused.retriedAfterLoss,
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
    _isPocket = paused.isPocket;
    _dailyDayKey = paused.dailyDayKey;
    _sessionPalette = sessionPalette;
    _iroMix = IroMix.fromKeys(paused.iroSources);
    _pocketSwatchOffset = IrodokuPalette.normalizePocketSwatchOffset(
      paused.pocketSwatchOffset,
    );
    _solution = SudokuBoard.fromFlat(paused.solution, pocket: paused.isPocket);
    _noteMode = false;
    _undoStack.clear();

    final n = paused.isPocket ? SudokuBoard.pocketSize : SudokuBoard.size;
    _cells = List.generate(n, (r) {
      return List.generate(n, (c) {
        return paused.cells[r * n + c];
      });
    });
    _refreshConflicts();
    _completedUnits = _successfullyCompletedUnits();
    _celebration = null;
    _resetAchievementSession();
    _usedNotes = paused.usedNotes;
    _retriedAfterLoss = paused.retriedAfterLoss;
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
      isPocket: _isPocket,
      dailyDayKey: _dailyDayKey,
      sessionPalette: _sessionPalette,
      iroMix: _iroMix,
      pocketSwatchOffset: _pocketSwatchOffset,
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
      retriedAfterLoss: _retriedAfterLoss,
    );
  }

  void _applyHeld(_HeldGameSession held) {
    _timer?.cancel();
    _generationToken++;
    _dailyReviewMode = false;
    _cells = [
      for (final row in held.cells) [for (final cell in row) cell.copyWith()],
    ];
    _solution = held.solution == null
        ? null
        : SudokuBoard.fromFlat(held.solution!, pocket: held.isPocket);
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
    _isPocket = held.isPocket;
    _dailyDayKey = held.dailyDayKey;
    _sessionPalette = held.sessionPalette;
    _iroMix = held.iroMix;
    _pocketSwatchOffset = IrodokuPalette.normalizePocketSwatchOffset(
      held.pocketSwatchOffset,
    );
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
    _retriedAfterLoss = held.retriedAfterLoss;
    _completedUnits = _successfullyCompletedUnits();
    if (_hasActiveGame && !isGameOver && !_isPaused) {
      _startTimer();
    }
  }

  SudokuBoard _toBoard() {
    return SudokuBoard(
      List.generate(
        gridSize,
        (r) => List.generate(gridSize, (c) => _cells[r][c].value),
      ),
      n: gridSize,
      boxWidth: boxW,
      boxHeight: boxH,
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
    if (_ownsSounds) unawaited(_sounds.dispose());
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
  final bool isPocket;
  final String? dailyDayKey;
  final GamePalette? sessionPalette;
  final IroMix? iroMix;
  final int pocketSwatchOffset;
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
  final bool retriedAfterLoss;

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
    required this.isPocket,
    required this.dailyDayKey,
    required this.sessionPalette,
    this.iroMix,
    this.pocketSwatchOffset = 0,
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
    this.retriedAfterLoss = false,
  });
}

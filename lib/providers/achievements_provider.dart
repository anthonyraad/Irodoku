import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/achievement.dart';
import '../models/achievements_progress.dart';
import '../models/difficulty.dart';
import '../models/game_palette.dart';
import '../models/game_stats.dart';
import '../services/preferences_service.dart';
import '../services/sound_service.dart';
import 'settings_provider.dart';

class AchievementsProvider extends ChangeNotifier {
  /// Pause before the achievement sting after a game-win SFX so the file's
  /// leading silence isn't covered by the win sound.
  static const _winAchievementSoundDelay = Duration(milliseconds: 800);

  final PreferencesService _prefs;
  AchievementsProgress _progress;
  Set<String> _seenIds;
  SettingsProvider? _settings;
  SoundService? _sounds;
  int _unlockSoundEpoch = 0;
  /// 0-based rows completed since the last XP grant (live unlocks only).
  final List<int> _pendingCompletedRows = [];

  AchievementsProvider(this._prefs)
      : _progress = _prefs.loadAchievements(),
        _seenIds = _prefs.loadSeenAchievementIds() {
    // Unlock anything already implied by persisted stats/counters.
    unawaited(reconcileFromExistingStats());
  }

  /// Wire audio after [SettingsProvider] / [SoundService] exist (e.g. from GameProvider).
  void bindAudio({
    required SettingsProvider settings,
    required SoundService sounds,
  }) {
    _settings = settings;
    _sounds = sounds;
  }

  AchievementsProgress get progress => _progress;

  bool isUnlocked(String id) => _progress.isUnlocked(id);

  /// Unlocked achievements not yet shown on the Achievements screen.
  Set<String> get unseenUnlockedIds =>
      _progress.unlockedIds.difference(_seenIds);

  /// Marks every currently unlocked achievement as seen on the Achievements page.
  Future<void> markUnlockedAchievementsSeen() async {
    final next = {..._seenIds, ..._progress.unlockedIds};
    if (next.length == _seenIds.length &&
        next.containsAll(_seenIds)) {
      return;
    }
    _seenIds = next;
    await _prefs.saveSeenAchievementIds(_seenIds);
  }

  Future<void> persist() => _prefs.saveAchievements(_progress);

  /// Toast label; locked cells with countable progress append `(current/target)`.
  String toastLabel(Achievement achievement) {
    final title = achievement.title;
    if (isUnlocked(achievement.id)) return title;
    final progress = progressToward(achievement);
    if (progress == null) return title;
    final (current, target) = progress;
    final shown = math.min(current, target);
    return '$title ($shown/$target)';
  }

  /// Countable progress for [achievement], or null when not applicable.
  (int current, int target)? progressToward(Achievement achievement) {
    final id = achievement.id;
    final p = _progress;

    // Palette win tiers: columns 1–3 on every palette row.
    const paletteWinTargets = <String, int>{
      'r1c1': 3, 'r1c2': 7, 'r1c3': 10,
      'r2c1': 3, 'r2c2': 7, 'r2c3': 10,
      'r3c1': 3, 'r3c2': 7, 'r3c3': 10,
      'r4c1': 3, 'r4c2': 7, 'r4c3': 10,
      'r5c1': 3, 'r5c2': 7, 'r5c3': 10,
      'r6c1': 3, 'r6c2': 7, 'r6c3': 10,
      'r7c1': 3, 'r7c2': 7, 'r7c3': 10,
      'r8c1': 3, 'r8c2': 7, 'r8c3': 10,
    };
    final paletteTarget = paletteWinTargets[id];
    if (paletteTarget != null) {
      return (p.winsForPalette(achievement.palette), paletteTarget);
    }

    return switch (id) {
      'r2c7' => (p.cellsErased, 100),
      'r2c8' => (_calendarStreak(p.winDayKeys), 3),
      'r2c9' => (p.consecutiveHardNoMistake, 3),
      'r3c7' => (_prefs.loadStats().pocketGamesWon, 30),
      'r4c9' => (p.consecutivePocketFastWins, 3),
      'r7c7' => (p.pocketNoMistakeWins, 100),
      'r5c4' => (
          math.min(_prefs.getDailyBestStreak(), 5),
          5,
        ),
      'r5c7' => (p.notesTaken, 1000),
      'r7c5' => (p.consecutiveExpertNoMistake, 3),
      'r8c7' => (
          math.min(_prefs.getDailyBestStreak(), 30),
          30,
        ),
      'r8c8' => (p.chromaticGamesWon, 30),
      'r8c9' => (p.masterNoMistakeWins, 30),
      _ => null,
    };
  }

  /// Unlocks achievements that can be proven from already-instrumented data
  /// (lifetime stats, best times, palette streaks, achievement counters).
  Future<void> reconcileFromExistingStats() async {
    final stats = _prefs.loadStats();
    final beforeUnlocked = Set<String>.from(_progress.unlockedIds);
    final priorWins = Map<GamePalette, int>.from(_progress.winsByPalette);
    final winsByPalette = Map<GamePalette, int>.from(priorWins);

    // Palette win streaks are a lower bound on total wins with that palette.
    for (final palette in GamePalette.values) {
      final lower = math.max(
        winsByPalette[palette] ?? 0,
        math.max(
          stats.bestStreakForPalette(palette),
          stats.currentStreakByPalette[palette] ?? 0,
        ),
      );
      if (lower > 0) winsByPalette[palette] = lower;
    }

    final chromaticGamesWon = math.max(
      _progress.chromaticGamesWon,
      stats.chromaticGamesWon,
    );
    _progress = _progress.copyWith(
      winsByPalette: winsByPalette,
      chromaticGamesWon: chromaticGamesWon,
    );
    final needsR4Persist = !_progress.r4TimeShiftV1;
    final needsR7c7Persist = !_progress.r7c7PocketV1;
    _migrateR4TimeShift();
    _migrateR7c7Pocket();

    final ids = <String>{};
    _addPaletteWinAchievements(ids, winsByPalette);
    _addCounterAchievements(ids, stats);
    _addStreakAchievements(ids);
    _addBestTimeAchievements(ids, stats);

    // Silent: retroactive unlocks shouldn't fanfare on launch.
    _unlockMany(ids, announce: false);

    final unlockedChanged = !setEquals(_progress.unlockedIds, beforeUnlocked);
    final winsChanged = !_intMapEquals(winsByPalette, priorWins);
    if (!unlockedChanged && !winsChanged && !needsR4Persist && !needsR7c7Persist) {
      return;
    }

    notifyListeners();
    await persist();
    if (needsR4Persist || needsR7c7Persist) {
      await _prefs.saveSeenAchievementIds(_seenIds);
    }
  }

  void _addPaletteWinAchievements(
    Set<String> ids,
    Map<GamePalette, int> winsByPalette,
  ) {
    void add(GamePalette p, String a3, String a7, String a10) {
      final n = winsByPalette[p] ?? 0;
      if (n >= 3) ids.add(a3);
      if (n >= 7) ids.add(a7);
      if (n >= 10) ids.add(a10);
    }

    add(GamePalette.standard, 'r1c1', 'r1c2', 'r1c3');
    add(GamePalette.rainbow, 'r2c1', 'r2c2', 'r2c3');
    add(GamePalette.world11, 'r3c1', 'r3c2', 'r3c3');
    add(GamePalette.neon, 'r4c1', 'r4c2', 'r4c3');
    add(GamePalette.pkmn, 'r5c1', 'r5c2', 'r5c3');
    add(GamePalette.pkmn2, 'r6c1', 'r6c2', 'r6c3');
    add(GamePalette.glass, 'r7c1', 'r7c2', 'r7c3');
    add(GamePalette.sky, 'r8c1', 'r8c2', 'r8c3');
  }

  void _addCounterAchievements(Set<String> ids, GameStats stats) {
    if (_progress.cellsErased >= 100) ids.add('r2c7');
    if (stats.pocketGamesWon >= 30) ids.add('r3c7');
    if (_progress.notesTaken >= 1000) ids.add('r5c7');
    if (_progress.consecutiveHardNoMistake >= 3) ids.add('r2c9');
    if (_progress.consecutiveExpertNoMistake >= 3) ids.add('r7c5');
    if (_progress.chromaticGamesWon >= 30) ids.add('r8c8');
    if (_progress.masterNoMistakeWins >= 30) ids.add('r8c9');
    if (_progress.consecutivePocketFastWins >= 3) ids.add('r4c9');
    if (_progress.pocketNoMistakeWins >= 100) ids.add('r7c7');
  }

  void _addStreakAchievements(Set<String> ids) {
    // Any historical calendar run counts, not only a streak ending today.
    if (_maxCalendarStreak(_progress.winDayKeys) >= 3) ids.add('r2c8');
    final dailyBest = _prefs.getDailyBestStreak();
    if (dailyBest >= 5) ids.add('r5c4');
    if (dailyBest >= 30) ids.add('r8c7');
  }

  void _addBestTimeAchievements(Set<String> ids, GameStats stats) {
    bool within(Difficulty d, Duration limit) {
      final best = stats.bestTimeFor(d);
      return best != null && best <= limit;
    }

    if (within(Difficulty.easy, const Duration(minutes: 4))) ids.add('r4c4');
    if (within(Difficulty.medium, const Duration(minutes: 8))) {
      ids.add('r4c5');
    }
    if (within(Difficulty.hard, const Duration(minutes: 12))) ids.add('r4c6');
    if (within(Difficulty.expert, const Duration(minutes: 18))) {
      ids.add('r4c7');
    }
    if (within(Difficulty.master, const Duration(minutes: 25))) {
      ids.add('r4c8');
    }

    // Exact timer achievements — only if a stored best time is exactly that.
    const exact454 = 4 * 60 + 54;
    for (final difficulty in Difficulty.values) {
      if (stats.bestTimeFor(difficulty)?.inSeconds == exact454 ||
          stats.chromaticBestTimeFor(difficulty)?.inSeconds == exact454) {
        ids.add('r3c9');
        break;
      }
    }
  }

  /// Old r4c6 Neon-Master / r4c7–c9 time goals → Hard 12 / Expert 18 / Master 25 / Pocket streak.
  void _migrateR4TimeShift() {
    if (_progress.r4TimeShiftV1) return;
    final ids = Set<String>.from(_progress.unlockedIds);
    final hadHard12 = ids.contains('r4c7');
    final hadExpert18 = ids.contains('r4c8');
    final hadMaster25 = ids.contains('r4c9');
    ids
      ..remove('r4c6')
      ..remove('r4c7')
      ..remove('r4c8')
      ..remove('r4c9');
    if (hadHard12) ids.add('r4c6');
    if (hadExpert18) ids.add('r4c7');
    if (hadMaster25) ids.add('r4c8');
    _seenIds = {..._seenIds}..remove('r4c9');
    _progress = _progress.copyWith(
      unlockedIds: ids,
      r4TimeShiftV1: true,
    );
  }

  /// Old r7c7 44:44 timer → Pocket no-mistake wins.
  void _migrateR7c7Pocket() {
    if (_progress.r7c7PocketV1) return;
    final ids = Set<String>.from(_progress.unlockedIds)..remove('r7c7');
    _seenIds = {..._seenIds}..remove('r7c7');
    _progress = _progress.copyWith(
      unlockedIds: ids,
      r7c7PocketV1: true,
    );
  }

  bool _unlock(
    String id, {
    bool announce = true,
    Duration announceDelay = Duration.zero,
  }) {
    if (_progress.isUnlocked(id)) return false;
    final before = Set<String>.from(_progress.unlockedIds);
    final unlocked = Set<String>.from(before)..add(id);
    _progress = _progress.copyWith(unlockedIds: unlocked);
    if (announce) {
      _playUnlockSound(delay: announceDelay);
      _recordNewlyCompletedRows(before, unlocked);
    }
    return true;
  }

  bool _unlockMany(
    Iterable<String> ids, {
    bool announce = true,
    Duration announceDelay = Duration.zero,
  }) {
    var changed = false;
    final before = Set<String>.from(_progress.unlockedIds);
    final unlocked = Set<String>.from(before);
    for (final id in ids) {
      if (unlocked.add(id)) changed = true;
    }
    if (changed) {
      _progress = _progress.copyWith(unlockedIds: unlocked);
      if (announce) {
        _playUnlockSound(delay: announceDelay);
        _recordNewlyCompletedRows(before, unlocked);
      }
    }
    return changed;
  }

  void _recordNewlyCompletedRows(Set<String> before, Set<String> after) {
    for (var row = 0; row < Achievement.rowCount; row++) {
      if (Achievement.isRowComplete(after, row) &&
          !Achievement.isRowComplete(before, row)) {
        _pendingCompletedRows.add(row);
      }
    }
  }

  /// XP for rows completed since the last grant; clears the pending list.
  int consumeAchievedXp() {
    var xp = 0;
    for (final row in _pendingCompletedRows) {
      xp += Achievement.xpForCompletedRow(row);
    }
    _pendingCompletedRows.clear();
    return xp;
  }

  void _playUnlockSound({Duration delay = Duration.zero}) {
    if (_settings?.soundEnabled != true) return;
    final sounds = _sounds;
    if (sounds == null) return;
    final epoch = ++_unlockSoundEpoch;
    if (delay <= Duration.zero) {
      unawaited(sounds.playAchievement());
      return;
    }
    unawaited(
      Future<void>.delayed(delay, () {
        if (epoch != _unlockSoundEpoch) return;
        if (_settings?.soundEnabled != true) return;
        unawaited(sounds.playAchievement());
      }),
    );
  }

  Future<void> recordErase() async {
    final next = _progress.cellsErased + 1;
    _progress = _progress.copyWith(cellsErased: next);
    if (next >= 100) _unlock('r2c7');
    notifyListeners();
    await persist();
  }

  Future<void> recordUndo() async {
    final next = _progress.undoCount + 1;
    _progress = _progress.copyWith(undoCount: next);
    notifyListeners();
    await persist();
  }

  Future<void> recordNoteTaken() async {
    final next = _progress.notesTaken + 1;
    _progress = _progress.copyWith(notesTaken: next);
    if (next >= 1000) _unlock('r5c7');
    notifyListeners();
    await persist();
  }

  /// Unlocks when the first correct fill of a Kanto game is Blue (value 3).
  Future<void> recordFirstFill({
    required GamePalette palette,
    required int colorValue,
  }) async {
    if (palette != GamePalette.pkmn || colorValue != 3) return;
    if (_progress.isUnlocked('r5c5')) return;
    _unlock('r5c5');
    notifyListeners();
    await persist();
  }

  Future<void> recordSessionFlags({
    required bool completedRowColBoxSimultaneously,
    required bool completedNineUnitsInNineSeconds,
    required bool filledNineDistinctColorsConsecutively,
  }) async {
    final ids = <String>[];
    if (completedRowColBoxSimultaneously) ids.add('r5c8');
    if (completedNineUnitsInNineSeconds) ids.add('r7c8');
    if (filledNineDistinctColorsConsecutively) ids.add('r7c9');
    if (ids.isEmpty) return;
    if (!_unlockMany(ids)) return;
    notifyListeners();
    await persist();
  }

  /// Call after a Daily Challenge win updates the persisted streak.
  Future<void> onDailyChallengeWon({required int streak}) async {
    final best = math.max(streak, _prefs.getDailyBestStreak());
    final ids = <String>{
      if (best >= 5) 'r5c4',
      if (best >= 30) 'r8c7',
    };
    if (ids.isEmpty) {
      notifyListeners();
      return;
    }
    if (!_unlockMany(ids, announceDelay: _winAchievementSoundDelay)) {
      return;
    }
    notifyListeners();
    await persist();
  }

  /// Pocket and Pocket [Chromatic] wins both count toward r3c7 / r4c9 / r7c7.
  static const _pocketFastLimit = Duration(minutes: 1, seconds: 30);

  Future<void> onPocketGamesWon({
    required int pocketGamesWon,
    required Duration elapsed,
    required int mistakes,
  }) async {
    final fast = elapsed <= _pocketFastLimit;
    final consecutive = fast ? _progress.consecutivePocketFastWins + 1 : 0;
    final pocketNoMistakeWins = mistakes == 0
        ? _progress.pocketNoMistakeWins + 1
        : _progress.pocketNoMistakeWins;
    _progress = _progress.copyWith(
      consecutivePocketFastWins: consecutive,
      pocketNoMistakeWins: pocketNoMistakeWins,
    );

    final ids = <String>{
      if (pocketGamesWon >= 30) 'r3c7',
      if (consecutive >= 3) 'r4c9',
      if (pocketNoMistakeWins >= 100) 'r7c7',
    };
    _unlockMany(ids, announceDelay: _winAchievementSoundDelay);
    notifyListeners();
    await persist();
  }

  Future<void> onPocketLoss() async {
    if (_progress.consecutivePocketFastWins == 0) return;
    _progress = _progress.copyWith(consecutivePocketFastWins: 0);
    notifyListeners();
    await persist();
  }

  Future<void> evaluateWin({
    required Difficulty difficulty,
    required Duration elapsed,
    required int mistakes,
    required GamePalette palette,
    required AchievementGameContext ctx,
  }) async {
    final winsByPalette = Map<GamePalette, int>.from(_progress.winsByPalette);
    final paletteWins = (winsByPalette[palette] ?? 0) + 1;
    winsByPalette[palette] = paletteWins;

    final today = _dayKey(DateTime.now());
    final winDays = _withDay(_progress.winDayKeys, today);
    final hardDays = difficulty == Difficulty.hard
        ? _withDay(_progress.hardWinDayKeys, today)
        : _progress.hardWinDayKeys;

    var consecutiveHardNoMistake = _progress.consecutiveHardNoMistake;
    if (difficulty == Difficulty.hard && mistakes == 0) {
      consecutiveHardNoMistake += 1;
    } else {
      consecutiveHardNoMistake = 0;
    }

    var consecutiveExpertNoMistake = _progress.consecutiveExpertNoMistake;
    if (difficulty == Difficulty.expert && mistakes == 0) {
      consecutiveExpertNoMistake += 1;
    } else {
      consecutiveExpertNoMistake = 0;
    }

    var masterNoMistakeWins = _progress.masterNoMistakeWins;
    if (difficulty == Difficulty.master && mistakes == 0) {
      masterNoMistakeWins += 1;
    }

    var chromaticGamesWon = _progress.chromaticGamesWon;
    if (ctx.chromatic) {
      chromaticGamesWon += 1;
    }

    String? lastExpert = _progress.lastExpertWinPaletteKey;
    String? lastMaster = _progress.lastMasterWinPaletteKey;
    var unlockKantoJohtoExpert = false;
    var unlockGlassSkyMaster = false;

    if (difficulty == Difficulty.expert) {
      final key = palette.storageKey;
      if ((lastExpert == GamePalette.pkmn.storageKey &&
              palette == GamePalette.pkmn2) ||
          (lastExpert == GamePalette.pkmn2.storageKey &&
              palette == GamePalette.pkmn)) {
        unlockKantoJohtoExpert = true;
      }
      lastExpert = key;
    } else {
      lastExpert = null;
    }

    if (difficulty == Difficulty.master) {
      final key = palette.storageKey;
      if ((lastMaster == GamePalette.glass.storageKey &&
              palette == GamePalette.sky) ||
          (lastMaster == GamePalette.sky.storageKey &&
              palette == GamePalette.glass)) {
        unlockGlassSkyMaster = true;
      }
      lastMaster = key;
    } else {
      lastMaster = null;
    }

    _progress = _progress.copyWith(
      winsByPalette: winsByPalette,
      winDayKeys: winDays,
      hardWinDayKeys: hardDays,
      consecutiveHardNoMistake: consecutiveHardNoMistake,
      consecutiveExpertNoMistake: consecutiveExpertNoMistake,
      masterNoMistakeWins: masterNoMistakeWins,
      chromaticGamesWon: chromaticGamesWon,
      lastExpertWinPaletteKey: lastExpert,
      lastMasterWinPaletteKey: lastMaster,
      clearLastExpertWinPaletteKey: lastExpert == null,
      clearLastMasterWinPaletteKey: lastMaster == null,
    );

    final ids = <String>{};
    _addPaletteWinAchievements(ids, winsByPalette);

    // Default row
    if (ctx.lastFillRow == 8 && ctx.lastFillCol == 8) ids.add('r1c4');
    if (ctx.lastFillRow == 0 && ctx.lastFillCol == 0) ids.add('r1c5');
    if (difficulty == Difficulty.hard && palette == GamePalette.standard) {
      ids.add('r1c6');
    }
    if (ctx.lastFillRow == 4 && ctx.lastFillCol == 4) ids.add('r1c7');
    if (ctx.usedDarkMode) ids.add('r1c8');
    if (difficulty == Difficulty.easy && !ctx.usedNotes) ids.add('r1c9');

    // Rainbow row
    if (!ctx.usedUndo) ids.add('r2c4');
    if (mistakes == 0) ids.add('r2c5');
    if (difficulty == Difficulty.master && palette == GamePalette.rainbow) {
      ids.add('r2c6');
    }
    if (_progress.cellsErased >= 100) ids.add('r2c7');
    if (_calendarStreak(winDays) >= 3) ids.add('r2c8');
    if (consecutiveHardNoMistake >= 3) ids.add('r2c9');

    // 1-1 row
    if (mistakes == 2) ids.add('r3c4');
    if (difficulty == Difficulty.hard && !ctx.paused) ids.add('r3c5');
    if (difficulty == Difficulty.master && palette == GamePalette.world11) {
      ids.add('r3c6');
    }
    if (difficulty == Difficulty.expert && !ctx.paused) ids.add('r3c8');
    if (elapsed.inSeconds == 4 * 60 + 54) {
      ids.add('r3c9');
    }

    // Neon row
    if (difficulty == Difficulty.easy &&
        elapsed <= const Duration(minutes: 4)) {
      ids.add('r4c4');
    }
    if (difficulty == Difficulty.medium &&
        elapsed <= const Duration(minutes: 8)) {
      ids.add('r4c5');
    }
    if (difficulty == Difficulty.hard &&
        elapsed <= const Duration(minutes: 12)) {
      ids.add('r4c6');
    }
    if (difficulty == Difficulty.expert &&
        elapsed <= const Duration(minutes: 18)) {
      ids.add('r4c7');
    }
    if (difficulty == Difficulty.master &&
        elapsed <= const Duration(minutes: 25)) {
      ids.add('r4c8');
    }

    // Kanto row (r5c4 Daily streak is checked in [onDailyChallengeWon])
    if (difficulty == Difficulty.master && palette == GamePalette.pkmn) {
      ids.add('r5c6');
    }
    if (_progress.notesTaken >= 1000) ids.add('r5c7');
    if (ctx.completedRowColBoxSimultaneously) ids.add('r5c8');
    if (difficulty == Difficulty.expert &&
        palette == GamePalette.pkmn &&
        ctx.lastFillColor == 2) {
      ids.add('r5c9');
    }

    // Johto row
    if (ctx.rowsCompletedInFirst90Seconds >= 3) ids.add('r6c4');
    if (ctx.colsCompletedInFirst90Seconds >= 3) ids.add('r6c5');
    if (difficulty == Difficulty.master && palette == GamePalette.pkmn2) {
      ids.add('r6c6');
    }
    if (ctx.boxesCompletedInFirst90Seconds >= 3) ids.add('r6c7');
    if (unlockKantoJohtoExpert) ids.add('r6c8');
    if (difficulty == Difficulty.expert &&
        palette == GamePalette.pkmn2 &&
        ctx.lastFillColor == 8) {
      ids.add('r6c9');
    }

    // Glass row
    if (difficulty == Difficulty.medium && !ctx.usedNotes) ids.add('r7c4');
    if (consecutiveExpertNoMistake >= 3) ids.add('r7c5');
    if (difficulty == Difficulty.master && palette == GamePalette.glass) {
      ids.add('r7c6');
    }
    if (ctx.completedNineUnitsInNineSeconds) ids.add('r7c8');
    if (ctx.filledNineDistinctColorsConsecutively) ids.add('r7c9');

    // Sky row (r8c7 Daily streak is checked in [onDailyChallengeWon])
    if (difficulty == Difficulty.master &&
        palette == GamePalette.sky &&
        ctx.lastFillColor == 3) {
      ids.add('r8c4');
    }
    if (ctx.chromatic && !ctx.usedNotes && mistakes == 0) {
      ids.add('r8c5');
    }
    if (unlockGlassSkyMaster) ids.add('r8c6');
    if (chromaticGamesWon >= 30) ids.add('r8c8');
    if (masterNoMistakeWins >= 30) ids.add('r8c9');

    // First-fill can also be recorded at win if session captured it.
    if (palette == GamePalette.pkmn && ctx.firstFillColor == 3) {
      ids.add('r5c5');
    }

    _unlockMany(ids, announceDelay: _winAchievementSoundDelay);
    notifyListeners();
    await persist();
  }

  static bool _intMapEquals(Map<GamePalette, int> a, Map<GamePalette, int> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  static String _dayKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static List<String> _withDay(List<String> days, String today) {
    if (days.contains(today)) return days;
    return [...days, today]..sort();
  }

  /// Consecutive calendar days ending today.
  static int _calendarStreak(List<String> sortedDays) {
    if (sortedDays.isEmpty) return 0;
    final set = sortedDays.toSet();
    var cursor = DateTime.now();
    var streak = 0;
    while (true) {
      final key = _dayKey(cursor);
      if (!set.contains(key)) break;
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// Longest run of consecutive calendar days anywhere in [days].
  static int _maxCalendarStreak(List<String> days) {
    if (days.isEmpty) return 0;
    final sorted = [...days.toSet()]..sort();
    var best = 1;
    var current = 1;
    for (var i = 1; i < sorted.length; i++) {
      final prev = DateTime.parse(sorted[i - 1]);
      final next = DateTime.parse(sorted[i]);
      if (next.difference(prev).inDays == 1) {
        current += 1;
        if (current > best) best = current;
      } else {
        current = 1;
      }
    }
    return best;
  }
}

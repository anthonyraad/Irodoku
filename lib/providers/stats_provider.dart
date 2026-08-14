import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/difficulty.dart';
import '../models/game_palette.dart';
import '../models/game_stats.dart';
import '../models/player_xp.dart';
import '../services/preferences_service.dart';

class StatsProvider extends ChangeNotifier {
  final PreferencesService _prefs;
  GameStats _stats;
  XpAward? _lastXpAward;

  Future<void> _writeQueue = Future.value();

  StatsProvider(this._prefs) : _stats = _prefs.loadStats() {
    if (!_prefs.hasTotalXp) {
      _stats = _stats.copyWith(totalXp: PlayerXp.backfillFrom(_stats));
      unawaited(persist());
    }
  }

  GameStats get stats => _stats;
  XpAward? get lastXpAward => _lastXpAward;

  bool get devMode => _prefs.getDevMode();

  bool isUnlocked(Difficulty difficulty) =>
      devMode || _stats.isUnlocked(difficulty);

  bool isPaletteUnlocked(GamePalette palette) =>
      devMode || _stats.isPaletteUnlocked(palette);

  /// True when every menu palette is available (unlocks Chromatic mode).
  bool get areAllMenuPalettesUnlocked =>
      GamePalette.menuValues.every(isPaletteUnlocked);

  bool get isIroenUnlocked => devMode || _stats.isIroenUnlocked;

  bool get isDailyChallengeUnlocked =>
      devMode || _stats.isDailyChallengeUnlocked;

  bool get isGraffitiUnlocked => devMode || _stats.isGraffitiUnlocked;

  void notifyDevModeChanged() => notifyListeners();

  Future<void> recordGameStarted() async {
    _stats = _stats.copyWith(gamesPlayed: _stats.gamesPlayed + 1);
    notifyListeners();
    await persist();
  }

  Future<List<GamePalette>> recordWin({
    required Difficulty difficulty,
    required Duration elapsed,
    required int mistakes,
    required GamePalette palette,
    bool chromatic = false,
    bool daily = false,
    int dailyStreak = 0,
    int achievedXp = 0,
  }) async {
    final newlyUnlocked = recordWinSync(
      difficulty: difficulty,
      elapsed: elapsed,
      mistakes: mistakes,
      palette: palette,
      chromatic: chromatic,
      daily: daily,
      dailyStreak: dailyStreak,
      achievedXp: achievedXp,
    );
    await persist();
    return newlyUnlocked;
  }

  List<GamePalette> recordWinSync({
    required Difficulty difficulty,
    required Duration elapsed,
    required int mistakes,
    required GamePalette palette,
    bool chromatic = false,
    bool daily = false,
    int dailyStreak = 0,
    int achievedXp = 0,
  }) {
    final newlyUnlocked = _applyWin(
      difficulty: difficulty,
      elapsed: elapsed,
      mistakes: mistakes,
      palette: palette,
      chromatic: chromatic,
      daily: daily,
      dailyStreak: dailyStreak,
      achievedXp: achievedXp,
    );
    notifyListeners();
    return newlyUnlocked;
  }

  Future<void> persist() {
    _writeQueue = _writeQueue.catchError((_) {}).then((_) {
      return _prefs.saveStats(_stats);
    });
    return _writeQueue;
  }

  String _todayKey() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  bool get isFirstWinOfDay => _prefs.getXpLastAwardDay() != _todayKey();

  XpAward _awardWinXp({
    required Difficulty difficulty,
    required int mistakes,
    required Duration elapsed,
    String? sourceLabel,
    bool daily = false,
    int dailyStreak = 0,
    bool chromatic = false,
    int achievedXp = 0,
  }) {
    final first = isFirstWinOfDay;
    final award = PlayerXp.compute(
      difficulty: difficulty,
      mistakes: mistakes,
      elapsed: elapsed,
      firstWinOfDay: first,
      previousTotal: _stats.totalXp,
      sourceLabel: sourceLabel,
      daily: daily,
      dailyStreak: dailyStreak,
      chromatic: chromatic,
      achievedXp: achievedXp,
    );
    _stats = _stats.copyWith(totalXp: award.newTotal);
    _lastXpAward = award;
    unawaited(_prefs.setXpLastAwardDay(_todayKey()));
    return award;
  }

  /// Persists a finished Graffiti match. Mutual defeat counts as a loss.
  Future<void> recordGraffitiResult(
    GraffitiMatchResult result, {
    int mistakes = 0,
    Duration elapsed = Duration.zero,
  }) async {
    _stats = switch (result) {
      GraffitiMatchResult.win =>
        _stats.copyWith(graffitiWins: _stats.graffitiWins + 1),
      GraffitiMatchResult.loss =>
        _stats.copyWith(graffitiLosses: _stats.graffitiLosses + 1),
      GraffitiMatchResult.draw =>
        _stats.copyWith(graffitiDraws: _stats.graffitiDraws + 1),
    };
    if (result == GraffitiMatchResult.win) {
      _awardWinXp(
        difficulty: PlayerXp.graffitiDifficulty,
        mistakes: mistakes,
        elapsed: elapsed,
        sourceLabel: 'Graffiti',
      );
    } else {
      _lastXpAward = null;
    }
    notifyListeners();
    await persist();
  }

  List<GamePalette> _applyWin({
    required Difficulty difficulty,
    required Duration elapsed,
    required int mistakes,
    required GamePalette palette,
    required bool chromatic,
    required bool daily,
    required int dailyStreak,
    required int achievedXp,
  }) {
    final newStreak = _stats.currentStreak + 1;
    final bestStreak =
        newStreak > _stats.bestStreak ? newStreak : _stats.bestStreak;

    final bestTimes = Map<Difficulty, Duration?>.from(_stats.bestTimes);
    final previous = bestTimes[difficulty];
    if (previous == null || elapsed < previous) {
      bestTimes[difficulty] = elapsed;
    }

    final winsByDifficulty = Map<Difficulty, int>.from(_stats.winsByDifficulty);
    winsByDifficulty[difficulty] = _stats.winsFor(difficulty) + 1;

    var chromaticGamesWon = _stats.chromaticGamesWon;
    final chromaticBestTimes =
        Map<Difficulty, Duration?>.from(_stats.chromaticBestTimes);
    final chromaticWinsByDifficulty =
        Map<Difficulty, int>.from(_stats.chromaticWinsByDifficulty);
    if (chromatic) {
      chromaticGamesWon += 1;
      final chromaticPrevious = chromaticBestTimes[difficulty];
      if (chromaticPrevious == null || elapsed < chromaticPrevious) {
        chromaticBestTimes[difficulty] = elapsed;
      }
      chromaticWinsByDifficulty[difficulty] =
          (_stats.chromaticWinsFor(difficulty)) + 1;
    }

    final currentStreakByPalette =
        Map<GamePalette, int>.from(_stats.currentStreakByPalette);
    final bestStreakByPalette =
        Map<GamePalette, int>.from(_stats.bestStreakByPalette);
    for (final p in GamePalette.values) {
      if (p != palette) currentStreakByPalette[p] = 0;
    }
    final paletteCurrent = (currentStreakByPalette[palette] ?? 0) + 1;
    currentStreakByPalette[palette] = paletteCurrent;
    if (paletteCurrent > (bestStreakByPalette[palette] ?? 0)) {
      bestStreakByPalette[palette] = paletteCurrent;
    }

    final unlockedPalettes = Set<GamePalette>.from(_stats.unlockedPalettes);
    final newlyUnlocked = <GamePalette>[];
    final newGamesWon = _stats.gamesWon + 1;

    if (!unlockedPalettes.contains(GamePalette.world11) && newGamesWon >= 1) {
      unlockedPalettes.add(GamePalette.world11);
      newlyUnlocked.add(GamePalette.world11);
    }

    if (!unlockedPalettes.contains(GamePalette.neon) &&
        difficulty == Difficulty.easy &&
        elapsed < const Duration(minutes: 8)) {
      unlockedPalettes.add(GamePalette.neon);
      newlyUnlocked.add(GamePalette.neon);
    }

    if (!unlockedPalettes.contains(GamePalette.pkmn) && newStreak >= 4) {
      unlockedPalettes.add(GamePalette.pkmn);
      newlyUnlocked.add(GamePalette.pkmn);
    }

    if (!unlockedPalettes.contains(GamePalette.pkmn2) &&
        difficulty == Difficulty.hard &&
        mistakes == 0) {
      unlockedPalettes.add(GamePalette.pkmn2);
      newlyUnlocked.add(GamePalette.pkmn2);
    }

    if (!unlockedPalettes.contains(GamePalette.glass) &&
        difficulty == Difficulty.expert &&
        mistakes == 0) {
      unlockedPalettes.add(GamePalette.glass);
      newlyUnlocked.add(GamePalette.glass);
    }

    if (!unlockedPalettes.contains(GamePalette.sky) &&
        difficulty == Difficulty.master) {
      unlockedPalettes.add(GamePalette.sky);
      newlyUnlocked.add(GamePalette.sky);
    }

    _stats = _stats.copyWith(
      currentStreak: newStreak,
      bestStreak: bestStreak,
      gamesWon: newGamesWon,
      bestTimes: bestTimes,
      winsByDifficulty: winsByDifficulty,
      chromaticGamesWon: chromaticGamesWon,
      chromaticBestTimes: chromaticBestTimes,
      chromaticWinsByDifficulty: chromaticWinsByDifficulty,
      unlockedPalettes: unlockedPalettes,
      bestStreakByPalette: bestStreakByPalette,
      currentStreakByPalette: currentStreakByPalette,
    );
    _awardWinXp(
      difficulty: difficulty,
      mistakes: mistakes,
      elapsed: elapsed,
      daily: daily,
      dailyStreak: dailyStreak,
      chromatic: chromatic,
      achievedXp: achievedXp,
    );
    return newlyUnlocked;
  }

  Future<void> resetStreak({required GamePalette palette}) async {
    resetStreakSync(palette: palette);
    await persist();
  }

  void resetStreakSync({required GamePalette palette}) {
    final currentStreakByPalette =
        Map<GamePalette, int>.from(_stats.currentStreakByPalette);
    final hadPaletteStreak = (currentStreakByPalette[palette] ?? 0) > 0;
    currentStreakByPalette[palette] = 0;
    if (_stats.currentStreak == 0 && !hadPaletteStreak) return;
    _stats = _stats.copyWith(
      currentStreak: 0,
      currentStreakByPalette: currentStreakByPalette,
    );
    notifyListeners();
  }
}

enum GraffitiMatchResult { win, loss, draw }

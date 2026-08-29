import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/achievements_progress.dart';
import '../models/difficulty.dart';
import '../models/game_palette.dart';
import '../models/game_stats.dart';
import '../models/iroen_mosaic.dart';
import '../models/iroen_state.dart';
import '../models/paused_game.dart';

class PreferencesService {
  static const _keyDifficulty = 'difficulty';
  static const _keyDarkMode = 'dark_mode';
  static const _keySoundEnabled = 'sound_enabled';
  static const _keyXlPicker = 'xl_picker';
  static const _keyChromatic = 'chromatic';
  static const _keyPalette = 'palette';
  static const _keyCurrentStreak = 'stats_current_streak';
  static const _keyBestStreak = 'stats_best_streak';
  static const _keyGamesPlayed = 'stats_games_played';
  static const _keyGamesWon = 'stats_games_won';
  static const _keyChromaticGamesWon = 'stats_chromatic_games_won';
  static const _keyGraffitiWins = 'stats_graffiti_wins';
  static const _keyGraffitiLosses = 'stats_graffiti_losses';
  static const _keyGraffitiDraws = 'stats_graffiti_draws';
  static const _keyPocketGraffitiWins = 'stats_pocket_graffiti_wins';
  static const _keyPocketGraffitiLosses = 'stats_pocket_graffiti_losses';
  static const _keyPocketGraffitiDraws = 'stats_pocket_graffiti_draws';
  static const _keyPocketDailyWins = 'stats_pocket_daily_wins';
  static const _keyPocketDailyBestTime = 'stats_pocket_daily_best_time';
  static const _keyPocketWins = 'stats_pocket_wins';
  static const _keyPocketBestTime = 'stats_pocket_best_time';
  static const _keyPocketChromaticWins = 'stats_pocket_chromatic_wins';
  static const _keyPocketChromaticBestTime = 'stats_pocket_chromatic_best_time';
  static const _keyPocketCurrentStreak = 'stats_pocket_current_streak';
  static const _keyPocketBestStreak = 'stats_pocket_best_streak';
  static const _keyPocketChromaticCurrentStreak =
      'stats_pocket_chromatic_current_streak';
  static const _keyPocketChromaticBestStreak =
      'stats_pocket_chromatic_best_streak';
  static const _keyTotalXp = 'stats_total_xp';
  static const _keyXpLastAwardDay = 'stats_xp_last_award_day';
  static const _keyXpLastWinPalette = 'stats_xp_last_win_palette';
  static const _keyUnlockedPalettes = 'unlocked_palettes';
  static const _keyPausedGame = 'paused_game';
  static const _keyParkedRegularGame = 'parked_regular_game';
  static const _keyParkedChromaticGame = 'parked_chromatic_game';
  static const _keyParkedDailyGame = 'parked_daily_game';
  static const _keyParkedPocketGame = 'parked_pocket_game';
  static const _keyParkedPocketChromaticGame = 'parked_pocket_chromatic_game';
  static const _keyParkedPocketDailyGame = 'parked_pocket_daily_game';
  static const _keyCompletedDailyGame = 'completed_daily_game';
  static const _keyCompletedPocketDailyGame = 'completed_pocket_daily_game';
  static const _keyFailedDailyGame = 'failed_daily_game';
  static const _keyIroenState = 'iroen_state';
  static const _keyIroenGallery = 'iroen_gallery';
  static const _keyIroenActiveMosaicId = 'iroen_active_mosaic_id';
  static const _keyDevMode = 'dev_mode';
  static const _keyAchievements = 'achievements_progress';
  static const _keyAchievementsSeen = 'achievements_seen_ids';
  static const _keyDailyLastCompleted = 'daily_last_completed_day';
  static const _keyDailyLastFailed = 'daily_last_failed_day';
  static const _keyDailyStreak = 'daily_streak';
  static const _keyDailyBestStreak = 'daily_best_streak';
  static const _keyPocketDailyLastCompleted = 'pocket_daily_last_completed_day';
  static const _keyPocketDailyStreak = 'pocket_daily_streak';
  static const _keyPocketDailyBestStreak = 'pocket_daily_best_streak';
  static const _keyPaletteBeforeDaily = 'palette_before_daily';

  final SharedPreferences _prefs;

  PreferencesService(this._prefs);

  static Future<PreferencesService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return PreferencesService(prefs);
  }

  Difficulty getDifficulty() {
    final key = _prefs.getString(_keyDifficulty);
    final difficulty = Difficulty.fromStorageKey(key);
    // Rewrite legacy Hard key ("expert") to the modern "hard" key.
    if (key == 'expert') {
      _prefs.setString(_keyDifficulty, Difficulty.hard.storageKey);
    }
    return difficulty;
  }

  Future<void> setDifficulty(Difficulty difficulty) async {
    await _prefs.setString(_keyDifficulty, difficulty.storageKey);
  }

  bool getDarkMode() => _prefs.getBool(_keyDarkMode) ?? false;

  Future<void> setDarkMode(bool enabled) async {
    await _prefs.setBool(_keyDarkMode, enabled);
  }

  /// Defaults to on when unset.
  bool getSoundEnabled() => _prefs.getBool(_keySoundEnabled) ?? true;

  Future<void> setSoundEnabled(bool enabled) async {
    await _prefs.setBool(_keySoundEnabled, enabled);
  }

  /// Defaults to on when unset.
  bool getXlPicker() => _prefs.getBool(_keyXlPicker) ?? true;

  Future<void> setXlPicker(bool enabled) async {
    await _prefs.setBool(_keyXlPicker, enabled);
  }

  bool getChromatic() => _prefs.getBool(_keyChromatic) ?? false;

  Future<void> setChromatic(bool enabled) async {
    await _prefs.setBool(_keyChromatic, enabled);
  }

  bool getDevMode() => _prefs.getBool(_keyDevMode) ?? false;

  Future<void> setDevMode(bool enabled) async {
    await _prefs.setBool(_keyDevMode, enabled);
  }

  bool get hasTotalXp => _prefs.containsKey(_keyTotalXp);

  String? getXpLastAwardDay() => _prefs.getString(_keyXpLastAwardDay);

  Future<void> setXpLastAwardDay(String dayKey) async {
    await _prefs.setString(_keyXpLastAwardDay, dayKey);
  }

  /// Storage key of the palette used on the last XP-awarding win, or null.
  String? getXpLastWinPalette() => _prefs.getString(_keyXpLastWinPalette);

  Future<void> setXpLastWinPalette(String paletteKey) async {
    await _prefs.setString(_keyXpLastWinPalette, paletteKey);
  }

  /// `yyyy-MM-dd` of the last completed Daily Irodoku, or null.
  String? getDailyLastCompletedDay() =>
      _prefs.getString(_keyDailyLastCompleted);

  /// `yyyy-MM-dd` of the last failed Daily Irodoku, or null.
  String? getDailyLastFailedDay() => _prefs.getString(_keyDailyLastFailed);

  int getDailyStreak() => _prefs.getInt(_keyDailyStreak) ?? 0;

  /// Highest Daily Iro win streak ever achieved.
  int getDailyBestStreak() {
    final best = _prefs.getInt(_keyDailyBestStreak) ?? 0;
    final current = getDailyStreak();
    // Migrate: older installs only tracked the live streak.
    return best > current ? best : current;
  }

  Future<void> setDailyProgress({
    required String lastCompletedDay,
    required int streak,
  }) async {
    await _prefs.setString(_keyDailyLastCompleted, lastCompletedDay);
    await _prefs.setInt(_keyDailyStreak, streak);
    final best = _prefs.getInt(_keyDailyBestStreak) ?? 0;
    if (streak > best) {
      await _prefs.setInt(_keyDailyBestStreak, streak);
    }
  }

  String? getPocketDailyLastCompletedDay() =>
      _prefs.getString(_keyPocketDailyLastCompleted);

  int getPocketDailyStreak() => _prefs.getInt(_keyPocketDailyStreak) ?? 0;

  int getPocketDailyBestStreak() {
    final best = _prefs.getInt(_keyPocketDailyBestStreak) ?? 0;
    final current = getPocketDailyStreak();
    return best > current ? best : current;
  }

  Future<void> setPocketDailyProgress({
    required String lastCompletedDay,
    required int streak,
  }) async {
    await _prefs.setString(_keyPocketDailyLastCompleted, lastCompletedDay);
    await _prefs.setInt(_keyPocketDailyStreak, streak);
    final best = _prefs.getInt(_keyPocketDailyBestStreak) ?? 0;
    if (streak > best) {
      await _prefs.setInt(_keyPocketDailyBestStreak, streak);
    }
  }

  Future<void> resetDailyStreak() async {
    await _prefs.setInt(_keyDailyStreak, 0);
  }

  Future<void> setDailyFailedDay(String dayKey) async {
    await _prefs.setString(_keyDailyLastFailed, dayKey);
  }

  Future<void> clearDailyFailedDay() async {
    await _prefs.remove(_keyDailyLastFailed);
  }

  /// Palette to restore after leaving a Daily Irodoku session.
  GamePalette? getPaletteBeforeDaily() {
    final key = _prefs.getString(_keyPaletteBeforeDaily);
    if (key == null || key.isEmpty) return null;
    return GamePalette.fromStorageKey(key);
  }

  Future<void> setPaletteBeforeDaily(GamePalette palette) async {
    await _prefs.setString(_keyPaletteBeforeDaily, palette.storageKey);
  }

  Future<void> clearPaletteBeforeDaily() async {
    await _prefs.remove(_keyPaletteBeforeDaily);
  }

  GamePalette getPalette() {
    return GamePalette.fromStorageKey(_prefs.getString(_keyPalette));
  }

  Future<void> setPalette(GamePalette palette) async {
    await _prefs.setString(_keyPalette, palette.storageKey);
  }

  GameStats loadStats() {
    final bestTimes = <Difficulty, Duration?>{};
    final winsByDifficulty = <Difficulty, int>{};
    final chromaticBestTimes = <Difficulty, Duration?>{};
    final chromaticWinsByDifficulty = <Difficulty, int>{};
    for (final d in Difficulty.values) {
      final ms = _prefs.getInt(_bestTimeKey(d));
      bestTimes[d] = ms == null ? null : Duration(milliseconds: ms);
      winsByDifficulty[d] = _prefs.getInt(_winsKey(d)) ?? 0;
      final chromaticMs = _prefs.getInt(_chromaticBestTimeKey(d));
      chromaticBestTimes[d] =
          chromaticMs == null ? null : Duration(milliseconds: chromaticMs);
      chromaticWinsByDifficulty[d] = _prefs.getInt(_chromaticWinsKey(d)) ?? 0;
    }
    _migrateLegacyHardStats(bestTimes, winsByDifficulty);
    final bestStreakByPalette = <GamePalette, int>{};
    final currentStreakByPalette = <GamePalette, int>{};
    final pocketBestStreakByPalette = <GamePalette, int>{};
    final pocketCurrentStreakByPalette = <GamePalette, int>{};
    for (final palette in GamePalette.values) {
      bestStreakByPalette[palette] =
          _prefs.getInt(_paletteBestStreakKey(palette)) ?? 0;
      currentStreakByPalette[palette] =
          _prefs.getInt(_paletteCurrentStreakKey(palette)) ?? 0;
      pocketBestStreakByPalette[palette] =
          _prefs.getInt(_pocketPaletteBestStreakKey(palette)) ?? 0;
      pocketCurrentStreakByPalette[palette] =
          _prefs.getInt(_pocketPaletteCurrentStreakKey(palette)) ?? 0;
    }
    return GameStats(
      currentStreak: _prefs.getInt(_keyCurrentStreak) ?? 0,
      bestStreak: _prefs.getInt(_keyBestStreak) ?? 0,
      gamesPlayed: _prefs.getInt(_keyGamesPlayed) ?? 0,
      gamesWon: _prefs.getInt(_keyGamesWon) ?? 0,
      bestTimes: bestTimes,
      winsByDifficulty: winsByDifficulty,
      chromaticGamesWon: _prefs.getInt(_keyChromaticGamesWon) ?? 0,
      chromaticBestTimes: chromaticBestTimes,
      chromaticWinsByDifficulty: chromaticWinsByDifficulty,
      unlockedPalettes: _loadUnlockedPalettes(),
      bestStreakByPalette: bestStreakByPalette,
      currentStreakByPalette: currentStreakByPalette,
      graffitiWins: _prefs.getInt(_keyGraffitiWins) ?? 0,
      graffitiLosses: _prefs.getInt(_keyGraffitiLosses) ?? 0,
      graffitiDraws: _prefs.getInt(_keyGraffitiDraws) ?? 0,
      totalXp: _prefs.getInt(_keyTotalXp) ?? 0,
      pocketWins: _prefs.getInt(_keyPocketWins) ?? 0,
      pocketBestTime: _durationFromMs(_prefs.getInt(_keyPocketBestTime)),
      pocketChromaticWins: _prefs.getInt(_keyPocketChromaticWins) ?? 0,
      pocketChromaticBestTime:
          _durationFromMs(_prefs.getInt(_keyPocketChromaticBestTime)),
      pocketBestStreakByPalette: pocketBestStreakByPalette,
      pocketCurrentStreakByPalette: pocketCurrentStreakByPalette,
      pocketCurrentStreak: _prefs.getInt(_keyPocketCurrentStreak) ?? 0,
      pocketBestStreak: _prefs.getInt(_keyPocketBestStreak) ?? 0,
      pocketChromaticCurrentStreak:
          _prefs.getInt(_keyPocketChromaticCurrentStreak) ?? 0,
      pocketChromaticBestStreak:
          _prefs.getInt(_keyPocketChromaticBestStreak) ?? 0,
      pocketGraffitiWins: _prefs.getInt(_keyPocketGraffitiWins) ?? 0,
      pocketGraffitiLosses: _prefs.getInt(_keyPocketGraffitiLosses) ?? 0,
      pocketGraffitiDraws: _prefs.getInt(_keyPocketGraffitiDraws) ?? 0,
      pocketDailyWins: _prefs.getInt(_keyPocketDailyWins) ?? 0,
      pocketDailyBestTime:
          _durationFromMs(_prefs.getInt(_keyPocketDailyBestTime)),
    );
  }

  Future<void> saveStats(GameStats stats) async {
    await _prefs.setInt(_keyCurrentStreak, stats.currentStreak);
    await _prefs.setInt(_keyBestStreak, stats.bestStreak);
    await _prefs.setInt(_keyGamesPlayed, stats.gamesPlayed);
    await _prefs.setInt(_keyGamesWon, stats.gamesWon);
    await _prefs.setInt(_keyChromaticGamesWon, stats.chromaticGamesWon);
    await _prefs.setInt(_keyGraffitiWins, stats.graffitiWins);
    await _prefs.setInt(_keyGraffitiLosses, stats.graffitiLosses);
    await _prefs.setInt(_keyGraffitiDraws, stats.graffitiDraws);
    await _prefs.setInt(_keyPocketGraffitiWins, stats.pocketGraffitiWins);
    await _prefs.setInt(_keyPocketGraffitiLosses, stats.pocketGraffitiLosses);
    await _prefs.setInt(_keyPocketGraffitiDraws, stats.pocketGraffitiDraws);
    await _prefs.setInt(_keyPocketDailyWins, stats.pocketDailyWins);
    await _setOptionalDuration(
      _keyPocketDailyBestTime,
      stats.pocketDailyBestTime,
    );
    await _prefs.setInt(_keyTotalXp, stats.totalXp);
    await _prefs.setInt(_keyPocketWins, stats.pocketWins);
    await _setOptionalDuration(_keyPocketBestTime, stats.pocketBestTime);
    await _prefs.setInt(_keyPocketChromaticWins, stats.pocketChromaticWins);
    await _setOptionalDuration(
      _keyPocketChromaticBestTime,
      stats.pocketChromaticBestTime,
    );
    await _prefs.setInt(_keyPocketCurrentStreak, stats.pocketCurrentStreak);
    await _prefs.setInt(_keyPocketBestStreak, stats.pocketBestStreak);
    await _prefs.setInt(
      _keyPocketChromaticCurrentStreak,
      stats.pocketChromaticCurrentStreak,
    );
    await _prefs.setInt(
      _keyPocketChromaticBestStreak,
      stats.pocketChromaticBestStreak,
    );
    for (final d in Difficulty.values) {
      final time = stats.bestTimes[d];
      if (time == null) {
        await _prefs.remove(_bestTimeKey(d));
      } else {
        await _prefs.setInt(_bestTimeKey(d), time.inMilliseconds);
      }
      await _prefs.setInt(_winsKey(d), stats.winsFor(d));
      final chromaticTime = stats.chromaticBestTimes[d];
      if (chromaticTime == null) {
        await _prefs.remove(_chromaticBestTimeKey(d));
      } else {
        await _prefs.setInt(
          _chromaticBestTimeKey(d),
          chromaticTime.inMilliseconds,
        );
      }
      await _prefs.setInt(_chromaticWinsKey(d), stats.chromaticWinsFor(d));
    }
    await _prefs.setStringList(
      _keyUnlockedPalettes,
      stats.unlockedPalettes.map((palette) => palette.storageKey).toList(),
    );
    for (final palette in GamePalette.values) {
      await _prefs.setInt(
        _paletteBestStreakKey(palette),
        stats.bestStreakForPalette(palette),
      );
      await _prefs.setInt(
        _paletteCurrentStreakKey(palette),
        stats.currentStreakByPalette[palette] ?? 0,
      );
      await _prefs.setInt(
        _pocketPaletteBestStreakKey(palette),
        stats.pocketBestStreakByPalette[palette] ?? 0,
      );
      await _prefs.setInt(
        _pocketPaletteCurrentStreakKey(palette),
        stats.pocketCurrentStreakByPalette[palette] ?? 0,
      );
    }
  }

  Duration? _durationFromMs(int? ms) =>
      ms == null ? null : Duration(milliseconds: ms);

  Future<void> _setOptionalDuration(String key, Duration? time) async {
    if (time == null) {
      await _prefs.remove(key);
    } else {
      await _prefs.setInt(key, time.inMilliseconds);
    }
  }

  String _bestTimeKey(Difficulty d) => 'stats_best_time_${d.storageKey}';

  String _winsKey(Difficulty d) => 'stats_wins_${d.storageKey}';

  String _chromaticBestTimeKey(Difficulty d) =>
      'stats_chromatic_best_time_${d.storageKey}';

  String _chromaticWinsKey(Difficulty d) =>
      'stats_chromatic_wins_${d.storageKey}';

  String _paletteBestStreakKey(GamePalette palette) =>
      'stats_palette_best_streak_${palette.storageKey}';

  String _paletteCurrentStreakKey(GamePalette palette) =>
      'stats_palette_current_streak_${palette.storageKey}';

  String _pocketPaletteBestStreakKey(GamePalette palette) =>
      'stats_pocket_palette_best_streak_${palette.storageKey}';

  String _pocketPaletteCurrentStreakKey(GamePalette palette) =>
      'stats_pocket_palette_current_streak_${palette.storageKey}';

  Set<GamePalette> _loadUnlockedPalettes() {
    final keys = _prefs.getStringList(_keyUnlockedPalettes);
    if (keys == null) return {};
    return keys.map(GamePalette.fromStorageKey).toSet();
  }

  /// Hard was previously stored under the "expert" preference keys.
  /// Migrates once into Hard's modern keys, then clears the legacy entries so
  /// they can't collide with a future Expert key or double-count on load.
  void _migrateLegacyHardStats(
    Map<Difficulty, Duration?> bestTimes,
    Map<Difficulty, int> winsByDifficulty,
  ) {
    const legacyWinsKey = 'stats_wins_expert';
    const legacyBestKey = 'stats_best_time_expert';
    final legacyWins = _prefs.getInt(legacyWinsKey);
    if (legacyWins != null) {
      if (legacyWins > 0) {
        final hardWins = winsByDifficulty[Difficulty.hard] ?? 0;
        // Prefer the larger value — avoids stacking the same legacy total
        // onto Hard on every launch before keys were cleared.
        if (legacyWins > hardWins) {
          winsByDifficulty[Difficulty.hard] = legacyWins;
        }
      }
      _prefs.remove(legacyWinsKey);
    }
    final legacyBestMs = _prefs.getInt(legacyBestKey);
    if (legacyBestMs != null) {
      final legacyBest = Duration(milliseconds: legacyBestMs);
      final current = bestTimes[Difficulty.hard];
      if (current == null || legacyBest < current) {
        bestTimes[Difficulty.hard] = legacyBest;
      }
      _prefs.remove(legacyBestKey);
    }
  }

  PausedGame? loadPausedGame() => _loadPaused(_keyPausedGame);

  Future<void> savePausedGame(PausedGame game) async {
    await _prefs.setString(_keyPausedGame, jsonEncode(game.toJson()));
  }

  Future<void> clearPausedGame() async {
    await _prefs.remove(_keyPausedGame);
  }

  PausedGame? loadParkedRegularGame() => _loadPaused(_keyParkedRegularGame);

  Future<void> saveParkedRegularGame(PausedGame game) async {
    await _prefs.setString(_keyParkedRegularGame, jsonEncode(game.toJson()));
  }

  Future<void> clearParkedRegularGame() async {
    await _prefs.remove(_keyParkedRegularGame);
  }

  PausedGame? loadParkedChromaticGame() =>
      _loadPaused(_keyParkedChromaticGame);

  Future<void> saveParkedChromaticGame(PausedGame game) async {
    await _prefs.setString(_keyParkedChromaticGame, jsonEncode(game.toJson()));
  }

  Future<void> clearParkedChromaticGame() async {
    await _prefs.remove(_keyParkedChromaticGame);
  }

  PausedGame? loadParkedDailyGame() => _loadPaused(_keyParkedDailyGame);

  Future<void> saveParkedDailyGame(PausedGame game) async {
    await _prefs.setString(_keyParkedDailyGame, jsonEncode(game.toJson()));
  }

  Future<void> clearParkedDailyGame() async {
    await _prefs.remove(_keyParkedDailyGame);
  }

  PausedGame? loadParkedPocketGame() => _loadPaused(_keyParkedPocketGame);

  Future<void> saveParkedPocketGame(PausedGame game) async {
    await _prefs.setString(_keyParkedPocketGame, jsonEncode(game.toJson()));
  }

  Future<void> clearParkedPocketGame() async {
    await _prefs.remove(_keyParkedPocketGame);
  }

  PausedGame? loadParkedPocketChromaticGame() =>
      _loadPaused(_keyParkedPocketChromaticGame);

  Future<void> saveParkedPocketChromaticGame(PausedGame game) async {
    await _prefs.setString(
      _keyParkedPocketChromaticGame,
      jsonEncode(game.toJson()),
    );
  }

  Future<void> clearParkedPocketChromaticGame() async {
    await _prefs.remove(_keyParkedPocketChromaticGame);
  }

  PausedGame? loadParkedPocketDailyGame() =>
      _loadPaused(_keyParkedPocketDailyGame);

  Future<void> saveParkedPocketDailyGame(PausedGame game) async {
    await _prefs.setString(
      _keyParkedPocketDailyGame,
      jsonEncode(game.toJson()),
    );
  }

  Future<void> clearParkedPocketDailyGame() async {
    await _prefs.remove(_keyParkedPocketDailyGame);
  }

  PausedGame? loadCompletedDailyGame() => _loadPaused(_keyCompletedDailyGame);

  Future<void> saveCompletedDailyGame(PausedGame game) async {
    await _prefs.setString(_keyCompletedDailyGame, jsonEncode(game.toJson()));
  }

  Future<void> clearCompletedDailyGame() async {
    await _prefs.remove(_keyCompletedDailyGame);
  }

  PausedGame? loadCompletedPocketDailyGame() =>
      _loadPaused(_keyCompletedPocketDailyGame);

  Future<void> saveCompletedPocketDailyGame(PausedGame game) async {
    await _prefs.setString(
      _keyCompletedPocketDailyGame,
      jsonEncode(game.toJson()),
    );
  }

  Future<void> clearCompletedPocketDailyGame() async {
    await _prefs.remove(_keyCompletedPocketDailyGame);
  }

  PausedGame? loadFailedDailyGame() => _loadPaused(_keyFailedDailyGame);

  Future<void> saveFailedDailyGame(PausedGame game) async {
    await _prefs.setString(_keyFailedDailyGame, jsonEncode(game.toJson()));
  }

  Future<void> clearFailedDailyGame() async {
    await _prefs.remove(_keyFailedDailyGame);
  }

  PausedGame? _loadPaused(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return PausedGame.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  IroenState? loadIroenState() {
    final raw = _prefs.getString(_keyIroenState);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return IroenState.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveIroenState(IroenState state) async {
    await _prefs.setString(_keyIroenState, jsonEncode(state.toJson()));
  }

  List<IroenMosaic> loadIroenGallery() {
    final raw = _prefs.getString(_keyIroenGallery);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map)
            IroenMosaic.fromJson(Map<String, dynamic>.from(item)),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveIroenGallery(List<IroenMosaic> mosaics) async {
    await _prefs.setString(
      _keyIroenGallery,
      jsonEncode([for (final mosaic in mosaics) mosaic.toJson()]),
    );
  }

  String? getIroenActiveMosaicId() => _prefs.getString(_keyIroenActiveMosaicId);

  Future<void> setIroenActiveMosaicId(String? id) async {
    if (id == null || id.isEmpty) {
      await _prefs.remove(_keyIroenActiveMosaicId);
    } else {
      await _prefs.setString(_keyIroenActiveMosaicId, id);
    }
  }

  AchievementsProgress loadAchievements() {
    final raw = _prefs.getString(_keyAchievements);
    if (raw == null || raw.isEmpty) return const AchievementsProgress();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const AchievementsProgress();
      return AchievementsProgress.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return const AchievementsProgress();
    }
  }

  Future<void> saveAchievements(AchievementsProgress progress) async {
    await _prefs.setString(_keyAchievements, jsonEncode(progress.toJson()));
  }

  /// Achievement IDs the player has already seen on the Achievements screen.
  Set<String> loadSeenAchievementIds() {
    final raw = _prefs.getStringList(_keyAchievementsSeen);
    if (raw == null) return {};
    return raw.toSet();
  }

  Future<void> saveSeenAchievementIds(Set<String> ids) async {
    await _prefs.setStringList(_keyAchievementsSeen, ids.toList()..sort());
  }
}

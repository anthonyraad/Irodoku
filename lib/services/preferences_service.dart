import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/difficulty.dart';
import '../models/game_palette.dart';
import '../models/game_stats.dart';
import '../models/iroen_state.dart';
import '../models/paused_game.dart';

class PreferencesService {
  static const _keyDifficulty = 'difficulty';
  static const _keyDarkMode = 'dark_mode';
  static const _keySoundEnabled = 'sound_enabled';
  static const _keyXlPicker = 'xl_picker';
  static const _keyPalette = 'palette';
  static const _keyCurrentStreak = 'stats_current_streak';
  static const _keyBestStreak = 'stats_best_streak';
  static const _keyGamesPlayed = 'stats_games_played';
  static const _keyGamesWon = 'stats_games_won';
  static const _keyUnlockedPalettes = 'unlocked_palettes';
  static const _keyPausedGame = 'paused_game';
  static const _keyIroenState = 'iroen_state';
  static const _keyDevMode = 'dev_mode';

  final SharedPreferences _prefs;

  PreferencesService(this._prefs);

  static Future<PreferencesService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return PreferencesService(prefs);
  }

  Difficulty getDifficulty() {
    return Difficulty.fromStorageKey(_prefs.getString(_keyDifficulty));
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

  bool getXlPicker() => _prefs.getBool(_keyXlPicker) ?? false;

  Future<void> setXlPicker(bool enabled) async {
    await _prefs.setBool(_keyXlPicker, enabled);
  }

  bool getDevMode() => _prefs.getBool(_keyDevMode) ?? false;

  Future<void> setDevMode(bool enabled) async {
    await _prefs.setBool(_keyDevMode, enabled);
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
    for (final d in Difficulty.values) {
      final ms = _prefs.getInt(_bestTimeKey(d));
      bestTimes[d] = ms == null ? null : Duration(milliseconds: ms);
      winsByDifficulty[d] = _prefs.getInt(_winsKey(d)) ?? 0;
    }
    _migrateLegacyHardStats(bestTimes, winsByDifficulty);
    final bestStreakByPalette = <GamePalette, int>{};
    final currentStreakByPalette = <GamePalette, int>{};
    for (final palette in GamePalette.values) {
      bestStreakByPalette[palette] =
          _prefs.getInt(_paletteBestStreakKey(palette)) ?? 0;
      currentStreakByPalette[palette] =
          _prefs.getInt(_paletteCurrentStreakKey(palette)) ?? 0;
    }
    return GameStats(
      currentStreak: _prefs.getInt(_keyCurrentStreak) ?? 0,
      bestStreak: _prefs.getInt(_keyBestStreak) ?? 0,
      gamesPlayed: _prefs.getInt(_keyGamesPlayed) ?? 0,
      gamesWon: _prefs.getInt(_keyGamesWon) ?? 0,
      bestTimes: bestTimes,
      winsByDifficulty: winsByDifficulty,
      unlockedPalettes: _loadUnlockedPalettes(),
      bestStreakByPalette: bestStreakByPalette,
      currentStreakByPalette: currentStreakByPalette,
    );
  }

  Future<void> saveStats(GameStats stats) async {
    await _prefs.setInt(_keyCurrentStreak, stats.currentStreak);
    await _prefs.setInt(_keyBestStreak, stats.bestStreak);
    await _prefs.setInt(_keyGamesPlayed, stats.gamesPlayed);
    await _prefs.setInt(_keyGamesWon, stats.gamesWon);
    for (final d in Difficulty.values) {
      final time = stats.bestTimes[d];
      if (time == null) {
        await _prefs.remove(_bestTimeKey(d));
      } else {
        await _prefs.setInt(_bestTimeKey(d), time.inMilliseconds);
      }
      await _prefs.setInt(_winsKey(d), stats.winsFor(d));
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
    }
  }

  String _bestTimeKey(Difficulty d) => 'stats_best_time_${d.storageKey}';

  String _winsKey(Difficulty d) => 'stats_wins_${d.storageKey}';

  String _paletteBestStreakKey(GamePalette palette) =>
      'stats_palette_best_streak_${palette.storageKey}';

  String _paletteCurrentStreakKey(GamePalette palette) =>
      'stats_palette_current_streak_${palette.storageKey}';

  Set<GamePalette> _loadUnlockedPalettes() {
    final keys = _prefs.getStringList(_keyUnlockedPalettes);
    if (keys == null) return {};
    return keys.map(GamePalette.fromStorageKey).toSet();
  }

  /// Hard was previously stored under the "expert" preference keys.
  void _migrateLegacyHardStats(
    Map<Difficulty, Duration?> bestTimes,
    Map<Difficulty, int> winsByDifficulty,
  ) {
    const legacyWinsKey = 'stats_wins_expert';
    const legacyBestKey = 'stats_best_time_expert';
    final legacyWins = _prefs.getInt(legacyWinsKey);
    if (legacyWins != null && legacyWins > 0) {
      winsByDifficulty[Difficulty.hard] =
          (winsByDifficulty[Difficulty.hard] ?? 0) + legacyWins;
    }
    final legacyBestMs = _prefs.getInt(legacyBestKey);
    if (legacyBestMs != null) {
      final legacyBest = Duration(milliseconds: legacyBestMs);
      final current = bestTimes[Difficulty.hard];
      if (current == null || legacyBest < current) {
        bestTimes[Difficulty.hard] = legacyBest;
      }
    }
  }

  PausedGame? loadPausedGame() {
    final raw = _prefs.getString(_keyPausedGame);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return PausedGame.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> savePausedGame(PausedGame game) async {
    await _prefs.setString(_keyPausedGame, jsonEncode(game.toJson()));
  }

  Future<void> clearPausedGame() async {
    await _prefs.remove(_keyPausedGame);
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
}

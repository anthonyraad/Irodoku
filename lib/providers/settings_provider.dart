import 'package:flutter/foundation.dart';

import '../models/difficulty.dart';
import '../models/game_palette.dart';
import '../models/game_stats.dart';
import '../services/preferences_service.dart';
import 'stats_provider.dart';

class SettingsProvider extends ChangeNotifier {
  static const _devModeToggleCount = 20;
  static const _devModeToggleWindow = Duration(seconds: 8);

  final PreferencesService _prefs;
  final StatsProvider _stats;

  Difficulty _difficulty;
  bool _darkMode;
  bool _devMode;
  bool _soundEnabled;
  bool _xlPicker;
  GamePalette _palette;
  int _darkModeToggleStreak = 0;
  DateTime? _lastDarkModeToggle;

  SettingsProvider(this._prefs, {required StatsProvider stats})
      : _stats = stats,
        _difficulty = _prefs.getDifficulty(),
        _darkMode = _prefs.getDarkMode(),
        _devMode = _prefs.getDevMode(),
        _soundEnabled = _prefs.getSoundEnabled(),
        _xlPicker = _prefs.getXlPicker(),
        _palette = _prefs.getPalette() {
    _clampDifficultyToUnlocked();
    _clampPaletteToUnlocked();
  }

  Difficulty get difficulty => _difficulty;
  bool get darkMode => _darkMode;
  bool get devMode => _devMode;
  bool get soundEnabled => _soundEnabled;
  bool get xlPicker => _xlPicker;
  GamePalette get palette => _palette;

  Future<void> setDifficulty(Difficulty difficulty) async {
    if (_difficulty == difficulty) return;
    if (!_devMode && !_prefs.loadStats().isUnlocked(difficulty)) return;
    _difficulty = difficulty;
    notifyListeners();
    await _prefs.setDifficulty(difficulty);
  }

  Future<void> setDarkMode(bool enabled) async {
    if (_darkMode == enabled) return;

    final now = DateTime.now();
    if (_lastDarkModeToggle == null ||
        now.difference(_lastDarkModeToggle!) > _devModeToggleWindow) {
      _darkModeToggleStreak = 0;
    }
    _lastDarkModeToggle = now;
    _darkModeToggleStreak++;

    _darkMode = enabled;
    notifyListeners();
    await _prefs.setDarkMode(enabled);

    if (_darkModeToggleStreak >= _devModeToggleCount) {
      _darkModeToggleStreak = 0;
      await _toggleDevMode();
    }
  }

  Future<void> setSoundEnabled(bool enabled) async {
    if (_soundEnabled == enabled) return;
    _soundEnabled = enabled;
    notifyListeners();
    await _prefs.setSoundEnabled(enabled);
  }

  Future<void> setXlPicker(bool enabled) async {
    if (_xlPicker == enabled) return;
    _xlPicker = enabled;
    notifyListeners();
    await _prefs.setXlPicker(enabled);
  }

  Future<void> setPalette(GamePalette palette, {bool force = false}) async {
    if (_palette == palette) return;
    if (!force) {
      if (!palette.visibleInMenu) return;
      if (!_devMode && !_prefs.loadStats().isPaletteUnlocked(palette)) return;
    }
    _palette = palette;
    notifyListeners();
    await _prefs.setPalette(palette);
  }

  /// Call after stats change so a locked selection can't stick around.
  void ensureDifficultyUnlocked([GameStats? stats]) {
    if (_devMode) return;
    final current = stats ?? _prefs.loadStats();
    if (current.isUnlocked(_difficulty)) return;
    _difficulty = current.highestUnlocked;
    notifyListeners();
    _prefs.setDifficulty(_difficulty);
  }

  void ensurePaletteUnlocked([GameStats? stats]) {
    if (_devMode) return;
    final current = stats ?? _prefs.loadStats();
    if (current.isPaletteUnlocked(_palette) && _palette.visibleInMenu) return;
    _palette = current.fallbackPalette;
    notifyListeners();
    _prefs.setPalette(_palette);
  }

  void _clampDifficultyToUnlocked() {
    if (_devMode) return;
    final stats = _prefs.loadStats();
    if (stats.isUnlocked(_difficulty)) return;
    _difficulty = stats.highestUnlocked;
    _prefs.setDifficulty(_difficulty);
  }

  void _clampPaletteToUnlocked() {
    if (_devMode) return;
    final stats = _prefs.loadStats();
    if (stats.isPaletteUnlocked(_palette) && _palette.visibleInMenu) return;
    _palette = stats.fallbackPalette;
    _prefs.setPalette(_palette);
  }

  Future<void> _toggleDevMode() async {
    final enabling = !_devMode;
    _devMode = enabling;
    await _prefs.setDevMode(_devMode);

    if (!enabling) {
      _difficulty = Difficulty.easy;
      _palette = GamePalette.standard;
      await _prefs.setDifficulty(_difficulty);
      await _prefs.setPalette(_palette);
      ensureDifficultyUnlocked();
      ensurePaletteUnlocked();
    }

    _stats.notifyDevModeChanged();
    notifyListeners();
  }
}

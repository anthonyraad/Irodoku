import 'package:flutter/foundation.dart';

import '../models/difficulty.dart';
import '../models/game_palette.dart';
import '../models/game_stats.dart';
import '../services/preferences_service.dart';
import 'achievements_provider.dart';
import 'stats_provider.dart';

class SettingsProvider extends ChangeNotifier {
  static const _devModeToggleCount = 20;
  static const _devModeToggleWindow = Duration(seconds: 8);
  static const _syncRevealToggleCount = 8;
  static const _syncRevealToggleWindow = Duration(seconds: 4);

  final PreferencesService _prefs;
  final StatsProvider _stats;
  final AchievementsProvider _achievements;

  Difficulty _difficulty;
  bool _darkMode;
  bool _devMode;
  bool _soundEnabled;
  bool _xlPicker;
  bool _chromatic;
  GamePalette _palette;
  bool _pocketSwipeDiscovered;
  int _darkModeToggleStreak = 0;
  DateTime? _lastDarkModeToggle;
  int _soundToggleStreak = 0;
  DateTime? _lastSoundToggle;
  bool _syncVisible = false;

  SettingsProvider(
    this._prefs, {
    required StatsProvider stats,
    required AchievementsProvider achievements,
  })  : _stats = stats,
        _achievements = achievements,
        _difficulty = _prefs.getDifficulty(),
        _darkMode = _prefs.getDarkMode(),
        _devMode = _prefs.getDevMode(),
        _soundEnabled = _prefs.getSoundEnabled(),
        _xlPicker = _prefs.getXlPicker(),
        _chromatic = _prefs.getChromatic(),
        _palette = _prefs.getPalette(),
        _pocketSwipeDiscovered = _prefs.getPocketSwipeDiscovered() {
    _clampDifficultyToUnlocked();
    _clampPaletteToUnlocked();
    _clampChromaticToUnlocked();
  }

  void applyAfterProgressLoad() {
    _pocketSwipeDiscovered = _prefs.getPocketSwipeDiscovered();
    ensureDifficultyUnlocked(_stats.stats);
    ensurePaletteUnlocked(_stats.stats);
    _clampChromaticToUnlocked();
    notifyListeners();
  }

  Difficulty get difficulty => _difficulty;
  bool get darkMode => _darkMode;
  bool get devMode => _devMode;
  bool get soundEnabled => _soundEnabled;
  /// Hidden until Sound is toggled rapidly 8 times on this Settings visit.
  bool get syncVisible => _syncVisible;

  void hideSync() {
    _syncVisible = false;
    _soundToggleStreak = 0;
    _lastSoundToggle = null;
  }
  /// XL is temporarily forced on (Settings toggle hidden). Prefs + [setXlPicker]
  /// remain so the compact picker can be restored later.
  bool get xlPicker => true;
  bool get chromatic => _chromatic;
  GamePalette get palette => _palette;
  /// True after a successful swipe-right to Pocket on the Main Menu button.
  bool get pocketSwipeDiscovered => _pocketSwipeDiscovered;
  bool get isIroUnlocked => _devMode || _achievements.allUnlocked;

  Future<void> markPocketSwipeDiscovered() async {
    if (_pocketSwipeDiscovered) return;
    _pocketSwipeDiscovered = true;
    await _prefs.setPocketSwipeDiscovered(true);
  }

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

    if (!_syncVisible) {
      final now = DateTime.now();
      if (_lastSoundToggle == null ||
          now.difference(_lastSoundToggle!) > _syncRevealToggleWindow) {
        _soundToggleStreak = 0;
      }
      _lastSoundToggle = now;
      _soundToggleStreak++;
      if (_soundToggleStreak >= _syncRevealToggleCount) {
        _soundToggleStreak = 0;
        _syncVisible = true;
      }
    }

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

  Future<void> setChromatic(bool enabled) async {
    if (_chromatic == enabled) return;
    if (enabled && !_stats.areAllMenuPalettesUnlocked) return;
    _chromatic = enabled;
    notifyListeners();
    await _prefs.setChromatic(enabled);
  }

  Future<void> setPalette(GamePalette palette, {bool force = false}) async {
    if (_palette == palette) return;
    if (!force) {
      if (palette == GamePalette.iro) {
        if (!isIroUnlocked) return;
      } else {
        if (!palette.visibleInMenu) return;
        if (!_devMode && !_prefs.loadStats().isPaletteUnlocked(palette)) {
          return;
        }
      }
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
    if (_palette == GamePalette.iro) {
      if (_achievements.allUnlocked) return;
    } else {
      final current = stats ?? _prefs.loadStats();
      if (current.isPaletteUnlocked(_palette) && _palette.visibleInMenu) {
        return;
      }
    }
    final current = stats ?? _prefs.loadStats();
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
    if (_palette == GamePalette.iro) {
      if (_achievements.allUnlocked) return;
    } else {
      final stats = _prefs.loadStats();
      if (stats.isPaletteUnlocked(_palette) && _palette.visibleInMenu) return;
    }
    _palette = _prefs.loadStats().fallbackPalette;
    _prefs.setPalette(_palette);
  }

  void _clampChromaticToUnlocked() {
    if (!_chromatic) return;
    if (_stats.areAllMenuPalettesUnlocked) return;
    _chromatic = false;
    _prefs.setChromatic(false);
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

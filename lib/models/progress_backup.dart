import 'achievements_progress.dart';
import 'difficulty.dart';
import 'game_palette.dart';
import 'game_stats.dart';
import 'iroen_mosaic.dart';
import 'iroen_state.dart';

int _asInt(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

String? _asString(dynamic value) {
  if (value == null) return null;
  if (value is String) return value.isEmpty ? null : value;
  if (value is num || value is bool) return value.toString();
  return null;
}

Map<String, dynamic> _asJsonMap(Map<dynamic, dynamic> raw) => {
      for (final entry in raw.entries) entry.key.toString(): entry.value,
    };

Duration? _asDuration(dynamic value) {
  if (value == null) return null;
  final ms = _asInt(value, -1);
  if (ms < 0) return null;
  return Duration(milliseconds: ms);
}

Map<String, int> _durationMapToJson(Map<Difficulty, Duration?> times) => {
      for (final difficulty in Difficulty.values)
        if (times[difficulty] != null)
          difficulty.storageKey: times[difficulty]!.inMilliseconds,
    };

Map<Difficulty, Duration?> _durationMapFromJson(dynamic raw) {
  final out = <Difficulty, Duration?>{};
  if (raw is! Map) return out;
  for (final entry in raw.entries) {
    final ms = _asInt(entry.value, -1);
    if (ms < 0) continue;
    out[Difficulty.fromStorageKey(entry.key.toString())] =
        Duration(milliseconds: ms);
  }
  return out;
}

Map<String, int> _difficultyIntMapToJson(Map<Difficulty, int> counts) => {
      for (final difficulty in Difficulty.values)
        difficulty.storageKey: counts[difficulty] ?? 0,
    };

Map<Difficulty, int> _difficultyIntMapFromJson(dynamic raw) {
  final out = <Difficulty, int>{};
  if (raw is! Map) return out;
  for (final entry in raw.entries) {
    out[Difficulty.fromStorageKey(entry.key.toString())] = _asInt(entry.value);
  }
  return out;
}

Map<String, int> _paletteIntMapToJson(Map<GamePalette, int> counts) => {
      for (final palette in GamePalette.values)
        if ((counts[palette] ?? 0) != 0) palette.storageKey: counts[palette]!,
    };

Map<GamePalette, int> _paletteIntMapFromJson(dynamic raw) {
  final out = <GamePalette, int>{};
  if (raw is! Map) return out;
  for (final entry in raw.entries) {
    out[GamePalette.fromStorageKey(entry.key.toString())] = _asInt(entry.value);
  }
  return out;
}

Map<String, dynamic> _statsToJson(GameStats stats) => {
      'currentStreak': stats.currentStreak,
      'bestStreak': stats.bestStreak,
      'gamesPlayed': stats.gamesPlayed,
      'gamesWon': stats.gamesWon,
      'bestTimes': _durationMapToJson(stats.bestTimes),
      'winsByDifficulty': _difficultyIntMapToJson(stats.winsByDifficulty),
      'chromaticGamesWon': stats.chromaticGamesWon,
      'chromaticBestTimes': _durationMapToJson(stats.chromaticBestTimes),
      'chromaticWinsByDifficulty':
          _difficultyIntMapToJson(stats.chromaticWinsByDifficulty),
      'unlockedPalettes': [
        for (final palette in stats.unlockedPalettes) palette.storageKey,
      ],
      'bestStreakByPalette': _paletteIntMapToJson(stats.bestStreakByPalette),
      'currentStreakByPalette':
          _paletteIntMapToJson(stats.currentStreakByPalette),
      'graffitiWins': stats.graffitiWins,
      'graffitiLosses': stats.graffitiLosses,
      'graffitiDraws': stats.graffitiDraws,
      'totalXp': stats.totalXp,
      'pocketWins': stats.pocketWins,
      'pocketBestTimeMs': stats.pocketBestTime?.inMilliseconds,
      'pocketChromaticWins': stats.pocketChromaticWins,
      'pocketChromaticBestTimeMs': stats.pocketChromaticBestTime?.inMilliseconds,
      'pocketBestStreakByPalette':
          _paletteIntMapToJson(stats.pocketBestStreakByPalette),
      'pocketCurrentStreakByPalette':
          _paletteIntMapToJson(stats.pocketCurrentStreakByPalette),
      'pocketCurrentStreak': stats.pocketCurrentStreak,
      'pocketBestStreak': stats.pocketBestStreak,
      'pocketChromaticCurrentStreak': stats.pocketChromaticCurrentStreak,
      'pocketChromaticBestStreak': stats.pocketChromaticBestStreak,
      'pocketGraffitiWins': stats.pocketGraffitiWins,
      'pocketGraffitiLosses': stats.pocketGraffitiLosses,
      'pocketGraffitiDraws': stats.pocketGraffitiDraws,
      'pocketDailyWins': stats.pocketDailyWins,
      'pocketDailyBestTimeMs': stats.pocketDailyBestTime?.inMilliseconds,
    };

GameStats _statsFromJson(Map<String, dynamic> json) {
  final unlockedRaw = json['unlockedPalettes'];
  return GameStats(
    currentStreak: _asInt(json['currentStreak']),
    bestStreak: _asInt(json['bestStreak']),
    gamesPlayed: _asInt(json['gamesPlayed']),
    gamesWon: _asInt(json['gamesWon']),
    bestTimes: _durationMapFromJson(json['bestTimes']),
    winsByDifficulty: _difficultyIntMapFromJson(json['winsByDifficulty']),
    chromaticGamesWon: _asInt(json['chromaticGamesWon']),
    chromaticBestTimes: _durationMapFromJson(json['chromaticBestTimes']),
    chromaticWinsByDifficulty:
        _difficultyIntMapFromJson(json['chromaticWinsByDifficulty']),
    unlockedPalettes: {
      if (unlockedRaw is List)
        for (final key in unlockedRaw)
          if (key is String) GamePalette.fromStorageKey(key),
    },
    bestStreakByPalette: _paletteIntMapFromJson(json['bestStreakByPalette']),
    currentStreakByPalette:
        _paletteIntMapFromJson(json['currentStreakByPalette']),
    graffitiWins: _asInt(json['graffitiWins']),
    graffitiLosses: _asInt(json['graffitiLosses']),
    graffitiDraws: _asInt(json['graffitiDraws']),
    totalXp: _asInt(json['totalXp']),
    pocketWins: _asInt(json['pocketWins']),
    pocketBestTime: _asDuration(json['pocketBestTimeMs']),
    pocketChromaticWins: _asInt(json['pocketChromaticWins']),
    pocketChromaticBestTime: _asDuration(json['pocketChromaticBestTimeMs']),
    pocketBestStreakByPalette:
        _paletteIntMapFromJson(json['pocketBestStreakByPalette']),
    pocketCurrentStreakByPalette:
        _paletteIntMapFromJson(json['pocketCurrentStreakByPalette']),
    pocketCurrentStreak: _asInt(json['pocketCurrentStreak']),
    pocketBestStreak: _asInt(json['pocketBestStreak']),
    pocketChromaticCurrentStreak: _asInt(json['pocketChromaticCurrentStreak']),
    pocketChromaticBestStreak: _asInt(json['pocketChromaticBestStreak']),
    pocketGraffitiWins: _asInt(json['pocketGraffitiWins']),
    pocketGraffitiLosses: _asInt(json['pocketGraffitiLosses']),
    pocketGraffitiDraws: _asInt(json['pocketGraffitiDraws']),
    pocketDailyWins: _asInt(json['pocketDailyWins']),
    pocketDailyBestTime: _asDuration(json['pocketDailyBestTimeMs']),
  );
}

/// Versioned snapshot of career progress for Google / RTDB Save and Load.
class ProgressBackup {
  static const int schemaVersion = 1;

  final int v;
  final GameStats stats;
  final AchievementsProgress achievements;
  final Set<String> seenAchievementIds;
  final String? dailyLastCompleted;
  final String? dailyLastFailed;
  final int dailyStreak;
  final int dailyBestStreak;
  final String? pocketDailyLastCompleted;
  final int pocketDailyStreak;
  final int pocketDailyBestStreak;
  final String? xpLastAwardDay;
  final String? xpLastWinPalette;
  final bool pocketSwipeDiscovered;
  final IroenState? iroen;
  final List<IroenMosaic> iroenGallery;
  final String? iroenActiveMosaicId;

  const ProgressBackup({
    this.v = schemaVersion,
    required this.stats,
    required this.achievements,
    this.seenAchievementIds = const {},
    this.dailyLastCompleted,
    this.dailyLastFailed,
    this.dailyStreak = 0,
    this.dailyBestStreak = 0,
    this.pocketDailyLastCompleted,
    this.pocketDailyStreak = 0,
    this.pocketDailyBestStreak = 0,
    this.xpLastAwardDay,
    this.xpLastWinPalette,
    this.pocketSwipeDiscovered = false,
    this.iroen,
    this.iroenGallery = const [],
    this.iroenActiveMosaicId,
  });

  Map<String, dynamic> toJson() => {
        'v': v,
        'stats': _statsToJson(stats),
        'achievements': achievements.toJson(),
        'seenAchievementIds': seenAchievementIds.toList()..sort(),
        'dailyLastCompleted': dailyLastCompleted,
        'dailyLastFailed': dailyLastFailed,
        'dailyStreak': dailyStreak,
        'dailyBestStreak': dailyBestStreak,
        'pocketDailyLastCompleted': pocketDailyLastCompleted,
        'pocketDailyStreak': pocketDailyStreak,
        'pocketDailyBestStreak': pocketDailyBestStreak,
        'xpLastAwardDay': xpLastAwardDay,
        'xpLastWinPalette': xpLastWinPalette,
        'pocketSwipeDiscovered': pocketSwipeDiscovered,
        'iroen': iroen?.toJson(),
        'iroenGallery': [for (final mosaic in iroenGallery) mosaic.toJson()],
        'iroenActiveMosaicId': iroenActiveMosaicId,
      };

  factory ProgressBackup.fromJson(Map<String, dynamic> json) {
    final version = _asInt(json['v'], schemaVersion);
    if (version < 1 || version > schemaVersion) {
      throw const FormatException('Unsupported progress backup version');
    }
    final statsRaw = json['stats'];
    if (statsRaw is! Map) {
      throw const FormatException('Progress backup is missing stats');
    }
    final achievementsRaw = json['achievements'];
    final seenRaw = json['seenAchievementIds'];
    final iroenRaw = json['iroen'];
    final galleryRaw = json['iroenGallery'];
    return ProgressBackup(
      v: version,
      stats: _statsFromJson(_asJsonMap(statsRaw)),
      achievements: achievementsRaw is Map
          ? AchievementsProgress.fromJson(_asJsonMap(achievementsRaw))
          : const AchievementsProgress(),
      seenAchievementIds: {
        if (seenRaw is List)
          for (final id in seenRaw)
            if (id is String || id is num) id.toString(),
      },
      dailyLastCompleted: _asString(json['dailyLastCompleted']),
      dailyLastFailed: _asString(json['dailyLastFailed']),
      dailyStreak: _asInt(json['dailyStreak']),
      dailyBestStreak: _asInt(json['dailyBestStreak']),
      pocketDailyLastCompleted: _asString(json['pocketDailyLastCompleted']),
      pocketDailyStreak: _asInt(json['pocketDailyStreak']),
      pocketDailyBestStreak: _asInt(json['pocketDailyBestStreak']),
      xpLastAwardDay: _asString(json['xpLastAwardDay']),
      xpLastWinPalette: _asString(json['xpLastWinPalette']),
      pocketSwipeDiscovered: json['pocketSwipeDiscovered'] == true,
      iroen: iroenRaw is Map ? IroenState.fromJson(_asJsonMap(iroenRaw)) : null,
      iroenGallery: [
        if (galleryRaw is List)
          for (final item in galleryRaw)
            if (item is Map) IroenMosaic.fromJson(_asJsonMap(item)),
      ],
      iroenActiveMosaicId: _asString(json['iroenActiveMosaicId']),
    );
  }
}

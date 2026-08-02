import 'game_palette.dart';

/// Persistent achievement unlocks and lifetime counters.
class AchievementsProgress {
  final Set<String> unlockedIds;
  final Map<GamePalette, int> winsByPalette;
  final int cellsErased;
  final int undoCount;
  final int notesTaken;
  final List<String> winDayKeys;
  final List<String> hardWinDayKeys;
  final int consecutiveHardNoMistake;
  final int consecutiveExpertNoMistake;
  final int masterNoMistakeWins;
  final int chromaticGamesWon;
  final String? lastExpertWinPaletteKey;
  final String? lastMasterWinPaletteKey;

  const AchievementsProgress({
    this.unlockedIds = const {},
    this.winsByPalette = const {},
    this.cellsErased = 0,
    this.undoCount = 0,
    this.notesTaken = 0,
    this.winDayKeys = const [],
    this.hardWinDayKeys = const [],
    this.consecutiveHardNoMistake = 0,
    this.consecutiveExpertNoMistake = 0,
    this.masterNoMistakeWins = 0,
    this.chromaticGamesWon = 0,
    this.lastExpertWinPaletteKey,
    this.lastMasterWinPaletteKey,
  });

  bool isUnlocked(String id) => unlockedIds.contains(id);

  int winsForPalette(GamePalette palette) => winsByPalette[palette] ?? 0;

  AchievementsProgress copyWith({
    Set<String>? unlockedIds,
    Map<GamePalette, int>? winsByPalette,
    int? cellsErased,
    int? undoCount,
    int? notesTaken,
    List<String>? winDayKeys,
    List<String>? hardWinDayKeys,
    int? consecutiveHardNoMistake,
    int? consecutiveExpertNoMistake,
    int? masterNoMistakeWins,
    int? chromaticGamesWon,
    String? lastExpertWinPaletteKey,
    String? lastMasterWinPaletteKey,
    bool clearLastExpertWinPaletteKey = false,
    bool clearLastMasterWinPaletteKey = false,
  }) {
    return AchievementsProgress(
      unlockedIds: unlockedIds ?? this.unlockedIds,
      winsByPalette: winsByPalette ?? this.winsByPalette,
      cellsErased: cellsErased ?? this.cellsErased,
      undoCount: undoCount ?? this.undoCount,
      notesTaken: notesTaken ?? this.notesTaken,
      winDayKeys: winDayKeys ?? this.winDayKeys,
      hardWinDayKeys: hardWinDayKeys ?? this.hardWinDayKeys,
      consecutiveHardNoMistake:
          consecutiveHardNoMistake ?? this.consecutiveHardNoMistake,
      consecutiveExpertNoMistake:
          consecutiveExpertNoMistake ?? this.consecutiveExpertNoMistake,
      masterNoMistakeWins: masterNoMistakeWins ?? this.masterNoMistakeWins,
      chromaticGamesWon: chromaticGamesWon ?? this.chromaticGamesWon,
      lastExpertWinPaletteKey: clearLastExpertWinPaletteKey
          ? null
          : (lastExpertWinPaletteKey ?? this.lastExpertWinPaletteKey),
      lastMasterWinPaletteKey: clearLastMasterWinPaletteKey
          ? null
          : (lastMasterWinPaletteKey ?? this.lastMasterWinPaletteKey),
    );
  }

  Map<String, dynamic> toJson() => {
        'unlockedIds': unlockedIds.toList(),
        'winsByPalette': {
          for (final e in winsByPalette.entries) e.key.storageKey: e.value,
        },
        'cellsErased': cellsErased,
        'undoCount': undoCount,
        'notesTaken': notesTaken,
        'winDayKeys': winDayKeys,
        'hardWinDayKeys': hardWinDayKeys,
        'consecutiveHardNoMistake': consecutiveHardNoMistake,
        'consecutiveExpertNoMistake': consecutiveExpertNoMistake,
        'masterNoMistakeWins': masterNoMistakeWins,
        'chromaticGamesWon': chromaticGamesWon,
        'lastExpertWinPaletteKey': lastExpertWinPaletteKey,
        'lastMasterWinPaletteKey': lastMasterWinPaletteKey,
      };

  factory AchievementsProgress.fromJson(Map<String, dynamic> json) {
    final unlockedRaw = json['unlockedIds'];
    final unlocked = <String>{
      if (unlockedRaw is List)
        for (final id in unlockedRaw)
          if (id is String) id,
    };

    final winsRaw = json['winsByPalette'];
    final wins = <GamePalette, int>{};
    if (winsRaw is Map) {
      for (final entry in winsRaw.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String || value is! int) continue;
        wins[GamePalette.fromStorageKey(key)] = value;
      }
    }

    List<String> stringList(dynamic raw) {
      if (raw is! List) return const [];
      return [
        for (final item in raw)
          if (item is String) item,
      ];
    }

    return AchievementsProgress(
      unlockedIds: unlocked,
      winsByPalette: wins,
      cellsErased: (json['cellsErased'] as int?) ?? 0,
      undoCount: (json['undoCount'] as int?) ?? 0,
      notesTaken: (json['notesTaken'] as int?) ?? 0,
      winDayKeys: stringList(json['winDayKeys']),
      hardWinDayKeys: stringList(json['hardWinDayKeys']),
      consecutiveHardNoMistake:
          (json['consecutiveHardNoMistake'] as int?) ?? 0,
      consecutiveExpertNoMistake:
          (json['consecutiveExpertNoMistake'] as int?) ?? 0,
      masterNoMistakeWins: (json['masterNoMistakeWins'] as int?) ?? 0,
      chromaticGamesWon: (json['chromaticGamesWon'] as int?) ?? 0,
      lastExpertWinPaletteKey: json['lastExpertWinPaletteKey'] as String?,
      lastMasterWinPaletteKey: json['lastMasterWinPaletteKey'] as String?,
    );
  }
}

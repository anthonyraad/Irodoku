/// Public Daily leaderboard row. [uid] is never shown in the UI.
class DailyLeaderboardEntry {
  final String uid;
  final String name;
  final int ms;
  final int atMs;

  const DailyLeaderboardEntry({
    required this.uid,
    required this.name,
    required this.ms,
    required this.atMs,
  });

  String get formattedTime => formatLeaderboardTime(ms);

  Map<String, dynamic> toJson() => {
        'name': name,
        'ms': ms,
        'at': atMs,
      };

  static DailyLeaderboardEntry? fromSnapshot(String uid, Object? value) {
    if (value is! Map) return null;
    final data = Map<Object?, Object?>.from(value);
    final ms = _asInt(data['ms']);
    if (ms == null || ms <= 0) return null;
    final name = DisplayName.trySanitize(data['name']?.toString() ?? '') ??
        DisplayName.fallback;
    return DailyLeaderboardEntry(
      uid: uid,
      name: name,
      ms: ms,
      atMs: _asInt(data['at']) ?? 0,
    );
  }
}

class DailyLeaderboardBoard {
  final List<DailyLeaderboardEntry> top;
  final DailyLeaderboardEntry? you;
  /// 1-based rank among every posted time that day, if known.
  final int? youRank;

  const DailyLeaderboardBoard({
    required this.top,
    this.you,
    this.youRank,
  });

  static DailyLeaderboardBoard fromEntries({
    required List<DailyLeaderboardEntry> entries,
    required String? youUid,
    int topN = 50,
  }) {
    final sorted = [...entries]..sort((a, b) {
        final byTime = a.ms.compareTo(b.ms);
        if (byTime != 0) return byTime;
        return a.atMs.compareTo(b.atMs);
      });
    DailyLeaderboardEntry? you;
    int? youRank;
    if (youUid != null && youUid.isNotEmpty) {
      for (var i = 0; i < sorted.length; i++) {
        if (sorted[i].uid == youUid) {
          you = sorted[i];
          youRank = i + 1;
          break;
        }
      }
    }
    return DailyLeaderboardBoard(
      top: sorted.take(topN).toList(),
      you: you,
      youRank: youRank,
    );
  }
}

abstract final class DisplayName {
  static const int minLength = 2;
  static const int maxLength = 10;
  static const String fallback = 'Player';

  static final _allowed = RegExp(r'^[A-Za-z0-9 ._\-]+$');

  /// Trim, collapse spaces. Null when the result is not a legal public name.
  static String? trySanitize(String raw) {
    final trimmed = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.length < minLength || trimmed.length > maxLength) return null;
    if (!_allowed.hasMatch(trimmed)) return null;
    return trimmed;
  }

  static String orFallback(String raw) =>
      trySanitize(raw) ?? fallback;
}

String formatLeaderboardTime(int ms) {
  final totalSeconds = (ms / 1000).floor().clamp(0, 24 * 60 * 60);
  final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/daily_irodoku.dart';
import '../models/daily_leaderboard.dart';
import 'graffiti_firebase_service.dart';

/// Public Daily times on the shared Irodoku RTDB.
class DailyLeaderboardService {
  DailyLeaderboardService._();

  static const rootPath = 'irodoku_daily';
  static const classicBranch = 'classic';
  static const pocketBranch = 'pocket';
  static const topN = 50;
  static const minMs = 5000;
  static const maxMs = 24 * 60 * 60 * 1000;

  static DatabaseReference _dayRef(String dayKey, {required bool pocket}) =>
      GraffitiFirebaseService.database
          .ref('$rootPath/$dayKey/${pocket ? pocketBranch : classicBranch}');

  static Future<bool> submit({
    required String dayKey,
    required bool pocket,
    required String name,
    required int ms,
  }) async {
    if (ms < minMs || ms > maxMs) return false;
    final ready = await GraffitiFirebaseService.ensureInitialized();
    if (!ready) return false;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final sanitized = DisplayName.orFallback(name);
    final ref = _dayRef(dayKey, pocket: pocket).child(uid);
    try {
      final result = await ref.runTransaction((Object? current) {
        if (current is Map) {
          final existing = DailyLeaderboardEntry.fromSnapshot(uid, current);
          if (existing != null && existing.ms <= ms) {
            return Transaction.abort();
          }
        }
        return Transaction.success({
          'name': sanitized,
          'ms': ms,
          'at': DateTime.now().millisecondsSinceEpoch,
        });
      });
      return result.committed || result.snapshot.exists;
    } catch (_) {
      return false;
    }
  }

  static Future<void> updateTodayName(String name) async {
    final sanitized = DisplayName.trySanitize(name);
    if (sanitized == null) return;
    final ready = await GraffitiFirebaseService.ensureInitialized();
    if (!ready) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final dayKey = DailyIrodoku.dayKeyFor(DateTime.now());
    for (final pocket in [false, true]) {
      final ref = _dayRef(dayKey, pocket: pocket).child(uid);
      try {
        final snap = await ref.get();
        if (!snap.exists) continue;
        await ref.update({'name': sanitized});
      } catch (_) {}
    }
  }

  static Future<DailyLeaderboardBoard> fetch({
    required String dayKey,
    required bool pocket,
  }) async {
    final ready = await GraffitiFirebaseService.ensureInitialized();
    if (!ready) {
      return const DailyLeaderboardBoard(top: []);
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    try {
      final snap = await _dayRef(dayKey, pocket: pocket).get();
      final entries = <DailyLeaderboardEntry>[];
      final value = snap.value;
      if (value is Map) {
        for (final entry in value.entries) {
          final parsed = DailyLeaderboardEntry.fromSnapshot(
            entry.key.toString(),
            entry.value,
          );
          if (parsed != null) entries.add(parsed);
        }
      }
      return DailyLeaderboardBoard.fromEntries(
        entries: entries,
        youUid: uid,
        topN: topN,
      );
    } catch (_) {
      return const DailyLeaderboardBoard(top: []);
    }
  }
}

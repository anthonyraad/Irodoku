import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

import '../firebase_options.dart';

/// RTDB helpers for Graffiti multiplayer (rooms share the word-multiplayer RTDB).
class GraffitiFirebaseService {
  GraffitiFirebaseService._();

  /// Same top-level path as Wordle Battle; rooms are tagged with [appTag].
  static const roomsPath = 'rooms';
  static const appTag = 'irodoku_graffiti';
  static const maxMistakes = 3;
  static const maxQuickMatchScan = 80;

  static bool _initialized = false;
  static bool get isReady => _initialized;

  static FirebaseDatabase get database {
    if (kIsWeb) {
      final url = DefaultFirebaseOptions.web.databaseURL;
      if (url != null && url.isNotEmpty) {
        return FirebaseDatabase.instanceFor(
          app: Firebase.app(),
          databaseURL: url,
        );
      }
    }
    return FirebaseDatabase.instance;
  }

  static DatabaseReference roomRef(String code) =>
      database.ref('$roomsPath/$code');

  static Future<bool> ensureInitialized() async {
    if (_initialized) return true;
    try {
      if (Firebase.apps.isEmpty) {
        if (kIsWeb) {
          await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
        } else if (defaultTargetPlatform == TargetPlatform.android) {
          try {
            await Firebase.initializeApp();
          } catch (_) {
            await Firebase.initializeApp(
              options: DefaultFirebaseOptions.android,
            );
          }
        } else {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
        }
      }
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
      _initialized = true;
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('Graffiti Firebase init failed: $e');
      return false;
    }
  }

  static String? get playerId => FirebaseAuth.instance.currentUser?.uid;

  static String generateRoomCode([Random? random]) {
    final r = random ?? Random();
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(5, (_) => chars[r.nextInt(chars.length)]).join();
  }

  static Future<String> uniqueRoomCode() async {
    for (var i = 0; i < 12; i++) {
      final code = generateRoomCode();
      final snap = await roomRef(code).get();
      if (!snap.exists) return code;
    }
    return generateRoomCode();
  }

  static Future<void> createRoom({
    required String roomCode,
    required String hostId,
    required bool isQuickMatch,
  }) async {
    final ref = roomRef(roomCode);
    await ref.set({
      'app': appTag,
      'host': hostId,
      'players': {hostId: true},
      'gameState': 'waiting',
      'isQuickMatch': isQuickMatch,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'winner': null,
      'solo': false,
    });
    await ref.onDisconnect().remove();
  }

  static Future<TransactionResult> joinRoomTransaction({
    required String roomCode,
    required String playerId,
  }) async {
    final ref = roomRef(roomCode);
    TransactionResult? result;
    const backoffMs = [0, 300, 600];
    for (var attempt = 0; attempt < backoffMs.length; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(milliseconds: backoffMs[attempt]));
      }
      result = await ref.runTransaction((Object? data) {
        if (data == null) return Transaction.abort();
        final room = Map<dynamic, dynamic>.from(data as Map);
        final players =
            Map<dynamic, dynamic>.from(room['players'] as Map? ?? {});
        if (players.length >= 2 || room['gameState'] != 'waiting') {
          return Transaction.abort();
        }
        players[playerId] = true;
        room['players'] = players;
        return Transaction.success(room);
      });
      if (result.committed) break;
    }
    return result!;
  }

  /// Host writes puzzle + empty board and starts play when 2 players are present.
  static Future<void> hostStartGame({
    required String roomCode,
    required String hostId,
    required String opponentId,
    required List<int> puzzle,
    required List<int> solution,
  }) async {
    final board = <String, Map<String, dynamic>>{};
    for (var i = 0; i < 81; i++) {
      final v = puzzle[i];
      if (v == 0) continue;
      final r = i ~/ 9;
      final c = i % 9;
      board['${r}_$c'] = {
        'v': v,
        'locked': true,
        'by': 'given',
        'mistake': false,
      };
    }

    await roomRef(roomCode).update({
      'gameState': 'playing',
      'puzzle': puzzle,
      'solution': solution,
      'board': board,
      'stats': {
        hostId: {'correct': 0, 'mistakes': 0},
        opponentId: {'correct': 0, 'mistakes': 0},
      },
      'winner': null,
      'solo': false,
    });
  }

  static Future<TransactionResult> placeColorTransaction({
    required String roomCode,
    required String playerId,
    required int row,
    required int col,
    required int value,
  }) async {
    final key = '${row}_$col';
    return roomRef(roomCode).runTransaction((Object? raw) {
      if (raw == null) return Transaction.abort();
      final data = Map<dynamic, dynamic>.from(raw as Map);
      if (data['gameState'] != 'playing') return Transaction.abort();

      final stats = Map<dynamic, dynamic>.from(data['stats'] as Map? ?? {});
      final myStats = Map<dynamic, dynamic>.from(stats[playerId] as Map? ?? {});
      final myMistakes = (myStats['mistakes'] as num?)?.toInt() ?? 0;
      if (myMistakes >= maxMistakes) return Transaction.abort();

      final board = Map<dynamic, dynamic>.from(data['board'] as Map? ?? {});
      final existing = board[key];
      if (existing is Map) {
        final cell = Map<dynamic, dynamic>.from(existing);
        if (cell['locked'] == true) return Transaction.abort();
      }

      final solution = List<dynamic>.from(data['solution'] as List? ?? []);
      if (solution.length != 81) return Transaction.abort();
      final correct = (solution[row * 9 + col] as num).toInt();

      if (value == correct) {
        board[key] = {
          'v': value,
          'locked': true,
          'by': playerId,
          'mistake': false,
        };
        myStats['correct'] = ((myStats['correct'] as num?)?.toInt() ?? 0) + 1;
      } else {
        board[key] = {
          'v': value,
          'locked': false,
          'by': playerId,
          'mistake': true,
        };
        myStats['mistakes'] = myMistakes + 1;
      }
      stats[playerId] = myStats;
      data['board'] = board;
      data['stats'] = stats;

      _applyEndConditions(data, stats);
      return Transaction.success(data);
    });
  }

  /// Clears an unlocked cell the player previously filled (undo mistake / overwrite).
  static Future<TransactionResult> clearOwnFillTransaction({
    required String roomCode,
    required String playerId,
    required int row,
    required int col,
    required int expectedValue,
    required bool wasMistake,
  }) async {
    final key = '${row}_$col';
    return roomRef(roomCode).runTransaction((Object? raw) {
      if (raw == null) return Transaction.abort();
      final data = Map<dynamic, dynamic>.from(raw as Map);
      if (data['gameState'] != 'playing') return Transaction.abort();

      final board = Map<dynamic, dynamic>.from(data['board'] as Map? ?? {});
      final existing = board[key];
      if (existing is! Map) return Transaction.abort();
      final cell = Map<dynamic, dynamic>.from(existing);
      if (cell['locked'] == true) return Transaction.abort();
      if (cell['by']?.toString() != playerId) return Transaction.abort();
      if ((cell['v'] as num?)?.toInt() != expectedValue) {
        return Transaction.abort();
      }

      board.remove(key);
      data['board'] = board;

      if (wasMistake) {
        final stats = Map<dynamic, dynamic>.from(data['stats'] as Map? ?? {});
        final myStats =
            Map<dynamic, dynamic>.from(stats[playerId] as Map? ?? {});
        final m = (myStats['mistakes'] as num?)?.toInt() ?? 0;
        myStats['mistakes'] = m > 0 ? m - 1 : 0;
        stats[playerId] = myStats;
        data['stats'] = stats;
      }

      return Transaction.success(data);
    });
  }

  static void _applyEndConditions(
    Map<dynamic, dynamic> data,
    Map<dynamic, dynamic> stats,
  ) {
    final playerIds = stats.keys.map((k) => k.toString()).toList();
    if (playerIds.length < 2) return;

    final a = playerIds[0];
    final b = playerIds[1];
    final aStats = Map<dynamic, dynamic>.from(stats[a] as Map? ?? {});
    final bStats = Map<dynamic, dynamic>.from(stats[b] as Map? ?? {});
    final aMistakes = (aStats['mistakes'] as num?)?.toInt() ?? 0;
    final bMistakes = (bStats['mistakes'] as num?)?.toInt() ?? 0;

    if (aMistakes >= maxMistakes && bMistakes >= maxMistakes) {
      data['gameState'] = 'finished';
      data['winner'] = 'defeat';
      return;
    }

    final board = Map<dynamic, dynamic>.from(data['board'] as Map? ?? {});
    final puzzle = List<dynamic>.from(data['puzzle'] as List? ?? []);
    if (puzzle.length != 81) return;

    var emptyLeft = 0;
    for (var i = 0; i < 81; i++) {
      final given = (puzzle[i] as num?)?.toInt() ?? 0;
      if (given != 0) continue;
      final r = i ~/ 9;
      final c = i % 9;
      final cell = board['${r}_$c'];
      if (cell is! Map || cell['locked'] != true) {
        emptyLeft++;
      }
    }
    if (emptyLeft > 0) return;

    final aCorrect = (aStats['correct'] as num?)?.toInt() ?? 0;
    final bCorrect = (bStats['correct'] as num?)?.toInt() ?? 0;
    data['gameState'] = 'finished';
    if (aCorrect > bCorrect) {
      data['winner'] = a;
    } else if (bCorrect > aCorrect) {
      data['winner'] = b;
    } else if (aMistakes < bMistakes) {
      data['winner'] = a;
    } else if (bMistakes < aMistakes) {
      data['winner'] = b;
    } else {
      data['winner'] = 'draw';
    }
  }

  static Future<String?> findOpenQuickMatchRoom(String excludePlayerId) async {
    // Prefer indexed query; fall back to a shallow scan if the index is missing.
    DataSnapshot snap;
    try {
      snap = await database
          .ref(roomsPath)
          .orderByChild('app')
          .equalTo(appTag)
          .limitToLast(maxQuickMatchScan)
          .get();
    } catch (_) {
      snap = await database.ref(roomsPath).limitToLast(maxQuickMatchScan).get();
    }
    if (!snap.exists || snap.value is! Map) return null;
    final rooms = Map<dynamic, dynamic>.from(snap.value as Map);
    final entries = rooms.entries.toList()
      ..sort((a, b) {
        final aMap = a.value is Map ? Map<dynamic, dynamic>.from(a.value) : {};
        final bMap = b.value is Map ? Map<dynamic, dynamic>.from(b.value) : {};
        final aAt = (aMap['createdAt'] as num?)?.toInt() ?? 0;
        final bAt = (bMap['createdAt'] as num?)?.toInt() ?? 0;
        return bAt.compareTo(aAt);
      });

    for (final e in entries) {
      if (e.value is! Map) continue;
      final room = Map<dynamic, dynamic>.from(e.value as Map);
      if (room['app'] != appTag) continue;
      if (room['gameState'] != 'waiting') continue;
      if (room['isQuickMatch'] != true) continue;
      final players =
          Map<dynamic, dynamic>.from(room['players'] as Map? ?? {});
      if (players.length != 1) continue;
      if (players.containsKey(excludePlayerId)) continue;
      return e.key.toString();
    }
    return null;
  }

  static Future<void> leaveRoom({
    required String roomCode,
    required String playerId,
    required bool isHost,
  }) async {
    final ref = roomRef(roomCode);
    if (isHost) {
      await ref.remove();
      return;
    }
    await ref.runTransaction((Object? raw) {
      if (raw == null) return Transaction.abort();
      final data = Map<dynamic, dynamic>.from(raw as Map);
      final players =
          Map<dynamic, dynamic>.from(data['players'] as Map? ?? {});
      players.remove(playerId);
      data['players'] = players;
      if (data['gameState'] == 'playing') {
        data['solo'] = true;
      }
      return Transaction.success(data);
    });
  }
}

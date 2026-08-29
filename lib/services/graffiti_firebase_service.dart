import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform, debugPrint;

import '../firebase_options.dart';

/// RTDB helpers for Graffiti multiplayer (rooms share the word-multiplayer RTDB).
class GraffitiFirebaseService {
  GraffitiFirebaseService._();

  /// Same top-level path as Wordle Battle; rooms are tagged with [appTag].
  static const roomsPath = 'rooms';
  static const appTag = 'irodoku_graffiti';
  static const pocketAppTag = 'irodoku_graffiti_pocket';
  static const maxMistakes = 3;
  static const pocketMaxMistakes = 2;
  static const maxQuickMatchScan = 120;

  static String appTagFor({required bool pocket}) =>
      pocket ? pocketAppTag : appTag;

  static int gridSizeOf(List<dynamic> values) {
    if (values.length == 36) return 6;
    return 9;
  }

  static int maxMistakesForGrid(int n) =>
      n == 6 ? pocketMaxMistakes : maxMistakes;

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
    bool pocket = false,
  }) async {
    final ref = roomRef(roomCode);
    await ref.set({
      'app': appTagFor(pocket: pocket),
      'host': hostId,
      'players': {hostId: true},
      'gameState': 'waiting',
      'isQuickMatch': isQuickMatch,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'winner': null,
      'solo': false,
      'pocket': pocket,
    });
    // Host disconnect while still alone deletes the lobby room.
    // Cancelled in [cancelHostDisconnect] once a second player seats.
    await ref.onDisconnect().remove();
  }

  /// Host-only: stop wiping the room if this client disconnects mid-match.
  static Future<void> cancelHostDisconnect(String roomCode) async {
    try {
      await roomRef(roomCode).onDisconnect().cancel();
    } catch (_) {}
  }

  /// Seats [playerId] in an open waiting room. Returns false if the seat
  /// could not be taken (full, missing, wrong app, or race).
  ///
  /// Uses a direct write to `players/$id` plus a verify read instead of a
  /// whole-room transaction — FlutterFire/web often aborts those with
  /// `committed: false` even when the room is joinable.
  static Future<bool> joinRoomAsPlayer({
    required String roomCode,
    required String playerId,
    bool pocket = false,
  }) async {
    final ref = roomRef(roomCode);
    final expectedApp = appTagFor(pocket: pocket);

    final before = await ref.get();
    if (!before.exists || before.value is! Map) {
      debugPrint('Graffiti join: room $roomCode missing');
      return false;
    }
    final room = Map<dynamic, dynamic>.from(before.value as Map);
    if (room['app']?.toString() != expectedApp) {
      debugPrint('Graffiti join: $roomCode wrong app (${room['app']})');
      return false;
    }
    if (room['gameState']?.toString() != 'waiting') {
      debugPrint('Graffiti join: $roomCode not waiting (${room['gameState']})');
      return false;
    }

    final playersRef = ref.child('players');
    final existing = Map<dynamic, dynamic>.from(room['players'] as Map? ?? {});
    if (existing.containsKey(playerId)) {
      return true; // already seated
    }
    if (existing.length >= 2) {
      debugPrint('Graffiti join: $roomCode already full');
      return false;
    }

    try {
      await playersRef.child(playerId).set(true);
    } catch (e) {
      debugPrint('Graffiti join write failed for $roomCode: $e');
      return false;
    }

    final afterSnap = await playersRef.get();
    if (!afterSnap.exists || afterSnap.value is! Map) {
      debugPrint('Graffiti join: players missing after write ($roomCode)');
      return false;
    }
    final seated = Map<dynamic, dynamic>.from(afterSnap.value as Map);
    if (!seated.containsKey(playerId)) {
      debugPrint('Graffiti join: seat missing after write ($roomCode)');
      return false;
    }
    if (seated.length > 2) {
      // Lost a rare 3-way race — give up the seat.
      try {
        await playersRef.child(playerId).remove();
      } catch (_) {}
      debugPrint('Graffiti join: overfilled $roomCode, retracted seat');
      return false;
    }

    final stateSnap = await ref.child('gameState').get();
    if (stateSnap.value?.toString() != 'waiting') {
      // Host may have already flipped to playing after seeing 2 players.
      // Still a successful seat.
      debugPrint('Graffiti join: $roomCode state now ${stateSnap.value}');
    }
    return true;
  }

  /// Host writes puzzle + empty board and starts play when 2 players are present.
  static Future<void> hostStartGame({
    required String roomCode,
    required String hostId,
    required String opponentId,
    required List<int> puzzle,
    required List<int> solution,
    required String palette,
  }) async {
    final n = gridSizeOf(puzzle);
    final board = <String, Map<String, dynamic>>{};
    for (var i = 0; i < n * n; i++) {
      final v = puzzle[i];
      if (v == 0) continue;
      final r = i ~/ n;
      final c = i % n;
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
      'palette': palette,
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

      final solution = List<dynamic>.from(data['solution'] as List? ?? []);
      final n = gridSizeOf(solution);
      if (solution.length != n * n) return Transaction.abort();
      if (myMistakes >= maxMistakesForGrid(n)) return Transaction.abort();

      final board = Map<dynamic, dynamic>.from(data['board'] as Map? ?? {});
      final existing = board[key];
      if (existing is Map) {
        final cell = Map<dynamic, dynamic>.from(existing);
        if (cell['locked'] == true) return Transaction.abort();
      }

      final correct = (solution[row * n + col] as num).toInt();

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

  /// Clears an unlocked cell the player previously filled (undo / erase).
  ///
  /// Mistake counts are permanent — clearing a wrong fill does not reduce
  /// [stats.mistakes].
  static Future<TransactionResult> clearOwnFillTransaction({
    required String roomCode,
    required String playerId,
    required int row,
    required int col,
    required int expectedValue,
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

    final puzzle = List<dynamic>.from(data['puzzle'] as List? ?? []);
    final n = gridSizeOf(puzzle);
    if (puzzle.length != n * n) return;
    final cap = maxMistakesForGrid(n);

    if (aMistakes >= cap && bMistakes >= cap) {
      data['gameState'] = 'finished';
      data['winner'] = 'defeat';
      return;
    }

    final board = Map<dynamic, dynamic>.from(data['board'] as Map? ?? {});

    var emptyLeft = 0;
    for (var i = 0; i < n * n; i++) {
      final given = (puzzle[i] as num?)?.toInt() ?? 0;
      if (given != 0) continue;
      final r = i ~/ n;
      final c = i % n;
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

  static Future<String?> findOpenQuickMatchRoom(
    String excludePlayerId, {
    bool pocket = false,
  }) async {
    final tag = appTagFor(pocket: pocket);
    // Scan /rooms only (RTDB rules allow this path; no separate lobby index).
    DataSnapshot? snap;
    try {
      snap = await database
          .ref(roomsPath)
          .orderByChild('app')
          .equalTo(tag)
          .limitToLast(maxQuickMatchScan)
          .get();
    } catch (e) {
      debugPrint('Graffiti app-index scan failed, using shallow scan: $e');
      try {
        snap =
            await database.ref(roomsPath).limitToLast(maxQuickMatchScan).get();
      } catch (e2) {
        debugPrint('Graffiti rooms scan failed: $e2');
        return null;
      }
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
      final code = e.key.toString();
      // Always re-read the room so we don't join a stale list snapshot.
      if (await _isJoinableQuickRoom(code, excludePlayerId, pocket: pocket)) {
        return code;
      }
    }
    return null;
  }

  static Future<bool> _isJoinableQuickRoom(
    String code,
    String excludePlayerId, {
    bool pocket = false,
  }) async {
    final snap = await roomRef(code).get();
    if (!snap.exists || snap.value is! Map) return false;
    final room = Map<dynamic, dynamic>.from(snap.value as Map);
    if (room['app'] != appTagFor(pocket: pocket)) return false;
    if (room['gameState']?.toString() != 'waiting') return false;
    if (room['isQuickMatch'] != true) return false;
    final players = Map<dynamic, dynamic>.from(room['players'] as Map? ?? {});
    if (players.length != 1) return false;
    if (players.containsKey(excludePlayerId)) return false;
    return true;
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

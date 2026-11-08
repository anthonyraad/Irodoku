import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../models/hyperchroma.dart';
import 'graffiti_firebase_service.dart';

/// One shared note add or remove. Both players read the same cell.
class HyperchromaNoteChange {
  final int row;
  final int col;
  final int value;
  final bool add;

  const HyperchromaNoteChange({
    required this.row,
    required this.col,
    required this.value,
    required this.add,
  });
}

/// Shared Hyperchroma room on the same RTDB path as Graffiti, different app tag.
class HyperchromaCoopService {
  HyperchromaCoopService._();

  static const appTag = 'irodoku_hyperchroma';

  static int _clockOffset = 0;

  static int now() => DateTime.now().millisecondsSinceEpoch + _clockOffset;

  static Future<bool> ensureReady() async {
    final ok = await GraffitiFirebaseService.ensureInitialized();
    if (!ok) return false;
    try {
      final snap = await GraffitiFirebaseService.database
          .ref('.info/serverTimeOffset')
          .get();
      _clockOffset = (snap.value as num?)?.toInt() ?? 0;
    } catch (_) {}
    return true;
  }

  static String? get playerId => GraffitiFirebaseService.playerId;

  static DatabaseReference roomRef(String code) =>
      GraffitiFirebaseService.roomRef(code);

  static Future<String> createRoom({
    required String hostId,
    required bool quickMatch,
    String? displayName,
  }) async {
    final code = await GraffitiFirebaseService.uniqueRoomCode();
    final payload = <String, dynamic>{
      'app': appTag,
      'host': hostId,
      'players': {hostId: true},
      'gameState': 'waiting',
      'isQuickMatch': quickMatch,
      'createdAt': now(),
      'partnerLeft': false,
    };
    final name = GraffitiFirebaseService.sanitizedDisplayName(displayName);
    if (name != null) payload['names'] = {hostId: name};
    final ref = roomRef(code);
    await ref.set(payload);
    await ref.onDisconnect().remove();
    return code;
  }

  static Future<String?> findOpenQuickRoom(String excludePlayerId) async {
    DataSnapshot? snap;
    try {
      snap = await GraffitiFirebaseService.database
          .ref(GraffitiFirebaseService.roomsPath)
          .orderByChild('app')
          .equalTo(appTag)
          .limitToLast(GraffitiFirebaseService.maxQuickMatchScan)
          .get();
    } catch (_) {
      try {
        snap = await GraffitiFirebaseService.database
            .ref(GraffitiFirebaseService.roomsPath)
            .limitToLast(GraffitiFirebaseService.maxQuickMatchScan)
            .get();
      } catch (_) {
        return null;
      }
    }
    if (!snap.exists || snap.value is! Map) return null;
    final rooms = Map<dynamic, dynamic>.from(snap.value as Map);
    for (final entry in rooms.entries) {
      final code = entry.key.toString();
      if (await _joinable(code, excludePlayerId)) return code;
    }
    return null;
  }

  static Future<bool> _joinable(String code, String excludePlayerId) async {
    final snap = await roomRef(code).get();
    if (!snap.exists || snap.value is! Map) return false;
    final room = Map<dynamic, dynamic>.from(snap.value as Map);
    if (room['app']?.toString() != appTag) return false;
    if (room['gameState']?.toString() != 'waiting') return false;
    if (room['isQuickMatch'] != true) return false;
    final players = Map<dynamic, dynamic>.from(room['players'] as Map? ?? {});
    if (players.length != 1) return false;
    if (players.containsKey(excludePlayerId)) return false;
    return true;
  }

  static Future<bool> joinRoom({
    required String roomCode,
    required String playerId,
    String? displayName,
  }) async {
    final ref = roomRef(roomCode);
    final before = await ref.get();
    if (!before.exists || before.value is! Map) return false;
    final room = Map<dynamic, dynamic>.from(before.value as Map);
    if (room['app']?.toString() != appTag) return false;
    if (room['gameState']?.toString() != 'waiting') return false;
    final existing = Map<dynamic, dynamic>.from(room['players'] as Map? ?? {});
    if (existing.containsKey(playerId)) return true;
    if (existing.length >= 2) return false;
    try {
      await ref.child('players').child(playerId).set(true);
    } catch (_) {
      return false;
    }
    final after = await ref.child('players').get();
    if (!after.exists || after.value is! Map) return false;
    final seated = Map<dynamic, dynamic>.from(after.value as Map);
    if (!seated.containsKey(playerId)) return false;
    if (seated.length > 2) {
      try {
        await ref.child('players').child(playerId).remove();
      } catch (_) {}
      return false;
    }
    await GraffitiFirebaseService.writePlayerName(
      roomCode: roomCode,
      playerId: playerId,
      displayName: displayName,
    );
    return true;
  }

  /// Waiting host disconnect deletes the lobby. Once seated, leave a flag.
  static Future<void> armMatchDisconnect({
    required String roomCode,
    required String playerId,
  }) async {
    final ref = roomRef(roomCode);
    try {
      await ref.onDisconnect().cancel();
    } catch (_) {}
    await ref.onDisconnect().update({
      'players/$playerId': null,
      'partnerLeft': true,
    });
  }

  static Future<void> leaveWaiting({
    required String roomCode,
    required String playerId,
    required bool isHost,
  }) async {
    final ref = roomRef(roomCode);
    try {
      await ref.onDisconnect().cancel();
    } catch (_) {}
    if (isHost) {
      await ref.remove();
      return;
    }
    await ref.child('players').child(playerId).remove();
  }

  static Future<void> publishBoard({
    required String roomCode,
    required List<int> puzzle,
    required List<int> solution,
    required int boardId,
    required int boardsCleared,
    required int endsAt,
    required int sketches,
    required int steadfast,
    required bool trace,
    required bool telepathy,
    required String palette,
    required int cellsFilled,
    required int emptyOnBoard,
    bool partnerLeft = false,
  }) async {
    await roomRef(roomCode).update({
      'gameState': 'playing',
      'dealing': false,
      'boardId': boardId,
      'boardsCleared': boardsCleared,
      'puzzle': puzzle,
      'solution': solution,
      'cells': <String, dynamic>{},
      'endsAt': endsAt,
      'sketches': sketches,
      'steadfast': steadfast,
      'trace': trace,
      'telepathy': telepathy,
      'palette': palette,
      'cellsFilled': cellsFilled,
      'filledOnBoard': 0,
      'emptyOnBoard': emptyOnBoard,
      'partnerLeft': partnerLeft,
    });
  }

  static Future<bool> placeColor({
    required String roomCode,
    required String playerId,
    required int row,
    required int col,
    required int value,
    required String? hopPalette,
  }) {
    return _transact(
      roomCode,
      (data, at) => applyPlacement(
        data,
        at,
        row: row,
        col: col,
        value: value,
        hopPalette: hopPalette,
      ),
    );
  }

  /// One shared fill. A repeated wrong color erases, and the color drops
  /// from notes in the rest of its row, column, and box.
  @visibleForTesting
  static bool applyPlacement(
    Map<dynamic, dynamic> data,
    int at, {
    required int row,
    required int col,
    required int value,
    required String? hopPalette,
  }) {
    if (!_editable(data, row, col)) return false;
    final puzzle = _ints(data['puzzle']);
    final solution = _ints(data['solution']);
    final n = 9;
    final correct = solution[row * n + col];
    final cells = _cells(data);
    final key = '${row}_$col';
    final current = _cell(cells, key);
    if (_int(current['v']) == value) {
      cells.remove(key);
      data['cells'] = cells;
      return true;
    }
    final gain = HyperchromaRules.coopGainSeconds * 1000;
    final penalty = HyperchromaRules.mistakePenaltySeconds * 1000;
    var endsAt = (data['endsAt'] as num?)?.toInt() ?? at;
    if (value == correct) {
      final boxWasDone = _boxDone(puzzle, solution, cells, row, col);
      cells[key] = {
        'v': value,
        'locked': true,
        'notes': <String, bool>{},
      };
      data['cellsFilled'] = _int(data['cellsFilled']) + 1;
      data['filledOnBoard'] = _int(data['filledOnBoard']) + 1;
      if (!boxWasDone && _boxDone(puzzle, solution, cells, row, col)) {
        data['sketches'] = _int(data['sketches']) + 1;
      }
      endsAt += gain;
      var steadfast = _int(data['steadfast']);
      if (steadfast > 0) {
        steadfast -= 1;
      } else if (hopPalette != null) {
        data['palette'] = hopPalette;
      }
      if (_unitCompleted(puzzle, solution, cells, row, col)) steadfast = 0;
      data['steadfast'] = steadfast;
      if (_boardComplete(puzzle, solution, cells)) data['dealing'] = true;
    } else {
      cells[key] = {
        'v': value,
        'locked': false,
        'notes': <String, bool>{},
      };
      endsAt -= penalty;
    }
    _stripPeerNotes(cells, puzzle, row, col, value);
    data['cells'] = cells;
    data['endsAt'] = endsAt;
    if (endsAt <= at) data['gameState'] = 'finished';
    return true;
  }

  static Future<bool> toggleNote({
    required String roomCode,
    required int row,
    required int col,
    required int value,
    required bool add,
  }) {
    return changeNotes(
      roomCode: roomCode,
      changes: [
        HyperchromaNoteChange(row: row, col: col, value: value, add: add),
      ],
    );
  }

  /// Add or remove notes for either player. One transaction, so a bulk
  /// pencil lands together.
  static Future<bool> changeNotes({
    required String roomCode,
    required List<HyperchromaNoteChange> changes,
  }) {
    return _transact(roomCode, (data, at) {
      if (changes.isEmpty) return false;
      final cells = _cells(data);
      var changed = false;
      for (final change in changes) {
        if (!_editable(data, change.row, change.col)) continue;
        final key = '${change.row}_${change.col}';
        final current = _cell(cells, key);
        final notes = _noteList(current['notes']);
        if (change.add) {
          final had = notes.contains(change.value);
          if (!had) notes.add(change.value);
          if (had && _int(current['v']) == 0) continue;
          current['v'] = 0;
          current['locked'] = false;
        } else {
          if (!notes.contains(change.value)) continue;
          notes.remove(change.value);
          current['v'] = 0;
          current['locked'] = false;
        }
        notes.sort();
        current['notes'] = _noteStore(notes);
        if (_int(current['v']) == 0 && notes.isEmpty) {
          cells.remove(key);
        } else {
          cells[key] = current;
        }
        changed = true;
      }
      if (!changed) return false;
      data['cells'] = cells;
      if (((data['endsAt'] as num?)?.toInt() ?? at) <= at) {
        data['gameState'] = 'finished';
      }
      return true;
    });
  }

  /// Drop every note on these cells. A committed color stays.
  static Future<bool> clearNotes({
    required String roomCode,
    required List<({int row, int col})> cells,
  }) {
    return _transact(roomCode, (data, at) {
      final stored = _cells(data);
      var changed = false;
      for (final cell in cells) {
        if (!_editable(data, cell.row, cell.col)) continue;
        final key = '${cell.row}_${cell.col}';
        final current = _cell(stored, key);
        if (_noteList(current['notes']).isEmpty) continue;
        current['notes'] = <String, bool>{};
        if (_int(current['v']) == 0) {
          stored.remove(key);
        } else {
          stored[key] = current;
        }
        changed = true;
      }
      if (!changed) return false;
      data['cells'] = stored;
      return true;
    });
  }

  static Future<bool> clearCell({
    required String roomCode,
    required int row,
    required int col,
  }) {
    return _transact(roomCode, (data, at) {
      if (!_editable(data, row, col)) return false;
      final cells = _cells(data);
      cells.remove('${row}_$col');
      data['cells'] = cells;
      return true;
    });
  }

  static Future<bool> sketchBox({
    required String roomCode,
    required int box,
    required int value,
  }) {
    return _transact(roomCode, (data, at) {
      if (_int(data['sketches']) <= 0) return false;
      final added = _pencilBox(data, box, fillAllColors: false, only: value);
      if (added == 0) return false;
      data['sketches'] = _int(data['sketches']) - 1;
      return true;
    });
  }

  static Future<bool> traceBox({
    required String roomCode,
    required int row,
    required int col,
  }) {
    return _transact(roomCode, (data, at) {
      if (data['trace'] != true) return false;
      final box = (row ~/ 3) * 3 + (col ~/ 3);
      final added = _pencilBox(data, box, fillAllColors: true, only: null);
      if (added == 0) return false;
      data['trace'] = false;
      return true;
    });
  }

  static Future<bool> telepathy({
    required String roomCode,
    required int box,
    required int value,
    required String? hopPalette,
  }) {
    return _transact(roomCode, (data, at) {
      if (data['telepathy'] != true) return false;
      final solution = _ints(data['solution']);
      final cells = _cells(data);
      final boxRow = (box ~/ 3) * 3;
      final boxCol = (box % 3) * 3;
      int? row;
      int? col;
      for (var r = boxRow; r < boxRow + 3; r++) {
        for (var c = boxCol; c < boxCol + 3; c++) {
          if (solution[r * 9 + c] == value) {
            row = r;
            col = c;
          }
        }
      }
      if (row == null || col == null) return false;
      final puzzle = _ints(data['puzzle']);
      if (puzzle[row * 9 + col] == value) return false;
      final key = '${row}_$col';
      final existing = _cell(cells, key);
      if (existing['locked'] == true && _int(existing['v']) == value) {
        return false;
      }
      final boxWasDone = _boxDone(puzzle, solution, cells, row, col);
      cells[key] = {
        'v': value,
        'locked': true,
        'notes': <String, bool>{},
      };
      data['cells'] = cells;
      data['telepathy'] = false;
      data['cellsFilled'] = _int(data['cellsFilled']) + 1;
      data['filledOnBoard'] = _int(data['filledOnBoard']) + 1;
      if (!boxWasDone && _boxDone(puzzle, solution, cells, row, col)) {
        data['sketches'] = _int(data['sketches']) + 1;
      }
      var steadfast = _int(data['steadfast']);
      if (steadfast > 0) {
        steadfast -= 1;
      } else if (hopPalette != null) {
        data['palette'] = hopPalette;
      }
      if (_unitCompleted(puzzle, solution, cells, row, col)) steadfast = 0;
      data['steadfast'] = steadfast;
      if (_boardComplete(puzzle, solution, cells)) data['dealing'] = true;
      return true;
    });
  }

  static Future<bool> buy({
    required String roomCode,
    required String effect,
    required int cost,
  }) {
    return _transact(roomCode, (data, at) {
      if (_int(data['sketches']) < cost) return false;
      data['sketches'] = _int(data['sketches']) - cost;
      switch (effect) {
        case 'steadfast':
          data['steadfast'] = HyperchromaRules.steadfastFills;
        case 'trace':
          data['trace'] = true;
        case 'telepathy':
          data['telepathy'] = true;
      }
      return true;
    });
  }

  static Future<void> timeout(String roomCode) async {
    await _transact(roomCode, (data, at) {
      final endsAt = (data['endsAt'] as num?)?.toInt() ?? 0;
      if (endsAt > at) return false;
      data['gameState'] = 'finished';
      return true;
    });
  }

  static Future<bool> claimHost({
    required String roomCode,
    required String playerId,
  }) {
    return _transact(roomCode, (data, at) {
      final players = Map<dynamic, dynamic>.from(data['players'] as Map? ?? {});
      final host = data['host']?.toString();
      if (host == playerId) return false;
      if (host != null && players.containsKey(host)) return false;
      if (!players.containsKey(playerId)) return false;
      data['host'] = playerId;
      data['partnerLeft'] = true;
      return true;
    });
  }

  static int emptyCount(List<int> puzzle) =>
      puzzle.where((value) => value == 0).length;

  static Future<bool> _transact(
    String roomCode,
    bool Function(Map<dynamic, dynamic> data, int at) change,
  ) async {
    final result = await roomRef(roomCode).runTransaction((Object? raw) {
      if (raw is! Map) return Transaction.abort();
      final data = Map<dynamic, dynamic>.from(raw);
      if (data['gameState']?.toString() != 'playing') return Transaction.abort();
      if (data['dealing'] == true) return Transaction.abort();
      final at = now();
      if (!change(data, at)) return Transaction.abort();
      return Transaction.success(data);
    });
    return result.committed;
  }

  static bool _editable(Map<dynamic, dynamic> data, int row, int col) {
    final puzzle = _ints(data['puzzle']);
    if (row < 0 || col < 0 || row > 8 || col > 8) return false;
    if (puzzle.length != 81) return false;
    if (puzzle[row * 9 + col] != 0) return false;
    final cell = _cell(_cells(data), '${row}_$col');
    if (cell['locked'] == true) return false;
    return true;
  }

  /// Drop [value] from peer notes in the same row, column, and box.
  static void _stripPeerNotes(
    Map<dynamic, dynamic> cells,
    List<int> puzzle,
    int row,
    int col,
    int value,
  ) {
    for (var r = 0; r < 9; r++) {
      for (var c = 0; c < 9; c++) {
        if (r == row && c == col) continue;
        final sameUnit =
            r == row ||
            c == col ||
            (r ~/ 3 == row ~/ 3 && c ~/ 3 == col ~/ 3);
        if (!sameUnit) continue;
        if (puzzle.length == 81 && puzzle[r * 9 + c] != 0) continue;
        final key = '${r}_$c';
        final peer = _cell(cells, key);
        if (peer['locked'] == true) continue;
        final notes = _noteList(peer['notes']);
        if (!notes.contains(value)) continue;
        notes.remove(value);
        peer['notes'] = _noteStore(notes);
        peer['v'] = 0;
        peer['locked'] = false;
        if (notes.isEmpty) {
          cells.remove(key);
        } else {
          cells[key] = peer;
        }
      }
    }
  }

  static int _pencilBox(
    Map<dynamic, dynamic> data,
    int box, {
    required bool fillAllColors,
    required int? only,
  }) {
    final cells = _cells(data);
    final puzzle = _ints(data['puzzle']);
    final boxRow = (box ~/ 3) * 3;
    final boxCol = (box % 3) * 3;
    var added = 0;
    for (var r = boxRow; r < boxRow + 3; r++) {
      for (var c = boxCol; c < boxCol + 3; c++) {
        if (puzzle[r * 9 + c] != 0) continue;
        final key = '${r}_$c';
        final cell = _cell(cells, key);
        if (cell['locked'] == true) continue;
        if (_int(cell['v']) != 0) continue;
        final notes = _noteList(cell['notes']);
        final colors = fillAllColors ? List<int>.generate(9, (i) => i + 1) : [only!];
        var changed = false;
        for (final value in colors) {
          if (notes.contains(value)) continue;
          if (!_valid(puzzle, cells, r, c, value)) continue;
          notes.add(value);
          changed = true;
          added++;
        }
        if (!changed) continue;
        notes.sort();
        cell['notes'] = _noteStore(notes);
        cell['v'] = 0;
        cell['locked'] = false;
        cells[key] = cell;
      }
    }
    data['cells'] = cells;
    return added;
  }

  static bool _valid(
    List<int> puzzle,
    Map<dynamic, dynamic> cells,
    int row,
    int col,
    int value,
  ) {
    int at(int r, int c) {
      if (puzzle[r * 9 + c] != 0) return puzzle[r * 9 + c];
      return _int(_cell(cells, '${r}_$c')['v']);
    }

    for (var c = 0; c < 9; c++) {
      if (c != col && at(row, c) == value) return false;
    }
    for (var r = 0; r < 9; r++) {
      if (r != row && at(r, col) == value) return false;
    }
    final br = (row ~/ 3) * 3;
    final bc = (col ~/ 3) * 3;
    for (var r = br; r < br + 3; r++) {
      for (var c = bc; c < bc + 3; c++) {
        if ((r != row || c != col) && at(r, c) == value) return false;
      }
    }
    return true;
  }

  static bool _unitCompleted(
    List<int> puzzle,
    List<int> solution,
    Map<dynamic, dynamic> cells,
    int row,
    int col,
  ) {
    bool filled(int r, int c) {
      final wanted = solution[r * 9 + c];
      if (puzzle[r * 9 + c] == wanted) return true;
      final cell = _cell(cells, '${r}_$c');
      return cell['locked'] == true && _int(cell['v']) == wanted;
    }

    var rowOk = true;
    var colOk = true;
    for (var i = 0; i < 9; i++) {
      if (!filled(row, i)) rowOk = false;
      if (!filled(i, col)) colOk = false;
    }
    final br = (row ~/ 3) * 3;
    final bc = (col ~/ 3) * 3;
    var boxOk = true;
    for (var r = br; r < br + 3; r++) {
      for (var c = bc; c < bc + 3; c++) {
        if (!filled(r, c)) boxOk = false;
      }
    }
    return rowOk || colOk || boxOk;
  }

  static bool _boxDone(
    List<int> puzzle,
    List<int> solution,
    Map<dynamic, dynamic> cells,
    int row,
    int col,
  ) {
    final br = (row ~/ 3) * 3;
    final bc = (col ~/ 3) * 3;
    for (var r = br; r < br + 3; r++) {
      for (var c = bc; c < bc + 3; c++) {
        final wanted = solution[r * 9 + c];
        if (puzzle[r * 9 + c] == wanted) continue;
        final cell = _cell(cells, '${r}_$c');
        if (cell['locked'] != true || _int(cell['v']) != wanted) return false;
      }
    }
    return true;
  }

  static bool _boardComplete(
    List<int> puzzle,
    List<int> solution,
    Map<dynamic, dynamic> cells,
  ) {
    if (solution.length != 81 || puzzle.length != 81) return false;
    for (var i = 0; i < 81; i++) {
      final wanted = solution[i];
      if (puzzle[i] == wanted) continue;
      final cell = _cell(cells, '${i ~/ 9}_${i % 9}');
      if (_int(cell['v']) != wanted || cell['locked'] != true) return false;
    }
    return true;
  }

  static Map<dynamic, dynamic> _cells(Map<dynamic, dynamic> data) =>
      Map<dynamic, dynamic>.from(data['cells'] as Map? ?? {});

  static Map<dynamic, dynamic> _cell(Map<dynamic, dynamic> cells, String key) {
    final raw = cells[key];
    if (raw is Map) return Map<dynamic, dynamic>.from(raw);
    return <dynamic, dynamic>{};
  }

  /// Notes survive the server as a color→true map. Lists and index maps
  /// are accepted so an older write still shows up.
  static Set<int> readNotes(Object? raw) => _noteList(raw).toSet();

  static Map<String, bool> _noteStore(List<int> notes) => {
    for (final note in notes)
      if (note >= 1 && note <= 9) '$note': true,
  };

  static List<int> _noteList(Object? raw) {
    final values = <int>{};
    void add(Object? value) {
      final number = value is num ? value.toInt() : int.tryParse('$value');
      if (number != null && number >= 1 && number <= 9) values.add(number);
    }

    if (raw is List) {
      for (final value in raw) {
        add(value);
      }
    } else if (raw is Map) {
      for (final entry in raw.entries) {
        final flag = entry.value;
        if (flag == true || flag == 1) {
          add(entry.key);
        } else {
          add(flag);
        }
      }
    }
    final notes = values.toList()..sort();
    return notes;
  }

  static List<int> _ints(Object? raw) {
    if (raw is! List) return const [];
    return [for (final value in raw) (value as num).toInt()];
  }

  static int _int(Object? raw) => raw is num ? raw.toInt() : 0;
}

/// Lobby plus the room listener handed to the live game once the match starts.
class HyperchromaCoopLink {
  HyperchromaCoopLink();

  String? roomCode;
  bool isHost = false;
  String? playerId;
  Map<dynamic, dynamic>? latest;
  void Function(Map<dynamic, dynamic> room)? onRoom;

  StreamSubscription<DatabaseEvent>? _sub;
  bool _handedOff = false;

  bool get handedOff => _handedOff;

  Future<void> listen(String code) async {
    roomCode = code;
    await _sub?.cancel();
    _sub = HyperchromaCoopService.roomRef(code).onValue.listen((event) {
      final value = event.snapshot.value;
      if (value is! Map) {
        latest = {'gameState': 'closed'};
        onRoom?.call(latest!);
        return;
      }
      latest = Map<dynamic, dynamic>.from(value);
      onRoom?.call(latest!);
    });
  }

  void handoff(void Function(Map<dynamic, dynamic> room) apply) {
    _handedOff = true;
    onRoom = apply;
    final room = latest;
    if (room != null) apply(room);
  }

  Future<void> closeIfLobby() async {
    if (_handedOff) return;
    final code = roomCode;
    final id = playerId;
    await _sub?.cancel();
    _sub = null;
    if (code != null && id != null) {
      await HyperchromaCoopService.leaveWaiting(
        roomCode: code,
        playerId: id,
        isHost: isHost,
      );
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }
}

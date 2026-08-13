import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import '../models/cell.dart';
import '../models/difficulty.dart';
import '../services/graffiti_firebase_service.dart';
import '../sudoku/sudoku_generator.dart';

enum GraffitiPhase {
  idle,
  connecting,
  searching,
  waiting,
  playing,
  finished,
}

enum GraffitiOutcome { none, win, lose, draw, defeat }

sealed class _GraffitiUndo {
  const _GraffitiUndo();
}

class _NoteUndo extends _GraffitiUndo {
  final int row;
  final int col;
  final int value;
  final bool added;
  const _NoteUndo({
    required this.row,
    required this.col,
    required this.value,
    required this.added,
  });
}

class _FillUndo extends _GraffitiUndo {
  final int row;
  final int col;
  final int value;
  final bool wasMistake;
  const _FillUndo({
    required this.row,
    required this.col,
    required this.value,
    required this.wasMistake,
  });
}

/// Multiplayer Graffiti session (Firebase RTDB). Separate from [GameProvider].
class GraffitiProvider extends ChangeNotifier {
  GraffitiPhase _phase = GraffitiPhase.idle;
  String? _roomCode;
  String? _playerId;
  String? _opponentId;
  bool _isHost = false;
  bool _solo = false;
  String? _statusMessage;
  String? _toast;
  GraffitiOutcome _outcome = GraffitiOutcome.none;

  List<List<Cell>> _cells = List.generate(
    9,
    (_) => List.generate(9, (_) => const Cell()),
  );
  List<int> _solution = List.filled(81, 0);

  int? _selectedRow;
  int? _selectedCol;
  bool _noteMode = false;
  final List<_GraffitiUndo> _undoStack = [];

  int _myCorrect = 0;
  int _myMistakes = 0;
  int _oppCorrect = 0;
  int _oppMistakes = 0;

  StreamSubscription<DatabaseEvent>? _roomSub;
  bool _startingGame = false;
  bool _busy = false;

  GraffitiPhase get phase => _phase;
  String? get roomCode => _roomCode;
  String? get playerId => _playerId;
  String? get opponentId => _opponentId;
  bool get isHost => _isHost;
  bool get solo => _solo;
  String? get statusMessage => _statusMessage;
  String? get toast => _toast;
  GraffitiOutcome get outcome => _outcome;
  bool get busy => _busy;

  List<List<Cell>> get cells => _cells;
  int? get selectedRow => _selectedRow;
  int? get selectedCol => _selectedCol;
  bool get noteMode => _noteMode;
  bool get canUndo => _undoStack.isNotEmpty && !_eliminated;
  int get myCorrect => _myCorrect;
  int get myMistakes => _myMistakes;
  int get oppCorrect => _oppCorrect;
  int get oppMistakes => _oppMistakes;
  bool get eliminated => _eliminated;
  bool get controlsEnabled =>
      _phase == GraffitiPhase.playing && !_eliminated && _outcome == GraffitiOutcome.none;

  bool get _eliminated =>
      _myMistakes >= GraffitiFirebaseService.maxMistakes;

  Cell? get selectedCell {
    final r = _selectedRow;
    final c = _selectedCol;
    if (r == null || c == null) return null;
    return _cells[r][c];
  }

  bool get canEraseSelected {
    final cell = selectedCell;
    if (cell == null || !controlsEnabled) return false;
    return cell.isEditable && (cell.value != 0 || cell.hasNotes);
  }

  void clearToast() {
    if (_toast == null) return;
    _toast = null;
    notifyListeners();
  }

  Future<bool> _ensureReady() async {
    _phase = GraffitiPhase.connecting;
    _statusMessage = 'Connecting…';
    notifyListeners();
    final ok = await GraffitiFirebaseService.ensureInitialized();
    if (!ok) {
      _phase = GraffitiPhase.idle;
      _statusMessage = 'Multiplayer unavailable (Firebase init failed).';
      notifyListeners();
      return false;
    }
    _playerId = GraffitiFirebaseService.playerId;
    if (_playerId == null) {
      _phase = GraffitiPhase.idle;
      _statusMessage = 'Could not sign in.';
      notifyListeners();
      return false;
    }
    return true;
  }

  Future<void> quickPlay() async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      if (!await _ensureReady()) return;
      final pid = _playerId!;
      _phase = GraffitiPhase.searching;
      _statusMessage = 'Searching for opponent…';
      notifyListeners();

      final open =
          await GraffitiFirebaseService.findOpenQuickMatchRoom(pid);
      if (open != null) {
        await _joinRoom(open, asQuickMatch: true);
        return;
      }

      final code = await GraffitiFirebaseService.uniqueRoomCode();
      _roomCode = code;
      _isHost = true;
      await GraffitiFirebaseService.createRoom(
        roomCode: code,
        hostId: pid,
        isQuickMatch: true,
      );
      _phase = GraffitiPhase.waiting;
      _statusMessage = 'Waiting for opponent…';
      _listenToRoom();
      notifyListeners();
    } catch (e) {
      _failToIdle('Quick Play failed.');
      debugPrint('Graffiti quickPlay: $e');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> createRoom() async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      if (!await _ensureReady()) return;
      final code = await GraffitiFirebaseService.uniqueRoomCode();
      _roomCode = code;
      _isHost = true;
      await GraffitiFirebaseService.createRoom(
        roomCode: code,
        hostId: _playerId!,
        isQuickMatch: false,
      );
      _phase = GraffitiPhase.waiting;
      _statusMessage = 'Room $code — waiting for opponent…';
      _listenToRoom();
    } catch (e) {
      _failToIdle('Could not create room.');
      debugPrint('Graffiti createRoom: $e');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> joinRoom(String code) async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      await _joinRoom(code.trim().toUpperCase());
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _joinRoom(String code, {bool asQuickMatch = false}) async {
    if (!await _ensureReady()) return;
    final pid = _playerId!;
    final ref = GraffitiFirebaseService.roomRef(code);
    final exists = await ref.get();
    if (!exists.exists) {
      _failToIdle('Room not found.');
      return;
    }
    final data = Map<dynamic, dynamic>.from(exists.value as Map);
    if (data['app'] != GraffitiFirebaseService.appTag) {
      _failToIdle('Not a Graffiti room.');
      return;
    }
    final players = Map<dynamic, dynamic>.from(data['players'] as Map? ?? {});
    if (players.length >= 2) {
      _failToIdle('Room is full.');
      return;
    }
    final result = await GraffitiFirebaseService.joinRoomTransaction(
      roomCode: code,
      playerId: pid,
    );
    if (!result.committed) {
      _failToIdle(asQuickMatch ? 'Match taken — try again.' : 'Could not join.');
      return;
    }
    _roomCode = code;
    _isHost = false;
    final hostId = data['host']?.toString();
    if (hostId != null && hostId != pid) _opponentId = hostId;
    _phase = GraffitiPhase.waiting;
    _statusMessage = 'Joined $code — waiting to start…';
    _listenToRoom();
    notifyListeners();
  }

  void _failToIdle(String message) {
    _phase = GraffitiPhase.idle;
    _statusMessage = message;
    _roomCode = null;
    notifyListeners();
  }

  void _listenToRoom() {
    _roomSub?.cancel();
    final code = _roomCode;
    if (code == null) return;
    _roomSub = GraffitiFirebaseService.roomRef(code).onValue.listen((event) {
      final raw = event.snapshot.value;
      if (raw == null) {
        if (_phase == GraffitiPhase.playing || _phase == GraffitiPhase.finished) {
          _toast = 'Opponent left';
          _solo = true;
          notifyListeners();
        } else if (_phase != GraffitiPhase.searching) {
          _resetSession(message: 'Room closed.');
        }
        return;
      }
      _applyRoomSnapshot(Map<dynamic, dynamic>.from(raw as Map));
    });
  }

  void _applyRoomSnapshot(Map<dynamic, dynamic> data) {
    final players =
        Map<dynamic, dynamic>.from(data['players'] as Map? ?? {});
    final pid = _playerId;
    if (pid != null && opponentId == null && players.length == 2) {
      for (final k in players.keys) {
        final id = k.toString();
        if (id != pid) {
          _opponentId = id;
          break;
        }
      }
    }

    final gameState = data['gameState']?.toString() ?? 'waiting';
    final wasPlaying = _phase == GraffitiPhase.playing;

    if (players.length < 2 &&
        wasPlaying &&
        data['solo'] != true &&
        gameState == 'playing') {
      _solo = true;
      _toast = 'Opponent left';
    }
    if (data['solo'] == true) {
      _solo = true;
    }

    if (_isHost &&
        players.length == 2 &&
        gameState == 'waiting' &&
        !_startingGame) {
      _startingGame = true;
      Future.microtask(() async {
        try {
          await _hostStartGame();
        } finally {
          _startingGame = false;
        }
      });
    }

    if (gameState == 'playing' || gameState == 'finished') {
      _hydrateBoard(data);
      _hydrateStats(data);
      if (gameState == 'playing') {
        _phase = GraffitiPhase.playing;
        _statusMessage = _solo ? 'Playing solo' : 'Graffiti';
      } else {
        _phase = GraffitiPhase.finished;
        _resolveOutcome(data['winner']?.toString());
      }
    }

    notifyListeners();
  }

  Future<void> _hostStartGame() async {
    final code = _roomCode;
    final host = _playerId;
    final opp = _opponentId;
    if (code == null || host == null || opp == null) return;
    final generated = SudokuGenerator().generate(Difficulty.medium);
    await GraffitiFirebaseService.hostStartGame(
      roomCode: code,
      hostId: host,
      opponentId: opp,
      puzzle: generated.puzzle.toFlat(),
      solution: generated.solution.toFlat(),
    );
  }

  void _hydrateBoard(Map<dynamic, dynamic> data) {
    final puzzle = List<dynamic>.from(data['puzzle'] as List? ?? []);
    final solution = List<dynamic>.from(data['solution'] as List? ?? []);
    if (solution.length == 81) {
      _solution = solution.map((e) => (e as num).toInt()).toList();
    }

    final board = Map<dynamic, dynamic>.from(data['board'] as Map? ?? {});
    final next = List.generate(
      9,
      (r) => List.generate(9, (c) {
        final given = puzzle.length == 81
            ? ((puzzle[r * 9 + c] as num?)?.toInt() ?? 0)
            : 0;
        final remote = board['${r}_$c'];
        final localNotes = _cells[r][c].notes;

        if (given != 0) {
          return Cell(value: given, isGiven: true, isLocked: true);
        }
        if (remote is Map) {
          final cell = Map<dynamic, dynamic>.from(remote);
          final v = (cell['v'] as num?)?.toInt() ?? 0;
          final locked = cell['locked'] == true;
          final mistake = cell['mistake'] == true;
          return Cell(
            value: v,
            notes: locked ? const {} : localNotes,
            isLocked: locked,
            hasConflict: mistake && !locked,
          );
        }
        return Cell(notes: localNotes);
      }),
    );
    _cells = next;
    _pruneInvalidFillUndos();
  }

  void _pruneInvalidFillUndos() {
    _undoStack.removeWhere((entry) {
      if (entry is! _FillUndo) return false;
      final cell = _cells[entry.row][entry.col];
      if (cell.isLocked || cell.isGiven) return true;
      if (cell.value != entry.value) return true;
      return false;
    });
  }

  void _hydrateStats(Map<dynamic, dynamic> data) {
    final stats = Map<dynamic, dynamic>.from(data['stats'] as Map? ?? {});
    final pid = _playerId;
    final oid = _opponentId;
    if (pid != null && stats[pid] is Map) {
      final mine = Map<dynamic, dynamic>.from(stats[pid] as Map);
      _myCorrect = (mine['correct'] as num?)?.toInt() ?? 0;
      _myMistakes = (mine['mistakes'] as num?)?.toInt() ?? 0;
    }
    if (oid != null && stats[oid] is Map) {
      final opp = Map<dynamic, dynamic>.from(stats[oid] as Map);
      _oppCorrect = (opp['correct'] as num?)?.toInt() ?? 0;
      _oppMistakes = (opp['mistakes'] as num?)?.toInt() ?? 0;
    }
  }

  void _resolveOutcome(String? winner) {
    if (winner == 'draw') {
      _outcome = GraffitiOutcome.draw;
      _statusMessage = 'Draw';
    } else if (winner == 'defeat') {
      _outcome = GraffitiOutcome.defeat;
      _statusMessage = 'Mutual defeat';
    } else if (winner != null && winner == _playerId) {
      _outcome = GraffitiOutcome.win;
      _statusMessage = 'You win!';
    } else if (winner != null && winner.isNotEmpty) {
      _outcome = GraffitiOutcome.lose;
      _statusMessage = 'You lose';
    }
  }

  void selectCell(int row, int col) {
    if (_phase != GraffitiPhase.playing && _phase != GraffitiPhase.finished) {
      return;
    }
    if (_selectedRow == row && _selectedCol == col) {
      _selectedRow = null;
      _selectedCol = null;
    } else {
      _selectedRow = row;
      _selectedCol = col;
    }
    notifyListeners();
  }

  void toggleNoteMode() {
    if (!controlsEnabled) return;
    _noteMode = !_noteMode;
    notifyListeners();
  }

  Future<void> inputColor(int value) async {
    if (!controlsEnabled || value < 1 || value > 9) return;
    final r = _selectedRow;
    final c = _selectedCol;
    if (r == null || c == null) return;
    final cell = _cells[r][c];
    if (!cell.isEditable) return;

    if (_noteMode) {
      _toggleNote(r, c, value);
      return;
    }

    final code = _roomCode;
    final pid = _playerId;
    if (code == null || pid == null) return;

    final result = await GraffitiFirebaseService.placeColorTransaction(
      roomCode: code,
      playerId: pid,
      row: r,
      col: c,
      value: value,
    );
    if (!result.committed) return;

    final correct = _solution[r * 9 + c] == value;
    // Snapshot listener applies board; optimistic local for snappy feel.
    if (correct) {
      _cells[r][c] = Cell(value: value, isLocked: true);
      // Correct fills are shared/locked — not undoable.
    } else {
      _undoStack.add(
        _FillUndo(row: r, col: c, value: value, wasMistake: true),
      );
      _cells[r][c] = Cell(value: value, hasConflict: true);
      _myMistakes =
          (_myMistakes + 1).clamp(0, GraffitiFirebaseService.maxMistakes);
    }
    notifyListeners();
  }

  void addNote(int value) {
    if (!controlsEnabled) return;
    final r = _selectedRow;
    final c = _selectedCol;
    if (r == null || c == null) return;
    _toggleNote(r, c, value, forceAdd: true);
  }

  void removeNote(int value) {
    if (!controlsEnabled) return;
    final r = _selectedRow;
    final c = _selectedCol;
    if (r == null || c == null) return;
    _toggleNote(r, c, value, forceRemove: true);
  }

  void _toggleNote(
    int r,
    int c,
    int value, {
    bool forceAdd = false,
    bool forceRemove = false,
  }) {
    final cell = _cells[r][c];
    if (!cell.isEditable) return;
    final has = cell.hasNote(value);
    if (forceAdd && has) return;
    if (forceRemove && !has) return;
    final added = forceAdd || (!forceRemove && !has);
    _cells[r][c] = added ? cell.withNoteAdded(value) : cell.withNoteRemoved(value);
    _undoStack.add(_NoteUndo(row: r, col: c, value: value, added: added));
    notifyListeners();
  }

  Future<void> clearSelectedCell() async {
    if (!controlsEnabled) return;
    final r = _selectedRow;
    final c = _selectedCol;
    if (r == null || c == null) return;
    final cell = _cells[r][c];
    if (!cell.isEditable) return;

    if (cell.hasNotes) {
      for (final n in cell.notes.toList()) {
        _undoStack.add(_NoteUndo(row: r, col: c, value: n, added: true));
      }
      _cells[r][c] = cell.copyWith(clearNotes: true, clearValue: true);
      notifyListeners();
      return;
    }

    if (cell.value != 0 && cell.hasConflict) {
      // Erase counts as undoing own mistake fill remotely.
      await _undoFill(r, c, cell.value, wasMistake: true, pushUndo: false);
    }
  }

  Future<void> undo() async {
    if (!canUndo) return;
    final entry = _undoStack.removeLast();
    switch (entry) {
      case _NoteUndo(:final row, :final col, :final value, :final added):
        final cell = _cells[row][col];
        if (!cell.isEditable) break;
        _cells[row][col] =
            added ? cell.withNoteRemoved(value) : cell.withNoteAdded(value);
        notifyListeners();
      case _FillUndo(
          :final row,
          :final col,
          :final value,
          :final wasMistake,
        ):
        await _undoFill(row, col, value, wasMistake: wasMistake, pushUndo: false);
    }
  }

  Future<void> _undoFill(
    int row,
    int col,
    int value, {
    required bool wasMistake,
    required bool pushUndo,
  }) async {
    final cell = _cells[row][col];
    if (cell.isLocked || cell.isGiven) return;
    if (cell.value != value) return; // opponent overwrote — invalidate

    final code = _roomCode;
    final pid = _playerId;
    if (code == null || pid == null) return;

    final result = await GraffitiFirebaseService.clearOwnFillTransaction(
      roomCode: code,
      playerId: pid,
      row: row,
      col: col,
      expectedValue: value,
      wasMistake: wasMistake,
    );
    if (!result.committed) return;

    _cells[row][col] = const Cell();
    if (wasMistake && _myMistakes > 0) _myMistakes--;
    if (pushUndo) {
      _undoStack.add(
        _FillUndo(row: row, col: col, value: value, wasMistake: wasMistake),
      );
    }
    notifyListeners();
  }

  Future<void> leave() async {
    final code = _roomCode;
    final pid = _playerId;
    if (code != null && pid != null) {
      try {
        await GraffitiFirebaseService.leaveRoom(
          roomCode: code,
          playerId: pid,
          isHost: _isHost && _phase != GraffitiPhase.playing,
        );
      } catch (_) {}
    }
    _resetSession();
  }

  void _resetSession({String? message}) {
    _roomSub?.cancel();
    _roomSub = null;
    _phase = GraffitiPhase.idle;
    _roomCode = null;
    _opponentId = null;
    _isHost = false;
    _solo = false;
    _statusMessage = message;
    _outcome = GraffitiOutcome.none;
    _cells = List.generate(9, (_) => List.generate(9, (_) => const Cell()));
    _solution = List.filled(81, 0);
    _selectedRow = null;
    _selectedCol = null;
    _noteMode = false;
    _undoStack.clear();
    _myCorrect = 0;
    _myMistakes = 0;
    _oppCorrect = 0;
    _oppMistakes = 0;
    _startingGame = false;
    notifyListeners();
  }

  bool isRelated(int row, int col) {
    final r = _selectedRow;
    final c = _selectedCol;
    if (r == null || c == null) return false;
    if (row == r && col == c) return false;
    if (row == r || col == c) return true;
    return row ~/ 3 == r ~/ 3 && col ~/ 3 == c ~/ 3;
  }

  bool isSameColor(int row, int col) {
    final r = _selectedRow;
    final c = _selectedCol;
    if (r == null || c == null) return false;
    final selected = _cells[r][c].value;
    if (selected == 0) return false;
    return _cells[row][col].value == selected;
  }

  @override
  void dispose() {
    _roomSub?.cancel();
    super.dispose();
  }
}

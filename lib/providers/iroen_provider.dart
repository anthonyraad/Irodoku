import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/cell.dart';
import '../models/game_palette.dart';
import '../models/iroen_mosaic.dart';
import '../models/iroen_state.dart';
import '../services/preferences_service.dart';
import '../sudoku/sudoku_board.dart';

enum IroenZoomPhase { off, pickingQuadrant, zoomed }

/// Free-form 9×9 coloring with optional 3× zoom per sudoku box.
class IroenProvider extends ChangeNotifier {
  static const int _maxUndo = 60;
  static const int _maxGallery = 12;
  static const int _detailSize = IroenState.detailSize;

  final PreferencesService _prefs;

  late List<List<int>> _detail;
  (int, int)? _selected;
  bool _bulkNoteSelect = false;
  final Set<int> _bulkSelected = {};
  final List<_IroenUndoSnapshot> _undoStack = [];
  IroenZoomPhase _zoomPhase = IroenZoomPhase.off;
  (int, int)? _zoomBox;
  List<IroenMosaic> _gallery = [];
  String? _activeMosaicId;

  IroenProvider({required PreferencesService preferences})
      : _prefs = preferences {
    _loadFromPrefs();
  }

  List<IroenMosaic> get gallery => List.unmodifiable(_gallery);
  String? get activeMosaicId => _activeMosaicId;

  bool get _hasActiveGallerySlot =>
      _activeMosaicId != null &&
      _gallery.any((mosaic) => mosaic.id == _activeMosaicId);

  /// Can update the active slot, or create a new one if under the cap.
  bool get canSaveToGallery {
    if (_isDetailEmpty) return false;
    if (_hasActiveGallerySlot) return true;
    return _gallery.length < _maxGallery;
  }

  bool get canSaveAsNew => !_isDetailEmpty && _gallery.length < _maxGallery;

  IroenZoomPhase get zoomPhase => _zoomPhase;
  bool get isPickingQuadrant => _zoomPhase == IroenZoomPhase.pickingQuadrant;
  bool get isZoomedIn => _zoomPhase == IroenZoomPhase.zoomed;
  bool get zoomButtonActive => _zoomPhase != IroenZoomPhase.off;
  (int, int)? get zoomBox => _zoomBox;

  (int, int)? get selected => _selected;
  bool get bulkNoteSelect => _bulkNoteSelect;
  bool get canUndo => _undoStack.isNotEmpty;

  bool get hasCellSelection =>
      _selected != null || _bulkNoteSelect || isPickingQuadrant;

  bool isCellSelected(int row, int col) {
    if (_bulkNoteSelect) {
      return _bulkSelected.contains(_cellKey(row, col));
    }
    return _selected?.$1 == row && _selected?.$2 == col;
  }

  bool get canEraseSelection {
    if (_bulkNoteSelect && _bulkSelected.length >= 2) {
      return _bulkEditableCells().any((rc) => _valueAt(rc.$1, rc.$2) != 0);
    }
    final sel = _selected;
    if (sel == null) return false;
    return _valueAt(sel.$1, sel.$2) != 0;
  }

  bool get canEnterBulkNoteSelectFromToolbar =>
      !_bulkNoteSelect && !isPickingQuadrant;

  Cell cellAt(int row, int col) => Cell(value: _valueAt(row, col));

  List<int> mosaicAt(int row, int col) {
    final mainRow = row * 3;
    final mainCol = col * 3;
    return [
      for (var dr = 0; dr < 3; dr++)
        for (var dc = 0; dc < 3; dc++)
          _detail[mainRow + dr][mainCol + dc],
    ];
  }

  bool mosaicIsUniform(int row, int col) {
    final values = mosaicAt(row, col);
    final first = values.first;
    return values.every((value) => value == first);
  }

  static int _cellKey(int row, int col) => row * SudokuBoard.size + col;

  int _valueAt(int row, int col) {
    if (isZoomedIn) {
      final (boxRow, boxCol) = _zoomBox!;
      return _detail[boxRow * 9 + row][boxCol * 9 + col];
    }
    return _mainRepresentative(row, col);
  }

  int _mainRepresentative(int row, int col) {
    final values = mosaicAt(row, col);
    final nonZero = values.where((value) => value != 0).toList();
    if (nonZero.isEmpty) return 0;
    if (nonZero.length == values.length &&
        nonZero.every((value) => value == nonZero.first)) {
      return nonZero.first;
    }
    return nonZero.first;
  }

  void _setValueAt(int row, int col, int value) {
    if (isZoomedIn) {
      final (boxRow, boxCol) = _zoomBox!;
      _detail[boxRow * 9 + row][boxCol * 9 + col] = value;
      return;
    }
    final baseRow = row * 3;
    final baseCol = col * 3;
    for (var dr = 0; dr < 3; dr++) {
      for (var dc = 0; dc < 3; dc++) {
        _detail[baseRow + dr][baseCol + dc] = value;
      }
    }
  }

  void toggleZoom() {
    switch (_zoomPhase) {
      case IroenZoomPhase.off:
        _exitBulkNoteSelect();
        _selected = null;
        _zoomPhase = IroenZoomPhase.pickingQuadrant;
      case IroenZoomPhase.pickingQuadrant:
        _zoomPhase = IroenZoomPhase.off;
      case IroenZoomPhase.zoomed:
        _zoomPhase = IroenZoomPhase.off;
        _zoomBox = null;
        _selected = null;
        _exitBulkNoteSelect();
    }
    notifyListeners();
  }

  void selectQuadrant(int boxRow, int boxCol) {
    if (!isPickingQuadrant) return;
    _zoomBox = (boxRow, boxCol);
    _zoomPhase = IroenZoomPhase.zoomed;
    _selected = null;
    _exitBulkNoteSelect();
    notifyListeners();
  }

  void selectCell(int row, int col) {
    if (isPickingQuadrant) {
      selectQuadrant(row ~/ 3, col ~/ 3);
      return;
    }

    if (_bulkNoteSelect) {
      _toggleBulkCell(row, col);
      return;
    }

    if (_selected != null && _selected!.$1 == row && _selected!.$2 == col) {
      _selected = null;
      notifyListeners();
      return;
    }
    _selected = (row, col);
    notifyListeners();
  }

  void handleCellLongPress(int row, int col) {
    if (isPickingQuadrant) return;
    if (_bulkNoteSelect) {
      _exitBulkNoteSelect();
      _selected = (row, col);
      notifyListeners();
      return;
    }

    enterBulkNoteSelect(row, col);
  }

  void enterBulkNoteSelect(int row, int col) {
    if (isPickingQuadrant) return;
    _bulkNoteSelect = true;
    _bulkSelected.add(_cellKey(row, col));
    _selected = (row, col);
    notifyListeners();
  }

  void enterBulkNoteSelectFromToolbar() {
    if (!canEnterBulkNoteSelectFromToolbar) return;
    final sel = _selected;
    if (sel != null) {
      enterBulkNoteSelect(sel.$1, sel.$2);
      return;
    }
    _bulkNoteSelect = true;
    _selected = null;
    notifyListeners();
  }

  void toggleBulkSelectMode() {
    if (isPickingQuadrant) return;
    if (_bulkNoteSelect) {
      _exitBulkNoteSelect();
      notifyListeners();
      return;
    }
    final sel = _selected;
    if (sel != null) {
      enterBulkNoteSelect(sel.$1, sel.$2);
      return;
    }
    _bulkNoteSelect = true;
    notifyListeners();
  }

  void _toggleBulkCell(int row, int col) {
    final key = _cellKey(row, col);
    if (_bulkSelected.contains(key)) {
      _bulkSelected.remove(key);
      if (_bulkSelected.isEmpty) {
        _exitBulkNoteSelect();
        _selected = null;
      } else if (_selected?.$1 == row && _selected?.$2 == col) {
        final last = _bulkSelected.last;
        _selected = (last ~/ SudokuBoard.size, last % SudokuBoard.size);
      }
    } else {
      _bulkSelected.add(key);
      _selected = (row, col);
    }
    notifyListeners();
  }

  void _exitBulkNoteSelect() {
    _bulkNoteSelect = false;
    _bulkSelected.clear();
  }

  void clearSelection() {
    if (isPickingQuadrant) {
      _zoomPhase = IroenZoomPhase.off;
      notifyListeners();
      return;
    }
    if (_selected == null && !_bulkNoteSelect) return;
    _exitBulkNoteSelect();
    _selected = null;
    notifyListeners();
  }

  void applyPickerColor(int value) {
    if (_bulkNoteSelect && _bulkSelected.isNotEmpty) {
      _applyColorToBulk(value);
      return;
    }
    setSelectedColor(value);
  }

  void setSelectedColor(int value) {
    final sel = _selected;
    if (sel == null) return;
    final (row, col) = sel;
    final current = _valueAt(row, col);

    _pushUndo();

    if (current == value) {
      _setValueAt(row, col, 0);
      _selected = null;
      _persist();
      notifyListeners();
      return;
    }

    _setValueAt(row, col, value);
    _selected = null;
    _persist();
    notifyListeners();
  }

  Iterable<(int, int)> _bulkEditableCells() sync* {
    for (final key in _bulkSelected) {
      yield (key ~/ SudokuBoard.size, key % SudokuBoard.size);
    }
  }

  void _applyColorToBulk(int value) {
    final targets = _bulkEditableCells().toList();
    if (targets.isEmpty) return;

    final allMatch = targets.every((rc) => _valueAt(rc.$1, rc.$2) == value);

    _pushUndo();
    var changed = false;
    for (final (row, col) in targets) {
      final current = _valueAt(row, col);
      final next = allMatch ? 0 : value;
      if (current != next) {
        _setValueAt(row, col, next);
        changed = true;
      }
    }
    if (changed) {
      _persist();
      notifyListeners();
    } else {
      _undoStack.removeLast();
    }
  }

  void clearSelectedCell() {
    if (_bulkNoteSelect && _bulkSelected.length >= 2) {
      _clearValuesInBulkSelection();
      return;
    }
    final sel = _selected;
    if (sel == null) return;
    clearCell(sel.$1, sel.$2, clearSelection: false);
  }

  void _clearValuesInBulkSelection() {
    final targets = _bulkEditableCells()
        .where((rc) => _valueAt(rc.$1, rc.$2) != 0)
        .toList();
    if (targets.isEmpty) return;

    _pushUndo();
    for (final (row, col) in targets) {
      _setValueAt(row, col, 0);
    }
    _persist();
    notifyListeners();
  }

  void clearCell(int row, int col, {bool clearSelection = true}) {
    if (_valueAt(row, col) == 0) return;

    _pushUndo();
    _setValueAt(row, col, 0);
    if (clearSelection &&
        _selected != null &&
        _selected!.$1 == row &&
        _selected!.$2 == col) {
      _selected = null;
    }
    _persist();
    notifyListeners();
  }

  void undo() {
    if (!canUndo) return;
    final snap = _undoStack.removeLast();
    _detail = snap.detail;
    _selected = snap.selected;
    _bulkNoteSelect = snap.bulkNoteSelect;
    _bulkSelected
      ..clear()
      ..addAll(snap.bulkSelected);
    _zoomPhase = snap.zoomPhase;
    _zoomBox = snap.zoomBox;
    _persist();
    notifyListeners();
  }

  void _pushUndo() {
    _undoStack.add(
      _IroenUndoSnapshot(
        detail: _cloneDetail(),
        selected: _selected,
        bulkNoteSelect: _bulkNoteSelect,
        bulkSelected: {..._bulkSelected},
        zoomPhase: _zoomPhase,
        zoomBox: _zoomBox,
      ),
    );
    if (_undoStack.length > _maxUndo) {
      _undoStack.removeAt(0);
    }
  }

  List<List<int>> _cloneDetail() {
    return List.generate(
      _detailSize,
      (r) => List<int>.from(_detail[r]),
    );
  }

  void _loadFromPrefs() {
    _gallery = _prefs.loadIroenGallery();
    _activeMosaicId = _prefs.getIroenActiveMosaicId();
    final saved = _prefs.loadIroenState();
    if (saved != null) {
      _applyDetail(saved.detail);
    } else {
      _resetGrid();
    }
  }

  void _persist() {
    unawaited(_prefs.saveIroenState(IroenState(detail: _flatDetail())));
  }

  List<int> _flatDetail() => [
        for (var r = 0; r < _detailSize; r++)
          for (var c = 0; c < _detailSize; c++) _detail[r][c],
      ];

  bool get _isDetailEmpty {
    for (final row in _detail) {
      for (final value in row) {
        if (value != 0) return false;
      }
    }
    return true;
  }

  void _applyDetail(List<int> flat) {
    _detail = List.generate(_detailSize, (r) {
      return List.generate(_detailSize, (c) {
        return flat[r * _detailSize + c];
      });
    });
  }

  void _resetGrid() {
    _detail = List.generate(
      _detailSize,
      (_) => List.filled(_detailSize, 0),
    );
    _selected = null;
    _zoomPhase = IroenZoomPhase.off;
    _zoomBox = null;
    _exitBulkNoteSelect();
    _undoStack.clear();
  }

  /// Saves the current canvas into the gallery.
  /// Updates the active mosaic when one is loaded; otherwise creates a new slot.
  Future<IroenMosaic?> saveToGallery(GamePalette palette) async {
    if (!canSaveToGallery) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final flat = _flatDetail();

    final activeIndex = _activeMosaicId == null
        ? -1
        : _gallery.indexWhere((m) => m.id == _activeMosaicId);

    if (activeIndex >= 0) {
      final existing = _gallery[activeIndex];
      final updated = existing.copyWith(
        detail: flat,
        updatedAtMs: now,
        palette: palette,
      );
      _gallery = [..._gallery]..[activeIndex] = updated;
      await _prefs.saveIroenGallery(_gallery);
      notifyListeners();
      return updated;
    }

    if (_gallery.length >= _maxGallery) return null;
    final mosaic = IroenMosaic(
      id: 'm_$now',
      name: 'Mosaic ${_gallery.length + 1}',
      detail: flat,
      updatedAtMs: now,
      palette: palette,
    );
    _gallery = [..._gallery, mosaic];
    _activeMosaicId = mosaic.id;
    await _prefs.saveIroenGallery(_gallery);
    await _prefs.setIroenActiveMosaicId(_activeMosaicId);
    notifyListeners();
    return mosaic;
  }

  /// Always creates a new gallery slot from the current canvas.
  Future<IroenMosaic?> saveAsNew(GamePalette palette) async {
    if (!canSaveAsNew) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final mosaic = IroenMosaic(
      id: 'm_$now',
      name: 'Mosaic ${_gallery.length + 1}',
      detail: _flatDetail(),
      updatedAtMs: now,
      palette: palette,
    );
    _gallery = [..._gallery, mosaic];
    _activeMosaicId = mosaic.id;
    await _prefs.saveIroenGallery(_gallery);
    await _prefs.setIroenActiveMosaicId(_activeMosaicId);
    notifyListeners();
    return mosaic;
  }

  Future<IroenMosaic?> loadMosaic(String id) async {
    IroenMosaic? mosaic;
    for (final item in _gallery) {
      if (item.id == id) {
        mosaic = item;
        break;
      }
    }
    if (mosaic == null) return null;

    _pushUndo();
    _applyDetail(mosaic.detail);
    _selected = null;
    _zoomPhase = IroenZoomPhase.off;
    _zoomBox = null;
    _exitBulkNoteSelect();
    _activeMosaicId = mosaic.id;
    _persist();
    await _prefs.setIroenActiveMosaicId(_activeMosaicId);
    notifyListeners();
    return mosaic;
  }

  Future<void> deleteMosaic(String id) async {
    final next = _gallery.where((m) => m.id != id).toList();
    if (next.length == _gallery.length) return;
    _gallery = next;
    if (_activeMosaicId == id) {
      _activeMosaicId = null;
      await _prefs.setIroenActiveMosaicId(null);
    }
    await _prefs.saveIroenGallery(_gallery);
    notifyListeners();
  }

  Future<void> renameMosaic(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final index = _gallery.indexWhere((m) => m.id == id);
    if (index < 0) return;
    _gallery = [..._gallery]
      ..[index] = _gallery[index].copyWith(name: trimmed);
    await _prefs.saveIroenGallery(_gallery);
    notifyListeners();
  }

  /// Clears the working canvas (does not delete gallery slots).
  Future<void> newCanvas() async {
    _pushUndo();
    _resetGrid();
    _activeMosaicId = null;
    _persist();
    await _prefs.setIroenActiveMosaicId(null);
    notifyListeners();
  }
}

class _IroenUndoSnapshot {
  final List<List<int>> detail;
  final (int, int)? selected;
  final bool bulkNoteSelect;
  final Set<int> bulkSelected;
  final IroenZoomPhase zoomPhase;
  final (int, int)? zoomBox;

  const _IroenUndoSnapshot({
    required this.detail,
    required this.selected,
    required this.bulkNoteSelect,
    required this.bulkSelected,
    required this.zoomPhase,
    required this.zoomBox,
  });
}

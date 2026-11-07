import 'package:flutter/widgets.dart';

/// Provider hooks for hold-and-drag multi-select (bulk note select).
///
/// Shared by Iroen, classic Irodoku, Pocket, Graffiti, and [Graffiti]
/// so the drag behavior stays identical across modes.
abstract class BulkPaintTarget {
  /// Paint gestures are ignored while this is false (e.g. Iroen quadrant pick).
  bool get bulkPaintEnabled;
  void prepareBulkPaintGesture();
  void beginBulkPaint();

  /// Add a cell to the bulk selection (entering bulk if needed). Never toggles off.
  void addBulkCell(int row, int col);
  void endBulkPaint();

  /// Called on lift when no drag happened (stationary long-press in bulk).
  void completePendingBulkExit(int? row, int? col);
}

/// Pointer tracking for drag-to-add over a square grid of [gridSize] cells.
///
/// Wrap the cell layer in a [Listener] wired to [onPointerDown] /
/// [onPointerMove] / [onPointerUp], and give that layer [layerKey].
class BulkPaintGesture {
  BulkPaintGesture({required this.gridSize});

  static const paintSlop = 12.0;

  int gridSize;
  final layerKey = GlobalKey();

  int? _pointer;
  Offset? _downGlobal;
  (int, int)? _start;
  (int, int)? _last;
  var _painting = false;

  bool get isPainting => _painting;

  void onPointerDown(BulkPaintTarget target, PointerDownEvent event) {
    if (!target.bulkPaintEnabled) return;
    target.prepareBulkPaintGesture();
    _pointer = event.pointer;
    _downGlobal = event.position;
    _start = cellAtGlobal(event.position);
    _last = _start;
    _painting = false;
  }

  void onPointerMove(BulkPaintTarget target, PointerMoveEvent event) {
    if (_pointer != event.pointer || !target.bulkPaintEnabled) return;
    if (!_painting) {
      final origin = _downGlobal;
      if (origin == null || (event.position - origin).distance < paintSlop) {
        return;
      }
    }
    final cell = cellAtGlobal(event.position);
    if (cell == null || cell == _last) return;
    if (!_painting) {
      final start = _start;
      if (start == null) return;
      target.beginBulkPaint();
      target.addBulkCell(start.$1, start.$2);
      _painting = true;
    }
    target.addBulkCell(cell.$1, cell.$2);
    _last = cell;
  }

  void onPointerUp(BulkPaintTarget target, PointerEvent event) {
    if (_pointer != event.pointer) return;
    if (_painting) {
      target.endBulkPaint();
    } else {
      final start = _start;
      target.completePendingBulkExit(start?.$1, start?.$2);
    }
    _pointer = null;
    _downGlobal = null;
    _start = null;
    _last = null;
    _painting = false;
  }

  (int, int)? cellAtGlobal(Offset global) {
    final box = layerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final local = box.globalToLocal(global);
    final size = box.size;
    if (size.width <= 0 || size.height <= 0) return null;
    final col = (local.dx / size.width * gridSize).floor();
    final row = (local.dy / size.height * gridSize).floor();
    if (row < 0 || row >= gridSize || col < 0 || col >= gridSize) return null;
    return (row, col);
  }
}

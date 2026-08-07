import 'dart:async';

import 'package:flutter/material.dart';

import '../core/bulk_note_rainbow_border.dart';
import '../core/organic_swatch_motion.dart';
import '../core/palette.dart';
import '../core/theme.dart';
import '../models/game_palette.dart';
import '../models/palette_swatch.dart';
import '../providers/iroen_provider.dart';
import '../sudoku/sudoku_board.dart';
import 'color_cell.dart';

class IroenGrid extends StatefulWidget {
  final IroenProvider iroen;
  final GamePalette palette;

  const IroenGrid({
    super.key,
    required this.iroen,
    required this.palette,
  });

  @override
  State<IroenGrid> createState() => _IroenGridState();
}

class _IroenGridState extends State<IroenGrid> with TickerProviderStateMixin {
  static const _borderPulseDuration = Duration(milliseconds: 1400);
  static const _rainbowBorderDuration = BulkNoteRainbowBorder.duration;

  late final AnimationController _borderPulseController;
  late final AnimationController _rainbowBorderController;
  bool _holdingGlassMotion = false;

  @override
  void initState() {
    super.initState();
    _syncGlassMotion();
    _borderPulseController = AnimationController(
      vsync: this,
      duration: _borderPulseDuration,
    );
    _rainbowBorderController = AnimationController(
      vsync: this,
      duration: _rainbowBorderDuration,
    );
    widget.iroen.addListener(_onIroenChanged);
    _syncBorderPulse();
    _syncRainbowBorder();
  }

  @override
  void didUpdateWidget(covariant IroenGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.iroen != widget.iroen) {
      oldWidget.iroen.removeListener(_onIroenChanged);
      widget.iroen.addListener(_onIroenChanged);
    }
    _syncBorderPulse();
    _syncRainbowBorder();
    _syncGlassMotion();
  }

  @override
  void dispose() {
    widget.iroen.removeListener(_onIroenChanged);
    _syncGlassMotion(forceOff: true);
    _borderPulseController.dispose();
    _rainbowBorderController.dispose();
    super.dispose();
  }

  void _syncGlassMotion({bool forceOff = false}) {
    final needs = !forceOff &&
        (widget.palette == GamePalette.glass ||
            widget.palette == GamePalette.sky);
    if (needs && !_holdingGlassMotion) {
      OrganicSwatchMotion.retain();
      _holdingGlassMotion = true;
    } else if (!needs && _holdingGlassMotion) {
      OrganicSwatchMotion.release();
      _holdingGlassMotion = false;
    }
  }

  void _onIroenChanged() {
    if (mounted) {
      _syncBorderPulse();
      _syncRainbowBorder();
    }
  }

  void _syncBorderPulse() {
    if (widget.iroen.bulkNoteSelect || widget.iroen.isPickingQuadrant) {
      if (_borderPulseController.isAnimating) {
        _borderPulseController.stop();
        _borderPulseController.value = 0;
      }
      return;
    }
    if (widget.iroen.selected != null) {
      if (!_borderPulseController.isAnimating) {
        _borderPulseController.repeat(reverse: true);
      }
    } else {
      _borderPulseController.stop();
      _borderPulseController.value = 0;
    }
  }

  void _syncRainbowBorder() {
    if (widget.iroen.bulkNoteSelect && widget.iroen.selected != null) {
      if (!_rainbowBorderController.isAnimating) {
        _rainbowBorderController.repeat(reverse: true);
      }
    } else {
      _rainbowBorderController.stop();
      _rainbowBorderController.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = IrodokuTheme.boardBrightness;
    final thin = IrodokuTheme.thinGridLine(brightness);
    final thick = IrodokuTheme.thickGridLine(brightness);
    final iroen = widget.iroen;
    final selected = iroen.isPickingQuadrant ? null : iroen.selected;
    final bulkNoteSelect = iroen.bulkNoteSelect;

    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: thick, width: 2.5),
          color: IrodokuTheme.emptyCellFill(brightness),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildCellLayer(
              iroen: iroen,
              thin: thin,
              thick: thick,
              selected: selected,
            ),
            if (iroen.isPickingQuadrant)
              IgnorePointer(
                child: CustomPaint(
                  painter: _QuadrantPickOverlayPainter(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            if (selected != null)
              AnimatedBuilder(
                animation: bulkNoteSelect
                    ? _rainbowBorderController
                    : _borderPulseController,
                builder: (context, _) => IgnorePointer(
                  child: CustomPaint(
                    painter: _IroenPeerBorderPainter(
                      row: selected.$1,
                      col: selected.$2,
                      color: bulkNoteSelect
                          ? null
                          : IrodokuTheme.relatedUnitBorderPulse(
                              brightness,
                              Curves.easeInOut.transform(
                                _borderPulseController.value,
                              ),
                            ),
                      rainbowPhase: bulkNoteSelect
                          ? _rainbowBorderController.value
                          : null,
                      rainbowBrightness:
                          bulkNoteSelect ? brightness : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCellLayer({
    required IroenProvider iroen,
    required Color thin,
    required Color thick,
    required (int, int)? selected,
  }) {
    bool inSelectedUnit(int r, int c) {
      if (selected == null) return false;
      final (sr, sc) = selected;
      return r == sr ||
          c == sc ||
          (r ~/ 3 == sr ~/ 3 && c ~/ 3 == sc ~/ 3);
    }

    final selectedValue =
        selected == null ? 0 : iroen.cellAt(selected.$1, selected.$2).value;
    final useMosaic = !iroen.isZoomedIn;

    return Column(
      children: List.generate(SudokuBoard.size, (row) {
        return Expanded(
          child: Row(
            children: List.generate(SudokuBoard.size, (col) {
              final isSelected = iroen.isCellSelected(row, col);
              final isRelated =
                  selected != null && inSelectedUnit(row, col) && !isSelected;
              final cell = iroen.cellAt(row, col);
              final isSameColor = selected != null &&
                  !isSelected &&
                  selectedValue != 0 &&
                  cell.value == selectedValue;

              final rightW = (col + 1) % 3 == 0 && col != 8 ? 2.0 : 0.6;
              final bottomW = (row + 1) % 3 == 0 && row != 8 ? 2.0 : 0.6;
              final rightColor =
                  (col + 1) % 3 == 0 && col != 8 ? thick : thin;
              final bottomColor =
                  (row + 1) % 3 == 0 && row != 8 ? thick : thin;

              final cellWidget = useMosaic
                  ? _IroenMosaicCell(
                      subValues: iroen.mosaicAt(row, col),
                      palette: widget.palette,
                      isSelected: isSelected,
                      isRelated: isRelated,
                      isSameColor: isSameColor,
                      bulkNoteSelect: iroen.bulkNoteSelect,
                      onTap: () => iroen.selectCell(row, col),
                      onLongPress: iroen.isPickingQuadrant
                          ? null
                          : () => iroen.handleCellLongPress(row, col),
                      onDoubleTap: iroen.isPickingQuadrant
                          ? null
                          : () => iroen.clearCell(row, col),
                    )
                  : ColorCell(
                      cell: cell,
                      isSelected: isSelected,
                      palette: widget.palette,
                      bulkNoteSelect: iroen.bulkNoteSelect,
                      isRelated: isRelated,
                      isSameColor: isSameColor,
                      onTap: () => iroen.selectCell(row, col),
                      onLongPress: () => iroen.handleCellLongPress(row, col),
                      onDoubleTap: () => iroen.clearCell(row, col),
                    );

              return Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    cellWidget,
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      width: rightW,
                      child: ColoredBox(color: rightColor),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: bottomW,
                      child: ColoredBox(color: bottomColor),
                    ),
                  ],
                ),
              );
            }),
          ),
        );
      }),
    );
  }
}

class _IroenMosaicCell extends StatefulWidget {
  final List<int> subValues;
  final GamePalette palette;
  final bool isSelected;
  final bool isRelated;
  final bool isSameColor;
  final bool bulkNoteSelect;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDoubleTap;

  const _IroenMosaicCell({
    required this.subValues,
    required this.palette,
    required this.isSelected,
    required this.isRelated,
    required this.isSameColor,
    this.bulkNoteSelect = false,
    this.onTap,
    this.onLongPress,
    this.onDoubleTap,
  });

  @override
  State<_IroenMosaicCell> createState() => _IroenMosaicCellState();
}

class _IroenMosaicCellState extends State<_IroenMosaicCell> {
  /// Match [ColorCell]: select on pointer-down so onDoubleTap doesn't delay taps.
  static const _longPressDuration = Duration(milliseconds: 500);

  Timer? _longPressTimer;
  bool _longPressTriggered = false;

  @override
  void dispose() {
    _cancelLongPressTimer();
    super.dispose();
  }

  void _cancelLongPressTimer() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  void _onPointerDown(PointerDownEvent event) {
    _longPressTriggered = false;
    _cancelLongPressTimer();
    if (widget.onLongPress != null) {
      _longPressTimer = Timer(_longPressDuration, () {
        if (!mounted) return;
        _longPressTriggered = true;
        widget.onLongPress!();
      });
    }
    // Immediate select (avoids ~300ms double-tap timeout). In bulk mode,
    // toggle on pointer-up instead so a long-press can exit without toggling.
    if (!widget.bulkNoteSelect && widget.onTap != null) {
      widget.onTap!();
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _cancelLongPressTimer();
    if (!_longPressTriggered &&
        widget.bulkNoteSelect &&
        widget.onTap != null) {
      widget.onTap!();
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _cancelLongPressTimer();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = IrodokuTheme.boardBrightness;
    final emptyFill = IrodokuTheme.emptyCellFill(brightness);
    final primary = Theme.of(context).colorScheme.primary;

    final body = Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: _MosaicPainter(
            subValues: widget.subValues,
            palette: widget.palette,
            emptyFill: emptyFill,
            selectionHighlight: widget.isSelected
                ? IrodokuTheme.selectedCellHighlight(brightness, primary)
                : null,
            relatedWash: widget.isRelated && !widget.isSelected
                ? IrodokuTheme.relatedCellOverlay(brightness)
                : null,
            sameColorWash: widget.isSameColor && !widget.isSelected
                ? IrodokuTheme.sameColorOverlay(brightness)
                : null,
            repaint: widget.palette == GamePalette.glass ||
                    widget.palette == GamePalette.sky
                ? OrganicSwatchMotion.listenable
                : null,
          ),
        ),
        if (widget.isSelected)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: primary,
                    width: IrodokuTheme.selectedCellBorderWidth,
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    final interactive = widget.onTap != null ||
        widget.onLongPress != null ||
        widget.onDoubleTap != null;
    if (!interactive) return body;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: widget.onTap != null || widget.onLongPress != null
          ? _onPointerDown
          : null,
      onPointerUp: widget.onTap != null || widget.onLongPress != null
          ? _onPointerUp
          : null,
      onPointerCancel:
          widget.onLongPress != null ? _onPointerCancel : null,
      child: GestureDetector(
        // Empty onTap keeps the detector in the arena for double-tap without
        // delaying selection (selection already ran on pointer-down).
        onTap: widget.onTap != null ? () {} : null,
        onDoubleTap: widget.onDoubleTap,
        behavior: HitTestBehavior.opaque,
        child: body,
      ),
    );
  }
}

class _MosaicPainter extends CustomPainter {
  final List<int> subValues;
  final GamePalette palette;
  final Color emptyFill;
  final Color? selectionHighlight;
  final Color? relatedWash;
  final Color? sameColorWash;

  _MosaicPainter({
    required this.subValues,
    required this.palette,
    required this.emptyFill,
    required this.selectionHighlight,
    required this.relatedWash,
    required this.sameColorWash,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = emptyFill);

    if (relatedWash != null) {
      canvas.drawRect(rect, Paint()..color = relatedWash!);
    }
    if (sameColorWash != null) {
      canvas.drawRect(rect, Paint()..color = sameColorWash!);
    }

    final tileW = size.width / 3;
    final tileH = size.height / 3;
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 3; col++) {
        final value = subValues[row * 3 + col];
        if (value == 0) continue;
        final color = IrodokuPalette.swatchForValue(value, palette);
        if (color == null) continue;
        drawSwatchRect(
          canvas,
          Rect.fromLTWH(col * tileW, row * tileH, tileW, tileH),
          color,
        );
      }
    }

    if (selectionHighlight != null) {
      canvas.drawRect(rect, Paint()..color = selectionHighlight!);
    }
  }

  @override
  bool shouldRepaint(covariant _MosaicPainter oldDelegate) {
    return oldDelegate.subValues != subValues ||
        oldDelegate.palette != palette ||
        oldDelegate.selectionHighlight != selectionHighlight ||
        oldDelegate.relatedWash != relatedWash ||
        oldDelegate.sameColorWash != sameColorWash;
  }
}

class _QuadrantPickOverlayPainter extends CustomPainter {
  final Color color;

  const _QuadrantPickOverlayPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / SudokuBoard.size;
    final cellH = size.height / SudokuBoard.size;
    final fill = Paint()..color = color.withValues(alpha: 0.08);
    final border = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    for (var boxRow = 0; boxRow < 3; boxRow++) {
      for (var boxCol = 0; boxCol < 3; boxCol++) {
        final rect = Rect.fromLTWH(
          boxCol * 3 * cellW,
          boxRow * 3 * cellH,
          3 * cellW,
          3 * cellH,
        );
        canvas.drawRect(rect, fill);
        canvas.drawRect(rect, border);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QuadrantPickOverlayPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _IroenPeerBorderPainter extends CustomPainter {
  final int row;
  final int col;
  final Color? color;
  final double? rainbowPhase;
  final Brightness? rainbowBrightness;

  const _IroenPeerBorderPainter({
    required this.row,
    required this.col,
    required this.color,
    this.rainbowPhase,
    this.rainbowBrightness,
  });

  Paint _strokePaint(Size size) {
    if (rainbowPhase != null && rainbowBrightness != null) {
      return BulkNoteRainbowBorder.strokePaint(
        size: size,
        phase: rainbowPhase!,
        brightness: rainbowBrightness!,
      );
    }

    return Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.square
      ..isAntiAlias = true
      ..color = color!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / SudokuBoard.size;
    final cellH = size.height / SudokuBoard.size;
    final paint = _strokePaint(size);

    final boxCol = col ~/ 3;
    final boxRow = row ~/ 3;
    final boxLeft = boxCol * 3 * cellW;
    final boxTop = boxRow * 3 * cellH;
    final boxRight = boxLeft + 3 * cellW;
    final boxBottom = boxTop + 3 * cellH;
    final rowTop = row * cellH;
    final rowBottom = rowTop + cellH;
    final colLeft = col * cellW;
    final colRight = colLeft + cellW;

    if (rowTop > boxTop) {
      canvas.drawLine(Offset(boxLeft, boxTop), Offset(boxLeft, rowTop), paint);
      canvas.drawLine(Offset(boxRight, boxTop), Offset(boxRight, rowTop), paint);
    }
    if (rowBottom < boxBottom) {
      canvas.drawLine(Offset(boxLeft, rowBottom), Offset(boxLeft, boxBottom), paint);
      canvas.drawLine(Offset(boxRight, rowBottom), Offset(boxRight, boxBottom), paint);
    }
    if (colLeft > boxLeft) {
      canvas.drawLine(Offset(boxLeft, boxTop), Offset(colLeft, boxTop), paint);
      canvas.drawLine(Offset(boxLeft, boxBottom), Offset(colLeft, boxBottom), paint);
    }
    if (colRight < boxRight) {
      canvas.drawLine(Offset(colRight, boxTop), Offset(boxRight, boxTop), paint);
      canvas.drawLine(Offset(colRight, boxBottom), Offset(boxRight, boxBottom), paint);
    }

    if (boxLeft > 0) {
      canvas.drawLine(Offset(0, rowTop), Offset(boxLeft, rowTop), paint);
      canvas.drawLine(Offset(0, rowBottom), Offset(boxLeft, rowBottom), paint);
      canvas.drawLine(Offset(0, rowTop), Offset(0, rowBottom), paint);
    } else {
      canvas.drawLine(Offset(boxLeft, rowTop), Offset(boxLeft, rowBottom), paint);
    }
    if (boxRight < size.width) {
      canvas.drawLine(Offset(boxRight, rowTop), Offset(size.width, rowTop), paint);
      canvas.drawLine(Offset(boxRight, rowBottom), Offset(size.width, rowBottom), paint);
      canvas.drawLine(Offset(size.width, rowTop), Offset(size.width, rowBottom), paint);
    } else {
      canvas.drawLine(Offset(boxRight, rowTop), Offset(boxRight, rowBottom), paint);
    }

    if (boxTop > 0) {
      canvas.drawLine(Offset(colLeft, 0), Offset(colLeft, boxTop), paint);
      canvas.drawLine(Offset(colRight, 0), Offset(colRight, boxTop), paint);
      canvas.drawLine(Offset(colLeft, 0), Offset(colRight, 0), paint);
    } else {
      canvas.drawLine(Offset(colLeft, boxTop), Offset(colRight, boxTop), paint);
    }
    if (boxBottom < size.height) {
      canvas.drawLine(Offset(colLeft, boxBottom), Offset(colLeft, size.height), paint);
      canvas.drawLine(Offset(colRight, boxBottom), Offset(colRight, size.height), paint);
      canvas.drawLine(Offset(colLeft, size.height), Offset(colRight, size.height), paint);
    } else {
      canvas.drawLine(Offset(colLeft, boxBottom), Offset(colRight, boxBottom), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _IroenPeerBorderPainter oldDelegate) {
    return oldDelegate.row != row ||
        oldDelegate.col != col ||
        oldDelegate.color != color ||
        oldDelegate.rainbowPhase != rainbowPhase ||
        oldDelegate.rainbowBrightness != rainbowBrightness;
  }
}

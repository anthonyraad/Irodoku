import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/game_palette.dart';
import '../providers/graffiti_provider.dart';
import '../sudoku/sudoku_board.dart';
import 'color_cell.dart';

/// Same visual grid as [SudokuGrid]: outer frame, overlay thin/thick lines,
/// and pulsing peer unit borders on selection.
class GraffitiGrid extends StatefulWidget {
  final GraffitiProvider game;
  final GamePalette palette;

  const GraffitiGrid({
    super.key,
    required this.game,
    required this.palette,
  });

  @override
  State<GraffitiGrid> createState() => _GraffitiGridState();
}

class _GraffitiGridState extends State<GraffitiGrid>
    with SingleTickerProviderStateMixin {
  static const _borderPulseDuration = Duration(milliseconds: 1400);

  late final AnimationController _borderPulseController;

  @override
  void initState() {
    super.initState();
    _borderPulseController = AnimationController(
      vsync: this,
      duration: _borderPulseDuration,
    );
    widget.game.addListener(_onGameChanged);
    _syncBorderPulse();
  }

  @override
  void didUpdateWidget(covariant GraffitiGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game != widget.game) {
      oldWidget.game.removeListener(_onGameChanged);
      widget.game.addListener(_onGameChanged);
    }
    _syncBorderPulse();
  }

  @override
  void dispose() {
    widget.game.removeListener(_onGameChanged);
    _borderPulseController.dispose();
    super.dispose();
  }

  void _onGameChanged() => _syncBorderPulse();

  void _syncBorderPulse() {
    final selected =
        widget.game.selectedRow != null && widget.game.selectedCol != null;
    if (selected) {
      if (!_borderPulseController.isAnimating) {
        _borderPulseController.repeat(reverse: true);
      }
    } else {
      _borderPulseController.stop();
      _borderPulseController.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final brightness = IrodokuTheme.boardBrightness;
    final thin = IrodokuTheme.thinGridLine(brightness);
    final thick = IrodokuTheme.thickGridLine(brightness);
    final selectedRow = game.selectedRow;
    final selectedCol = game.selectedCol;
    final hasSelection = selectedRow != null && selectedCol != null;

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
              game: game,
              palette: widget.palette,
              thin: thin,
              thick: thick,
              selectedRow: selectedRow,
              selectedCol: selectedCol,
            ),
            if (hasSelection)
              AnimatedBuilder(
                animation: _borderPulseController,
                builder: (context, _) => IgnorePointer(
                  child: CustomPaint(
                    painter: _PeerUnitBorderPainter(
                      row: selectedRow,
                      col: selectedCol,
                      color: IrodokuTheme.relatedUnitBorderPulse(
                        brightness,
                        Curves.easeInOut.transform(
                          _borderPulseController.value,
                        ),
                      ),
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
    required GraffitiProvider game,
    required GamePalette palette,
    required Color thin,
    required Color thick,
    required int? selectedRow,
    required int? selectedCol,
  }) {
    final hasSelection = selectedRow != null && selectedCol != null;
    final selectedCell = hasSelection
        ? game.cells[selectedRow][selectedCol]
        : null;
    final selectedValue = selectedCell?.value ?? 0;
    // Given / locked: unit borders only — no cell fill washes.
    final washPeers = selectedCell != null && selectedCell.isEditable;

    bool inSelectedUnit(int r, int c) {
      if (!hasSelection) return false;
      return r == selectedRow ||
          c == selectedCol ||
          (r ~/ 3 == selectedRow ~/ 3 && c ~/ 3 == selectedCol ~/ 3);
    }

    return Column(
      children: List.generate(SudokuBoard.size, (row) {
        return Expanded(
          child: Row(
            children: List.generate(SudokuBoard.size, (col) {
              final cell = game.cells[row][col];
              final isSelected =
                  game.selectedRow == row && game.selectedCol == col;
              final isRelated =
                  washPeers && inSelectedUnit(row, col) && !isSelected;
              final isSameColor = washPeers &&
                  !isSelected &&
                  selectedValue != 0 &&
                  cell.value == selectedValue;

              final rightW = (col + 1) % 3 == 0 && col != 8 ? 2.0 : 0.6;
              final bottomW = (row + 1) % 3 == 0 && row != 8 ? 2.0 : 0.6;
              final rightColor =
                  (col + 1) % 3 == 0 && col != 8 ? thick : thin;
              final bottomColor =
                  (row + 1) % 3 == 0 && row != 8 ? thick : thin;

              // Grid lines are overlays so they don't inset ColorCell.
              return Expanded(
                child: RepaintBoundary(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColorCell(
                        cell: cell,
                        isSelected: isSelected,
                        isRelated: isRelated,
                        isSameColor: isSameColor,
                        palette: palette,
                        row: row,
                        col: col,
                        onTap: () => game.selectCell(row, col),
                      ),
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
                ),
              );
            }),
          ),
        );
      }),
    );
  }
}

/// Draws the selected 3×3 box plus row/column outlines outside that box.
/// Same geometry as [SudokuGrid]'s peer-unit border painter.
class _PeerUnitBorderPainter extends CustomPainter {
  final int row;
  final int col;
  final Color color;

  const _PeerUnitBorderPainter({
    required this.row,
    required this.col,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cellW = size.width / SudokuBoard.size;
    final cellH = size.height / SudokuBoard.size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.square
      ..isAntiAlias = true
      ..color = color;

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

    // 3×3 box — gaps where peer row/column bands meet the box edge.
    if (rowTop > boxTop) {
      canvas.drawLine(
        Offset(boxLeft, boxTop),
        Offset(boxLeft, rowTop),
        paint,
      );
      canvas.drawLine(
        Offset(boxRight, boxTop),
        Offset(boxRight, rowTop),
        paint,
      );
    }
    if (rowBottom < boxBottom) {
      canvas.drawLine(
        Offset(boxLeft, rowBottom),
        Offset(boxLeft, boxBottom),
        paint,
      );
      canvas.drawLine(
        Offset(boxRight, rowBottom),
        Offset(boxRight, boxBottom),
        paint,
      );
    }
    if (colLeft > boxLeft) {
      canvas.drawLine(
        Offset(boxLeft, boxTop),
        Offset(colLeft, boxTop),
        paint,
      );
      canvas.drawLine(
        Offset(boxLeft, boxBottom),
        Offset(colLeft, boxBottom),
        paint,
      );
    }
    if (colRight < boxRight) {
      canvas.drawLine(
        Offset(colRight, boxTop),
        Offset(boxRight, boxTop),
        paint,
      );
      canvas.drawLine(
        Offset(colRight, boxBottom),
        Offset(boxRight, boxBottom),
        paint,
      );
    }

    // Row bands outside the box — open toward the box (no spur at the box edge).
    if (boxLeft > 0) {
      canvas.drawLine(Offset(0, rowTop), Offset(boxLeft, rowTop), paint);
      canvas.drawLine(Offset(0, rowBottom), Offset(boxLeft, rowBottom), paint);
      canvas.drawLine(Offset(0, rowTop), Offset(0, rowBottom), paint);
    } else {
      canvas.drawLine(
        Offset(boxLeft, rowTop),
        Offset(boxLeft, rowBottom),
        paint,
      );
    }
    if (boxRight < size.width) {
      canvas.drawLine(
        Offset(boxRight, rowTop),
        Offset(size.width, rowTop),
        paint,
      );
      canvas.drawLine(
        Offset(boxRight, rowBottom),
        Offset(size.width, rowBottom),
        paint,
      );
      canvas.drawLine(
        Offset(size.width, rowTop),
        Offset(size.width, rowBottom),
        paint,
      );
    } else {
      canvas.drawLine(
        Offset(boxRight, rowTop),
        Offset(boxRight, rowBottom),
        paint,
      );
    }

    // Column bands outside the box — open toward the box.
    if (boxTop > 0) {
      canvas.drawLine(Offset(colLeft, 0), Offset(colLeft, boxTop), paint);
      canvas.drawLine(Offset(colRight, 0), Offset(colRight, boxTop), paint);
      canvas.drawLine(Offset(colLeft, 0), Offset(colRight, 0), paint);
    } else {
      canvas.drawLine(Offset(colLeft, boxTop), Offset(colRight, boxTop), paint);
    }
    if (boxBottom < size.height) {
      canvas.drawLine(
        Offset(colLeft, boxBottom),
        Offset(colLeft, size.height),
        paint,
      );
      canvas.drawLine(
        Offset(colRight, boxBottom),
        Offset(colRight, size.height),
        paint,
      );
      canvas.drawLine(
        Offset(colLeft, size.height),
        Offset(colRight, size.height),
        paint,
      );
    } else {
      canvas.drawLine(
        Offset(colLeft, boxBottom),
        Offset(colRight, boxBottom),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PeerUnitBorderPainter oldDelegate) {
    return oldDelegate.row != row ||
        oldDelegate.col != col ||
        oldDelegate.color != color;
  }
}

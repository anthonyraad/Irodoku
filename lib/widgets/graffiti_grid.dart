import 'package:flutter/material.dart';

import '../core/bulk_note_rainbow_border.dart';
import '../core/celebration_colors.dart';
import '../core/organic_swatch_motion.dart';
import '../core/palette.dart';
import '../core/theme.dart';
import '../models/game_palette.dart';
import '../models/palette_swatch.dart';
import '../models/unit_celebration.dart';
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
    with TickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 1100);
  static const _staggerFraction = 0.045;
  static const _borderPulseDuration = Duration(milliseconds: 1400);
  static const _rainbowBorderDuration = BulkNoteRainbowBorder.duration;

  late final AnimationController _controller;
  late final AnimationController _borderPulseController;
  late final AnimationController _rainbowBorderController;
  int _lastCelebrationId = 0;
  bool _holdingGlassMotion = false;

  @override
  void initState() {
    super.initState();
    _lastCelebrationId = widget.game.celebration?.id ?? 0;
    _controller = AnimationController(vsync: this, duration: _duration);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.game.clearCelebration();
      }
    });
    _borderPulseController = AnimationController(
      vsync: this,
      duration: _borderPulseDuration,
    );
    _rainbowBorderController = AnimationController(
      vsync: this,
      duration: _rainbowBorderDuration,
    );
    widget.game.addListener(_onGameChanged);
    _syncBorderPulse();
    _syncRainbowBorder();
    _syncGlassMotion();
  }

  @override
  void didUpdateWidget(covariant GraffitiGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game != widget.game) {
      oldWidget.game.removeListener(_onGameChanged);
      widget.game.addListener(_onGameChanged);
    }
    _maybeStartCelebration();
    _syncBorderPulse();
    _syncRainbowBorder();
    _syncGlassMotion();
  }

  @override
  void dispose() {
    widget.game.removeListener(_onGameChanged);
    _syncGlassMotion(forceOff: true);
    _controller.dispose();
    _borderPulseController.dispose();
    _rainbowBorderController.dispose();
    super.dispose();
  }

  void _onGameChanged() {
    _maybeStartCelebration();
    _syncBorderPulse();
    _syncRainbowBorder();
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

  void _maybeStartCelebration() {
    final celebration = widget.game.celebration;
    if (celebration == null) return;
    if (celebration.id == _lastCelebrationId) return;
    _lastCelebrationId = celebration.id;
    _controller.forward(from: 0);
  }

  double _cellProgress(int stagger) {
    final start = stagger * _staggerFraction;
    const end = 1.0;
    if (_controller.value <= start) return 0;
    return ((_controller.value - start) / (end - start)).clamp(0.0, 1.0);
  }

  void _syncBorderPulse() {
    if (widget.game.bulkNoteSelect) {
      if (_borderPulseController.isAnimating) {
        _borderPulseController.stop();
        _borderPulseController.value = 0;
      }
      return;
    }
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

  void _syncRainbowBorder() {
    if (widget.game.bulkNoteSelect &&
        widget.game.selectedRow != null &&
        widget.game.selectedCol != null) {
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
    final game = widget.game;
    final brightness = IrodokuTheme.boardBrightness;
    final thin = IrodokuTheme.thinGridLine(brightness);
    final thick = IrodokuTheme.thickGridLine(brightness);
    final selectedRow = game.selectedRow;
    final selectedCol = game.selectedCol;
    final hasSelection = selectedRow != null && selectedCol != null;
    final bulkNoteSelect = game.bulkNoteSelect;
    final celebration = game.celebration;

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
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => _buildCellLayer(
                game: game,
                palette: widget.palette,
                thin: thin,
                thick: thick,
                selectedRow: selectedRow,
                selectedCol: selectedCol,
                celebration: celebration,
              ),
            ),
            if (hasSelection)
              AnimatedBuilder(
                animation: bulkNoteSelect
                    ? _rainbowBorderController
                    : _borderPulseController,
                builder: (context, _) => IgnorePointer(
                  child: CustomPaint(
                    painter: _PeerUnitBorderPainter(
                      row: selectedRow,
                      col: selectedCol,
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
                      rainbowBrightness: bulkNoteSelect ? brightness : null,
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
    required UnitCelebration? celebration,
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
              final isSelected = game.isCellSelected(row, col);
              final isRelated =
                  washPeers && inSelectedUnit(row, col) && !isSelected;
              final isSameColor = washPeers &&
                  !isSelected &&
                  selectedValue != 0 &&
                  cell.value == selectedValue;

              PaletteSwatch? celebrationSwatch;
              var celebrationScale = 1.0;
              var celebrationShimmer = 0.0;

              if (celebration != null &&
                  celebration.contains(row, col) &&
                  _controller.isAnimating) {
                final stagger = celebration.staggerFor(row, col);
                final t = _cellProgress(stagger);
                if (t > 0) {
                  final originalValue = celebration.originalValueFor(row, col);
                  final original =
                      IrodokuPalette.swatchForValue(originalValue, palette)!;
                  celebrationSwatch = CelebrationColors.swatchFor(
                    t: t,
                    stagger: stagger,
                    original: original,
                    palette: palette,
                  );
                  celebrationScale = CelebrationColors.scaleFor(t);
                  celebrationShimmer = CelebrationColors.shimmerFor(t);
                }
              }

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
                        bulkNoteSelect: game.bulkNoteSelect,
                        celebrationSwatch: celebrationSwatch,
                        celebrationScale: celebrationScale,
                        celebrationShimmer: celebrationShimmer,
                        row: row,
                        col: col,
                        noteClearWave: game.noteClearWave,
                        onTap: () => game.selectCell(row, col),
                        onLongPress: !game.controlsEnabled || !cell.isEditable
                            ? null
                            : () => game.handleCellLongPress(row, col),
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
  final Color? color;
  final double? rainbowPhase;
  final Brightness? rainbowBrightness;

  const _PeerUnitBorderPainter({
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
        oldDelegate.color != color ||
        oldDelegate.rainbowPhase != rainbowPhase ||
        oldDelegate.rainbowBrightness != rainbowBrightness;
  }
}

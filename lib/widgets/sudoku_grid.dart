import 'package:flutter/material.dart';

import '../core/bulk_note_rainbow_border.dart';
import '../core/celebration_colors.dart';
import '../core/color_cycle.dart';
import '../core/organic_swatch_motion.dart';
import '../core/palette.dart';
import '../core/theme.dart';
import '../models/game_palette.dart';
import '../models/palette_swatch.dart';
import '../models/unit_celebration.dart';
import '../providers/game_provider.dart';
import '../sudoku/sudoku_board.dart';
import 'color_cell.dart';

class SudokuGrid extends StatefulWidget {
  final GameProvider game;
  final GamePalette palette;
  /// Optional live swatches (e.g. chromatic crossfade); falls back to [palette].
  final List<PaletteSwatch>? displaySwatches;

  const SudokuGrid({
    super.key,
    required this.game,
    required this.palette,
    this.displaySwatches,
  });

  @override
  State<SudokuGrid> createState() => _SudokuGridState();
}

class _SudokuGridState extends State<SudokuGrid> with TickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 1100);
  static const _staggerFraction = 0.045;
  static const _borderPulseDuration = Duration(milliseconds: 1400);
  static const _rainbowBorderDuration = BulkNoteRainbowBorder.duration;
  static const _colorCycleDuration = Duration(milliseconds: 1050);

  late final AnimationController _controller;
  late final AnimationController _borderPulseController;
  late final AnimationController _rainbowBorderController;
  late final AnimationController _colorCycleController;
  int _lastCelebrationId = 0;
  int _lastColorCycleSeq = 0;
  bool _holdingGlassMotion = false;

  @override
  void initState() {
    super.initState();
    // Treat existing seqs as already seen so a remount can't replay them.
    _lastCelebrationId = widget.game.celebration?.id ?? 0;
    _lastColorCycleSeq = widget.game.colorCycleSeq;
    _syncGlassMotion();
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
    _colorCycleController = AnimationController(
      vsync: this,
      duration: _colorCycleDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _colorCycleController.value = 0;
        }
      });
    widget.game.addListener(_onGameChanged);
    _syncBorderPulse();
  }

  @override
  void didUpdateWidget(covariant SudokuGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game != widget.game) {
      oldWidget.game.removeListener(_onGameChanged);
      widget.game.addListener(_onGameChanged);
    }
    _maybeStartCelebration();
    _maybeStartColorCycle();
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
    _colorCycleController.dispose();
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

  void _onGameChanged() {
    // GameScreen's Consumer rebuilds this widget; only drive local animations here.
    _maybeStartCelebration();
    _maybeStartColorCycle();
    _syncBorderPulse();
    _syncRainbowBorder();
  }

  void _syncBorderPulse() {
    if (widget.game.bulkNoteSelect) {
      if (_borderPulseController.isAnimating) {
        _borderPulseController.stop();
        _borderPulseController.value = 0;
      }
      return;
    }
    if (widget.game.selected != null) {
      if (!_borderPulseController.isAnimating) {
        _borderPulseController.repeat(reverse: true);
      }
    } else {
      _borderPulseController.stop();
      _borderPulseController.value = 0;
    }
  }

  void _syncRainbowBorder() {
    if (widget.game.bulkNoteSelect && widget.game.selected != null) {
      if (!_rainbowBorderController.isAnimating) {
        _rainbowBorderController.repeat(reverse: true);
      }
    } else {
      _rainbowBorderController.stop();
      _rainbowBorderController.value = 0;
    }
  }

  void _maybeStartCelebration() {
    final celebration = widget.game.celebration;
    if (celebration == null) return;
    if (celebration.id == _lastCelebrationId) return;
    _lastCelebrationId = celebration.id;
    _controller.forward(from: 0);
  }

  void _maybeStartColorCycle() {
    final seq = widget.game.colorCycleSeq;
    if (seq == _lastColorCycleSeq) return;
    _lastColorCycleSeq = seq;
    if (_colorCycleController.isAnimating) {
      _colorCycleController.stop();
    }
    _colorCycleController.forward(from: 0);
  }

  double? _cellColorCyclePhase(int row, int col) {
    // Only while animating — a completed controller sits at 1.0, which used to
    // keep cells stuck on solid representative colors after the shimmer.
    if (!_colorCycleController.isAnimating) return null;
    final filter = widget.game.colorCycleFilterValue;
    if (filter != null) {
      final cell = widget.game.cellAt(row, col);
      if (cell.value != filter) return null;
    }
    final global = Curves.easeInOut.transform(_colorCycleController.value);
    return ColorCycle.staggeredPhase(global, row, col);
  }

  double _cellProgress(int stagger) {
    final start = stagger * _staggerFraction;
    const end = 1.0;
    if (_controller.value <= start) return 0;
    return ((_controller.value - start) / (end - start)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final brightness = IrodokuTheme.boardBrightness;
    final thin = IrodokuTheme.thinGridLine(brightness);
    final thick = IrodokuTheme.thickGridLine(brightness);
    final celebration = game.celebration;
    final selected = game.selected;
    final bulkNoteSelect = game.bulkNoteSelect;

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
              animation: Listenable.merge([_controller, _colorCycleController]),
              builder: (context, _) => _buildCellLayer(
                game: game,
                palette: widget.palette,
                displaySwatches: widget.displaySwatches,
                brightness: brightness,
                thin: thin,
                thick: thick,
                celebration: celebration,
                selected: selected,
              ),
            ),
            if (selected != null)
              AnimatedBuilder(
                animation: bulkNoteSelect
                    ? _rainbowBorderController
                    : _borderPulseController,
                builder: (context, _) => IgnorePointer(
                  child: CustomPaint(
                    painter: _PeerUnitBorderPainter(
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
    required GameProvider game,
    required GamePalette palette,
    required List<PaletteSwatch>? displaySwatches,
    required Brightness brightness,
    required Color thin,
    required Color thick,
    required UnitCelebration? celebration,
    required (int, int)? selected,
  }) {
    bool inSelectedUnit(int r, int c) {
      if (selected == null) return false;
      final (sr, sc) = selected;
      return r == sr ||
          c == sc ||
          (r ~/ 3 == sr ~/ 3 && c ~/ 3 == sc ~/ 3);
    }

    final selectedCell =
        selected == null ? null : game.cellAt(selected.$1, selected.$2);
    final selectedValue = selectedCell?.value ?? 0;
    // Given / locked: unit borders only — no cell fill washes.
    final washPeers = selectedCell != null && selectedCell.isEditable;

    return Column(
      children: List.generate(SudokuBoard.size, (row) {
        return Expanded(
          child: Row(
            children: List.generate(SudokuBoard.size, (col) {
              final cell = game.cellAt(row, col);
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
                      IrodokuPalette.swatchFromList(
                        originalValue,
                        displaySwatches,
                      ) ??
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
                        // Fresh State each puzzle so reveal/departing don't
                        // carry across new games (same grid slot reuse).
                        key: ValueKey('cell-${game.boardEpoch}-$row-$col'),
                        cell: cell,
                        isSelected: isSelected,
                        palette: palette,
                        displaySwatches: displaySwatches,
                        bulkNoteSelect: game.bulkNoteSelect,
                        isRelated: isRelated,
                        isSameColor: isSameColor,
                        celebrationSwatch: celebrationSwatch,
                        celebrationScale: celebrationScale,
                        celebrationShimmer: celebrationShimmer,
                        colorCyclePhase: _cellColorCyclePhase(row, col),
                        colorCycleSteps: game.colorCycleSteps,
                        row: row,
                        col: col,
                        noteClearWave: game.noteClearWave,
                        onTap: game.isGenerating ||
                                game.isGameOver ||
                                game.isPaused
                            ? null
                            : () => game.selectCell(row, col),
                        onLongPress: game.isGenerating ||
                                game.isGameOver ||
                                game.isPaused ||
                                !cell.isEditable
                            ? null
                            : () => game.handleCellLongPress(row, col),
                        onDoubleTap: game.isGenerating ||
                                game.isGameOver ||
                                game.isPaused ||
                                !cell.isEditable
                            ? null
                            : () => game.clearCell(row, col),
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
      // 3×3 on the left edge — close the row band at the box/grid edge.
      canvas.drawLine(Offset(boxLeft, rowTop), Offset(boxLeft, rowBottom), paint);
    }
    if (boxRight < size.width) {
      canvas.drawLine(Offset(boxRight, rowTop), Offset(size.width, rowTop), paint);
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
      // 3×3 on the right edge — close the row band at the box edge.
      canvas.drawLine(Offset(boxRight, rowTop), Offset(boxRight, rowBottom), paint);
    }

    // Column bands outside the box — open toward the box (no spur at the box edge).
    if (boxTop > 0) {
      canvas.drawLine(Offset(colLeft, 0), Offset(colLeft, boxTop), paint);
      canvas.drawLine(Offset(colRight, 0), Offset(colRight, boxTop), paint);
      canvas.drawLine(Offset(colLeft, 0), Offset(colRight, 0), paint);
    } else {
      // 3×3 on the top edge — close the column band at the box edge.
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
      // 3×3 on the bottom edge — close the column band at the box edge.
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

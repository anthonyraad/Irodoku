import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/color_cycle.dart';
import '../core/organic_swatch_motion.dart';
import '../core/palette.dart';
import '../core/theme.dart';
import '../models/cell.dart';
import '../models/game_palette.dart';
import '../models/palette_swatch.dart';

class ColorCell extends StatefulWidget {
  final Cell cell;
  final bool isSelected;
  final bool isRelated;
  final bool isSameColor;
  final GamePalette palette;
  final bool bulkNoteSelect;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDoubleTap;
  final Color? celebrationColor;
  final double celebrationScale;
  final double celebrationShimmer;
  /// 0–1 local phase for the title-tap palette sweep; null when inactive.
  final double? colorCyclePhase;
  final int colorCycleSteps;

  const ColorCell({
    super.key,
    required this.cell,
    required this.isSelected,
    required this.palette,
    this.bulkNoteSelect = false,
    this.isRelated = false,
    this.isSameColor = false,
    this.onTap,
    this.onLongPress,
    this.onDoubleTap,
    this.celebrationColor,
    this.celebrationScale = 1,
    this.celebrationShimmer = 0,
    this.colorCyclePhase,
    this.colorCycleSteps = 4,
  });

  @override
  State<ColorCell> createState() => _ColorCellState();
}

class _ColorCellState extends State<ColorCell> {
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
    if (!widget.bulkNoteSelect && widget.onTap != null) {
      widget.onTap!();
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _cancelLongPressTimer();
    if (!_longPressTriggered && widget.bulkNoteSelect && widget.onTap != null) {
      widget.onTap!();
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _cancelLongPressTimer();
  }

  @override
  Widget build(BuildContext context) {
    final cell = widget.cell;
    final brightness = IrodokuTheme.boardBrightness;
    final emptyFill = cell.isGiven
        ? IrodokuTheme.givenCellFill(brightness)
        : IrodokuTheme.emptyCellFill(brightness);
    final conflictColor = IrodokuTheme.conflictBorder(brightness);
    final celebrating = widget.celebrationColor != null;
    final primary = Theme.of(context).colorScheme.primary;
    final colorCyclePhase = widget.colorCyclePhase;

    PaletteSwatch? committedSwatch;
    Map<int, PaletteSwatch>? noteSwatches;
    if (!celebrating) {
      if (cell.value != 0 && !cell.hasNotes) {
        committedSwatch = colorCyclePhase != null
            ? ColorCycle.displaySwatch(
                cell.value,
                colorCyclePhase,
                stepCount: widget.colorCycleSteps,
                palette: widget.palette,
              )
            : IrodokuPalette.swatchForValue(cell.value, widget.palette);
      } else if (cell.notes.isNotEmpty) {
        noteSwatches = {
          for (final value in cell.notes)
            value: colorCyclePhase != null
                ? ColorCycle.displaySwatch(
                    value,
                    colorCyclePhase,
                    stepCount: widget.colorCycleSteps,
                    palette: widget.palette,
                  )
                : IrodokuPalette.swatchForValue(value, widget.palette)!,
        };
      }
    }

    final Border? chromeBorder = cell.hasConflict && !celebrating
        ? Border.all(color: conflictColor, width: 2.5)
        : widget.isSelected
            ? Border.all(
                color: primary,
                width: IrodokuTheme.selectedCellBorderWidth,
              )
            : null;

    Color? committedOutline;
    Map<int, Color>? noteOutlines;
    if (!celebrating) {
      committedOutline =
          IrodokuPalette.outlineForValue(cell.value, widget.palette);
      if (cell.notes.isNotEmpty) {
        noteOutlines = {
          for (final value in cell.notes)
            if (IrodokuPalette.outlineForValue(value, widget.palette)
                case final outline?)
              value: outline,
        };
      }
    }

    final body = Stack(
      fit: StackFit.expand,
      children: [
        // One painter owns background + notes/fill so web can't drop the layer.
        Positioned.fill(
          child: CustomPaint(
            painter: _CellPainter(
              emptyFill:
                  celebrating ? widget.celebrationColor! : emptyFill,
              notes: celebrating ? const <int>{} : cell.notes,
              noteSwatches: noteSwatches,
              committedSwatch: celebrating ? null : committedSwatch,
              committedOutline: committedOutline,
              noteOutlines: noteOutlines,
              selectionHighlight: widget.isSelected && !celebrating
                  ? IrodokuTheme.selectedCellHighlight(brightness, primary)
                  : null,
              relatedWash: widget.isRelated && !widget.isSelected && !celebrating
                  ? IrodokuTheme.relatedCellOverlay(brightness)
                  : null,
              sameColorWash:
                  widget.isSameColor && !widget.isSelected && !celebrating
                      ? IrodokuTheme.sameColorOverlay(brightness)
                      : null,
              givenWash: cell.isGiven && cell.value != 0 && !celebrating
                  ? Colors.black.withValues(alpha: 0.08)
                  : null,
              celebrationShimmer: celebrating && widget.celebrationShimmer > 0
                  ? widget.celebrationShimmer
                  : 0,
              repaint: _swatchAnimates(committedSwatch, noteSwatches)
                  ? OrganicSwatchMotion.listenable
                  : null,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        if (chromeBorder != null)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(border: chromeBorder),
                child: const SizedBox.expand(),
              ),
            ),
          ),
      ],
    );

    final interactive = widget.onTap != null || widget.onDoubleTap != null;
    if (!interactive) {
      return widget.celebrationScale == 1
          ? body
          : Transform.scale(scale: widget.celebrationScale, child: body);
    }

    final scaled = widget.celebrationScale == 1
        ? body
        : Transform.scale(scale: widget.celebrationScale, child: body);

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown:
          widget.onTap != null || widget.onLongPress != null ? _onPointerDown : null,
      onPointerUp:
          widget.onTap != null || widget.onLongPress != null ? _onPointerUp : null,
      onPointerCancel: widget.onLongPress != null ? _onPointerCancel : null,
      child: GestureDetector(
        onTap: widget.onTap != null ? () {} : null,
        onDoubleTap: widget.onDoubleTap,
        behavior: HitTestBehavior.opaque,
        child: scaled,
      ),
    );
  }
}

bool _swatchAnimates(
  PaletteSwatch? committed,
  Map<int, PaletteSwatch>? notes,
) {
  if (committed?.animated == true) return true;
  final noteSwatches = notes;
  if (noteSwatches == null) return false;
  return noteSwatches.values.any((swatch) => swatch.animated);
}

class _CellPainter extends CustomPainter {
  static const _outlineWidth = 1.5;

  final Color emptyFill;
  final Set<int> notes;
  final Map<int, PaletteSwatch>? noteSwatches;
  final PaletteSwatch? committedSwatch;
  final Color? committedOutline;
  final Map<int, Color>? noteOutlines;
  final Color? selectionHighlight;
  final Color? relatedWash;
  final Color? sameColorWash;
  final Color? givenWash;
  final double celebrationShimmer;

  _CellPainter({
    required this.emptyFill,
    required this.notes,
    required this.noteSwatches,
    required this.committedSwatch,
    required this.committedOutline,
    required this.noteOutlines,
    required this.selectionHighlight,
    required this.relatedWash,
    required this.sameColorWash,
    required this.givenWash,
    required this.celebrationShimmer,
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

    if (committedSwatch != null) {
      drawSwatchRect(canvas, rect, committedSwatch!);
    } else if (notes.isNotEmpty) {
      final slotW = size.width / 3;
      final slotH = size.height / 3;
      for (var value = 1; value <= 9; value++) {
        if (!notes.contains(value)) continue;
        final swatch = noteSwatches![value];
        if (swatch == null) continue;
        final row = (value - 1) ~/ 3;
        final col = (value - 1) % 3;
        drawSwatchRect(
          canvas,
          Rect.fromLTWH(col * slotW, row * slotH, slotW, slotH),
          swatch,
        );
      }
    }

    // Drawn above fills so matching colors stay visible.
    if (sameColorWash != null) {
      canvas.drawRect(rect, Paint()..color = sameColorWash!);
    }

    if (givenWash != null) {
      canvas.drawRect(rect, Paint()..color = givenWash!);
    }

    if (selectionHighlight != null) {
      canvas.drawRect(rect, Paint()..color = selectionHighlight!);
    }

    if (committedSwatch != null && committedOutline != null) {
      _strokeRect(canvas, rect, committedOutline!);
    } else if (notes.isNotEmpty && noteOutlines != null) {
      final slotW = size.width / 3;
      final slotH = size.height / 3;
      for (final entry in noteOutlines!.entries) {
        final value = entry.key;
        final row = (value - 1) ~/ 3;
        final col = (value - 1) % 3;
        _strokeRect(
          canvas,
          Rect.fromLTWH(col * slotW, row * slotH, slotW, slotH),
          entry.value,
        );
      }
    }

    if (celebrationShimmer > 0) {
      canvas.drawRect(
        rect,
        Paint()..color = Colors.white.withValues(alpha: celebrationShimmer),
      );
    }
  }

  void _strokeRect(Canvas canvas, Rect rect, Color color) {
    canvas.drawRect(
      rect.deflate(_outlineWidth / 2),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = _outlineWidth,
    );
  }

  @override
  bool shouldRepaint(covariant _CellPainter oldDelegate) {
    return emptyFill != oldDelegate.emptyFill ||
        !setEquals(notes, oldDelegate.notes) ||
        noteSwatches != oldDelegate.noteSwatches ||
        committedSwatch != oldDelegate.committedSwatch ||
        committedOutline != oldDelegate.committedOutline ||
        noteOutlines != oldDelegate.noteOutlines ||
        selectionHighlight != oldDelegate.selectionHighlight ||
        relatedWash != oldDelegate.relatedWash ||
        sameColorWash != oldDelegate.sameColorWash ||
        givenWash != oldDelegate.givenWash ||
        celebrationShimmer != oldDelegate.celebrationShimmer;
  }
}

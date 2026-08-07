import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/color_cycle.dart';
import '../core/organic_swatch_motion.dart';
import '../core/palette.dart';
import '../core/theme.dart';
import '../models/cell.dart';
import '../models/game_palette.dart';
import '../models/note_clear_wave.dart';
import '../models/palette_swatch.dart';
import 'circle_reveal_clipper.dart';

class ColorCell extends StatefulWidget {
  final Cell cell;
  final bool isSelected;
  final bool isRelated;
  final bool isSameColor;
  final GamePalette palette;
  /// When set (length 9), used for fills instead of [palette] lookups.
  final List<PaletteSwatch>? displaySwatches;
  final bool bulkNoteSelect;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDoubleTap;
  final PaletteSwatch? celebrationSwatch;
  final double celebrationScale;
  final double celebrationShimmer;
  /// 0–1 local phase for the title-tap palette sweep; null when inactive.
  final double? colorCyclePhase;
  final int colorCycleSteps;
  /// Board position; used with [noteClearWave] for outward dismiss stagger.
  final int? row;
  final int? col;
  final NoteClearWave? noteClearWave;

  const ColorCell({
    super.key,
    required this.cell,
    required this.isSelected,
    required this.palette,
    this.displaySwatches,
    this.bulkNoteSelect = false,
    this.isRelated = false,
    this.isSameColor = false,
    this.onTap,
    this.onLongPress,
    this.onDoubleTap,
    this.celebrationSwatch,
    this.celebrationScale = 1,
    this.celebrationShimmer = 0,
    this.colorCyclePhase,
    this.colorCycleSteps = 4,
    this.row,
    this.col,
    this.noteClearWave,
  });

  @override
  State<ColorCell> createState() => _ColorCellState();
}

class _ColorCellState extends State<ColorCell>
    with TickerProviderStateMixin {
  static const _longPressDuration = Duration(milliseconds: 500);
  static const _revealDuration = Duration(milliseconds: 280);
  /// Peer-note clear: quick inverse of the fill bloom.
  static const _noteDismissDuration = Duration(milliseconds: 160);

  Timer? _longPressTimer;
  Timer? _noteDismissStartTimer;
  bool _longPressTriggered = false;

  late final AnimationController _revealController;
  late final Animation<double> _reveal;
  late final AnimationController _noteDismissController;
  late final Animation<double> _noteDismiss;
  /// Notes removed from the model but still painted while shrinking out.
  final Map<int, PaletteSwatch> _departingNoteSwatches = {};
  final Map<int, Color> _departingNoteOutlines = {};
  /// Committed fill removed by erase / undo / toggle-off, shrinking out.
  PaletteSwatch? _departingCommittedSwatch;
  Color? _departingCommittedOutline;

  @override
  void initState() {
    super.initState();
    // Fully revealed by default so givens / restored boards don't bloom in.
    _revealController = AnimationController(
      vsync: this,
      duration: _revealDuration,
      value: 1,
    );
    _reveal = CurvedAnimation(
      parent: _revealController,
      curve: Curves.easeOutCubic,
    );
    _revealController.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && mounted) {
        if (_departingCommittedSwatch != null) {
          setState(() {
            _departingCommittedSwatch = null;
            _departingCommittedOutline = null;
          });
        }
        _revealController.duration = _revealDuration;
      }
    });
    _noteDismissController = AnimationController(
      vsync: this,
      duration: _noteDismissDuration,
    );
    _noteDismiss = CurvedAnimation(
      parent: _noteDismissController,
      curve: Curves.easeInCubic,
    );
    _noteDismissController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() {
          _departingNoteSwatches.clear();
          _departingNoteOutlines.clear();
        });
        _noteDismissController.value = 0;
      }
    });
  }

  @override
  void didUpdateWidget(ColorCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldCommitted = _hasCommittedFill(oldWidget.cell);
    final newCommitted = _hasCommittedFill(widget.cell);
    final valueChanged = oldWidget.cell.value != widget.cell.value;

    if (newCommitted && valueChanged && !widget.cell.isGiven) {
      // User placed or changed a color (picker tap, not a given).
      _clearDepartingCommitted();
      _revealController.duration = _revealDuration;
      _revealController.forward(from: 0);
      _clearDepartingNotes();
    } else if (oldCommitted && !newCommitted && !oldWidget.cell.isGiven) {
      // Erase / undo / same-color toggle: shrink the fill away.
      _beginDepartingCommitted(oldWidget.cell.value);
    }

    // Notes removed while empty (peer clear, note toggle, erase, undo).
    if (!newCommitted && widget.cell.value == 0) {
      final removed = oldWidget.cell.notes.difference(widget.cell.notes);
      if (removed.isNotEmpty) {
        _queueDepartingNotes(removed);
        _startNoteDismiss(_noteDismissDelay(removed));
      }
    }

    // Undo / re-add: stop dismissing notes that are live again.
    _departingNoteSwatches.removeWhere((value, _) => widget.cell.hasNote(value));
    _departingNoteOutlines.removeWhere((value, _) => widget.cell.hasNote(value));
    if (_hasCommittedFill(widget.cell)) {
      _clearDepartingCommitted();
    }
  }

  PaletteSwatch _swatchFor(int value) =>
      IrodokuPalette.swatchFromList(value, widget.displaySwatches) ??
      IrodokuPalette.swatchForValue(value, widget.palette)!;

  void _queueDepartingNotes(Set<int> removed) {
    for (final value in removed) {
      _departingNoteSwatches[value] = _swatchFor(value);
      final outline = IrodokuPalette.outlineForValue(value, widget.palette);
      if (outline != null) {
        _departingNoteOutlines[value] = outline;
      } else {
        _departingNoteOutlines.remove(value);
      }
    }
  }

  void _beginDepartingCommitted(int value) {
    _departingCommittedSwatch = _swatchFor(value);
    _departingCommittedOutline =
        IrodokuPalette.outlineForValue(value, widget.palette);
    _revealController.duration = _noteDismissDuration;
    _revealController.reverse(from: 1);
  }

  Duration _noteDismissDelay(Set<int> removed) {
    final wave = widget.noteClearWave;
    final row = widget.row;
    final col = widget.col;
    if (wave == null || row == null || col == null) return Duration.zero;
    if (!removed.contains(wave.value)) return Duration.zero;
    return wave.delayFor(row, col);
  }

  void _startNoteDismiss(Duration delay) {
    _noteDismissStartTimer?.cancel();
    _noteDismissController.value = 0;
    if (delay <= Duration.zero) {
      _noteDismissController.forward(from: 0);
      return;
    }
    _noteDismissStartTimer = Timer(delay, () {
      if (!mounted) return;
      _noteDismissController.forward(from: 0);
    });
  }

  void _clearDepartingNotes() {
    _noteDismissStartTimer?.cancel();
    _noteDismissStartTimer = null;
    if (_departingNoteSwatches.isEmpty &&
        !_noteDismissController.isAnimating &&
        _noteDismissController.value == 0) {
      return;
    }
    _departingNoteSwatches.clear();
    _departingNoteOutlines.clear();
    _noteDismissController.value = 0;
  }

  void _clearDepartingCommitted() {
    _departingCommittedSwatch = null;
    _departingCommittedOutline = null;
    if (_revealController.status == AnimationStatus.reverse) {
      _revealController.value = 1;
    }
    _revealController.duration = _revealDuration;
  }

  static bool _hasCommittedFill(Cell cell) =>
      cell.value != 0 && !cell.hasNotes;

  @override
  void dispose() {
    _cancelLongPressTimer();
    _noteDismissStartTimer?.cancel();
    _revealController.dispose();
    _noteDismissController.dispose();
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

  Listenable _painterRepaint(
    PaletteSwatch? committed,
    Map<int, PaletteSwatch>? notes,
  ) {
    final listenables = <Listenable>[_revealController, _noteDismissController];
    if (_swatchAnimates(committed, notes) ||
        _departingNoteSwatches.values.any((s) => s.animated)) {
      listenables.add(OrganicSwatchMotion.listenable);
    }
    return Listenable.merge(listenables);
  }

  @override
  Widget build(BuildContext context) {
    final cell = widget.cell;
    final brightness = IrodokuTheme.boardBrightness;
    final emptyFill = cell.isGiven
        ? IrodokuTheme.givenCellFill(brightness)
        : IrodokuTheme.emptyCellFill(brightness);
    final conflictColor = IrodokuTheme.conflictBorder(brightness);
    final celebrating = widget.celebrationSwatch != null;
    final primary = Theme.of(context).colorScheme.primary;
    final colorCyclePhase = widget.colorCyclePhase;

    PaletteSwatch swatchFor(int value) =>
        colorCyclePhase != null
            ? ColorCycle.displaySwatch(
                value,
                colorCyclePhase,
                stepCount: widget.colorCycleSteps,
                palette: widget.palette,
              )
            : _swatchFor(value);

    PaletteSwatch? committedSwatch;
    Map<int, PaletteSwatch>? noteSwatches;
    if (celebrating) {
      committedSwatch = widget.celebrationSwatch;
    } else if (cell.value != 0 && !cell.hasNotes) {
      committedSwatch = swatchFor(cell.value);
    } else if (_departingCommittedSwatch != null) {
      committedSwatch = _departingCommittedSwatch;
    } else {
      final live = cell.notes;
      final departing = _departingNoteSwatches.keys
          .where((value) => !live.contains(value))
          .toSet();
      if (live.isNotEmpty || departing.isNotEmpty) {
        noteSwatches = {
          for (final value in live) value: swatchFor(value),
          for (final value in departing)
            value: _departingNoteSwatches[value]!,
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
      if (cell.value != 0 && !cell.hasNotes) {
        committedOutline =
            IrodokuPalette.outlineForValue(cell.value, widget.palette);
      } else if (_departingCommittedSwatch != null) {
        committedOutline = _departingCommittedOutline;
      }
      if (noteSwatches != null) {
        noteOutlines = {
          for (final value in noteSwatches.keys)
            if ((IrodokuPalette.outlineForValue(value, widget.palette) ??
                    _departingNoteOutlines[value])
                case final outline?)
              value: outline,
        };
      }
    }

    final paintListenables = _painterRepaint(committedSwatch, noteSwatches);

    final body = Stack(
      fit: StackFit.expand,
      children: [
        // One painter owns background + notes/fill so web can't drop the layer.
        Positioned.fill(
          child: AnimatedBuilder(
            animation: paintListenables,
            builder: (context, _) {
              final collapsing = 1.0 - _noteDismiss.value;
              final Map<int, double>? noteReveal = noteSwatches == null
                  ? null
                  : {
                      for (final value in noteSwatches.keys)
                        value: cell.notes.contains(value) ? 1.0 : collapsing,
                    };
              return CustomPaint(
                painter: _CellPainter(
                  emptyFill: emptyFill,
                  notes: celebrating
                      ? const <int>{}
                      : {
                          ...cell.notes,
                          ..._departingNoteSwatches.keys,
                        },
                  noteSwatches: noteSwatches,
                  noteReveal: noteReveal,
                  committedSwatch: committedSwatch,
                  committedOutline: committedOutline,
                  noteOutlines: noteOutlines,
                  fillReveal: committedSwatch != null ? _reveal.value : 1,
                  selectionHighlight: widget.isSelected && !celebrating
                      ? IrodokuTheme.selectedCellHighlight(brightness, primary)
                      : null,
                  relatedWash:
                      widget.isRelated && !widget.isSelected && !celebrating
                          ? IrodokuTheme.relatedCellOverlay(brightness)
                          : null,
                  sameColorWash:
                      widget.isSameColor && !widget.isSelected && !celebrating
                          ? IrodokuTheme.sameColorOverlay(brightness)
                          : null,
                  givenWash: (cell.isGiven || cell.isLocked) &&
                          cell.value != 0 &&
                          !celebrating
                      ? Colors.black.withValues(alpha: 0.08)
                      : null,
                  celebrationShimmer:
                      celebrating && widget.celebrationShimmer > 0
                          ? widget.celebrationShimmer
                          : 0,
                  repaint: paintListenables,
                ),
                child: const SizedBox.expand(),
              );
            },
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
  /// Per-note 0–1 circle coverage; null means fully visible (1).
  final Map<int, double>? noteReveal;
  final PaletteSwatch? committedSwatch;
  final Color? committedOutline;
  final Map<int, Color>? noteOutlines;
  /// 0–1 center bloom for committed fill; 1 = fully visible.
  final double fillReveal;
  final Color? selectionHighlight;
  final Color? relatedWash;
  final Color? sameColorWash;
  final Color? givenWash;
  final double celebrationShimmer;

  _CellPainter({
    required this.emptyFill,
    required this.notes,
    required this.noteSwatches,
    required this.noteReveal,
    required this.committedSwatch,
    required this.committedOutline,
    required this.noteOutlines,
    required this.fillReveal,
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

    final reveal = fillReveal.clamp(0.0, 1.0);
    final revealing = committedSwatch != null && reveal < 1;

    if (committedSwatch != null) {
      if (revealing) {
        canvas.save();
        canvas.clipPath(CircleRevealClipper.pathFor(size, reveal));
      }
      drawSwatchRect(canvas, rect, committedSwatch!);
      if (revealing) canvas.restore();
    } else if (notes.isNotEmpty) {
      final slotW = size.width / 3;
      final slotH = size.height / 3;
      for (var value = 1; value <= 9; value++) {
        if (!notes.contains(value)) continue;
        final swatch = noteSwatches![value];
        if (swatch == null) continue;
        final row = (value - 1) ~/ 3;
        final col = (value - 1) % 3;
        final slot = Rect.fromLTWH(col * slotW, row * slotH, slotW, slotH);
        final noteT = (noteReveal?[value] ?? 1).clamp(0.0, 1.0);
        if (noteT <= 0) continue;
        _paintNoteSlot(canvas, slot, swatch, noteT, noteOutlines?[value]);
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
      if (revealing) {
        canvas.save();
        canvas.clipPath(CircleRevealClipper.pathFor(size, reveal));
      }
      _strokeRect(canvas, rect, committedOutline!);
      if (revealing) canvas.restore();
    }

    if (celebrationShimmer > 0) {
      canvas.drawRect(
        rect,
        Paint()..color = Colors.white.withValues(alpha: celebrationShimmer),
      );
    }
  }

  void _paintNoteSlot(
    Canvas canvas,
    Rect slot,
    PaletteSwatch swatch,
    double reveal,
    Color? outline,
  ) {
    canvas.save();
    canvas.translate(slot.left, slot.top);
    final local = Size(slot.width, slot.height);
    if (reveal < 1) {
      canvas.clipPath(CircleRevealClipper.pathFor(local, reveal));
    }
    drawSwatchRect(canvas, Offset.zero & local, swatch);
    if (outline != null) {
      _strokeRect(canvas, Offset.zero & local, outline);
    }
    canvas.restore();
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
        noteReveal != oldDelegate.noteReveal ||
        committedSwatch != oldDelegate.committedSwatch ||
        committedOutline != oldDelegate.committedOutline ||
        noteOutlines != oldDelegate.noteOutlines ||
        fillReveal != oldDelegate.fillReveal ||
        selectionHighlight != oldDelegate.selectionHighlight ||
        relatedWash != oldDelegate.relatedWash ||
        sameColorWash != oldDelegate.sameColorWash ||
        givenWash != oldDelegate.givenWash ||
        celebrationShimmer != oldDelegate.celebrationShimmer;
  }
}

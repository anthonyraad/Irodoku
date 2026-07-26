import 'dart:async';

import 'package:flutter/material.dart';

import '../core/bulk_note_rainbow_border.dart';
import '../core/theme.dart';

/// Minimal undo / erase / note controls under the board.
class GameToolbar extends StatefulWidget {
  final bool canUndo;
  final bool noteMode;
  final bool bulkNoteSelect;
  final bool canErase;
  final VoidCallback? onUndo;
  final VoidCallback? onErase;
  final VoidCallback? onToggleNote;
  final VoidCallback? onNoteLongPress;

  const GameToolbar({
    super.key,
    required this.canUndo,
    required this.noteMode,
    required this.bulkNoteSelect,
    required this.canErase,
    this.onUndo,
    this.onErase,
    this.onToggleNote,
    this.onNoteLongPress,
  });

  static const double height = 44;
  static const _eraserAsset = 'assets/icons/eraser.png';
  static const _noteAsset = 'assets/icons/note_icon.png';

  @override
  State<GameToolbar> createState() => _GameToolbarState();
}

class _GameToolbarState extends State<GameToolbar>
    with TickerProviderStateMixin {
  static const _pulseDuration = Duration(milliseconds: 1400);
  static const _rainbowDuration = BulkNoteRainbowBorder.duration;

  late final AnimationController _pulseController;
  late final AnimationController _rainbowController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: _pulseDuration,
    );
    _rainbowController = AnimationController(
      vsync: this,
      duration: _rainbowDuration,
    );
    _syncAnimations();
  }

  @override
  void didUpdateWidget(covariant GameToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteMode != widget.noteMode ||
        oldWidget.bulkNoteSelect != widget.bulkNoteSelect) {
      _syncAnimations();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rainbowController.dispose();
    super.dispose();
  }

  void _syncAnimations() {
    final bulk = widget.bulkNoteSelect && widget.noteMode;
    if (widget.noteMode) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _pulseController.stop();
      _pulseController.value = 0;
    }

    if (bulk) {
      if (!_rainbowController.isAnimating) {
        _rainbowController.repeat(reverse: true);
      }
    } else {
      _rainbowController.stop();
      _rainbowController.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final muted = scheme.onSurface.withValues(alpha: 0.38);
    final active = scheme.onSurface.withValues(alpha: 0.78);
    final bulk = widget.bulkNoteSelect && widget.noteMode;

    return SizedBox(
      height: GameToolbar.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          const buttonSize = 44.0;
          const buttonCount = 3;
          final gap = (width - buttonCount * buttonSize) / (buttonCount + 1);
          final noteCenterX =
              gap * buttonCount + buttonSize * (buttonCount - 0.5);
          final highlightLeft = width * 2 / 3;
          final highlightWidth = (2 * (noteCenterX - highlightLeft))
              .clamp(0.0, width - highlightLeft);

          return Stack(
            fit: StackFit.expand,
            children: [
              if (widget.noteMode)
                Positioned(
                  left: highlightLeft,
                  top: 0,
                  bottom: 0,
                  width: highlightWidth,
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, _) {
                      final t = Curves.easeInOut.transform(
                        _pulseController.value,
                      );
                      final alpha = 0.13 + t * 0.07;
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: alpha),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      );
                    },
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ToolButton(
                    tooltip: 'Undo',
                    icon: Icons.undo_rounded,
                    color: widget.canUndo ? active : muted,
                    onPressed: widget.canUndo ? widget.onUndo : null,
                  ),
                  _ToolButton(
                    tooltip: 'Erase',
                    assetPath: GameToolbar._eraserAsset,
                    color: widget.canErase ? active : muted,
                    onPressed: widget.canErase ? widget.onErase : null,
                  ),
                  if (bulk)
                    AnimatedBuilder(
                      animation: _rainbowController,
                      builder: (context, _) => _NoteToolButton(
                        color: IrodokuTheme.bulkNoteRainbowColor(
                          brightness,
                          _rainbowController.value,
                        ),
                        noteMode: widget.noteMode,
                        onToggleNote: widget.onToggleNote,
                        onLongPress: widget.onNoteLongPress,
                      ),
                    )
                  else
                    _NoteToolButton(
                      color: widget.noteMode ? scheme.primary : active,
                      noteMode: widget.noteMode,
                      onToggleNote: widget.onToggleNote,
                      onLongPress: widget.onNoteLongPress,
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NoteToolButton extends StatefulWidget {
  final Color color;
  final bool noteMode;
  final VoidCallback? onToggleNote;
  final VoidCallback? onLongPress;

  const _NoteToolButton({
    required this.color,
    required this.noteMode,
    this.onToggleNote,
    this.onLongPress,
  });

  @override
  State<_NoteToolButton> createState() => _NoteToolButtonState();
}

class _NoteToolButtonState extends State<_NoteToolButton> {
  static const _longPressDuration = Duration(milliseconds: 500);

  Timer? _longPressTimer;
  bool _longPressTriggered = false;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  void _cancelLongPressTimer() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (widget.onLongPress == null) return;
    _longPressTriggered = false;
    _cancelLongPressTimer();
    _longPressTimer = Timer(_longPressDuration, () {
      if (!mounted) return;
      _longPressTriggered = true;
      widget.onLongPress!();
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    _cancelLongPressTimer();
    if (_longPressTriggered || widget.onToggleNote == null) return;
    widget.onToggleNote!();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _cancelLongPressTimer();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onLongPress == null) {
      return _ToolButton(
        tooltip: 'Note',
        assetPath: GameToolbar._noteAsset,
        color: widget.color,
        onPressed: widget.onToggleNote,
      );
    }

    return Tooltip(
      message: 'Note',
      child: Material(
        color: Colors.transparent,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: ImageIcon(
                AssetImage(GameToolbar._noteAsset),
                size: 26,
                color: widget.color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final String tooltip;
  final IconData? icon;
  final String? assetPath;
  final Color color;
  final VoidCallback? onPressed;

  const _ToolButton({
    required this.tooltip,
    required this.color,
    required this.onPressed,
    this.icon,
    this.assetPath,
  }) : assert(icon != null || assetPath != null);

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (assetPath != null) {
      child = ImageIcon(
        AssetImage(assetPath!),
        size: 26,
        color: color,
      );
    } else {
      child = Icon(icon, size: 26, color: color);
    }

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

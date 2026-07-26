import 'dart:async';

import 'package:flutter/material.dart';

import '../core/bulk_note_rainbow_border.dart';
import '../core/theme.dart';

/// Undo, erase, bulk select, and zoom controls for Iroen mode.
class IroenToolbar extends StatefulWidget {
  final bool canUndo;
  final bool bulkNoteSelect;
  final bool canErase;
  final bool zoomActive;
  final VoidCallback? onUndo;
  final VoidCallback? onErase;
  final VoidCallback? onToggleBulk;
  final VoidCallback? onBulkLongPress;
  final VoidCallback? onToggleZoom;

  const IroenToolbar({
    super.key,
    required this.canUndo,
    required this.bulkNoteSelect,
    required this.canErase,
    required this.zoomActive,
    this.onUndo,
    this.onErase,
    this.onToggleBulk,
    this.onBulkLongPress,
    this.onToggleZoom,
  });

  static const double height = 44;
  static const _eraserAsset = 'assets/icons/eraser.png';
  static const _noteAsset = 'assets/icons/note_icon.png';

  @override
  State<IroenToolbar> createState() => _IroenToolbarState();
}

class _IroenToolbarState extends State<IroenToolbar>
    with TickerProviderStateMixin {
  static const _rainbowDuration = BulkNoteRainbowBorder.duration;

  late final AnimationController _rainbowController;

  @override
  void initState() {
    super.initState();
    _rainbowController = AnimationController(
      vsync: this,
      duration: _rainbowDuration,
    );
    _syncAnimations();
  }

  @override
  void didUpdateWidget(covariant IroenToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bulkNoteSelect != widget.bulkNoteSelect) {
      _syncAnimations();
    }
  }

  @override
  void dispose() {
    _rainbowController.dispose();
    super.dispose();
  }

  void _syncAnimations() {
    if (widget.bulkNoteSelect) {
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
    final bulk = widget.bulkNoteSelect;

    return SizedBox(
      height: IroenToolbar.height,
      child: Row(
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
            assetPath: IroenToolbar._eraserAsset,
            color: widget.canErase ? active : muted,
            onPressed: widget.canErase ? widget.onErase : null,
          ),
          if (bulk)
            AnimatedBuilder(
              animation: _rainbowController,
              builder: (context, _) => _BulkToolButton(
                color: IrodokuTheme.bulkNoteRainbowColor(
                  brightness,
                  _rainbowController.value,
                ),
                onToggleBulk: widget.onToggleBulk,
                onLongPress: widget.onBulkLongPress,
              ),
            )
          else
            _BulkToolButton(
              color: widget.bulkNoteSelect ? scheme.primary : active,
              onToggleBulk: widget.onToggleBulk,
              onLongPress: widget.onBulkLongPress,
            ),
          _ToolButton(
            tooltip: widget.zoomActive ? 'Zoom out' : 'Zoom',
            icon: widget.zoomActive
                ? Icons.zoom_out_map_rounded
                : Icons.zoom_in_map_rounded,
            color: widget.zoomActive ? scheme.primary : active,
            onPressed: widget.onToggleZoom,
          ),
        ],
      ),
    );
  }
}

class _BulkToolButton extends StatefulWidget {
  final Color color;
  final VoidCallback? onToggleBulk;
  final VoidCallback? onLongPress;

  const _BulkToolButton({
    required this.color,
    this.onToggleBulk,
    this.onLongPress,
  });

  @override
  State<_BulkToolButton> createState() => _BulkToolButtonState();
}

class _BulkToolButtonState extends State<_BulkToolButton> {
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
    if (_longPressTriggered || widget.onToggleBulk == null) return;
    widget.onToggleBulk!();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _cancelLongPressTimer();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onLongPress == null) {
      return _ToolButton(
        tooltip: 'Bulk select',
        assetPath: IroenToolbar._noteAsset,
        color: widget.color,
        onPressed: widget.onToggleBulk,
      );
    }

    return Tooltip(
      message: 'Bulk select',
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
                AssetImage(IroenToolbar._noteAsset),
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

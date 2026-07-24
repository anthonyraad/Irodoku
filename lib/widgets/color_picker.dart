import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/palette.dart';
import '../core/theme.dart';
import '../models/game_palette.dart';

class ColorPicker extends StatelessWidget {
  final double swatchSize;
  final ValueChanged<int> onColorSelected;
  final ValueChanged<int> onNoteAdded;
  final ValueChanged<int> onNoteRemoved;
  final bool visible;
  final bool xlMode;
  final GamePalette palette;

  const ColorPicker({
    super.key,
    required this.swatchSize,
    required this.onColorSelected,
    required this.onNoteAdded,
    required this.onNoteRemoved,
    required this.visible,
    required this.palette,
    this.xlMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final line = IrodokuTheme.thinGridLine(IrodokuTheme.boardBrightness);

    Widget picker;
    if (xlMode) {
      picker = SizedBox(
        width: swatchSize * 3,
        height: swatchSize * 3,
        child: Column(
          children: [
            for (var row = 0; row < 3; row++)
              SizedBox(
                height: swatchSize,
                child: Row(
                  children: [
                    for (var col = 0; col < 3; col++)
                      SizedBox(
                        width: swatchSize,
                        height: swatchSize,
                        child: _buildSwatch(
                          index: row * 3 + col,
                          line: line,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      );
    } else {
      picker = SizedBox(
        height: swatchSize,
        width: swatchSize * 9,
        child: Row(
          children: [
            for (var i = 0; i < 9; i++)
              SizedBox(
                width: swatchSize,
                height: swatchSize,
                child: _buildSwatch(index: i, line: line),
              ),
          ],
        ),
      );
    }

    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 150),
      child: IgnorePointer(
        ignoring: !visible,
        // Absorb taps so the game-screen dismiss GestureDetector doesn't steal them.
        child: GestureDetector(
          onTap: () {},
          behavior: HitTestBehavior.opaque,
          child: picker,
        ),
      ),
    );
  }

  Widget _buildSwatch({required int index, required Color line}) {
    final value = index + 1;
    final outline = IrodokuPalette.outlineForValue(value, palette);
    return _ColorSwatch(
      color: IrodokuPalette.colorsFor(palette)[index],
      borderColor: outline ?? line,
      borderWidth: outline != null ? 1.5 : 0.6,
      onTap: () => onColorSelected(value),
      onSwipeDown: () => onNoteAdded(value),
      onSwipeUp: () => onNoteRemoved(value),
    );
  }
}

class _ColorSwatch extends StatefulWidget {
  final Color color;
  final Color borderColor;
  final double borderWidth;
  final VoidCallback onTap;
  final VoidCallback onSwipeDown;
  final VoidCallback onSwipeUp;

  const _ColorSwatch({
    required this.color,
    required this.borderColor,
    required this.borderWidth,
    required this.onTap,
    required this.onSwipeDown,
    required this.onSwipeUp,
  });

  @override
  State<_ColorSwatch> createState() => _ColorSwatchState();
}

class _ColorSwatchState extends State<_ColorSwatch> {
  /// Distance in logical pixels to count as a vertical swipe.
  static const double _swipeThreshold = 8;

  int? _activePointer;
  Offset? _startGlobal;
  bool _resolved = false;

  void _onPointerDown(PointerDownEvent event) {
    _cleanupRoute();
    _activePointer = event.pointer;
    _startGlobal = event.position;
    _resolved = false;
    // Keep receiving move/up even after the finger leaves this small swatch.
    GestureBinding.instance.pointerRouter.addRoute(event.pointer, _onPointerRoute);
  }

  void _onPointerRoute(PointerEvent event) {
    if (_activePointer != event.pointer || _startGlobal == null) return;

    if (event is PointerMoveEvent) {
      if (_resolved) return;
      final dy = event.position.dy - _startGlobal!.dy;
      if (dy >= _swipeThreshold) {
        _resolved = true;
        widget.onSwipeDown();
      } else if (dy <= -_swipeThreshold) {
        _resolved = true;
        widget.onSwipeUp();
      }
      return;
    }

    if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (!_resolved && event is PointerUpEvent) {
        // No meaningful swipe — treat as a tap to commit a full color.
        widget.onTap();
      }
      _cleanupRoute();
    }
  }

  void _cleanupRoute() {
    final pointer = _activePointer;
    if (pointer != null) {
      GestureBinding.instance.pointerRouter.removeRoute(pointer, _onPointerRoute);
    }
    _activePointer = null;
    _startGlobal = null;
    _resolved = false;
  }

  @override
  void dispose() {
    _cleanupRoute();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.color,
          border: Border.all(color: widget.borderColor, width: widget.borderWidth),
        ),
      ),
    );
  }
}

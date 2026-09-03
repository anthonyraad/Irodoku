import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/palette.dart';
import '../core/theme.dart';
import '../models/game_palette.dart';
import '../models/palette_swatch.dart';

/// Maps keyboard keys to a picker color by a 3×3 layout:
///
/// ```
/// 7 8 9 / Q W E  →  1 2 3
/// 4 5 6 / A S D  →  4 5 6
/// 1 2 3 / Z X C  →  7 8 9
/// ```
///
/// Number-row and numpad digits share the same map. Returns null when the
/// key is unused or [maxColor] is below that slot (Pocket only has six).
int? colorValueForNumpadKey(LogicalKeyboardKey key, {int maxColor = 9}) {
  final value = switch (key) {
    LogicalKeyboardKey.digit7 ||
    LogicalKeyboardKey.numpad7 ||
    LogicalKeyboardKey.keyQ => 1,
    LogicalKeyboardKey.digit8 ||
    LogicalKeyboardKey.numpad8 ||
    LogicalKeyboardKey.keyW => 2,
    LogicalKeyboardKey.digit9 ||
    LogicalKeyboardKey.numpad9 ||
    LogicalKeyboardKey.keyE => 3,
    LogicalKeyboardKey.digit4 ||
    LogicalKeyboardKey.numpad4 ||
    LogicalKeyboardKey.keyA => 4,
    LogicalKeyboardKey.digit5 ||
    LogicalKeyboardKey.numpad5 ||
    LogicalKeyboardKey.keyS => 5,
    LogicalKeyboardKey.digit6 ||
    LogicalKeyboardKey.numpad6 ||
    LogicalKeyboardKey.keyD => 6,
    LogicalKeyboardKey.digit1 ||
    LogicalKeyboardKey.numpad1 ||
    LogicalKeyboardKey.keyZ => 7,
    LogicalKeyboardKey.digit2 ||
    LogicalKeyboardKey.numpad2 ||
    LogicalKeyboardKey.keyX => 8,
    LogicalKeyboardKey.digit3 ||
    LogicalKeyboardKey.numpad3 ||
    LogicalKeyboardKey.keyC => 9,
    _ => null,
  };
  if (value == null || value > maxColor) return null;
  return value;
}

class ColorPicker extends StatelessWidget {
  final double swatchSize;
  final ValueChanged<int> onColorSelected;
  final ValueChanged<int> onNoteAdded;
  final ValueChanged<int> onNoteRemoved;
  final bool visible;
  final bool xlMode;
  final bool pocket;
  /// When set (Pocket), swatch width can differ from [swatchSize] (height).
  final double? swatchWidth;
  final GamePalette palette;
  /// Optional live swatches (e.g. chromatic crossfade); falls back to [palette].
  final List<PaletteSwatch>? displaySwatches;
  final List<GamePalette>? swatchSources;

  const ColorPicker({
    super.key,
    required this.swatchSize,
    required this.onColorSelected,
    required this.onNoteAdded,
    required this.onNoteRemoved,
    required this.visible,
    required this.palette,
    this.displaySwatches,
    this.swatchSources,
    this.xlMode = false,
    this.pocket = false,
    this.swatchWidth,
  });

  @override
  Widget build(BuildContext context) {
    final line = IrodokuTheme.thinGridLine(IrodokuTheme.boardBrightness);

    Widget picker;
    if (pocket) {
      final chipW = swatchWidth ?? swatchSize;
      picker = SizedBox(
        width: chipW * 3,
        height: swatchSize * 2,
        child: Column(
          children: [
            for (var row = 0; row < 2; row++)
              SizedBox(
                height: swatchSize,
                child: Row(
                  children: [
                    for (var col = 0; col < 3; col++)
                      SizedBox(
                        width: chipW,
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
    } else if (xlMode) {
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

    return _NumpadColorKeys(
      enabled: visible,
      maxColor: pocket ? 6 : 9,
      onColorSelected: onColorSelected,
      child: AnimatedOpacity(
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
      ),
    );
  }

  Widget _buildSwatch({required int index, required Color line}) {
    final value = index + 1;
    final outline = IrodokuPalette.outlineForSlot(value, palette, swatchSources);
    final swatches = displaySwatches ?? IrodokuPalette.swatchesFor(palette);
    return _ColorSwatch(
      swatch: swatches[index],
      borderColor: outline ?? line,
      borderWidth: outline != null ? 1.5 : 0.6,
      onTap: () => onColorSelected(value),
      onSwipeDown: () => onNoteAdded(value),
      onSwipeUp: () => onNoteRemoved(value),
    );
  }
}

/// Listens for number / numpad keys while the picker is on screen, even if
/// the board has pointer focus.
class _NumpadColorKeys extends StatefulWidget {
  final bool enabled;
  final int maxColor;
  final ValueChanged<int> onColorSelected;
  final Widget child;

  const _NumpadColorKeys({
    required this.enabled,
    required this.maxColor,
    required this.onColorSelected,
    required this.child,
  });

  @override
  State<_NumpadColorKeys> createState() => _NumpadColorKeysState();
}

class _NumpadColorKeysState extends State<_NumpadColorKeys> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool get _textFieldFocused {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.findAncestorStateOfType<EditableTextState>() != null;
  }

  bool _onKey(KeyEvent event) {
    if (!widget.enabled) return false;
    if (event is! KeyDownEvent) return false;
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return false;
    }
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    if (_textFieldFocused) return false;
    final value = colorValueForNumpadKey(
      event.logicalKey,
      maxColor: widget.maxColor,
    );
    if (value == null) return false;
    widget.onColorSelected(value);
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ColorSwatch extends StatefulWidget {
  final PaletteSwatch swatch;
  final Color borderColor;
  final double borderWidth;
  final VoidCallback onTap;
  final VoidCallback onSwipeDown;
  final VoidCallback onSwipeUp;

  const _ColorSwatch({
    required this.swatch,
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
        decoration: widget.swatch.boxDecoration(
          border: Border.all(
            color: widget.borderColor,
            width: widget.borderWidth,
          ),
        ),
      ),
    );
  }
}

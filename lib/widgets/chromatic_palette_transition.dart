import 'package:flutter/material.dart';

import '../core/palette.dart';
import '../models/game_palette.dart';
import '../models/palette_swatch.dart';

/// Smoothly crossfades palette swatches when [palette] or [swatchKey] changes.
class ChromaticPaletteTransition extends StatefulWidget {
  final GamePalette palette;
  final bool animate;
  /// When set, used instead of [IrodokuPalette.swatchesFor] for [palette].
  final List<PaletteSwatch>? swatches;
  /// Identity of [swatches] so Iro remixes animate even when [palette] stays Iro.
  final String? swatchKey;
  final Widget Function(
    BuildContext context,
    GamePalette palette,
    List<PaletteSwatch> swatches,
  ) builder;

  const ChromaticPaletteTransition({
    super.key,
    required this.palette,
    required this.animate,
    this.swatches,
    this.swatchKey,
    required this.builder,
  });

  @override
  State<ChromaticPaletteTransition> createState() =>
      _ChromaticPaletteTransitionState();
}

class _ChromaticPaletteTransitionState extends State<ChromaticPaletteTransition>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 320);

  late final AnimationController _controller;
  late List<PaletteSwatch> _fromSwatches;
  late List<PaletteSwatch> _toSwatches;

  List<PaletteSwatch> _resolved({
    required GamePalette palette,
    List<PaletteSwatch>? swatches,
  }) =>
      swatches ?? IrodokuPalette.swatchesFor(palette);

  @override
  void initState() {
    super.initState();
    _toSwatches = _resolved(
      palette: widget.palette,
      swatches: widget.swatches,
    );
    _fromSwatches = _toSwatches;
    _controller = AnimationController(vsync: this, duration: _duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() {
            _fromSwatches = _toSwatches;
            _controller.value = 0;
          });
        }
      });
  }

  @override
  void didUpdateWidget(ChromaticPaletteTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    final paletteChanged = oldWidget.palette != widget.palette;
    final mixChanged = oldWidget.swatchKey != widget.swatchKey;
    if (!paletteChanged && !mixChanged) return;

    final next = _resolved(
      palette: widget.palette,
      swatches: widget.swatches,
    );

    if (!widget.animate) {
      _toSwatches = next;
      _fromSwatches = next;
      _controller.value = 0;
      return;
    }

    _fromSwatches = _visibleSwatches(
      fallbackPalette: oldWidget.palette,
      fallbackSwatches: oldWidget.swatches,
    );
    _toSwatches = next;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<PaletteSwatch> _visibleSwatches({
    required GamePalette fallbackPalette,
    List<PaletteSwatch>? fallbackSwatches,
  }) {
    if (_controller.isAnimating || _controller.value > 0) {
      return _lerpedSwatches(_controller.value);
    }
    return _resolved(
      palette: fallbackPalette,
      swatches: fallbackSwatches,
    );
  }

  List<PaletteSwatch> _lerpedSwatches(double rawT) {
    final t = Curves.easeInOutCubic.transform(rawT.clamp(0.0, 1.0));
    final to = _toSwatches;
    return [
      for (var i = 0; i < 9; i++) PaletteSwatch.lerp(_fromSwatches[i], to[i], t),
    ];
  }

  List<PaletteSwatch> _currentSwatches() {
    if (!_controller.isAnimating && _controller.value == 0) {
      return _resolved(
        palette: widget.palette,
        swatches: widget.swatches,
      );
    }
    return _lerpedSwatches(_controller.value);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return widget.builder(context, widget.palette, _currentSwatches());
      },
    );
  }
}

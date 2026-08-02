import 'package:flutter/material.dart';

import '../core/palette.dart';
import '../models/game_palette.dart';
import '../models/palette_swatch.dart';

/// Smoothly crossfades palette swatches when [palette] changes in chromatic mode.
class ChromaticPaletteTransition extends StatefulWidget {
  final GamePalette palette;
  final bool animate;
  final Widget Function(
    BuildContext context,
    GamePalette palette,
    List<PaletteSwatch> swatches,
  ) builder;

  const ChromaticPaletteTransition({
    super.key,
    required this.palette,
    required this.animate,
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
  late GamePalette _toPalette;

  @override
  void initState() {
    super.initState();
    _toPalette = widget.palette;
    _fromSwatches = IrodokuPalette.swatchesFor(widget.palette);
    _controller = AnimationController(vsync: this, duration: _duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() {
            _fromSwatches = IrodokuPalette.swatchesFor(_toPalette);
            _controller.value = 0;
          });
        }
      });
  }

  @override
  void didUpdateWidget(ChromaticPaletteTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.palette == widget.palette) return;

    if (!widget.animate) {
      _toPalette = widget.palette;
      _fromSwatches = IrodokuPalette.swatchesFor(widget.palette);
      _controller.value = 0;
      return;
    }

    // Capture what is currently on screen. Important: [widget.palette] is already
    // the new target here, so at rest we must use [oldWidget.palette].
    _fromSwatches = _visibleSwatches(fallbackPalette: oldWidget.palette);
    _toPalette = widget.palette;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<PaletteSwatch> _visibleSwatches({required GamePalette fallbackPalette}) {
    if (_controller.isAnimating || _controller.value > 0) {
      return _lerpedSwatches(_controller.value);
    }
    return IrodokuPalette.swatchesFor(fallbackPalette);
  }

  List<PaletteSwatch> _lerpedSwatches(double rawT) {
    final t = Curves.easeInOutCubic.transform(rawT.clamp(0.0, 1.0));
    final to = IrodokuPalette.swatchesFor(_toPalette);
    return [
      for (var i = 0; i < 9; i++) PaletteSwatch.lerp(_fromSwatches[i], to[i], t),
    ];
  }

  List<PaletteSwatch> _currentSwatches() {
    if (!_controller.isAnimating && _controller.value == 0) {
      return IrodokuPalette.swatchesFor(widget.palette);
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

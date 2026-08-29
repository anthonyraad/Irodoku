import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Shared bulk-select rainbow sweep for peer-unit borders.
abstract final class BulkNoteRainbowBorder {
  static const duration = Duration(milliseconds: 5200);
  /// Default select color → rainbow when entering multi-select.
  static const morphDuration = Duration(milliseconds: 200);

  static Paint strokePaint({
    required Size size,
    required double phase,
    required Brightness brightness,
    Color? fromColor,
    double morph = 1,
  }) {
    final rainbow = IrodokuTheme.bulkNoteBorderRainbow(brightness);
    final t = morph.clamp(0.0, 1.0);
    final colors = (fromColor != null && t < 1)
        ? [for (final color in rainbow) Color.lerp(fromColor, color, t)!]
        : rainbow;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.square
      ..isAntiAlias = true
      ..shader = SweepGradient(
        colors: colors,
        transform: GradientRotation(phase * 2 * math.pi),
      ).createShader(Offset.zero & size);
    return paint;
  }
}

/// Pulse, rainbow sweep, and default→rainbow morph for unit selection borders.
class BulkNoteBorderAnimation {
  static const _pulseDuration = Duration(milliseconds: 1400);

  final AnimationController pulse;
  final AnimationController rainbow;
  final AnimationController morph;

  late final Animation<double> morphValue;
  late final Listenable listenable;

  BulkNoteBorderAnimation(TickerProvider vsync)
      : pulse = AnimationController(vsync: vsync, duration: _pulseDuration),
        rainbow = AnimationController(
          vsync: vsync,
          duration: BulkNoteRainbowBorder.duration,
        ),
        morph = AnimationController(
          vsync: vsync,
          duration: BulkNoteRainbowBorder.morphDuration,
        ) {
    morphValue = CurvedAnimation(
      parent: morph,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    listenable = Listenable.merge([pulse, rainbow, morph]);
    morph.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        rainbow.stop();
        rainbow.value = 0;
      }
    });
  }

  void sync({required bool showPulse, required bool showRainbow}) {
    if (showRainbow) {
      if (pulse.isAnimating) pulse.stop();
      if (!rainbow.isAnimating) rainbow.repeat(reverse: true);
      morph.forward();
      return;
    }

    if (showPulse) {
      if (!pulse.isAnimating) pulse.repeat(reverse: true);
      morph.reverse();
      return;
    }

    pulse.stop();
    pulse.value = 0;
    morph.value = 0;
    rainbow.stop();
    rainbow.value = 0;
  }

  Color pulseColor(Brightness brightness) =>
      IrodokuTheme.relatedUnitBorderPulse(
        brightness,
        Curves.easeInOut.transform(pulse.value),
      );

  void dispose() {
    pulse.dispose();
    rainbow.dispose();
    morph.dispose();
  }
}

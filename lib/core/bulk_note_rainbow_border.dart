import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Shared bulk-select rainbow sweep for peer-unit borders.
abstract final class BulkNoteRainbowBorder {
  static const duration = Duration(milliseconds: 5200);

  static Paint strokePaint({
    required Size size,
    required double phase,
    required Brightness brightness,
  }) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.square
      ..isAntiAlias = true
      ..shader = SweepGradient(
        colors: IrodokuTheme.bulkNoteBorderRainbow(brightness),
        transform: GradientRotation(phase * 2 * math.pi),
      ).createShader(Offset.zero & size);
    return paint;
  }
}

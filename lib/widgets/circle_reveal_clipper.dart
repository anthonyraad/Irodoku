import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Circular clip from the center of [size], expanding with [fraction] (0–1).
///
/// At 1.0 the circle reaches the farthest corner so the cell is fully covered.
class CircleRevealClipper extends CustomClipper<Path> {
  final double fraction;

  const CircleRevealClipper({required this.fraction});

  static double farthestCornerRadius(Size size) {
    final center = size.center(Offset.zero);
    return math.max(
      math.max(
        (Offset.zero - center).distance,
        (Offset(size.width, 0) - center).distance,
      ),
      math.max(
        (Offset(0, size.height) - center).distance,
        (Offset(size.width, size.height) - center).distance,
      ),
    );
  }

  static Path pathFor(Size size, double fraction) {
    final center = size.center(Offset.zero);
    final radius = farthestCornerRadius(size) * fraction.clamp(0.0, 1.0);
    return Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
  }

  @override
  Path getClip(Size size) => pathFor(size, fraction);

  @override
  bool shouldReclip(CircleRevealClipper oldClipper) =>
      oldClipper.fraction != fraction;
}

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Keeps the mobile-like layout from stretching on wide web viewports.
abstract final class WebLayout {
  static const maxContentWidth = 480.0;

  static double contentWidth(BuildContext context) {
    return math.min(
      MediaQuery.sizeOf(context).width,
      maxContentWidth,
    );
  }

  static Widget wrap(BuildContext context, Widget? child) {
    if (!kIsWeb || child == null) {
      return child ?? const SizedBox.shrink();
    }

    final width = contentWidth(context);
    final height = MediaQuery.sizeOf(context).height;

    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: width,
          height: height,
          child: child,
        ),
      ),
    );
  }
}

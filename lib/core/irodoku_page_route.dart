import 'package:flutter/material.dart';

/// Material page route with a snappier transition than the default 300ms.
///
/// Keeps the platform [PageTransitionsTheme] builders (Android zoom, etc.)
/// while shortening enter/exit so titles and content appear sooner.
class IrodokuPageRoute<T> extends MaterialPageRoute<T> {
  IrodokuPageRoute({
    required super.builder,
    super.settings,
    super.fullscreenDialog,
    super.maintainState,
  });

  static const Duration forwardDuration = Duration(milliseconds: 160);
  static const Duration reverseDuration = Duration(milliseconds: 140);

  @override
  Duration get transitionDuration => forwardDuration;

  @override
  Duration get reverseTransitionDuration => reverseDuration;
}

import 'dart:async';

import 'package:flutter/material.dart';

/// Reveals [text] one character at a time. Increment [playToken] to replay.
///
/// Typing waits until the current [ModalRoute] enter animation has finished
/// (plus a short settle delay) so characters aren't consumed during Android
/// zoom/fade transitions or cold-start first frames.
class TypingTitle extends StatefulWidget {
  final String text;
  final VoidCallback? onTap;
  final int playToken;
  final TextStyle? style;
  final TextAlign? textAlign;
  final Duration charDelay;

  const TypingTitle({
    super.key,
    required this.text,
    this.onTap,
    this.playToken = 0,
    this.style,
    this.textAlign,
    this.charDelay = const Duration(milliseconds: 30),
  });

  @override
  State<TypingTitle> createState() => _TypingTitleState();
}

class _TypingTitleState extends State<TypingTitle> {
  static const _postTransitionDelay = Duration(milliseconds: 16);

  Timer? _timer;
  Animation<double>? _routeAnimation;
  AnimationStatusListener? _statusListener;
  int _visibleChars = 0;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleTyping();
    });
  }

  @override
  void didUpdateWidget(TypingTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playToken != oldWidget.playToken ||
        widget.text != oldWidget.text) {
      _scheduleTyping();
    }
  }

  void _detachRouteListener() {
    final animation = _routeAnimation;
    final listener = _statusListener;
    if (animation != null && listener != null) {
      animation.removeStatusListener(listener);
    }
    _routeAnimation = null;
    _statusListener = null;
  }

  void _scheduleTyping() {
    _timer?.cancel();
    _detachRouteListener();
    final gen = ++_generation;
    if (!mounted) return;

    setState(() => _visibleChars = 0);
    if (widget.text.isEmpty) return;

    void beginAfterSettle() {
      Future<void>.delayed(_postTransitionDelay, () {
        if (!mounted || gen != _generation) return;
        _runTyping(gen);
      });
    }

    final animation = ModalRoute.of(context)?.animation;
    if (animation == null ||
        animation.status == AnimationStatus.completed) {
      beginAfterSettle();
      return;
    }

    late final AnimationStatusListener listener;
    listener = (status) {
      if (status != AnimationStatus.completed) return;
      animation.removeStatusListener(listener);
      if (_statusListener == listener) {
        _routeAnimation = null;
        _statusListener = null;
      }
      if (!mounted || gen != _generation) return;
      beginAfterSettle();
    };
    _routeAnimation = animation;
    _statusListener = listener;
    animation.addStatusListener(listener);

    // Completed between the status check and listener attach.
    if (animation.status == AnimationStatus.completed) {
      animation.removeStatusListener(listener);
      _routeAnimation = null;
      _statusListener = null;
      beginAfterSettle();
    }
  }

  void _runTyping(int gen) {
    _timer?.cancel();
    _timer = Timer.periodic(widget.charDelay, (timer) {
      if (!mounted || gen != _generation) {
        timer.cancel();
        return;
      }
      if (_visibleChars >= widget.text.length) {
        timer.cancel();
        return;
      }
      setState(() => _visibleChars++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _detachRouteListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.text.substring(
      0,
      _visibleChars.clamp(0, widget.text.length),
    );

    final label = Text(
      visible,
      style: widget.style,
      textAlign: widget.textAlign,
    );

    if (widget.onTap == null) return label;

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: label,
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';

/// Reveals [text] one character at a time. Increment [playToken] to replay.
class TypingTitle extends StatefulWidget {
  final String text;
  final VoidCallback? onTap;
  final int playToken;

  const TypingTitle({
    super.key,
    required this.text,
    this.onTap,
    this.playToken = 0,
  });

  @override
  State<TypingTitle> createState() => _TypingTitleState();
}

class _TypingTitleState extends State<TypingTitle> {
  static const _charDelay = Duration(milliseconds: 55);

  Timer? _timer;
  int _visibleChars = 0;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  @override
  void didUpdateWidget(TypingTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playToken != oldWidget.playToken) {
      _startTyping();
    }
  }

  void _startTyping() {
    _timer?.cancel();
    if (!mounted) return;
    setState(() => _visibleChars = 0);
    if (widget.text.isEmpty) return;

    _timer = Timer.periodic(_charDelay, (timer) {
      if (!mounted) {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.text.substring(
      0,
      _visibleChars.clamp(0, widget.text.length),
    );

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Text(visible),
    );
  }
}

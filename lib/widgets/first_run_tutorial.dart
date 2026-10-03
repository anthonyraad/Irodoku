import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import 'menu_select_sound.dart';
import 'palette_sweep_mask.dart';

/// First-run overlay on the home Game Screen. Layout and rust.gif match 8X.
class FirstRunTutorialOverlay extends StatefulWidget {
  final VoidCallback onComplete;

  const FirstRunTutorialOverlay({super.key, required this.onComplete});

  static const steps = [
    "Welcome to Irodoku!\n\nEach row, column, and box must contain each of nine colors exactly once.",
    "To color in a cell, tap on it then select one of the 9 colors.",
    "Complete Irodoku puzzles and challenges to unlock palettes, game modes, and more.\n\nThere's a lot of color to uncover in this world; let's get started!",
  ];

  static const colorSweepNeedle = 'a lot of color';

  @override
  State<FirstRunTutorialOverlay> createState() =>
      _FirstRunTutorialOverlayState();
}

class _FirstRunTutorialOverlayState extends State<FirstRunTutorialOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade;
  late final Animation<double> _opacity;
  int _step = 0;
  int _skipTypingToken = 0;
  bool _typingComplete = false;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _opacity = CurvedAnimation(parent: _fade, curve: Curves.easeOut);
    _fade.forward();
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    await _fade.reverse();
    if (!mounted) return;
    widget.onComplete();
  }

  void _onAdvanceTap() {
    if (_finishing) return;
    if (!_typingComplete) {
      setState(() => _skipTypingToken++);
      return;
    }
    if (_step < FirstRunTutorialOverlay.steps.length - 1) {
      playMenuSelectSound(context);
      setState(() {
        _step++;
        _typingComplete = false;
        _skipTypingToken = 0;
      });
      return;
    }
    playMenuSelectSound(context);
    unawaited(_finish());
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.shortestSide < 600;
    final gifSize = compact ? 108.0 : 132.0;
    final text = FirstRunTutorialOverlay.steps[_step];
    const ink = Colors.black;
    const card = Color(0xFFF5F6F8);
    final bodyStyle = TextStyle(
      fontFamily: 'Balatro',
      fontSize: compact ? 14 : 16,
      color: ink,
      height: 1.4,
    );

    return FadeTransition(
      opacity: _opacity,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _onAdvanceTap,
                child: const ColoredBox(
                  color: Color(0xB3000000),
                ),
              ),
            ),
            Positioned(
              top: compact ? 8 : 12,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Center(
                  child: GestureDetector(
                    onTap: _onAdvanceTap,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/rust.gif',
                          width: gifSize,
                          height: gifSize,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                          gaplessPlayback: true,
                        ),
                        Transform.translate(
                          offset: const Offset(0, -30),
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth: size.width * 0.85,
                            ),
                            decoration: BoxDecoration(
                              color: card,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: ink, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .shadow
                                      .withValues(alpha: 0.26),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    18,
                                    20,
                                    32,
                                  ),
                                  child: _TypewriterText(
                                    key: ValueKey(_step),
                                    text: text,
                                    skipToken: _skipTypingToken,
                                    boldWord: _step == 0 ? 'Irodoku' : null,
                                    sweepColorWord: _step ==
                                        FirstRunTutorialOverlay.steps.length -
                                            1,
                                    onComplete: () {
                                      if (mounted) {
                                        setState(() => _typingComplete = true);
                                      }
                                    },
                                    style: bodyStyle,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                Positioned(
                                  right: 8,
                                  bottom: 4,
                                  child: IgnorePointer(
                                    child: Opacity(
                                      opacity: _typingComplete ? 1 : 0,
                                      child: _BlinkingCaret(color: ink),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlinkingCaret extends StatefulWidget {
  final Color color;

  const _BlinkingCaret({required this.color});

  @override
  State<_BlinkingCaret> createState() => _BlinkingCaretState();
}

class _BlinkingCaretState extends State<_BlinkingCaret> {
  static const _period = Duration(milliseconds: 480);

  Timer? _timer;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_period, (_) {
      if (!mounted) return;
      setState(() => _visible = !_visible);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: _visible ? 1 : 0,
      child: Icon(
        Icons.keyboard_arrow_down,
        size: 20,
        color: widget.color,
      ),
    );
  }
}

/// Reveals [text] quickly, pausing at each line break.
class _TypewriterText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final int skipToken;
  final String? boldWord;
  final bool sweepColorWord;
  final VoidCallback? onComplete;

  const _TypewriterText({
    super.key,
    required this.text,
    this.style,
    this.textAlign = TextAlign.center,
    this.skipToken = 0,
    this.boldWord,
    this.sweepColorWord = false,
    this.onComplete,
  });

  @override
  State<_TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<_TypewriterText> {
  static const _characterDuration = Duration(milliseconds: 12);
  static const _linePause = Duration(milliseconds: 520);

  Timer? _delay;
  Completer<void>? _waiting;
  int _visibleChars = 0;
  int _generation = 0;
  bool _notifiedComplete = false;

  int get _boldStart {
    final word = widget.boldWord;
    if (word == null || word.isEmpty) return -1;
    return widget.text.indexOf(word);
  }

  int get _sweepStart {
    if (!widget.sweepColorWord) return -1;
    final needle = FirstRunTutorialOverlay.colorSweepNeedle;
    final at = widget.text.indexOf(needle);
    if (at < 0) return -1;
    return at + needle.length - 5;
  }

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  @override
  void didUpdateWidget(_TypewriterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _startTyping();
      return;
    }
    if (oldWidget.skipToken != widget.skipToken &&
        _visibleChars < widget.text.length) {
      _completeNow();
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _completeWait();
    _generation++;
    super.dispose();
  }

  void _completeWait() {
    final waiting = _waiting;
    _waiting = null;
    if (waiting != null && !waiting.isCompleted) waiting.complete();
  }

  Future<void> _wait(Duration duration, int gen) {
    _delay?.cancel();
    _completeWait();
    if (!mounted || gen != _generation) return Future.value();
    final done = Completer<void>();
    _waiting = done;
    _delay = Timer(duration, () {
      if (!done.isCompleted) done.complete();
    });
    return done.future;
  }

  void _startTyping() {
    _delay?.cancel();
    final gen = ++_generation;
    _notifiedComplete = false;
    _visibleChars = 0;
    if (widget.text.isEmpty) {
      _notifyComplete();
      return;
    }
    unawaited(_runTyping(gen));
  }

  Future<void> _runTyping(int gen) async {
    var i = 0;
    while (i < widget.text.length) {
      if (!mounted || gen != _generation) return;
      if (widget.text[i] == '\n') {
        var end = i;
        while (end < widget.text.length && widget.text[end] == '\n') {
          end++;
        }
        setState(() => _visibleChars = end);
        i = end;
        await _wait(_linePause, gen);
        continue;
      }
      setState(() => _visibleChars = i + 1);
      i++;
      await _wait(_characterDuration, gen);
    }
    if (!mounted || gen != _generation) return;
    _notifyComplete();
  }

  void _completeNow() {
    _delay?.cancel();
    _completeWait();
    _generation++;
    setState(() => _visibleChars = widget.text.length);
    _notifyComplete();
  }

  void _notifyComplete() {
    if (_notifiedComplete) return;
    _notifiedComplete = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onComplete?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? const TextStyle();
    final visible = widget.text.substring(
      0,
      _visibleChars.clamp(0, widget.text.length),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return SizedBox(
          width: maxWidth,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              IgnorePointer(
                child: Opacity(
                  opacity: 0,
                  child: Text.rich(
                    _spanFor(widget.text, style, allowSweep: false),
                    textAlign: widget.textAlign,
                  ),
                ),
              ),
              Text.rich(
                _spanFor(visible, style, allowSweep: true),
                textAlign: widget.textAlign,
                overflow: TextOverflow.visible,
              ),
            ],
          ),
        );
      },
    );
  }

  TextSpan _spanFor(
    String visible,
    TextStyle style, {
    required bool allowSweep,
  }) {
    const sweepWord = 'color';
    final boldWord = widget.boldWord;
    final boldAt = _boldStart;
    final boldEnd =
        boldAt < 0 || boldWord == null ? -1 : boldAt + boldWord.length;
    final sweepAt = allowSweep ? _sweepStart : -1;
    final sweepEnd = sweepAt < 0 ? -1 : sweepAt + sweepWord.length;

    final children = <InlineSpan>[];
    var i = 0;
    while (i < visible.length) {
      if (boldAt >= 0 && i >= boldAt && i < boldEnd) {
        final end = visible.length < boldEnd ? visible.length : boldEnd;
        children.add(TextSpan(
          text: visible.substring(i, end),
          style: style.copyWith(fontWeight: FontWeight.w700),
        ));
        i = end;
        continue;
      }
      if (sweepAt >= 0 &&
          i == sweepAt &&
          visible.length >= sweepEnd) {
        children.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: _TutorialSweepLabel(text: sweepWord, style: style),
        ));
        i = sweepEnd;
        continue;
      }
      var next = visible.length;
      if (boldAt >= i && boldAt < next) next = boldAt;
      if (sweepAt >= i && sweepAt < next && visible.length >= sweepEnd) {
        next = sweepAt;
      }
      children.add(TextSpan(text: visible.substring(i, next)));
      i = next;
    }
    return TextSpan(style: style, children: children);
  }
}

/// Same delayed palette sweep used for "Irodoku" on How to Play.
class _TutorialSweepLabel extends StatefulWidget {
  final String text;
  final TextStyle? style;

  const _TutorialSweepLabel({required this.text, this.style});

  @override
  State<_TutorialSweepLabel> createState() => _TutorialSweepLabelState();
}

class _TutorialSweepLabelState extends State<_TutorialSweepLabel>
    with SingleTickerProviderStateMixin {
  static const _delay = Duration(milliseconds: 400);

  late final AnimationController _controller;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: PaletteSweepMask.duration,
    );
    _delayTimer = Timer(_delay, () {
      if (!mounted) return;
      _controller.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final settings = context.watch<SettingsProvider>();
    final colors = settings.colorsFor(settings.palette);
    final ink = style?.color ?? Theme.of(context).colorScheme.onSurface;
    final maskedStyle = style?.copyWith(color: Colors.white);
    if (colors.length < 2) {
      return Text(widget.text, style: style);
    }

    return PaletteSweepMask(
      colors: colors,
      ink: ink,
      progress: _controller,
      child: Text(widget.text, style: maskedStyle),
    );
  }
}

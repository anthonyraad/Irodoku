import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'timer_display.dart';

/// Hyperchroma clock with a brief shake and a +N / −N beside it when time
/// changes for a reason other than the one-second countdown.
class HyperchromaClockReadout extends StatefulWidget {
  final String time;
  final Color? color;
  final int pulse;
  final int pulseSerial;

  const HyperchromaClockReadout({
    super.key,
    required this.time,
    required this.pulse,
    required this.pulseSerial,
    this.color,
  });

  @override
  State<HyperchromaClockReadout> createState() =>
      _HyperchromaClockReadoutState();
}

class _HyperchromaClockReadoutState extends State<HyperchromaClockReadout>
    with TickerProviderStateMixin {
  static const _popDuration = Duration(milliseconds: 430);
  static const _inMs = 90.0;
  static const _holdMs = 240.0;

  late final AnimationController _pop;
  late final AnimationController _shake;
  int _serial = 0;
  int _shown = 0;

  @override
  void initState() {
    super.initState();
    _serial = widget.pulseSerial;
    _pop = AnimationController(vsync: this, duration: _popDuration);
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void didUpdateWidget(HyperchromaClockReadout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulseSerial == _serial || widget.pulse == 0) {
      _serial = widget.pulseSerial;
      return;
    }
    _serial = widget.pulseSerial;
    _shown = widget.pulse;
    _pop.forward(from: 0);
    _shake.forward(from: 0);
  }

  @override
  void dispose() {
    _pop.dispose();
    _shake.dispose();
    super.dispose();
  }

  double _scale(double t) {
    const inEnd = _inMs / 430;
    const outStart = (_inMs + _holdMs) / 430;
    if (t < inEnd) return Curves.easeOut.transform(t / inEnd);
    if (t < outStart) return 1;
    return 1 - Curves.easeIn.transform((t - outStart) / (1 - outStart));
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final label = _shown > 0 ? '+$_shown' : '$_shown';
    final gain = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF81C784)
        : const Color(0xFF1B7F37);
    final deltaColor = _shown < 0 ? Theme.of(context).colorScheme.error : gain;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _shake,
          builder: (context, child) {
            final t = _shake.value;
            final dx = reduce ? 0.0 : math.sin(t * math.pi * 6) * 2 * (1 - t);
            return Transform.translate(offset: Offset(dx, 0), child: child);
          },
          child: _SwiftClockColor(
            color: widget.color ??
                Theme.of(context).textTheme.titleMedium?.color ??
                Theme.of(context).colorScheme.onSurface,
            time: widget.time,
          ),
        ),
        AnimatedBuilder(
          animation: _pop,
          builder: (context, child) {
            final scale = reduce && _pop.isAnimating ? 1.0 : _scale(_pop.value);
            if (scale == 0) return const SizedBox.shrink();
            return Transform.scale(
              alignment: Alignment.centerLeft,
              scale: scale,
              child: child,
            );
          },
          child: Padding(
            padding: const EdgeInsets.only(left: 4),
            child: ExcludeSemantics(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: deltaColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Eases the Hyperchroma clock from one tint to the next. Levitate holds
/// purple, then this returns it to black or red.
class _SwiftClockColor extends StatefulWidget {
  final Color color;
  final String time;

  const _SwiftClockColor({required this.color, required this.time});

  @override
  State<_SwiftClockColor> createState() => _SwiftClockColorState();
}

class _SwiftClockColorState extends State<_SwiftClockColor>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 180);

  late final AnimationController _controller;
  late Color _from;
  late Color _to;

  @override
  void initState() {
    super.initState();
    _from = widget.color;
    _to = widget.color;
    _controller = AnimationController(vsync: this, duration: _duration)
      ..value = 1;
  }

  @override
  void didUpdateWidget(covariant _SwiftClockColor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color == widget.color) return;
    _from = Color.lerp(_from, _to, _controller.value) ?? _to;
    _to = widget.color;
    if (MediaQuery.disableAnimationsOf(context)) {
      _from = _to;
      _controller.value = 1;
      return;
    }
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeOut.transform(_controller.value);
        return TimerDisplay(
          time: widget.time,
          color: Color.lerp(_from, _to, t) ?? _to,
        );
      },
    );
  }
}

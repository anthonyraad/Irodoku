import 'package:flutter/material.dart';

import '../providers/game_provider.dart';

class MistakeDisplay extends StatefulWidget {
  final int mistakes;
  final int maxMistakes;

  const MistakeDisplay({
    super.key,
    required this.mistakes,
    this.maxMistakes = GameProvider.maxMistakes,
  });

  @override
  State<MistakeDisplay> createState() => _MistakeDisplayState();
}

class _MistakeDisplayState extends State<MistakeDisplay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  int _previousMistakes = 0;
  int? _pulsingIndex;

  @override
  void initState() {
    super.initState();
    _previousMistakes = widget.mistakes;
    // Scale-up ~255ms; scale-back is 35% longer (~345ms).
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.55 * 1.35).chain(
          CurveTween(curve: Curves.easeOutCubic),
        ),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.55 * 1.35, end: 1.0).chain(
          CurveTween(curve: Curves.easeInCubic),
        ),
        weight: 1.35,
      ),
    ]).animate(_controller);

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _pulsingIndex = null);
      }
    });
  }

  @override
  void didUpdateWidget(covariant MistakeDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mistakes > _previousMistakes &&
        widget.mistakes <= widget.maxMistakes) {
      _pulsingIndex = widget.mistakes - 1;
      _controller.forward(from: 0);
    } else if (widget.mistakes < _previousMistakes) {
      _pulsingIndex = null;
      _controller.stop();
      _controller.value = 0;
    }
    _previousMistakes = widget.mistakes;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final usedColor =
        brightness == Brightness.dark ? Colors.white : Colors.black;
    final unusedColor =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.28);

    return AnimatedBuilder(
      animation: _scale,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < widget.maxMistakes; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Transform.scale(
                scale: i == _pulsingIndex ? _scale.value : 1.0,
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CustomPaint(
                    painter: _MistakeXPainter(
                      color: i < widget.mistakes ? usedColor : unusedColor,
                      // Filled mistakes use a heavier stroke than empty slots.
                      strokeWidth: i < widget.mistakes ? 2.6 : 1.6,
                    ),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _MistakeXPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  const _MistakeXPainter({
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final inset = strokeWidth * 0.85;
    final a = Offset(inset, inset);
    final b = Offset(size.width - inset, size.height - inset);
    canvas.drawLine(a, b, paint);
    canvas.drawLine(Offset(size.width - inset, inset), Offset(inset, size.height - inset), paint);
  }

  @override
  bool shouldRepaint(covariant _MistakeXPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}

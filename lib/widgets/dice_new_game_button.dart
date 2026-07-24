import 'dart:math';

import 'package:flutter/material.dart';

/// App-bar New Game control matching Redraw's dice face + shake animation.
class DiceNewGameButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final String tooltip;

  const DiceNewGameButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'New game',
  });

  @override
  State<DiceNewGameButton> createState() => _DiceNewGameButtonState();
}

class _DiceNewGameButtonState extends State<DiceNewGameButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;
  int _diceNumber = 1;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 0.08), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.08, end: -0.08), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.08, end: 0.05), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.05, end: -0.03), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.03, end: 0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.linear,
    ));
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.onPressed == null) return;
    _shakeController.forward(from: 0);
    setState(() => _diceNumber = _random.nextInt(6) + 1);
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final color = iconTheme.color ??
        Theme.of(context).colorScheme.onSurface;

    return IconButton(
      tooltip: widget.tooltip,
      onPressed: widget.onPressed == null ? null : _handleTap,
      icon: RotationTransition(
        turns: _shakeAnimation,
        child: Opacity(
          opacity: widget.onPressed == null ? 0.38 : 1,
          child: DiceFace(
            number: _diceNumber,
            size: 22,
            color: color,
          ),
        ),
      ),
    );
  }
}

class DiceFace extends StatelessWidget {
  final int number;
  final double size;
  final Color color;

  const DiceFace({
    super.key,
    required this.number,
    required this.size,
    required this.color,
  });

  static const List<List<Offset>> _dotPositions = [
    [Offset(0.5, 0.5)],
    [Offset(0.2, 0.2), Offset(0.8, 0.8)],
    [Offset(0.2, 0.2), Offset(0.5, 0.5), Offset(0.8, 0.8)],
    [Offset(0.2, 0.2), Offset(0.8, 0.2), Offset(0.2, 0.8), Offset(0.8, 0.8)],
    [
      Offset(0.2, 0.2),
      Offset(0.8, 0.2),
      Offset(0.5, 0.5),
      Offset(0.2, 0.8),
      Offset(0.8, 0.8),
    ],
    [
      Offset(0.2, 0.2),
      Offset(0.2, 0.5),
      Offset(0.2, 0.8),
      Offset(0.8, 0.2),
      Offset(0.8, 0.5),
      Offset(0.8, 0.8),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final clamped = number.clamp(1, 6);
    final dotRadius = size * 0.1;
    final positions = _dotPositions[clamped - 1];

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DiceFacePainter(
          positions: positions,
          dotRadius: dotRadius,
          color: color,
          showFace: true,
        ),
      ),
    );
  }
}

class _DiceFacePainter extends CustomPainter {
  final List<Offset> positions;
  final double dotRadius;
  final Color color;
  final bool showFace;

  _DiceFacePainter({
    required this.positions,
    required this.dotRadius,
    required this.color,
    required this.showFace,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (showFace) {
      final facePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.shortestSide * 0.09;
      final inset = facePaint.strokeWidth / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            inset,
            inset,
            size.width - facePaint.strokeWidth,
            size.height - facePaint.strokeWidth,
          ),
          Radius.circular(size.shortestSide * 0.18),
        ),
        facePaint,
      );
    }

    final paint = Paint()..color = color;
    for (final pos in positions) {
      canvas.drawCircle(
        Offset(pos.dx * size.width, pos.dy * size.height),
        dotRadius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DiceFacePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.dotRadius != dotRadius ||
      oldDelegate.positions != positions ||
      oldDelegate.showFace != showFace;
}

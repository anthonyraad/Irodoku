import 'package:flutter/material.dart';

/// Pixel thought-cloud used as the Hyperchroma sketch mark.
///
/// A closed black outline, the same weight as the main-menu gear, wraps the
/// white cap and gray base so the top edge stays visible on a light board.
class SketchIcon extends StatelessWidget {
  /// Logical pixels per art pixel. 2 matches the menu icon's chunky pixels.
  final double pixel;

  const SketchIcon({super.key, this.pixel = 2});

  static const rows = <String>[
    '..BBBBBBBB..',
    '.BB*#####BB.',
    'BB########BB',
    'B##########B',
    'B+########oB',
    'Bo+######+oB',
    'BBo++##++oBB',
    '.BBoo++ooBB.',
    '..BBBooBBB..',
    '....BBBB....',
  ];

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(rows.first.length * pixel, rows.length * pixel),
      painter: _SketchIconPainter(pixel: pixel),
    );
  }
}

class _SketchIconPainter extends CustomPainter {
  final double pixel;

  const _SketchIconPainter({required this.pixel});

  static const _color = <String, Color>{
    'B': Color(0xFF000000),
    '#': Color(0xFFFFFFFF),
    '*': Color(0xFFD8D8D8),
    '+': Color(0xFFA0A0A0),
    'o': Color(0xFF606060),
  };

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = false;
    for (var y = 0; y < SketchIcon.rows.length; y++) {
      final row = SketchIcon.rows[y];
      for (var x = 0; x < row.length; x++) {
        final color = _color[row[x]];
        if (color == null) continue;
        paint.color = color;
        canvas.drawRect(
          Rect.fromLTWH(x * pixel, y * pixel, pixel, pixel),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SketchIconPainter oldDelegate) {
    return oldDelegate.pixel != pixel;
  }
}

/// Pops the sketch cloud when [count] goes up, matching a mistake X.
class SketchIconPulse extends StatefulWidget {
  final int count;

  const SketchIconPulse({super.key, required this.count});

  @override
  State<SketchIconPulse> createState() => _SketchIconPulseState();
}

class _SketchIconPulseState extends State<SketchIconPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late int _previous;

  @override
  void initState() {
    super.initState();
    _previous = widget.count;
    // Same pop as [MistakeDisplay]: scale-up ~255ms, scale-back ~345ms.
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
  }

  @override
  void didUpdateWidget(covariant SketchIconPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count > _previous) {
      _controller.forward(from: 0);
    } else if (widget.count < _previous) {
      _controller.stop();
      _controller.value = 0;
    }
    _previous = widget.count;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) {
        return Transform.scale(scale: _scale.value, child: child);
      },
      child: const SketchIcon(),
    );
  }
}

import 'package:flutter/material.dart';

class TimerDisplay extends StatelessWidget {
  final String time;
  final Color? color;

  const TimerDisplay({super.key, required this.time, this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      time,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

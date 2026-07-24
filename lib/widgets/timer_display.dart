import 'package:flutter/material.dart';

class TimerDisplay extends StatelessWidget {
  final String time;

  const TimerDisplay({super.key, required this.time});

  @override
  Widget build(BuildContext context) {
    return Text(
      time,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
            fontWeight: FontWeight.w500,
          ),
    );
  }
}

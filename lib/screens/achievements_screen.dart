import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/color_cycle.dart';
import '../core/palette.dart';
import '../models/achievement.dart';
import '../models/palette_swatch.dart';
import '../providers/achievements_provider.dart';
import '../widgets/typing_title.dart';

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen>
    with SingleTickerProviderStateMixin {
  static const _colorCycleDuration = Duration(milliseconds: 1050);

  late final AnimationController _colorCycleController;
  int _colorCycleSteps = 4;

  @override
  void initState() {
    super.initState();
    _colorCycleController = AnimationController(
      vsync: this,
      duration: _colorCycleDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _colorCycleController.value = 0;
        }
      });
  }

  @override
  void dispose() {
    _colorCycleController.dispose();
    super.dispose();
  }

  void _triggerColorCycle() {
    _colorCycleSteps = 4 + Random().nextInt(2); // 4 or 5
    if (_colorCycleController.isAnimating) {
      _colorCycleController.stop();
    }
    _colorCycleController.forward(from: 0);
  }

  double? _cellColorCyclePhase(int row, int col) {
    if (!_colorCycleController.isAnimating) return null;
    final global = Curves.easeInOut.transform(_colorCycleController.value);
    return ColorCycle.staggeredPhase(global, row, col);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TypingTitle(
          text: 'Achievements',
          onTap: _triggerColorCycle,
        ),
      ),
      body: Consumer<AchievementsProvider>(
        builder: (context, achievements, _) {
          return AnimatedBuilder(
            animation: _colorCycleController,
            builder: (context, _) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  const cols = 9;
                  const rows = 8;
                  const pad = 16.0;
                  const lineWidth = 1.0;
                  final maxWidth = constraints.maxWidth - pad * 2;
                  final maxHeight = constraints.maxHeight - pad * 2;
                  final cellFromWidth =
                      (maxWidth - lineWidth * (cols + 1)) / cols;
                  final cellFromHeight =
                      (maxHeight - lineWidth * (rows + 1)) / rows;
                  final cellSize = cellFromWidth < cellFromHeight
                      ? cellFromWidth
                      : cellFromHeight;
                  final gridHeight =
                      rows * cellSize + lineWidth * (rows + 1);
                  final topGap =
                      ((constraints.maxHeight - gridHeight) / 2)
                          .clamp(0.0, double.infinity) *
                      0.65;
                  final lineColor = Theme.of(context).dividerColor;

                  return Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(pad, topGap, pad, pad),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: lineColor,
                            width: lineWidth,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var r = 0; r < rows; r++) ...[
                              if (r > 0)
                                Container(
                                  height: lineWidth,
                                  color: lineColor,
                                ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (var c = 0; c < cols; c++) ...[
                                    if (c > 0)
                                      Container(
                                        width: lineWidth,
                                        height: cellSize,
                                        color: lineColor,
                                      ),
                                    _AchievementCell(
                                      achievement:
                                          Achievement.all[r * cols + c],
                                      size: cellSize,
                                      unlocked: achievements.isUnlocked(
                                        Achievement.all[r * cols + c].id,
                                      ),
                                      toastLabel: achievements.toastLabel(
                                        Achievement.all[r * cols + c],
                                      ),
                                      colorCyclePhase:
                                          _cellColorCyclePhase(r, c),
                                      colorCycleSteps: _colorCycleSteps,
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _AchievementCell extends StatelessWidget {
  final Achievement achievement;
  final double size;
  final bool unlocked;
  final String toastLabel;
  final double? colorCyclePhase;
  final int colorCycleSteps;

  const _AchievementCell({
    required this.achievement,
    required this.size,
    required this.unlocked,
    required this.toastLabel,
    this.colorCyclePhase,
    this.colorCycleSteps = 4,
  });

  @override
  Widget build(BuildContext context) {
    PaletteSwatch? swatch;
    if (unlocked) {
      swatch = colorCyclePhase != null
          ? ColorCycle.displaySwatch(
              achievement.colorValue,
              colorCyclePhase!,
              stepCount: colorCycleSteps,
              palette: achievement.palette,
            )
          : IrodokuPalette.swatchForValue(
              achievement.colorValue,
              achievement.palette,
            );
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (swatch != null)
            DecoratedBox(decoration: swatch.boxDecoration())
          else
            const ColoredBox(color: Colors.white),
          Material(
            color: Colors.transparent,
            child: InkWell(onTap: () => _showTitle(context)),
          ),
        ],
      ),
    );
  }

  void _showTitle(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(toastLabel),
        ),
      );
  }
}

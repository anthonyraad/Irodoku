import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/color_cycle.dart';
import '../core/palette.dart';
import '../models/achievement.dart';
import '../models/palette_swatch.dart';
import '../providers/achievements_provider.dart';
import '../widgets/circle_reveal_clipper.dart';
import '../widgets/typing_title.dart';

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen>
    with TickerProviderStateMixin {
  static const _colorCycleDuration = Duration(milliseconds: 1050);
  static const _revealDelay = Duration(milliseconds: 300);
  static const _revealDuration = Duration(milliseconds: 520);

  late final AnimationController _colorCycleController;
  late final AnimationController _revealController;
  int _colorCycleSteps = 4;

  /// Unlocked since last Achievements visit; animate these on open.
  Set<String> _revealIds = {};
  bool _revealArmed = false;
  bool _revealPlaying = false;

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
    _revealController = AnimationController(
      vsync: this,
      duration: _revealDuration,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final achievements = context.read<AchievementsProvider>();
      final unseen = achievements.unseenUnlockedIds;
      // Mark seen immediately so a later visit won't re-play these.
      unawaited(achievements.markUnlockedAchievementsSeen());
      if (unseen.isEmpty) return;
      setState(() {
        _revealIds = unseen;
        _revealArmed = true;
      });
      Future<void>.delayed(_revealDelay, () {
        if (!mounted) return;
        setState(() => _revealPlaying = true);
        _revealController.forward(from: 0);
      });
    });
  }

  @override
  void dispose() {
    _colorCycleController.dispose();
    _revealController.dispose();
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
            animation: Listenable.merge([
              _colorCycleController,
              _revealController,
            ]),
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
                  final revealT =
                      Curves.easeOutCubic.transform(_revealController.value);

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
                                    Builder(
                                      builder: (context) {
                                        final achievement =
                                            Achievement.all[r * cols + c];
                                        final unlocked = achievements
                                            .isUnlocked(achievement.id);
                                        final isNewReveal = _revealArmed &&
                                            _revealIds
                                                .contains(achievement.id);
                                        // Hold as locked until the delayed reveal runs.
                                        final showUnlocked = unlocked &&
                                            (!isNewReveal || _revealPlaying);
                                        final fillReveal = isNewReveal
                                            ? (_revealPlaying ? revealT : 0.0)
                                            : (showUnlocked ? 1.0 : 0.0);

                                        return _AchievementCell(
                                          achievement: achievement,
                                          size: cellSize,
                                          unlocked: showUnlocked,
                                          fillReveal: fillReveal,
                                          toastLabel:
                                              achievements.toastLabel(
                                            achievement,
                                          ),
                                          colorCyclePhase:
                                              _cellColorCyclePhase(r, c),
                                          colorCycleSteps: _colorCycleSteps,
                                        );
                                      },
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
  final double fillReveal;
  final String toastLabel;
  final double? colorCyclePhase;
  final int colorCycleSteps;

  const _AchievementCell({
    required this.achievement,
    required this.size,
    required this.unlocked,
    required this.fillReveal,
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

    final reveal = fillReveal.clamp(0.0, 1.0);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.white),
          if (swatch != null)
            ClipPath(
              clipper: CircleRevealClipper(fraction: reveal),
              child: DecoratedBox(decoration: swatch.boxDecoration()),
            ),
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

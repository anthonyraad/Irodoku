import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/palette.dart';
import '../core/theme.dart';
import '../models/difficulty.dart';
import '../models/game_palette.dart';
import '../providers/game_provider.dart';
import '../providers/stats_provider.dart';
import '../widgets/menu_select_sound.dart';
import '../widgets/typing_title.dart';
import '../widgets/xp_gain_panel.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  bool _showChromatic = false;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).appBarTheme.titleTextStyle ??
        Theme.of(context).textTheme.titleLarge;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Deeper (light mode) / brighter (dark mode) stops so no band washes out
    // against the app bar — especially yellow on light gray.
    final rainbowColors = isDark
        ? const [
            Color(0xFFFF8A80),
            Color(0xFFFFB74D),
            Color(0xFFFFD54F),
            Color(0xFF81C784),
            Color(0xFF64B5F6),
            Color(0xFFCE93D8),
          ]
        : const [
            Color(0xFFB71C1C),
            Color(0xFFE65100),
            Color(0xFFF9A825),
            Color(0xFF2E7D32),
            Color(0xFF1565C0),
            Color(0xFF6A1B9A),
          ];
    final title = TypingTitle(
      text: 'Stats',
      style: _showChromatic
          ? titleStyle?.copyWith(color: Colors.white)
          : titleStyle,
    );

    return Scaffold(
      appBar: AppBar(
        leading: const MenuBackButton(),
        title: _showChromatic
            ? Stack(
                alignment: Alignment.center,
                children: [
                  // Soft silhouette so thin Balatro strokes stay legible.
                  TypingTitle(
                    text: 'Stats',
                    style: titleStyle?.copyWith(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.55)
                          : Colors.white.withValues(alpha: 0.9),
                      shadows: [
                        Shadow(
                          color: isDark
                              ? Colors.black.withValues(alpha: 0.65)
                              : Colors.white.withValues(alpha: 0.95),
                          blurRadius: 2,
                          offset: const Offset(0, 0.5),
                        ),
                      ],
                    ),
                  ),
                  ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (bounds) => LinearGradient(
                      colors: rainbowColors,
                    ).createShader(
                      Rect.fromLTWH(0, 0, bounds.width, bounds.height),
                    ),
                    child: title,
                  ),
                ],
              )
            : title,
      ),
      body: Consumer2<StatsProvider, GameProvider>(
        builder: (context, statsProvider, game, _) {
          final stats = statsProvider.stats;
          final showChromaticButton = statsProvider.areAllMenuPalettesUnlocked;
          final bottomInset = MediaQuery.paddingOf(context).bottom;

          return Stack(
            children: [
              ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  showChromaticButton ? 72 + bottomInset : 16,
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: _LevelCard(totalXp: stats.totalXp),
                  ),
                  if (_showChromatic) ...[
                    _StatCard(
                      children: [
                        _StatRow(
                          label: 'Games won',
                          value: '${stats.chromaticGamesWon}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const _DifficultyStatsHeader(),
                    const SizedBox(height: 8),
                    _StatCard(
                      children: [
                        for (final difficulty in Difficulty.values)
                          _DifficultyStatsRow(
                            difficulty: difficulty.label,
                            bestTime: _formatBest(
                              stats.chromaticBestTimeFor(difficulty),
                            ),
                            wins: '${stats.chromaticWinsFor(difficulty)}',
                          ),
                      ],
                    ),
                  ] else ...[
                    _StatCard(
                      children: [
                        _StatRow(
                          label: 'Games won',
                          value: '${stats.gamesWon}',
                        ),
                        _StatRow(
                          label: 'Game streak',
                          value: '${stats.bestStreak}',
                          indent: true,
                        ),
                        _StatRow(
                          label: 'Daily streak',
                          value: '${game.dailyBestStreak}',
                          indent: true,
                        ),
                        _StatRow(
                          label: 'Graffiti record',
                          value: stats.graffitiRecordLabel,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const _DifficultyStatsHeader(),
                    const SizedBox(height: 8),
                    _StatCard(
                      children: [
                        for (final difficulty in Difficulty.values)
                          _DifficultyStatsRow(
                            difficulty: difficulty.label,
                            bestTime: _formatBest(
                              stats.bestTimeFor(difficulty),
                            ),
                            wins: '${stats.winsFor(difficulty)}',
                          ),
                      ],
                    ),
                    if (stats.favoritePalette case final favoritePalette?) ...[
                      const SizedBox(height: 20),
                      _StatCard(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: _PalettePreviewRow(palette: favoritePalette),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
              if (showChromaticButton)
                Positioned(
                  right: 16,
                  bottom: 12 + bottomInset,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      textStyle: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    onPressed: withMenuSelect(context, () {
                      setState(() => _showChromatic = !_showChromatic);
                    }),
                    child: Text(
                      _showChromatic ? '< All' : 'Chromatic >',
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String _formatBest(Duration? duration) {
    if (duration == null) return '—';
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}

class _PalettePreviewRow extends StatelessWidget {
  final GamePalette palette;

  const _PalettePreviewRow({required this.palette});

  @override
  Widget build(BuildContext context) {
    final line = IrodokuTheme.thinGridLine(IrodokuTheme.boardBrightness);
    final swatches = IrodokuPalette.swatchesFor(palette);

    return LayoutBuilder(
      builder: (context, constraints) {
        final swatchSize = constraints.maxWidth / 9;

        return SizedBox(
          height: swatchSize,
          child: Row(
            children: [
              for (var i = 0; i < 9; i++)
                SizedBox(
                  width: swatchSize,
                  height: swatchSize,
                  child: DecoratedBox(
                    decoration: swatches[i].boxDecoration(
                      border: Border.all(
                        color:
                            IrodokuPalette.outlineForValue(i + 1, palette) ??
                            line,
                        width: IrodokuPalette.outlineForValue(i + 1, palette) !=
                                null
                            ? 1.5
                            : 0.6,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _LevelCard extends StatelessWidget {
  final int totalXp;

  const _LevelCard({required this.totalXp});

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ??
            Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: XpLevelBar(totalXp: totalXp, ink: ink),
    );
  }
}

class _StatCard extends StatelessWidget {
  final List<Widget> children;

  const _StatCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ??
            Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: Theme.of(context).dividerColor,
              ),
          ],
        ],
      ),
    );
  }
}

class _DifficultyStatsHeader extends StatelessWidget {
  const _DifficultyStatsHeader();

  static TextStyle? _headerStyle(BuildContext context) {
    return Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface,
        );
  }

  @override
  Widget build(BuildContext context) {
    final style = _headerStyle(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text('Difficulty', style: style),
          ),
          Expanded(
            flex: 5,
            child: Text('Best time', style: style),
          ),
          Expanded(
            flex: 2,
            child: Text('Wins', style: style, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

class _DifficultyStatsRow extends StatelessWidget {
  final String difficulty;
  final String bestTime;
  final String wins;

  const _DifficultyStatsRow({
    required this.difficulty,
    required this.bestTime,
    required this.wins,
  });

  @override
  Widget build(BuildContext context) {
    final valueStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(difficulty, style: Theme.of(context).textTheme.bodyLarge),
          ),
          Expanded(
            flex: 5,
            child: Text(bestTime, style: valueStyle),
          ),
          Expanded(
            flex: 2,
            child: Text(wins, style: valueStyle, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final bool indent;

  const _StatRow({
    required this.label,
    required this.value,
    this.indent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(indent ? 28 : 16, 10, 16, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyLarge),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
      ),
    );
  }
}

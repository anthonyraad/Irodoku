import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/palette.dart';
import '../core/theme.dart';
import '../models/difficulty.dart';
import '../models/game_palette.dart';
import '../providers/stats_provider.dart';
import '../widgets/typing_title.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const TypingTitle(text: 'Stats'),
      ),
      body: Consumer<StatsProvider>(
        builder: (context, statsProvider, _) {
          final stats = statsProvider.stats;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatCard(
                children: [
                  _StatRow(label: 'Current streak', value: '${stats.currentStreak}'),
                  _StatRow(label: 'Best streak', value: '${stats.bestStreak}'),
                  _StatRow(label: 'Games won', value: '${stats.gamesWon}'),
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
                      bestTime: _formatBest(stats.bestTimeFor(difficulty)),
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
    final colors = IrodokuPalette.colorsFor(palette);

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
                    decoration: BoxDecoration(
                      color: colors[i],
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
          color: Colors.black,
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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

  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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

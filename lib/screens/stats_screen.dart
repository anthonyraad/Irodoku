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
  /// Main Menu [Stats]: Pocket / [Chromatic] wins and best times only.
  final bool pocket;

  const StatsScreen({super.key, this.pocket = false});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  bool _showChromatic = false;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).appBarTheme.titleTextStyle ??
        Theme.of(context).textTheme.titleLarge;

    return Scaffold(
      appBar: AppBar(
        leading: const MenuBackButton(),
        title: TypingTitle(
          text: widget.pocket ? '[Stats]' : 'Stats',
          style: titleStyle,
        ),
      ),
      body: Consumer2<StatsProvider, GameProvider>(
        builder: (context, statsProvider, game, _) {
          final stats = statsProvider.stats;
          final showChromaticButton =
              !widget.pocket && statsProvider.areAllMenuPalettesUnlocked;
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
                  if (widget.pocket) ...[
                    _StatCard(
                      children: [
                        _StatRow(
                          label: 'Games won',
                          value: '${stats.pocketGamesWon}',
                        ),
                        _StatRow(
                          label: '[Pocket] streak',
                          value: '${stats.pocketBestStreak}',
                          indent: true,
                        ),
                        _StatRow(
                          label: '[Chromatic] streak',
                          value: '${stats.pocketChromaticBestStreak}',
                          indent: true,
                        ),
                        _StatRow(
                          label: '[Daily] streak',
                          value: '${game.pocketDailyBestStreak}',
                          indent: true,
                        ),
                        _StatRow(
                          label: '[Graffiti] record',
                          value: stats.pocketGraffitiRecordLabel,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const _DifficultyStatsHeader(firstColumn: 'Mode'),
                    const SizedBox(height: 8),
                    _StatCard(
                      children: [
                        _DifficultyStatsRow(
                          difficulty: '[Pocket]',
                          bestTime: _formatBest(stats.pocketBestTime),
                          wins: '${stats.pocketWins}',
                        ),
                        _DifficultyStatsRow(
                          difficulty: '[Chromatic]',
                          bestTime: _formatBest(stats.pocketChromaticBestTime),
                          wins: '${stats.pocketChromaticWins}',
                        ),
                        _DifficultyStatsRow(
                          difficulty: '[Daily]',
                          bestTime: _formatBest(stats.pocketDailyBestTime),
                          wins: '${stats.pocketDailyWins}',
                        ),
                      ],
                    ),
                    if (stats.favoritePocketPalette
                        case final favoritePalette?) ...[
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
                  ] else ...[
                    _GamesWonCard(
                    chromatic: _showChromatic,
                    gamesWon: stats.gamesWon,
                    chromaticGamesWon: stats.chromaticGamesWon,
                    bestStreak: stats.bestStreak,
                    dailyBestStreak: game.dailyBestStreak,
                    graffitiRecord: stats.graffitiRecordLabel,
                  ),
                  const SizedBox(height: 20),
                  const _DifficultyStatsHeader(),
                  const SizedBox(height: 8),
                  if (_showChromatic) ...[
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

class _GamesWonCard extends StatefulWidget {
  final bool chromatic;
  final int gamesWon;
  final int chromaticGamesWon;
  final int bestStreak;
  final int dailyBestStreak;
  final String graffitiRecord;

  const _GamesWonCard({
    required this.chromatic,
    required this.gamesWon,
    required this.chromaticGamesWon,
    required this.bestStreak,
    required this.dailyBestStreak,
    required this.graffitiRecord,
  });

  @override
  State<_GamesWonCard> createState() => _GamesWonCardState();
}

class _GamesWonCardState extends State<_GamesWonCard>
    with SingleTickerProviderStateMixin {
  static const _staggerMs = 68;
  static const _popMs = 153;
  static const _extraCount = 3;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: _staggerMs * (_extraCount - 1) + _popMs,
      ),
      value: widget.chromatic ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(covariant _GamesWonCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chromatic == widget.chromatic) return;
    if (widget.chromatic) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Animation<double> _extraCollapse(int extraIndex) {
    final totalMs = _staggerMs * (_extraCount - 1) + _popMs;
    final startMs = _staggerMs * (_extraCount - 1 - extraIndex);
    return CurvedAnimation(
      parent: _controller,
      curve: Interval(
        startMs / totalMs,
        (startMs + _popMs) / totalMs,
        curve: Curves.easeInCubic,
      ),
    );
  }

  Widget _collapsingExtra({
    required int extraIndex,
    required Widget row,
  }) {
    final collapse = _extraCollapse(extraIndex);
    final hide = Tween<double>(begin: 1, end: 0).animate(collapse);
    return SizeTransition(
      sizeFactor: hide,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: hide,
        child: ScaleTransition(
          alignment: Alignment.topCenter,
          scale: hide,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: Theme.of(context).dividerColor,
              ),
              row,
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ??
            Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _StatRow(
            label: 'Games won',
            value:
                '${widget.chromatic ? widget.chromaticGamesWon : widget.gamesWon}',
          ),
          _collapsingExtra(
            extraIndex: 0,
            row: _StatRow(
              label: 'Game streak',
              value: '${widget.bestStreak}',
              indent: true,
            ),
          ),
          _collapsingExtra(
            extraIndex: 1,
            row: _StatRow(
              label: 'Daily streak',
              value: '${widget.dailyBestStreak}',
              indent: true,
            ),
          ),
          _collapsingExtra(
            extraIndex: 2,
            row: _StatRow(
              label: 'Graffiti record',
              value: widget.graffitiRecord,
            ),
          ),
        ],
      ),
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
  final String firstColumn;

  const _DifficultyStatsHeader({this.firstColumn = 'Difficulty'});

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
            child: Text(firstColumn, style: style),
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

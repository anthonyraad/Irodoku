import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/irodoku_page_route.dart';
import '../core/palette.dart';
import '../core/theme.dart';
import '../models/daily_irodoku.dart';
import '../models/difficulty.dart';
import '../models/game_palette.dart';
import '../models/game_stats.dart';
import '../providers/game_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/stats_provider.dart';
import '../widgets/start_new_game_dialog.dart';
import 'achievements_screen.dart';
import 'game_screen.dart';
import 'iroen_screen.dart';
import 'stats_screen.dart';

class SettingsScreen extends StatefulWidget {
  /// Cold-start: immediately push today's Daily after this menu appears.
  final bool openDailyOnLaunch;

  const SettingsScreen({super.key, this.openDailyOnLaunch = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _titleIconRevealDelay = Duration(milliseconds: 160);

  bool _titleIconsVisible = false;
  int _titleIconGeneration = 0;
  Timer? _titleIconTimer;
  Timer? _midnightTimer;
  bool _openingDaily = false;

  /// Scale title icons in after a short beat (title text stays static).
  void _scheduleTitleIcons() {
    _titleIconTimer?.cancel();
    final gen = ++_titleIconGeneration;
    setState(() => _titleIconsVisible = false);
    _titleIconTimer = Timer(_titleIconRevealDelay, () {
      if (!mounted || gen != _titleIconGeneration) return;
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
      setState(() => _titleIconsVisible = true);
    });
  }

  /// Hide title icons before a subpage covers this route so they aren't
  /// still visible when the user pops back.
  void _hideTitleIcons() {
    _titleIconTimer?.cancel();
    _titleIconGeneration++;
    if (!_titleIconsVisible) return;
    setState(() => _titleIconsVisible = false);
  }

  @override
  void initState() {
    super.initState();
    _scheduleMidnightRefresh();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scheduleTitleIcons();
    });
    if (widget.openDailyOnLaunch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final stats = context.read<StatsProvider>();
        _onDailyPressed(
          context,
          context.read<GameProvider>(),
          unlocked: stats.isDailyChallengeUnlocked,
          stats: stats.stats,
        );
      });
    }
  }

  @override
  void dispose() {
    _titleIconTimer?.cancel();
    _midnightTimer?.cancel();
    super.dispose();
  }

  /// Rebuild at PST midnight so the Daily button unlocks without relaunch.
  void _scheduleMidnightRefresh() {
    _midnightTimer?.cancel();
    _midnightTimer = Timer(
      DailyIrodoku.timeUntilNextReset() + const Duration(seconds: 1),
      () {
        if (!mounted) return;
        setState(() {});
        _scheduleMidnightRefresh();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: IrodokuTheme.settingsTheme(Theme.of(context)),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          await context.read<GameProvider>().leaveMenuToRegular();
          if (context.mounted) Navigator.of(context).pop();
        },
        child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MainMenuTitleIcon(visible: _titleIconsVisible),
              const SizedBox(width: 8),
              Text(
                'Main Menu',
                style: Theme.of(context).appBarTheme.titleTextStyle,
              ),
              const SizedBox(width: 8),
              _MainMenuTitleIcon(visible: _titleIconsVisible),
            ],
          ),
        ),
        body: Consumer3<SettingsProvider, StatsProvider, GameProvider>(
        builder: (context, settings, statsProvider, game, _) {
          final stats = statsProvider.stats;
          final chromaticUnlocked = statsProvider.areAllMenuPalettesUnlocked;
          final dailyUnlocked = statsProvider.isDailyChallengeUnlocked;
          final dailyFinished = game.isDailyFinishedToday;
          final dailyStreak = game.dailyStreakDisplay;
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: _PlayModeGrid(
                  busy: game.isGenerating,
                  dailyUnlocked: dailyUnlocked,
                  dailyFinished: dailyFinished,
                  dailyStreak: dailyStreak,
                  chromaticUnlocked: chromaticUnlocked,
                  iroenUnlocked: statsProvider.isIroenUnlocked,
                  onClassic: () => _onClassicPressed(context, game),
                  onDaily: () => _onDailyPressed(
                    context,
                    game,
                    unlocked: dailyUnlocked,
                    stats: stats,
                  ),
                  onChromatic: () => _onChromaticPressed(
                    context,
                    game,
                    unlocked: chromaticUnlocked,
                  ),
                  onIroen: () => _onIroenPressed(
                    context,
                    stats,
                    unlocked: statsProvider.isIroenUnlocked,
                  ),
                ),
              ),
              const Divider(height: 32),
              const _SectionHeader(title: 'Config'),
              ListTile(
                title: const Text('Difficulty'),
                trailing: DropdownButtonHideUnderline(
                  child: DropdownButton<Difficulty>(
                    value: settings.difficulty,
                    alignment: AlignmentDirectional.centerEnd,
                    items: [
                      for (final difficulty in Difficulty.values)
                        DropdownMenuItem(
                          value: difficulty,
                          child: _LockedMenuItem(
                            label: difficulty.label,
                            unlocked: statsProvider.isUnlocked(difficulty),
                          ),
                        ),
                    ],
                    selectedItemBuilder: (context) => [
                      for (final difficulty in Difficulty.values)
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: Text(difficulty.label),
                        ),
                    ],
                    onChanged: (difficulty) {
                      if (difficulty == null) return;
                      if (!statsProvider.isUnlocked(difficulty)) {
                        _showUnlockSnackBar(context, difficulty, stats);
                        return;
                      }
                      if (difficulty == settings.difficulty) return;
                      _onDifficultyChosen(context, settings, difficulty);
                    },
                  ),
                ),
              ),
              _CompactSwitchRow(
                label: 'Sound',
                value: settings.soundEnabled,
                onChanged: settings.setSoundEnabled,
              ),
              _CompactSwitchRow(
                label: 'Dark mode',
                value: settings.darkMode,
                onChanged: settings.setDarkMode,
              ),
              ListTile(
                title: const Text('Palette'),
                trailing: DropdownButtonHideUnderline(
                  child: DropdownButton<GamePalette>(
                    value: settings.palette,
                    alignment: AlignmentDirectional.centerEnd,
                    items: [
                      for (final palette in GamePalette.menuValues)
                        DropdownMenuItem(
                          value: palette,
                          child: _LockedMenuItem(
                            label: palette.label,
                            unlocked: statsProvider.isPaletteUnlocked(palette),
                          ),
                        ),
                    ],
                    selectedItemBuilder: (context) => [
                      for (final palette in GamePalette.menuValues)
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: Text(palette.label),
                        ),
                    ],
                    onChanged: (palette) {
                      if (palette == null) return;
                      if (!statsProvider.isPaletteUnlocked(palette)) {
                        _showPaletteLockedSnackBar(context, palette);
                        return;
                      }
                      if (palette == settings.palette) return;
                      _onPaletteChosen(context, settings, palette);
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: _PalettePreviewRow(palette: settings.palette),
              ),
              const Divider(height: 32),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _PlayModeButton(
                        label: 'Stats',
                        onPressed: () async {
                          _hideTitleIcons();
                          await Navigator.of(context).push(
                            IrodokuPageRoute(
                              builder: (_) => const StatsScreen(),
                            ),
                          );
                          if (!mounted) return;
                          _scheduleTitleIcons();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _PlayModeButton(
                        label: 'Achievements',
                        onPressed: () async {
                          _hideTitleIcons();
                          await Navigator.of(context).push(
                            IrodokuPageRoute(
                              builder: (_) => const AchievementsScreen(),
                            ),
                          );
                          if (!mounted) return;
                          _scheduleTitleIcons();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      ),
      ),
    );
  }

  Future<void> _onClassicPressed(
    BuildContext context,
    GameProvider game,
  ) async {
    await game.openClassicGame();
    if (!context.mounted) return;
    // Route through PopScope so leaveMenuToRegular runs once.
    await Navigator.of(context).maybePop();
  }

  Future<void> _onChromaticPressed(
    BuildContext context,
    GameProvider game, {
    required bool unlocked,
  }) async {
    if (!unlocked) {
      _showChromaticLockedSnackBar(context);
      return;
    }
    final started = await game.openChromaticGame();
    if (!context.mounted || !started) return;
    await Navigator.of(context).maybePop();
  }

  Future<void> _onIroenPressed(
    BuildContext context,
    GameStats stats, {
    required bool unlocked,
  }) async {
    if (!unlocked) {
      _showIroenLockedSnackBar(context, stats);
      return;
    }
    _hideTitleIcons();
    await Navigator.of(context).push(
      IrodokuPageRoute(builder: (_) => const IroenScreen()),
    );
    if (!mounted) return;
    _scheduleTitleIcons();
  }

  Future<void> _onDailyPressed(
    BuildContext context,
    GameProvider game, {
    required bool unlocked,
    required GameStats stats,
  }) async {
    if (_openingDaily || game.isGenerating) return;
    if (!unlocked) {
      _showDailyLockedSnackBar(context, stats);
      return;
    }
    _openingDaily = true;
    try {
      final started = await game.startDailyGame();
      if (!context.mounted || !started) return;
      _hideTitleIcons();
      await Navigator.of(context).push(
        IrodokuPageRoute(builder: (_) => const GameScreen(isDailyRoute: true)),
      );
      if (!mounted) return;
      _scheduleTitleIcons();
    } finally {
      _openingDaily = false;
    }
  }

  void _showDailyLockedSnackBar(BuildContext context, GameStats stats) {
    const need = GameStats.dailyChallengeUnlockMediumWins;
    final have = stats.winsFor(Difficulty.medium);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: SizedBox(
            width: double.infinity,
            child: Text.rich(
              TextSpan(
                style: Theme.of(context).snackBarTheme.contentTextStyle ??
                    TextStyle(
                      color: Theme.of(context).colorScheme.onInverseSurface,
                    ),
                children: [
                  TextSpan(text: 'Win $need '),
                  const TextSpan(
                    text: 'Medium',
                    style: TextStyle(
                      color: Colors.lightBlueAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(text: ' game ($have/$need)'),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
  }

  void _showChromaticLockedSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: SizedBox(
            width: double.infinity,
            child: Text(
              'Unlock every palette',
              textAlign: TextAlign.center,
              style: Theme.of(context).snackBarTheme.contentTextStyle ??
                  TextStyle(
                    color: Theme.of(context).colorScheme.onInverseSurface,
                  ),
            ),
          ),
        ),
      );
  }

  void _showIroenLockedSnackBar(BuildContext context, GameStats stats) {
    const need = GameStats.iroenUnlockWinsRequired;
    final have = stats.gamesWon;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: SizedBox(
            width: double.infinity,
            child: Text.rich(
              TextSpan(
                style: Theme.of(context).snackBarTheme.contentTextStyle ??
                    TextStyle(
                      color: Theme.of(context).colorScheme.onInverseSurface,
                    ),
                children: [
                  const TextSpan(text: 'Win '),
                  TextSpan(
                    text: '$need',
                    style: const TextStyle(
                      color: Colors.lightBlueAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(text: ' games ($have/$need)'),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
  }

  Future<void> _onDifficultyChosen(
    BuildContext context,
    SettingsProvider settings,
    Difficulty difficulty,
  ) async {
    final game = context.read<GameProvider>();
    await settings.setDifficulty(difficulty);
    if (!context.mounted) return;
    if (game.isGenerating) return;

    // Daily still live under Main Menu — only update the setting so parked
    // Classic/Chromatic progress is not wiped.
    if (game.isDaily) return;

    final preserveDaily = game.hasResumableDaily;

    // Mid-game: ask before discarding progress.
    if (game.hasInteracted && !game.isGameOver) {
      final startNew = await showStartNewGameDialog(context);
      if (!context.mounted) return;
      if (startNew == true) {
        await game.startNewGame(preserveHeldDaily: preserveDaily);
      }
      return;
    }

    // Untouched board (or finished game): apply immediately.
    if (game.hasActiveGame || game.isGameOver) {
      await game.startNewGame(preserveHeldDaily: preserveDaily);
    }
  }

  Future<void> _onPaletteChosen(
    BuildContext context,
    SettingsProvider settings,
    GamePalette palette,
  ) async {
    final game = context.read<GameProvider>();
    if (game.isGenerating) return;

    // Daily / Chromatic nested under menu: update the saved Config palette only.
    // Live Chromatic hops use a session palette and must not be overwritten here.
    if (game.isDaily || settings.chromatic) {
      await settings.setPalette(palette);
      return;
    }

    final preserveDaily = game.hasResumableDaily;

    // Mid-game: palette stays put unless the user starts a new puzzle.
    if (game.hasInteracted && !game.isGameOver) {
      final startNew = await showStartNewGameDialog(context);
      if (!context.mounted) return;
      if (startNew != true) return;
      await game.startNewGame(preserveHeldDaily: preserveDaily);
      await settings.setPalette(palette);
      return;
    }

    await settings.setPalette(palette);
  }

  void _showUnlockSnackBar(
    BuildContext context,
    Difficulty difficulty,
    GameStats stats,
  ) {
    final prerequisite = difficulty.unlockPrerequisite;
    if (prerequisite == null) return;
    final have = stats.winsFor(prerequisite);
    final need = Difficulty.unlockWinsRequired;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: SizedBox(
            width: double.infinity,
            child: Text.rich(
              TextSpan(
                style: Theme.of(context).snackBarTheme.contentTextStyle ??
                    TextStyle(
                      color: Theme.of(context).colorScheme.onInverseSurface,
                    ),
                children: [
                  TextSpan(text: 'Win $need '),
                  TextSpan(
                    text: prerequisite.label,
                    style: const TextStyle(
                      color: Colors.lightBlueAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(text: ' games ($have/$need)'),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
  }

  void _showPaletteLockedSnackBar(BuildContext context, GamePalette palette) {
    const highlightStyle = TextStyle(
      color: Colors.lightBlueAccent,
      fontWeight: FontWeight.w600,
    );
    final baseStyle = Theme.of(context).snackBarTheme.contentTextStyle ??
        TextStyle(color: Theme.of(context).colorScheme.onInverseSurface);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: SizedBox(
            width: double.infinity,
            child: Text.rich(
              TextSpan(
                style: baseStyle,
                children: [
                  for (final part in palette.unlockRequirementParts)
                    TextSpan(
                      text: part.text,
                      style: part.highlight ? highlightStyle : null,
                    ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
  }
}

class _MainMenuTitleIcon extends StatelessWidget {
  static const _asset = 'assets/icons/settings.png';
  static const _size = 22.0 * 0.85;

  final bool visible;

  const _MainMenuTitleIcon({required this.visible});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: AnimatedScale(
        scale: visible ? 1 : 0,
        // Snap off instantly so a replay never leaves leftover icons.
        duration: visible
            ? const Duration(milliseconds: 180)
            : Duration.zero,
        curve: Curves.easeOutBack,
        child: Image.asset(
          _asset,
          width: _size,
          height: _size,
          filterQuality: FilterQuality.none,
        ),
      ),
    );
  }
}

class _PlayModeGrid extends StatelessWidget {
  final bool busy;
  final bool dailyUnlocked;
  final bool dailyFinished;
  final int dailyStreak;
  final bool chromaticUnlocked;
  final bool iroenUnlocked;
  final VoidCallback onClassic;
  final VoidCallback onDaily;
  final VoidCallback onChromatic;
  final VoidCallback onIroen;

  const _PlayModeGrid({
    required this.busy,
    required this.dailyUnlocked,
    required this.dailyFinished,
    required this.dailyStreak,
    required this.chromaticUnlocked,
    required this.iroenUnlocked,
    required this.onClassic,
    required this.onDaily,
    required this.onChromatic,
    required this.onIroen,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PlayModeButton(
          label: 'Classic Game',
          enabled: !busy,
          onPressed: onClassic,
        ),
        const SizedBox(height: 12),
        _PlayModeButton(
          label: 'Daily Challenge',
          trailing: dailyUnlocked && dailyStreak > 0 ? 'x$dailyStreak' : null,
          enabled: !busy,
          muted: dailyUnlocked && dailyFinished,
          locked: !dailyUnlocked,
          onPressed: onDaily,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _PlayModeButton(
                label: 'Chromatic',
                enabled: !busy,
                locked: !chromaticUnlocked,
                onPressed: onChromatic,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PlayModeButton(
                label: 'Iroen',
                enabled: true,
                locked: !iroenUnlocked,
                onPressed: onIroen,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PlayModeButton extends StatelessWidget {
  static const _borderRadius = BorderRadius.all(Radius.circular(8));

  final String label;
  final String? trailing;
  final bool enabled;
  final bool muted;
  final bool locked;
  final VoidCallback onPressed;

  const _PlayModeButton({
    required this.label,
    required this.onPressed,
    this.trailing,
    this.enabled = true,
    this.muted = false,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final interactive = enabled;
    // Match the old Daily Iro button: muted fill/border when finished or locked.
    final visuallyMuted = muted || locked || !interactive;
    final ink = scheme.onSurface.withValues(alpha: visuallyMuted ? 0.55 : 1);
    final border = visuallyMuted ? scheme.outlineVariant : scheme.onSurface;
    final fill =
        visuallyMuted ? scheme.surfaceContainerHighest : scheme.surface;

    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: _borderRadius,
          boxShadow: interactive && !visuallyMuted
              ? [
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: 0.26),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: fill,
          shape: RoundedRectangleBorder(
            borderRadius: _borderRadius,
            side: BorderSide(color: border, width: 2.5),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: interactive ? onPressed : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: _PlayModeLabel(
                      label: label,
                      color: ink,
                      struckThrough: muted,
                    ),
                  ),
                  if (locked) ...[
                    const SizedBox(width: 10),
                    Icon(Icons.lock_outline, size: 20, color: ink),
                  ] else if (trailing != null) ...[
                    const SizedBox(width: 10),
                    Text(
                      trailing!,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: ink,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Label with an optional strikethrough raised into the letter mid-height.
class _PlayModeLabel extends StatelessWidget {
  final String label;
  final Color color;
  final bool struckThrough;

  const _PlayModeLabel({
    required this.label,
    required this.color,
    required this.struckThrough,
  });

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        );

    final text = Text(label, textAlign: TextAlign.center, style: style);
    if (!struckThrough) return text;

    return Stack(
      alignment: Alignment.center,
      children: [
        text,
        // Default TextDecoration.lineThrough sits low; nudge into x-height.
        Positioned.fill(
          child: IgnorePointer(
            child: Align(
              alignment: const Alignment(0, 0.09),
              child: ColoredBox(
                color: color,
                child: const SizedBox(height: 1.5, width: double.infinity),
              ),
            ),
          ),
        ),
      ],
    );
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

class _LockedMenuItem extends StatelessWidget {
  final String label;
  final bool unlocked;

  const _LockedMenuItem({
    required this.label,
    required this.unlocked,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.38);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: unlocked
              ? null
              : Theme.of(context).textTheme.bodyMedium?.copyWith(color: muted),
        ),
        if (!unlocked) ...[
          const SizedBox(width: 8),
          Icon(Icons.lock_outline, size: 16, color: muted),
        ],
      ],
    );
  }
}

class _CompactSwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _CompactSwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      title: Text(label),
      trailing: Transform.scale(
        scale: 0.82,
        alignment: Alignment.centerRight,
        child: Switch(
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          value: value,
          onChanged: onChanged,
        ),
      ),
      onTap: () => onChanged(!value),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.labelLarge;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      child: Text(
        title,
        style: base?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
              fontSize: (base.fontSize ?? 14) * 0.92,
            ),
      ),
    );
  }
}

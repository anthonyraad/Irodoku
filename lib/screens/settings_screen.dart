import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/irodoku_page_route.dart';
import '../core/theme.dart';
import '../models/daily_irodoku.dart';
import '../models/difficulty.dart';
import '../models/game_stats.dart';
import '../providers/game_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/stats_provider.dart';
import '../widgets/menu_action_button.dart';
import 'achievements_screen.dart';
import 'app_settings_screen.dart';
import 'game_screen.dart';
import 'graffiti_screen.dart';
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
                  onGraffiti: () => _onGraffitiPressed(context),
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
              const ConfigSettingsPanel(
                showSoundAndDarkMode: false,
              ),
              const Divider(height: 32),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: MenuActionButton(
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
                      child: MenuActionButton(
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: MenuActionButton(
                  label: 'Settings',
                  onPressed: () async {
                    _hideTitleIcons();
                    await Navigator.of(context).push(
                      IrodokuPageRoute(
                        builder: (_) => const AppSettingsScreen(),
                      ),
                    );
                    if (!mounted) return;
                    _scheduleTitleIcons();
                  },
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

  Future<void> _onGraffitiPressed(BuildContext context) async {
    _hideTitleIcons();
    await Navigator.of(context).push(
      IrodokuPageRoute(builder: (_) => const GraffitiScreen()),
    );
    if (!mounted) return;
    _scheduleTitleIcons();
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
  final VoidCallback onGraffiti;
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
    required this.onGraffiti,
    required this.onChromatic,
    required this.onIroen,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        MenuActionButton(
          label: 'Classic Game',
          enabled: !busy,
          onPressed: onClassic,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: MenuActionButton(
                label: 'Graffiti',
                enabled: !busy,
                onPressed: onGraffiti,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MenuActionButton(
                label: 'Daily Challenge',
                trailing:
                    dailyUnlocked && dailyStreak > 0 ? 'x$dailyStreak' : null,
                enabled: !busy,
                muted: dailyUnlocked && dailyFinished,
                locked: !dailyUnlocked,
                onPressed: onDaily,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: MenuActionButton(
                label: 'Chromatic',
                enabled: !busy,
                locked: !chromaticUnlocked,
                onPressed: onChromatic,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MenuActionButton(
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


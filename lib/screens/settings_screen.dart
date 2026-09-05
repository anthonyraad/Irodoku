import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/irodoku_page_route.dart';
import '../core/theme.dart';
import '../models/daily_irodoku.dart';
import '../models/difficulty.dart';
import '../models/game_stats.dart';
import '../models/player_xp.dart';
import '../providers/game_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/stats_provider.dart';
import '../widgets/menu_action_button.dart';
import '../widgets/menu_select_sound.dart';
import '../widgets/palette_sweep_mask.dart';
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

class _SettingsScreenState extends State<SettingsScreen>
    with TickerProviderStateMixin {
  static const _titleIconRevealDelay = Duration(milliseconds: 160);
  static const _streakSweepDelay = Duration(milliseconds: 440);

  bool _titleIconsVisible = false;
  int _titleIconGeneration = 0;
  int _streakSweepGeneration = 0;
  int _pocketNudgeEpoch = 0;
  Timer? _titleIconTimer;
  Timer? _streakSweepTimer;
  Timer? _midnightTimer;
  bool _openingDaily = false;
  bool _pocketMenu = false;
  late final AnimationController _statsShake;
  late final AnimationController _difficultySweep;
  late final AnimationController _streakSweep;

  /// Scale title icons in after a short beat (title text stays static).
  void _scheduleTitleIcons() {
    _titleIconTimer?.cancel();
    _streakSweepTimer?.cancel();
    final gen = ++_titleIconGeneration;
    final streakGen = ++_streakSweepGeneration;
    _streakSweep.value = 0;
    setState(() {
      _titleIconsVisible = false;
      _pocketNudgeEpoch++;
    });
    _titleIconTimer = Timer(_titleIconRevealDelay, () {
      if (!mounted || gen != _titleIconGeneration) return;
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
      setState(() => _titleIconsVisible = true);
    });
    _streakSweepTimer = Timer(_streakSweepDelay, () {
      if (!mounted || streakGen != _streakSweepGeneration) return;
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
      final game = context.read<GameProvider>();
      final stats = context.read<StatsProvider>();
      final unlocked = _pocketMenu
          ? stats.isPocketDailyUnlocked
          : (stats.isDailyChallengeUnlocked ||
              GameProvider.debugDailyStreakOverride != null);
      final streak = _pocketMenu
          ? game.pocketDailyStreakDisplay
          : game.dailyStreakDisplay;
      if (!unlocked || streak <= 0) return;
      _streakSweep.forward(from: 0);
    });
  }

  /// Hide title icons before a subpage covers this route so they aren't
  /// still visible when the user pops back.
  void _hideTitleIcons() {
    _titleIconTimer?.cancel();
    _streakSweepTimer?.cancel();
    _titleIconGeneration++;
    _streakSweepGeneration++;
    _streakSweep.value = 0;
    if (!_titleIconsVisible) return;
    setState(() => _titleIconsVisible = false);
  }

  @override
  void initState() {
    super.initState();
    _statsShake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 210),
    );
    _difficultySweep = AnimationController(
      vsync: this,
      duration: PaletteSweepMask.duration,
    );
    _streakSweep = AnimationController(
      vsync: this,
      duration: PaletteSweepMask.duration,
    );
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
    _statsShake.dispose();
    _difficultySweep.dispose();
    _streakSweep.dispose();
    _titleIconTimer?.cancel();
    _streakSweepTimer?.cancel();
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
          await context.read<GameProvider>().leaveMenuToRegular(
            pocket: _pocketMenu,
          );
          if (context.mounted) Navigator.of(context).pop();
        },
        child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const BackButtonIcon(),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () {
              playIgMenuSound(context);
              Navigator.maybePop(context);
            },
          ),
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
          final dailyUnlocked = statsProvider.isDailyChallengeUnlocked ||
              GameProvider.debugDailyStreakOverride != null;
          final graffitiUnlocked = statsProvider.isGraffitiUnlocked;
          final pocketGraffitiUnlocked = statsProvider.isPocketGraffitiUnlocked;
          final pocketDailyUnlocked = statsProvider.isPocketDailyUnlocked;
          final dailyFinished = game.isDailyFinishedToday;
          final pocketDailyFinished = game.isPocketDailyFinishedToday;
          final dailyStreak = game.dailyStreakDisplay;
          final pocketDailyStreak = game.pocketDailyStreakDisplay;
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
                  pocketDailyUnlocked: pocketDailyUnlocked,
                  pocketDailyFinished: pocketDailyFinished,
                  pocketDailyStreak: pocketDailyStreak,
                  chromaticUnlocked: chromaticUnlocked,
                  graffitiUnlocked: graffitiUnlocked,
                  pocketGraffitiUnlocked: pocketGraffitiUnlocked,
                  iroenUnlocked: statsProvider.isIroenUnlocked,
                  onClassic: () => _onClassicPressed(context, game),
                  onDaily: () => _onDailyPressed(
                    context,
                    game,
                    unlocked: dailyUnlocked,
                    stats: stats,
                  ),
                  onPocketDaily: () => _onDailyPressed(
                    context,
                    game,
                    unlocked: pocketDailyUnlocked,
                    stats: stats,
                    pocket: true,
                  ),
                  onGraffiti: () => _onGraffitiPressed(
                    context,
                    unlocked: graffitiUnlocked,
                    stats: stats,
                  ),
                  onPocketGraffiti: () => _onPocketGraffitiPressed(
                    context,
                    unlocked: pocketGraffitiUnlocked,
                    stats: stats,
                  ),
                  onChromatic: () => _onChromaticPressed(
                    context,
                    game,
                    unlocked: chromaticUnlocked,
                  ),
                  onPocketChromatic: () => _onPocketChromaticPressed(
                    context,
                    game,
                    unlocked: chromaticUnlocked,
                  ),
                  onIroen: () => _onIroenPressed(
                    context,
                    stats,
                    unlocked: statsProvider.isIroenUnlocked,
                  ),
                  onPocket: () => _onPocketPressed(context, game),
                  onPocketMenuChanged: (pocket) {
                    if (_pocketMenu == pocket) return;
                    setState(() => _pocketMenu = pocket);
                    _statsShake.forward(from: 0);
                    _streakSweep.value = 0;
                    final unlocked = pocket
                        ? statsProvider.isPocketDailyUnlocked
                        : (statsProvider.isDailyChallengeUnlocked ||
                            GameProvider.debugDailyStreakOverride != null);
                    final streak = pocket
                        ? game.pocketDailyStreakDisplay
                        : game.dailyStreakDisplay;
                    if (unlocked && streak > 0) {
                      _streakSweep.forward(from: 0);
                    }
                  },
                  difficultySweep: _difficultySweep,
                  streakSweep: _streakSweep,
                  pocketNudgeEpoch: _pocketNudgeEpoch,
                ),
              ),
              const Divider(height: 32),
              ConfigSettingsPanel(
                showSoundAndDarkMode: false,
                difficultyLocked: _pocketMenu,
                onDifficultyApplied: () {
                  _difficultySweep.forward(from: 0);
                },
              ),
              const Divider(height: 32),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: MenuActionButton(
                        label: _pocketMenu ? '[Stats]' : 'Stats',
                        labelShake: _statsShake,
                        onPressed: () async {
                          _hideTitleIcons();
                          await Navigator.of(context).push(
                            IrodokuPageRoute(
                              builder: (_) =>
                                  StatsScreen(pocket: _pocketMenu),
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

  Future<void> _onPocketPressed(
    BuildContext context,
    GameProvider game,
  ) async {
    await game.openPocketGame();
    if (!context.mounted) return;
    await Navigator.of(context).maybePop();
  }

  Future<void> _onPocketChromaticPressed(
    BuildContext context,
    GameProvider game, {
    required bool unlocked,
  }) async {
    if (!unlocked) {
      _showChromaticLockedSnackBar(context);
      return;
    }
    final started = await game.openPocketChromaticGame();
    if (!context.mounted || !started) return;
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
    bool pocket = false,
  }) async {
    if (_openingDaily || game.isGenerating) return;
    if (!unlocked) {
      if (pocket) {
        _showPocketGraffitiLockedSnackBar(context, stats);
      } else {
        _showDailyLockedSnackBar(context, stats);
      }
      return;
    }
    _openingDaily = true;
    try {
      final started = pocket
          ? await game.startPocketDailyGame()
          : await game.startDailyGame();
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

  Future<void> _onGraffitiPressed(
    BuildContext context, {
    required bool unlocked,
    required GameStats stats,
  }) async {
    if (!unlocked) {
      _showGraffitiLockedSnackBar(context, stats);
      return;
    }
    _hideTitleIcons();
    await Navigator.of(context).push(
      IrodokuPageRoute(builder: (_) => const GraffitiScreen()),
    );
    if (!mounted) return;
    _scheduleTitleIcons();
  }

  Future<void> _onPocketGraffitiPressed(
    BuildContext context, {
    required bool unlocked,
    required GameStats stats,
  }) async {
    if (!unlocked) {
      _showPocketGraffitiLockedSnackBar(context, stats);
      return;
    }
    _hideTitleIcons();
    await Navigator.of(context).push(
      IrodokuPageRoute(builder: (_) => const GraffitiScreen(pocket: true)),
    );
    if (!mounted) return;
    _scheduleTitleIcons();
  }

  void _showGraffitiLockedSnackBar(BuildContext context, GameStats stats) {
    const need = GameStats.graffitiUnlockEasyWins;
    final have = stats.winsFor(Difficulty.easy);
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
                    text: 'Easy',
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

  void _showPocketGraffitiLockedSnackBar(
    BuildContext context,
    GameStats stats,
  ) {
    const need = GameStats.graffitiUnlockPocketWins;
    final have = stats.pocketWins;
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
                    text: 'Pocket',
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
    final have = stats.iroenUnlockWins;
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

class _PlayModeGrid extends StatefulWidget {
  final bool busy;
  final bool dailyUnlocked;
  final bool dailyFinished;
  final int dailyStreak;
  final bool pocketDailyUnlocked;
  final bool pocketDailyFinished;
  final int pocketDailyStreak;
  final bool chromaticUnlocked;
  final bool graffitiUnlocked;
  final bool pocketGraffitiUnlocked;
  final bool iroenUnlocked;
  final VoidCallback onClassic;
  final VoidCallback onDaily;
  final VoidCallback onPocketDaily;
  final VoidCallback onGraffiti;
  final VoidCallback onPocketGraffiti;
  final VoidCallback onChromatic;
  final VoidCallback onPocketChromatic;
  final VoidCallback onIroen;
  final VoidCallback onPocket;
  final ValueChanged<bool> onPocketMenuChanged;
  final Animation<double> difficultySweep;
  final Animation<double> streakSweep;
  final int pocketNudgeEpoch;

  const _PlayModeGrid({
    required this.busy,
    required this.dailyUnlocked,
    required this.dailyFinished,
    required this.dailyStreak,
    required this.pocketDailyUnlocked,
    required this.pocketDailyFinished,
    required this.pocketDailyStreak,
    required this.chromaticUnlocked,
    required this.graffitiUnlocked,
    required this.pocketGraffitiUnlocked,
    required this.iroenUnlocked,
    required this.onClassic,
    required this.onDaily,
    required this.onPocketDaily,
    required this.onGraffiti,
    required this.onPocketGraffiti,
    required this.onChromatic,
    required this.onPocketChromatic,
    required this.onIroen,
    required this.onPocket,
    required this.onPocketMenuChanged,
    required this.difficultySweep,
    required this.streakSweep,
    required this.pocketNudgeEpoch,
  });

  @override
  State<_PlayModeGrid> createState() => _PlayModeGridState();
}

class _PlayModeGridState extends State<_PlayModeGrid>
    with SingleTickerProviderStateMixin {
  bool _pocket = false;
  late final AnimationController _chromaticShake;

  @override
  void initState() {
    super.initState();
    _chromaticShake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 210),
    );
  }

  @override
  void dispose() {
    _chromaticShake.dispose();
    super.dispose();
  }

  void _onPocketModeChanged(bool pocket) {
    if (_pocket == pocket) return;
    setState(() => _pocket = pocket);
    widget.onPocketMenuChanged(pocket);
    _chromaticShake.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final chromaticLabel =
        widget.chromaticUnlocked && _pocket ? '[Chromatic]' : 'Chromatic';
    final graffitiLabel =
        widget.pocketGraffitiUnlocked && _pocket ? '[Graffiti]' : 'Graffiti';
    final dailyLabel = widget.pocketDailyUnlocked && _pocket
        ? '[Daily Challenge]'
        : 'Daily Challenge';
    final graffitiUnlocked =
        _pocket ? widget.pocketGraffitiUnlocked : widget.graffitiUnlocked;
    final dailyUnlocked =
        _pocket ? widget.pocketDailyUnlocked : widget.dailyUnlocked;
    final dailyFinished =
        _pocket ? widget.pocketDailyFinished : widget.dailyFinished;
    final dailyStreak =
        _pocket ? widget.pocketDailyStreak : widget.dailyStreak;
    return Column(
      children: [
        _ClassicOrPocketButton(
          busy: widget.busy,
          onClassic: widget.onClassic,
          onPocket: widget.onPocket,
          onPocketModeChanged: _onPocketModeChanged,
          difficultySweep: widget.difficultySweep,
          pocketNudgeEpoch: widget.pocketNudgeEpoch,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: MenuActionButton(
                label: graffitiLabel,
                enabled: !widget.busy,
                locked: !graffitiUnlocked,
                onPressed: _pocket
                    ? widget.onPocketGraffiti
                    : widget.onGraffiti,
                labelShake: widget.pocketGraffitiUnlocked
                    ? _chromaticShake
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MenuActionButton(
                label: dailyLabel,
                badge: dailyUnlocked && dailyStreak > 0
                    ? 'x$dailyStreak'
                    : null,
                badgeSweep: widget.streakSweep,
                enabled: !widget.busy,
                muted: dailyUnlocked && dailyFinished,
                locked: !dailyUnlocked,
                onPressed: _pocket ? widget.onPocketDaily : widget.onDaily,
                labelShake: widget.pocketDailyUnlocked
                    ? _chromaticShake
                    : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: MenuActionButton(
                label: chromaticLabel,
                enabled: !widget.busy,
                locked: !widget.chromaticUnlocked,
                onPressed: _pocket && widget.chromaticUnlocked
                    ? widget.onPocketChromatic
                    : widget.onChromatic,
                labelShake:
                    widget.chromaticUnlocked ? _chromaticShake : null,
                labelSweep:
                    widget.chromaticUnlocked ? widget.difficultySweep : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MenuActionButton(
                label: 'Iroen',
                enabled: true,
                locked: !widget.iroenUnlocked,
                onPressed: widget.onIroen,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Full-width Classic / Pocket control. Swipe right for Pocket, left for Classic.
/// Resets to Classic when Main Menu is disposed (leaving the menu).
class _ClassicOrPocketButton extends StatefulWidget {
  final bool busy;
  final VoidCallback onClassic;
  final VoidCallback onPocket;
  final ValueChanged<bool> onPocketModeChanged;
  final Animation<double> difficultySweep;
  final int pocketNudgeEpoch;

  const _ClassicOrPocketButton({
    required this.busy,
    required this.onClassic,
    required this.onPocket,
    required this.onPocketModeChanged,
    required this.difficultySweep,
    required this.pocketNudgeEpoch,
  });

  @override
  State<_ClassicOrPocketButton> createState() => _ClassicOrPocketButtonState();
}

class _ClassicOrPocketButtonState extends State<_ClassicOrPocketButton>
    with TickerProviderStateMixin {
  static const _minDistance = 28.0;
  static const _minVelocity = 180.0;
  static const _ignoreTapAfterSwipe = Duration(milliseconds: 120);
  static const _nudgeDelay = Duration(milliseconds: 680);

  bool _pocket = false;
  double _dragDx = 0;
  bool _ignoreTap = false;
  Timer? _ignoreTapTimer;
  Timer? _nudgeTimer;
  late final AnimationController _shake;
  late final AnimationController _nudge;
  late final Animation<double> _nudgeSlide;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 210),
    );
    _nudge = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    );
    _nudgeSlide = _nudge.drive(const _PocketNudgeSlide());
  }

  @override
  void didUpdateWidget(covariant _ClassicOrPocketButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pocketNudgeEpoch != widget.pocketNudgeEpoch) {
      _scheduleNudge();
    }
  }

  @override
  void dispose() {
    _ignoreTapTimer?.cancel();
    _nudgeTimer?.cancel();
    _shake.dispose();
    _nudge.dispose();
    super.dispose();
  }

  void _scheduleNudge() {
    _nudgeTimer?.cancel();
    _nudge.stop();
    _nudge.value = 0;
    if (widget.pocketNudgeEpoch <= 0 || _pocket) return;
    final settings = context.read<SettingsProvider>();
    if (settings.pocketSwipeDiscovered) return;
    if (PlayerXp.levelFor(context.read<StatsProvider>().stats.totalXp) < 5) {
      return;
    }

    _nudgeTimer = Timer(_nudgeDelay, () {
      if (!mounted || _pocket) return;
      if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
      if (context.read<SettingsProvider>().pocketSwipeDiscovered) return;
      _nudge.forward(from: 0);
    });
  }

  void _cancelNudgeMotion() {
    _nudgeTimer?.cancel();
    if (_nudge.isAnimating || _nudge.value != 0) {
      _nudge.stop();
      _nudge.value = 0;
    }
  }

  void _dismissNudgeForever() {
    _cancelNudgeMotion();
    unawaited(context.read<SettingsProvider>().markPocketSwipeDiscovered());
  }

  void _setPocket(bool pocket) {
    if (_pocket == pocket) return;
    playMenuSelectSound(context);
    setState(() => _pocket = pocket);
    _shake.forward(from: 0);
    widget.onPocketModeChanged(pocket);
    if (pocket) _dismissNudgeForever();
  }

  void _suppressTapFromSwipe() {
    _ignoreTap = true;
    _ignoreTapTimer?.cancel();
    _ignoreTapTimer = Timer(_ignoreTapAfterSwipe, () {
      _ignoreTap = false;
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final swipeRight = _dragDx > _minDistance || velocity > _minVelocity;
    final swipeLeft = _dragDx < -_minDistance || velocity < -_minVelocity;
    _dragDx = 0;
    if (swipeRight) {
      _suppressTapFromSwipe();
      _setPocket(true);
    } else if (swipeLeft) {
      _suppressTapFromSwipe();
      _setPocket(false);
    }
  }

  void _onPressed() {
    if (_ignoreTap) return;
    if (_pocket) {
      widget.onPocket();
    } else {
      widget.onClassic();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragStart: (_) {
        _dragDx = 0;
        _cancelNudgeMotion();
      },
      onHorizontalDragUpdate: (details) => _dragDx += details.delta.dx,
      onHorizontalDragEnd: _onDragEnd,
      child: MenuActionButton(
        label: _pocket ? '[Pocket]' : 'Irodoku',
        enabled: !widget.busy,
        onPressed: _onPressed,
        labelShake: _shake,
        labelSlide: _nudgeSlide,
        labelSweep: widget.difficultySweep,
      ),
    );
  }
}

/// Ease the Irodoku label right, then rubber-band it back to rest.
class _PocketNudgeSlide extends Animatable<double> {
  static const _peak = 13.0;
  static const _pullEnd = 0.40;

  const _PocketNudgeSlide();

  @override
  double transform(double t) {
    if (t <= 0 || t >= 1) return 0;
    if (t < _pullEnd) {
      return Curves.easeOutCubic.transform(t / _pullEnd) * _peak;
    }
    final u = (t - _pullEnd) / (1 - _pullEnd);
    return _peak * math.exp(-5.2 * u) * math.cos(u * math.pi * 1.05);
  }
}


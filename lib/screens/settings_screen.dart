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
    setState(() => _titleIconsVisible = false);
    _titleIconTimer = Timer(_titleIconRevealDelay, () {
      if (!mounted || gen != _titleIconGeneration) return;
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
      setState(() => _titleIconsVisible = true);
    });
    _streakSweepTimer = Timer(_streakSweepDelay, () {
      if (!mounted || streakGen != _streakSweepGeneration) return;
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
      final game = context.read<GameProvider>();
      final unlocked =
          context.read<StatsProvider>().isDailyChallengeUnlocked ||
              GameProvider.debugDailyStreakOverride != null;
      if (!unlocked || game.dailyStreakDisplay <= 0) return;
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
          await context.read<GameProvider>().leaveMenuToRegular();
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
                  graffitiUnlocked: graffitiUnlocked,
                  iroenUnlocked: statsProvider.isIroenUnlocked,
                  onClassic: () => _onClassicPressed(context, game),
                  onDaily: () => _onDailyPressed(
                    context,
                    game,
                    unlocked: dailyUnlocked,
                    stats: stats,
                  ),
                  onGraffiti: () => _onGraffitiPressed(
                    context,
                    unlocked: graffitiUnlocked,
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
                  },
                  difficultySweep: _difficultySweep,
                  streakSweep: _streakSweep,
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

class _PlayModeGrid extends StatefulWidget {
  final bool busy;
  final bool dailyUnlocked;
  final bool dailyFinished;
  final int dailyStreak;
  final bool chromaticUnlocked;
  final bool graffitiUnlocked;
  final bool iroenUnlocked;
  final VoidCallback onClassic;
  final VoidCallback onDaily;
  final VoidCallback onGraffiti;
  final VoidCallback onChromatic;
  final VoidCallback onPocketChromatic;
  final VoidCallback onIroen;
  final VoidCallback onPocket;
  final ValueChanged<bool> onPocketMenuChanged;
  final Animation<double> difficultySweep;
  final Animation<double> streakSweep;

  const _PlayModeGrid({
    required this.busy,
    required this.dailyUnlocked,
    required this.dailyFinished,
    required this.dailyStreak,
    required this.chromaticUnlocked,
    required this.graffitiUnlocked,
    required this.iroenUnlocked,
    required this.onClassic,
    required this.onDaily,
    required this.onGraffiti,
    required this.onChromatic,
    required this.onPocketChromatic,
    required this.onIroen,
    required this.onPocket,
    required this.onPocketMenuChanged,
    required this.difficultySweep,
    required this.streakSweep,
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
    if (widget.chromaticUnlocked) {
      _chromaticShake.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chromaticLabel =
        widget.chromaticUnlocked && _pocket ? '[Chromatic]' : 'Chromatic';
    return Column(
      children: [
        _ClassicOrPocketButton(
          busy: widget.busy,
          onClassic: widget.onClassic,
          onPocket: widget.onPocket,
          onPocketModeChanged: _onPocketModeChanged,
          difficultySweep: widget.difficultySweep,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: MenuActionButton(
                label: 'Graffiti',
                enabled: !widget.busy,
                locked: !widget.graffitiUnlocked,
                onPressed: widget.onGraffiti,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MenuActionButton(
                label: 'Daily Challenge',
                badge: widget.dailyUnlocked && widget.dailyStreak > 0
                    ? 'x${widget.dailyStreak}'
                    : null,
                badgeSweep: widget.streakSweep,
                enabled: !widget.busy,
                muted: widget.dailyUnlocked && widget.dailyFinished,
                locked: !widget.dailyUnlocked,
                onPressed: widget.onDaily,
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

  const _ClassicOrPocketButton({
    required this.busy,
    required this.onClassic,
    required this.onPocket,
    required this.onPocketModeChanged,
    required this.difficultySweep,
  });

  @override
  State<_ClassicOrPocketButton> createState() => _ClassicOrPocketButtonState();
}

class _ClassicOrPocketButtonState extends State<_ClassicOrPocketButton>
    with SingleTickerProviderStateMixin {
  static const _minDistance = 28.0;
  static const _minVelocity = 180.0;
  static const _ignoreTapAfterSwipe = Duration(milliseconds: 120);

  bool _pocket = false;
  double _dragDx = 0;
  bool _ignoreTap = false;
  Timer? _ignoreTapTimer;
  late final AnimationController _shake;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 210),
    );
  }

  @override
  void dispose() {
    _ignoreTapTimer?.cancel();
    _shake.dispose();
    super.dispose();
  }

  void _setPocket(bool pocket) {
    if (_pocket == pocket) return;
    playMenuSelectSound(context);
    setState(() => _pocket = pocket);
    _shake.forward(from: 0);
    widget.onPocketModeChanged(pocket);
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
      onHorizontalDragStart: (_) => _dragDx = 0,
      onHorizontalDragUpdate: (details) => _dragDx += details.delta.dx,
      onHorizontalDragEnd: _onDragEnd,
      child: MenuActionButton(
        label: _pocket ? '[Pocket]' : 'Irodoku',
        enabled: !widget.busy,
        onPressed: _onPressed,
        labelShake: _shake,
        labelSweep: widget.difficultySweep,
      ),
    );
  }
}


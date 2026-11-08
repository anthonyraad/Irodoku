import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/irodoku_page_route.dart';
import '../discord/discord_bridge.dart';
import '../discord/discord_leaderboard.dart';
import '../discord/discord_mode.dart';
import '../core/theme.dart';
import '../models/daily_irodoku.dart';
import '../models/daily_leaderboard.dart';
import '../models/game_palette.dart';
import '../models/player_xp.dart';
import '../providers/game_provider.dart';
import '../providers/iroen_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/stats_provider.dart';
import '../services/daily_leaderboard_service.dart';
import '../widgets/chromatic_palette_transition.dart';
import '../widgets/color_picker.dart';
import '../widgets/dice_new_game_button.dart';
import '../widgets/first_run_tutorial.dart';
import '../widgets/game_toolbar.dart';
import '../widgets/hyperchroma_shop.dart';
import '../widgets/menu_select_sound.dart';
import '../widgets/mistake_display.dart';
import '../widgets/sketch_icon.dart';
import '../widgets/start_new_game_dialog.dart';
import '../widgets/sudoku_grid.dart';
import '../widgets/timer_display.dart';
import '../widgets/typing_title.dart';
import '../widgets/win_dialog.dart';
import 'daily_leaderboard_screen.dart';
import 'settings_screen.dart';

/// Font size that keeps [text] on the AppBar's true center without hitting
/// the leading or action clusters (otherwise Flutter shoves it left).
TextStyle? _centeredAppBarTitleStyle(
  BuildContext context, {
  required String text,
  required double leadingWidth,
  required double actionsWidth,
}) {
  final base = Theme.of(context).appBarTheme.titleTextStyle;
  if (base == null) return null;
  final maxWidth =
      MediaQuery.sizeOf(context).width -
      2 * math.max(leadingWidth, actionsWidth) -
      8;
  final baseSize = base.fontSize ?? 22;
  if (maxWidth <= 0) return base.copyWith(fontSize: 13);

  var fontSize = baseSize;
  final painter = TextPainter(
    textDirection: Directionality.of(context),
    maxLines: 1,
  );
  while (fontSize > 13) {
    painter
      ..text = TextSpan(
        text: text,
        style: base.copyWith(fontSize: fontSize),
      )
      ..layout();
    if (painter.width <= maxWidth) break;
    fontSize -= 0.5;
  }
  return fontSize == baseSize ? base : base.copyWith(fontSize: fontSize);
}

Color? _hyperchromaClockColor(BuildContext context, GameProvider game) {
  if (!game.isHyperchroma) return null;
  if (game.hyperchromaSeconds <= 0) return null;
  if (game.hyperchromaPulse > 0) return Colors.lightBlueAccent;
  if (game.hyperchromaPulse < 0 || game.hyperchromaSeconds <= 10) {
    return Theme.of(context).colorScheme.error;
  }
  return null;
}

class GameScreen extends StatefulWidget {
  /// When true, this route is the nested Daily Irodoku under Main Menu.
  final bool isDailyRoute;

  const GameScreen({super.key, this.isDailyRoute = false});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  bool _resultDialogShown = false;

  /// XP/unlocks only on the first Victory for this finished board.
  bool _offerResultXp = true;
  int _titlePlayToken = 0;
  bool _victoryOpen = false;
  bool _defeatOpen = false;
  String _resultTime = '';
  XpAward? _resultXp;
  final _boardKey = GlobalKey();
  final _overlayKey = GlobalKey();
  int? _sketchColor;
  Offset? _sketchGlobal;
  int? _sketchBox;

  @override
  void initState() {
    super.initState();
    if (!widget.isDailyRoute) {
      WidgetsBinding.instance.addObserver(this);
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final game = context.read<GameProvider>();
        await game.bootstrap();
        if (!mounted) return;
        if (!game.consumeOpenDailyRoutePending()) return;
        await Navigator.of(context).push(
          IrodokuPageRoute(
            builder: (_) => const SettingsScreen(openDailyOnLaunch: true),
          ),
        );
        if (!mounted) return;
        setState(() => _titlePlayToken++);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final game = context.read<GameProvider>();
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      game.holdHyperchromaForBackground(true);
      game.persistLiveGameForBackground();
    } else if (state == AppLifecycleState.resumed) {
      game.holdHyperchromaForBackground(false);
      game.onAppForeground();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _onNewGame() async {
    final game = context.read<GameProvider>();
    if (game.isGenerating) return;

    // Mid-match: confirm before discarding progress (same modal as difficulty).
    if (game.hasInteracted && !game.isGameOver) {
      final startNew = await showStartNewGameDialog(context);
      if (!mounted || startNew != true) return;
    }

    _resultDialogShown = false;
    _offerResultXp = true;
    _victoryOpen = false;
    _defeatOpen = false;
    if (game.isHyperchroma) {
      await game.restartHyperchroma();
    } else {
      await game.startNewGame();
    }
  }

  Future<void> _onTryAgain() async {
    final game = context.read<GameProvider>();
    if (game.isGenerating) return;
    _resultDialogShown = false;
    _offerResultXp = true;
    _victoryOpen = false;
    _defeatOpen = false;
    await game.retryFromDefeat();
  }

  /// Title-tap shimmer after Victory Close — skipped if they started a new game.
  Future<void> _playWinTitleShimmer() async {
    // Let the dialog finish fading so the board is fully visible.
    await Future<void>.delayed(const Duration(milliseconds: 240));
    if (!mounted) return;
    final game = context.read<GameProvider>();
    if (!game.isWon || game.isGenerating || game.isPaused) return;
    game.clearCelebration();
    game.triggerColorCycle(savedMosaics: context.read<IroenProvider>().gallery);
  }

  void _maybeShowResult(GameProvider game) {
    // Home and Daily routes share one provider — only the matching route
    // should present win/loss dialogs.
    if (widget.isDailyRoute != game.isDaily) return;

    if (game.isWon && !_resultDialogShown) {
      _resultDialogShown = true;
      final includeXp =
          _offerResultXp && !game.isDailyReview && !DiscordMode.enabled;
      _offerResultXp = false;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        if (includeXp) {
          final unlocks = game.consumePendingPaletteUnlocks();
          for (final palette in unlocks) {
            _showPaletteUnlockedSnackBar(context, palette);
          }
          final award = context.read<StatsProvider>().lastXpAward;
          if (award != null) {
            final stats = context.read<StatsProvider>();
            final bSides = {
              ...PlayerXp.bSidesUnlockedByLevelUp(
                fromXp: award.previousTotal,
                toXp: award.newTotal,
                paletteUnlocked: stats.isPaletteUnlocked,
              ),
              for (final palette in unlocks)
                if (context.read<SettingsProvider>().isBSideUnlocked(palette))
                  palette,
            };
            for (final palette in bSides) {
              _showBSideUnlockedSnackBar(context, palette);
            }
          }
        }
        if (widget.isDailyRoute) {
          final settings = context.read<SettingsProvider>();
          if (DiscordMode.enabled ||
              DisplayName.trySanitize(settings.displayName) != null) {
            unawaited(_submitDailyLeaderboard(game));
          }
        }
        if (!mounted) return;
        setState(() {
          _victoryOpen = true;
          _defeatOpen = false;
          _resultTime = game.isHyperchroma
              ? '${game.hyperchromaScore}'
              : game.formatElapsed();
          _resultXp = includeXp
              ? context.read<StatsProvider>().lastXpAward
              : null;
        });
      });
    } else if (game.isLost && !_resultDialogShown) {
      _resultDialogShown = true;
      _offerResultXp = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _defeatOpen = true);
      });
    } else if (!game.isGameOver) {
      _resultDialogShown = false;
      _offerResultXp = true;
      if (_victoryOpen || _defeatOpen) {
        _victoryOpen = false;
        _defeatOpen = false;
      }
    }
  }

  void _closeVictory() {
    if (!_victoryOpen) return;
    setState(() => _victoryOpen = false);
    unawaited(_playWinTitleShimmer());
  }

  void _closeDefeat() {
    if (!_defeatOpen) return;
    setState(() => _defeatOpen = false);
  }

  bool _sketchHitsBoard(Offset global) => _boxAtGlobal(global) != null;

  int? _boxAtGlobal(Offset global) {
    final render = _boardKey.currentContext?.findRenderObject();
    if (render is! RenderBox || !render.attached || !render.hasSize) {
      return null;
    }
    final local = render.globalToLocal(global);
    final size = render.size;
    if (local.dx < 0 ||
        local.dy < 0 ||
        local.dx >= size.width ||
        local.dy >= size.height) {
      return null;
    }
    final game = context.read<GameProvider>();
    final n = game.gridSize;
    if (n <= 0 || size.width <= 0 || size.height <= 0) return null;
    final col = (local.dx / (size.width / n)).floor().clamp(0, n - 1);
    final row = (local.dy / (size.height / n)).floor().clamp(0, n - 1);
    final boxCols = n ~/ game.boxW;
    return (row ~/ game.boxH) * boxCols + (col ~/ game.boxW);
  }

  void _onSketchDragUpdate(int color, Offset global) {
    final box = _boxAtGlobal(global);
    if (_sketchColor == color &&
        _sketchBox == box &&
        _sketchGlobal == global) {
      return;
    }
    setState(() {
      _sketchColor = color;
      _sketchGlobal = global;
      _sketchBox = box;
    });
  }

  void _clearSketchDrag() {
    if (_sketchColor == null && _sketchGlobal == null && _sketchBox == null) {
      return;
    }
    setState(() {
      _sketchColor = null;
      _sketchGlobal = null;
      _sketchBox = null;
    });
  }

  void _onSketchDragEnd(int color, Offset global) {
    final box = _boxAtGlobal(global);
    _clearSketchDrag();
    if (box == null || !mounted) return;
    context.read<GameProvider>().useSketch(box, color);
  }

  Widget? _sketchChip(GameProvider game) {
    final color = _sketchColor;
    final global = _sketchGlobal;
    if (color == null || global == null) return null;
    final overlay = _overlayKey.currentContext?.findRenderObject();
    if (overlay is! RenderBox || !overlay.attached || !overlay.hasSize) {
      return null;
    }
    final local = overlay.globalToLocal(global);
    final swatches = game.displaySwatches;
    final swatch = swatches != null && color >= 1 && color <= swatches.length
        ? swatches[color - 1]
        : null;
    final ink = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35);
    return Positioned(
      left: local.dx - 18,
      top: local.dy - 44,
      child: IgnorePointer(
        child: SizedBox(
          width: 36,
          height: 36,
          child: DecoratedBox(
            decoration: swatch?.boxDecoration(
                  border: Border.all(color: ink, width: 1),
                ) ??
                BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border.all(color: ink),
                ),
          ),
        ),
      ),
    );
  }

  void _openDailyLeaderboard(GameProvider game) {
    if (DiscordMode.enabled && game.isGameOver && game.isWon) {
      // One attempt per day: finishing swaps the puzzle for the leaderboard.
      DiscordMode.myMs = game.elapsed.inMilliseconds;
      DiscordMode.showLeaderboard.value = true;
      return;
    }
    if (DiscordMode.enabled) {
      showDiscordLeaderboard(
        context,
        game.dailyDayKey ?? DailyIrodoku.pocketForDate().dayKey,
      );
      return;
    }
    Navigator.of(context).push(
      IrodokuPageRoute(
        builder: (_) => DailyLeaderboardScreen(pocket: game.isPocket),
      ),
    );
  }

  Future<void> _submitDailyLeaderboard(GameProvider game) async {
    if (DiscordMode.enabled) {
      // Server validates the Discord token and writes to RTDB.
      final f = DiscordBridge.submitScore(
        game.dailyDayKey ?? DailyIrodoku.pocketForDate().dayKey,
        game.elapsed.inMilliseconds,
      );
      DiscordMode.pendingScore = f.then((_) {});
      await f;
      return;
    }
    final settings = context.read<SettingsProvider>();
    final name = DisplayName.orFallback(settings.displayName);
    final dayKey = game.dailyDayKey ?? DailyIrodoku.forDate().dayKey;
    await DailyLeaderboardService.submit(
      dayKey: dayKey,
      pocket: game.isPocket,
      name: name,
      ms: game.elapsed.inMilliseconds,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<GameProvider, SettingsProvider>(
      builder: (context, game, settings, _) {
        _maybeShowResult(game);
        final hasSelection = game.hasCellSelection;
        // Keep control-slot layout while paused / after win-loss so the board
        // doesn't resize; only the widgets themselves are removed.
        final reserveControlsLayout =
            !game.isGenerating && (game.hasActiveGame || game.isGameOver);
        final showControls =
            reserveControlsLayout && !game.isGameOver && !game.isPaused;
        final controlsEnabled = showControls;
        final canErase = game.canEraseSelection;
        final canPause =
            game.hasActiveGame && !game.isGenerating && !game.isGameOver;

        final titleText = widget.isDailyRoute
            ? (game.isPocket ? '[Daily Iro]' : 'Daily Iro')
            : game.isHyperchroma
            ? 'Hyperchroma'
            : game.isPocket && settings.chromatic
            ? '[Chromatic]'
            : game.isPocket
            ? 'Pocket'
            : (settings.chromatic ? 'Chromatic' : 'Irodoku');
        final titleStyle = _centeredAppBarTitleStyle(
          context,
          text: titleText,
          leadingWidth: widget.isDailyRoute && !DiscordMode.enabled ? 56 : 0,
          actionsWidth:
              kMinInteractiveDimension * (widget.isDailyRoute ? 1 : 3),
        );

        final scaffold = GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: hasSelection
              ? game.clearSelection
              : (game.isPaused ? game.resumeGame : null),
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              leading: widget.isDailyRoute && !DiscordMode.enabled
                  ? IconButton(
                      tooltip: 'Main Menu',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: withMenuSelect(
                        context,
                        () => Navigator.of(context).pop(),
                      ),
                    )
                  : null,
              title: TypingTitle(
                text: titleText,
                style: titleStyle,
                textAlign: TextAlign.center,
                playToken: _titlePlayToken,
                onTap: () => game.triggerColorCycle(
                  savedMosaics: context.read<IroenProvider>().gallery,
                ),
              ),
              actions: [
                IconButton(
                  tooltip: game.isPaused ? 'Resume' : 'Pause',
                  icon: Icon(
                    game.isPaused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                  ),
                  onPressed: canPause ? game.togglePause : null,
                ),
                if (!widget.isDailyRoute)
                  DiceNewGameButton(
                    onPressed: game.isGenerating ? null : _onNewGame,
                  ),
                if (!widget.isDailyRoute)
                  IconButton(
                    tooltip: 'Main Menu',
                    icon: Image.asset(
                      'assets/icons/settings.png',
                      width: 24,
                      height: 24,
                      filterQuality: FilterQuality.none,
                    ),
                    onPressed: withMenuSelect(context, () async {
                      final live = context.read<GameProvider>();
                      live.holdHyperchromaForMenu(true);
                      await Navigator.of(context).push(
                        IrodokuPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                      if (!mounted) return;
                      live.holdHyperchromaForMenu(false);
                      // Returning to a finished board should show Victory/Defeat again.
                      _resultDialogShown = false;
                      _victoryOpen = false;
                      _defeatOpen = false;
                      setState(() => _titlePlayToken++);
                    }),
                  ),
              ],
            ),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TimerDisplay(
                              time: game.formatElapsed(),
                              color: _hyperchromaClockColor(context, game),
                            ),
                          ),
                        ),
                        if (game.isHyperchroma)
                          Semantics(
                            label: 'Sketch ${game.hyperchromaSketches}',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ExcludeSemantics(
                                  child: SketchIconPulse(
                                    count: game.hyperchromaSketches,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${game.hyperchromaSketches}x',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.55),
                                      ),
                                ),
                              ],
                            ),
                          )
                        else
                          MistakeDisplay(
                            mistakes: game.mistakes,
                            maxMistakes: game.mistakeLimit,
                          ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: game.isPocket && !widget.isDailyRoute
                                ? const SizedBox.shrink()
                                : Text(
                                    widget.isDailyRoute
                                        ? (game.dailyDateLabel ?? '')
                                        : game.isHyperchroma
                                            ? game.hyperchromaLevelLabel
                                            : game.difficulty.label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withValues(alpha: 0.55),
                                        ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          const boardBorder = 2.5;
                          const pickerGap = 12.0;
                          const toolbarGap = 8.0;
                          final xlPicker = settings.xlPicker;
                          const xlSwatchCells = 3 * 0.85 * 0.85;
                          final pocketPicker = game.isPocket;
                          // Size the square like Classic (9×9) so Pocket's 6×6
                          // is the same on-screen height and width.
                          const layoutN = 9;
                          final belowFixed = reserveControlsLayout
                              ? toolbarGap + GameToolbar.height + pickerGap
                              : 0.0;
                          const pocketSwatchScale = 0.70;
                          final pickerRows = pocketPicker
                              ? 2.0 * layoutN / 3.0 * pocketSwatchScale
                              : (xlPicker ? xlSwatchCells * 3 : 1.0);
                          final cellFromWidth =
                              (constraints.maxWidth - boardBorder * 2) /
                              layoutN;
                          final cellFromHeight = reserveControlsLayout
                              ? (constraints.maxHeight -
                                        belowFixed -
                                        boardBorder * 2) /
                                    (layoutN + pickerRows)
                              : (constraints.maxHeight -
                                        belowFixed -
                                        boardBorder * 2) /
                                    layoutN;
                          final cellSize = math.min(
                            cellFromWidth,
                            cellFromHeight,
                          );
                          final boardSize =
                              cellSize * layoutN + boardBorder * 2;
                          final boardInner = cellSize * layoutN;
                          final swatchSize = pocketPicker
                              ? boardInner / 3 * pocketSwatchScale
                              : (xlPicker
                                    ? cellSize * xlSwatchCells
                                    : cellSize);
                          final pickerHeight = pocketPicker
                              ? swatchSize * 2.0
                              : swatchSize * (xlPicker ? 3.0 : 1.0);

                          return ChromaticPaletteTransition(
                            palette: game.activePalette,
                            swatches: game.displaySwatches,
                            swatchKey: game.iroMixKey,
                            animate:
                                settings.chromatic ||
                                game.isDaily ||
                                game.isHyperchroma,
                            builder: (context, palette, swatches) {
                              return Align(
                                alignment: Alignment.topCenter,
                                child: SizedBox(
                                  width: boardSize,
                                  child: Column(
                                    children: [
                                      SizedBox(
                                        width: boardSize,
                                        height: boardSize,
                                        child: Stack(
                                          alignment: Alignment.center,
                                          clipBehavior: Clip.hardEdge,
                                          children: [
                                            // Keep the grid mounted while paused so
                                            // resume doesn't remount and replay the
                                            // title-tap color-cycle shimmer.
                                            TickerMode(
                                              enabled: !game.isPaused,
                                              child: SudokuGrid(
                                                game: game,
                                                palette: palette,
                                                displaySwatches: swatches,
                                                boardKey: _boardKey,
                                                sketchBox: game.isHyperchroma
                                                    ? _sketchBox
                                                    : null,
                                                showFrame: !(game.isHyperchroma &&
                                                    game.isPaused),
                                              ),
                                            ),
                                            if (game.isPaused)
                                              Positioned.fill(
                                                child: game.isHyperchroma
                                                    ? HyperchromaShop(
                                                        sketches: game
                                                            .hyperchromaSketches,
                                                        onBuy: (effect) => game
                                                            .buyHyperchromaEffect(
                                                              effect,
                                                            ),
                                                      )
                                                    : _PausedBoard(
                                                        onResume:
                                                            game.resumeGame,
                                                      ),
                                              ),
                                            if (game.isGenerating)
                                              Container(
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context)
                                                      .scaffoldBackgroundColor
                                                      .withValues(alpha: 0.7),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: const Padding(
                                                  padding: EdgeInsets.all(24),
                                                  child:
                                                      CircularProgressIndicator(),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (reserveControlsLayout) ...[
                                        const SizedBox(height: toolbarGap),
                                        if (showControls)
                                          IgnorePointer(
                                            ignoring: !controlsEnabled,
                                            child: GestureDetector(
                                              onTap: () {},
                                              behavior: HitTestBehavior.opaque,
                                              child: GameToolbar(
                                                canUndo:
                                                    controlsEnabled &&
                                                    game.canUndo,
                                                noteMode: game.noteMode,
                                                bulkNoteSelect:
                                                    game.bulkNoteSelect,
                                                canErase:
                                                    controlsEnabled && canErase,
                                                onUndo: game.undo,
                                                onErase: game.clearSelectedCell,
                                                onToggleNote:
                                                    game.toggleNoteMode,
                                                onNoteLongPress:
                                                    game.canEnterBulkNoteSelectFromToolbar
                                                    ? game.enterBulkNoteSelectFromToolbar
                                                    : null,
                                              ),
                                            ),
                                          )
                                        else
                                          const SizedBox(
                                            height: GameToolbar.height,
                                          ),
                                        const SizedBox(height: pickerGap),
                                        if (showControls)
                                          IgnorePointer(
                                            ignoring: !controlsEnabled,
                                            child: Align(
                                              alignment: Alignment.center,
                                              child: ColorPicker(
                                                swatchSize: swatchSize,
                                                xlMode:
                                                    xlPicker && !pocketPicker,
                                                pocket: pocketPicker,
                                                palette: palette,
                                                displaySwatches: swatches,
                                                visible: true,
                                                onColorSelected:
                                                    game.applyPickerColor,
                                                onNoteAdded:
                                                    game.addSelectedNote,
                                                onNoteRemoved:
                                                    game.removeSelectedNote,
                                                onColorHoldStart:
                                                    game.selected == null &&
                                                        !game.bulkNoteSelect
                                                    ? game.beginPickerHoldSweep
                                                    : null,
                                                onColorHoldEnd:
                                                    game.selected == null &&
                                                        !game.bulkNoteSelect
                                                    ? game.endPickerHoldSweep
                                                    : null,
                                                sketchHitsBoard: game
                                                        .isHyperchroma
                                                    ? _sketchHitsBoard
                                                    : null,
                                                onSketchDragUpdate: game
                                                        .isHyperchroma
                                                    ? _onSketchDragUpdate
                                                    : null,
                                                onSketchDragEnd: game
                                                        .isHyperchroma
                                                    ? _onSketchDragEnd
                                                    : null,
                                                onSketchDragCancel:
                                                    game.isHyperchroma
                                                    ? _clearSketchDrag
                                                    : null,
                                              ),
                                            ),
                                          )
                                        else
                                          SizedBox(height: pickerHeight),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        Widget page = scaffold;
        if (widget.isDailyRoute) {
          page = PopScope(
            canPop: true,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) game.parkDailyForMenu();
            },
            child: scaffold,
          );
        } else {
          page = Stack(
            children: [
              scaffold,
              if (settings.showFirstRunTutorial)
                FirstRunTutorialOverlay(
                  onComplete: settings.completeFirstRunTutorial,
                ),
            ],
          );
        }
        // Keep this Stack even when the result is closed so the AppBar title
        // is not recreated (and retyped) on the same screen.
        return Stack(
          key: _overlayKey,
          children: [
            page,
            if (_sketchChip(game) case final chip?) chip,
            if (_victoryOpen || _defeatOpen)
              Positioned.fill(
                child: ResultScrim(
                  child: _victoryOpen
                      ? VictoryPanel(
                          title: game.isHyperchroma ? 'Game Over' : 'Victory',
                          time: game.isHyperchroma
                              ? 'Score: $_resultTime'
                              : _resultTime,
                          mark: game.isHyperchroma
                              ? const SketchIcon(pixel: 6)
                              : null,
                          xp: _resultXp,
                          showNewGame: !widget.isDailyRoute,
                          leaderboardLabel: widget.isDailyRoute
                              ? DiscordMode.enabled
                                    ? "See today's leaderboard"
                                    : (game.isPocket
                                          ? '[Rankings]'
                                          : 'Rankings')
                              : null,
                          onLeaderboard: widget.isDailyRoute
                              ? () => _openDailyLeaderboard(game)
                              : null,
                          onNewGame: _onNewGame,
                          onClose: _closeVictory,
                        )
                      : DefeatPanel(
                          title: game.isHyperchroma &&
                                  game.hyperchromaBoardsCleared == 0
                              ? 'Game Over'
                              : 'Defeat',
                          showNewGame: false,
                          detail: game.isHyperchroma
                              ? 'Score: ${game.hyperchromaScore}'
                              : null,
                          onTryAgain: _onTryAgain,
                          onNewGame: _onNewGame,
                          maxMistakes: game.mistakeLimit,
                          onClose: _closeDefeat,
                        ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _showPaletteUnlockedSnackBar(BuildContext context, GamePalette palette) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: SizedBox(
            width: double.infinity,
            child: Text.rich(
              TextSpan(
                style:
                    Theme.of(context).snackBarTheme.contentTextStyle ??
                    TextStyle(
                      color: Theme.of(context).colorScheme.onInverseSurface,
                    ),
                children: [
                  TextSpan(
                    text: palette.label,
                    style: const TextStyle(
                      color: Colors.lightBlueAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const TextSpan(text: ' unlocked!'),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
  }

  void _showBSideUnlockedSnackBar(BuildContext context, GamePalette palette) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: SizedBox(
            width: double.infinity,
            child: Text.rich(
              TextSpan(
                style:
                    Theme.of(context).snackBarTheme.contentTextStyle ??
                    TextStyle(
                      color: Theme.of(context).colorScheme.onInverseSurface,
                    ),
                children: [
                  TextSpan(
                    text: palette.label,
                    style: const TextStyle(
                      color: Colors.lightBlueAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const TextSpan(text: ' B-side unlocked!'),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
  }
}

class _PausedBoard extends StatelessWidget {
  /// Cropped glyph at the same on-screen size as the old 365px padded asset.
  static const _iconHeight = 127.0;

  final VoidCallback onResume;

  const _PausedBoard({required this.onResume});

  @override
  Widget build(BuildContext context) {
    final brightness = IrodokuTheme.boardBrightness;
    final thick = IrodokuTheme.thickGridLine(brightness);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onResume,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: IrodokuTheme.emptyCellFill(brightness),
          border: Border.all(color: thick, width: 2.5),
        ),
        child: ClipRect(
          child: Center(
            child: Image.asset(
              'assets/icons/pause_cropped.png',
              height: _iconHeight,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      ),
    );
  }
}

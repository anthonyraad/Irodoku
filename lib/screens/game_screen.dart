import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/irodoku_page_route.dart';
import '../core/theme.dart';
import '../models/game_palette.dart';
import '../providers/game_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/stats_provider.dart';
import '../widgets/chromatic_palette_transition.dart';
import '../widgets/color_picker.dart';
import '../widgets/dice_new_game_button.dart';
import '../widgets/game_toolbar.dart';
import '../widgets/menu_select_sound.dart';
import '../widgets/mistake_display.dart';
import '../widgets/start_new_game_dialog.dart';
import '../widgets/sudoku_grid.dart';
import '../widgets/timer_display.dart';
import '../widgets/typing_title.dart';
import '../widgets/win_dialog.dart';
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
  final maxWidth = MediaQuery.sizeOf(context).width -
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
      ..text = TextSpan(text: text, style: base.copyWith(fontSize: fontSize))
      ..layout();
    if (painter.width <= maxWidth) break;
    fontSize -= 0.5;
  }
  return fontSize == baseSize ? base : base.copyWith(fontSize: fontSize);
}

class GameScreen extends StatefulWidget {
  /// When true, this route is the nested Daily Irodoku under Main Menu.
  final bool isDailyRoute;

  const GameScreen({super.key, this.isDailyRoute = false});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  bool _resultDialogShown = false;
  /// XP/unlocks only on the first Victory for this finished board.
  bool _offerResultXp = true;
  int _titlePlayToken = 0;

  @override
  void initState() {
    super.initState();
    if (!widget.isDailyRoute) {
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
    await game.startNewGame();
  }

  Future<void> _onTryAgain() async {
    final game = context.read<GameProvider>();
    if (game.isGenerating) return;
    _resultDialogShown = false;
    _offerResultXp = true;
    await game.retryFromDefeat();
  }

  void _maybeShowResult(GameProvider game) {
    // Home and Daily routes share one provider — only the matching route
    // should present win/loss dialogs.
    if (widget.isDailyRoute != game.isDaily) return;

    if (game.isWon && !_resultDialogShown) {
      _resultDialogShown = true;
      final includeXp = _offerResultXp && !game.isDailyReview;
      _offerResultXp = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (includeXp) {
          final unlocks = game.consumePendingPaletteUnlocks();
          for (final palette in unlocks) {
            _showPaletteUnlockedSnackBar(context, palette);
          }
        }
        showWinDialog(
          context,
          time: game.formatElapsed(),
          showNewGame: !widget.isDailyRoute,
          onNewGame: _onNewGame,
          xp: includeXp ? context.read<StatsProvider>().lastXpAward : null,
        );
      });
    } else if (game.isLost && !_resultDialogShown) {
      _resultDialogShown = true;
      _offerResultXp = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showLoseDialog(
          context,
          showNewGame: false,
          onTryAgain: _onTryAgain,
          onNewGame: _onNewGame,
          maxMistakes: game.mistakeLimit,
        );
      });
    } else if (!game.isGameOver) {
      _resultDialogShown = false;
      _offerResultXp = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<GameProvider, SettingsProvider>(
      builder: (context, game, settings, _) {
        _maybeShowResult(game);
        final hasSelection = game.hasCellSelection;
        // Keep control-slot layout while paused / after win-loss so the board
        // doesn't resize; only the widgets themselves are removed.
        final reserveControlsLayout = !game.isGenerating &&
            (game.hasActiveGame || game.isGameOver);
        final showControls =
            reserveControlsLayout && !game.isGameOver && !game.isPaused;
        final controlsEnabled = showControls;
        final canErase = game.canEraseSelection;
        final canPause = game.hasActiveGame &&
            !game.isGenerating &&
            !game.isGameOver;

        final titleText = widget.isDailyRoute
            ? (game.isPocket ? '[Daily Challenge]' : 'Daily Challenge')
            : game.isPocket && settings.chromatic
                ? '[Chromatic]'
                : game.isPocket
                    ? 'Pocket'
                    : (settings.chromatic ? 'Chromatic' : 'Irodoku');
        final titleStyle = _centeredAppBarTitleStyle(
          context,
          text: titleText,
          leadingWidth: widget.isDailyRoute ? 56 : 0,
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
              leading: widget.isDailyRoute
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
                onTap: game.triggerColorCycle,
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
                      await Navigator.of(context).push(
                        IrodokuPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                      if (!mounted) return;
                      // Returning to a finished board should show Victory/Defeat again.
                      _resultDialogShown = false;
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
                            child: TimerDisplay(time: game.formatElapsed()),
                          ),
                        ),
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
                              ? toolbarGap +
                                  GameToolbar.height +
                                  pickerGap
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
                          final cellSize =
                              math.min(cellFromWidth, cellFromHeight);
                          final boardSize = cellSize * layoutN + boardBorder * 2;
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
                            animate: settings.chromatic || game.isDaily,
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
                                              ),
                                            ),
                                            if (game.isPaused)
                                              Positioned.fill(
                                                child: _PausedBoard(
                                                  onResume: game.resumeGame,
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
                                                canUndo: controlsEnabled &&
                                                    game.canUndo,
                                                noteMode: game.noteMode,
                                                bulkNoteSelect:
                                                    game.bulkNoteSelect,
                                                canErase: controlsEnabled &&
                                                    canErase,
                                                onUndo: game.undo,
                                                onErase: game.clearSelectedCell,
                                                onToggleNote:
                                                    game.toggleNoteMode,
                                                onNoteLongPress: game
                                                        .canEnterBulkNoteSelectFromToolbar
                                                    ? game
                                                        .enterBulkNoteSelectFromToolbar
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
                                              xlMode: xlPicker && !pocketPicker,
                                              pocket: pocketPicker,
                                              palette: palette,
                                              displaySwatches: swatches,
                                              swatchSources: game.iroSources,
                                              visible: true,
                                              onColorSelected:
                                                  game.applyPickerColor,
                                              onNoteAdded: game.addSelectedNote,
                                              onNoteRemoved:
                                                  game.removeSelectedNote,
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

        if (!widget.isDailyRoute) return scaffold;

        return PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) game.parkDailyForMenu();
          },
          child: scaffold,
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
                style: Theme.of(context).snackBarTheme.contentTextStyle ??
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

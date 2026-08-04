import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/irodoku_page_route.dart';
import '../core/theme.dart';
import '../models/game_palette.dart';
import '../providers/game_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/chromatic_palette_transition.dart';
import '../widgets/color_picker.dart';
import '../widgets/dice_new_game_button.dart';
import '../widgets/game_toolbar.dart';
import '../widgets/mistake_display.dart';
import '../widgets/start_new_game_dialog.dart';
import '../widgets/sudoku_grid.dart';
import '../widgets/timer_display.dart';
import '../widgets/typing_title.dart';
import '../widgets/win_dialog.dart';
import 'settings_screen.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  bool _resultDialogShown = false;
  int _titlePlayToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GameProvider>().bootstrap();
    });
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
    await game.startNewGame();
  }

  void _maybeShowResult(GameProvider game) {
    if (game.isWon && !_resultDialogShown) {
      _resultDialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final unlocks = game.consumePendingPaletteUnlocks();
        for (final palette in unlocks) {
          _showPaletteUnlockedSnackBar(context, palette);
        }
        showWinDialog(
          context,
          time: game.formatElapsed(),
          onNewGame: _onNewGame,
        );
      });
    } else if (game.isLost && !_resultDialogShown) {
      _resultDialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showLoseDialog(
          context,
          onNewGame: _onNewGame,
        );
      });
    } else if (!game.isGameOver) {
      _resultDialogShown = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<GameProvider, SettingsProvider>(
      builder: (context, game, settings, _) {
        _maybeShowResult(game);
        final hasSelection = game.hasCellSelection;
        final showControls = game.hasActiveGame &&
            !game.isGenerating &&
            !game.isGameOver &&
            !game.isPaused;
        final canErase = game.canEraseSelection;
        final canPause = game.hasActiveGame &&
            !game.isGenerating &&
            !game.isGameOver;

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: hasSelection
              ? game.clearSelection
              : (game.isPaused ? game.resumeGame : null),
          child: Scaffold(
            appBar: AppBar(
              title: TypingTitle(
                text: 'Irodoku',
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
                DiceNewGameButton(
                  onPressed: game.isGenerating ? null : _onNewGame,
                ),
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () async {
                    await Navigator.of(context).push(
                      IrodokuPageRoute(builder: (_) => const SettingsScreen()),
                    );
                    if (!mounted) return;
                    setState(() => _titlePlayToken++);
                  },
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
                        TimerDisplay(time: game.formatElapsed()),
                        const Spacer(),
                        MistakeDisplay(mistakes: game.mistakes),
                        const Spacer(),
                        Text(
                          game.difficulty.label,
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.55),
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
                          final belowFixed = showControls
                              ? toolbarGap +
                                  GameToolbar.height +
                                  pickerGap
                              : 0.0;
                          final pickerRows = xlPicker ? xlSwatchCells * 3 : 1.0;
                          final cellFromWidth =
                              (constraints.maxWidth - boardBorder * 2) / 9;
                          final cellFromHeight = showControls
                              ? (constraints.maxHeight -
                                      belowFixed -
                                      boardBorder * 2) /
                                  (9 + pickerRows)
                              : (constraints.maxHeight -
                                      belowFixed -
                                      boardBorder * 2) /
                                  9;
                          final cellSize =
                              math.min(cellFromWidth, cellFromHeight);
                          final boardSize = cellSize * 9 + boardBorder * 2;
                          final swatchSize = xlPicker ? cellSize * xlSwatchCells : cellSize;

                          return ChromaticPaletteTransition(
                            palette: settings.palette,
                            animate: settings.chromatic,
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
                                              _PausedBoard(
                                                size: boardSize,
                                                onResume: game.resumeGame,
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
                                      if (showControls) ...[
                                        const SizedBox(height: toolbarGap),
                                        GestureDetector(
                                          onTap: () {},
                                          behavior: HitTestBehavior.opaque,
                                          child: GameToolbar(
                                            canUndo: game.canUndo,
                                            noteMode: game.noteMode,
                                            bulkNoteSelect: game.bulkNoteSelect,
                                            canErase: canErase,
                                            onUndo: game.undo,
                                            onErase: game.clearSelectedCell,
                                            onToggleNote: game.toggleNoteMode,
                                            onNoteLongPress: game
                                                    .canEnterBulkNoteSelectFromToolbar
                                                ? game
                                                    .enterBulkNoteSelectFromToolbar
                                                : null,
                                          ),
                                        ),
                                        const SizedBox(height: pickerGap),
                                        ColorPicker(
                                          swatchSize: swatchSize,
                                          xlMode: xlPicker,
                                          palette: palette,
                                          displaySwatches: swatches,
                                          visible: true,
                                          onColorSelected:
                                              game.applyPickerColor,
                                          onNoteAdded: game.addSelectedNote,
                                          onNoteRemoved:
                                              game.removeSelectedNote,
                                        ),
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
  final double size;
  final VoidCallback onResume;

  const _PausedBoard({
    required this.size,
    required this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = IrodokuTheme.boardBrightness;
    final thick = IrodokuTheme.thickGridLine(brightness);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onResume,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: IrodokuTheme.emptyCellFill(brightness),
          border: Border.all(color: thick, width: 2.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.pause_circle_outline,
              size: 56,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.45),
            ),
            const SizedBox(height: 12),
            Text(
              'Paused',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontFamily: 'Balatro',
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

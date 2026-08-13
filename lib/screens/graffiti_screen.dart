import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../providers/graffiti_provider.dart';
import '../providers/settings_provider.dart';
import '../services/graffiti_firebase_service.dart';
import '../widgets/color_picker.dart';
import '../widgets/game_toolbar.dart';
import '../widgets/graffiti_grid.dart';
import '../widgets/menu_action_button.dart';
import '../widgets/mistake_display.dart';
import '../widgets/timer_display.dart';
import '../widgets/typing_title.dart';

class GraffitiScreen extends StatefulWidget {
  const GraffitiScreen({super.key});

  @override
  State<GraffitiScreen> createState() => _GraffitiScreenState();
}

class _GraffitiScreenState extends State<GraffitiScreen> {
  final _joinController = TextEditingController();
  GraffitiProvider? _game;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _game = context.read<GraffitiProvider>();
      _game!.addListener(_onGraffiti);
    });
  }

  void _onGraffiti() {
    if (!mounted) return;
    final game = _game;
    if (game == null) return;
    final toast = game.toast;
    if (toast != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(toast), duration: const Duration(seconds: 3)),
      );
      game.clearToast();
    }
  }

  @override
  void dispose() {
    _game?.removeListener(_onGraffiti);
    _joinController.dispose();
    super.dispose();
  }

  Future<void> _confirmLeave(BuildContext context, GraffitiProvider game) async {
    if (game.phase == GraffitiPhase.idle) {
      Navigator.of(context).pop();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Graffiti?'),
        content: const Text('You will disconnect from the match.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      await game.leave();
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: IrodokuTheme.settingsTheme(Theme.of(context)),
      child: Consumer2<GraffitiProvider, SettingsProvider>(
      builder: (context, game, settings, _) {
        final playing = game.phase == GraffitiPhase.playing ||
            game.phase == GraffitiPhase.finished;
        return Scaffold(
          appBar: AppBar(
            title: const TypingTitle(text: 'Graffiti'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => _confirmLeave(context, game),
            ),
            actions: [
              if (game.roomCode != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    child: Text(
                      game.roomCode!,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            letterSpacing: 1.2,
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
          body: SafeArea(
            child: playing ? _GameBody(game: game, settings: settings) : _LobbyBody(
              game: game,
              joinController: _joinController,
            ),
          ),
        );
      },
    ),
    );
  }
}

class _LobbyBody extends StatelessWidget {
  final GraffitiProvider game;
  final TextEditingController joinController;

  const _LobbyBody({
    required this.game,
    required this.joinController,
  });

  @override
  Widget build(BuildContext context) {
    final waiting = game.phase == GraffitiPhase.waiting ||
        game.phase == GraffitiPhase.searching ||
        game.phase == GraffitiPhase.connecting;
    final message = game.statusMessage;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(
          'Irodoku VS; color in more cells than your opponent to win',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.7),
              ),
        ),
        const SizedBox(height: 24),
        if (waiting) ...[
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 16),
          if (message != null)
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          if (game.roomCode != null && game.isHost) ...[
            const SizedBox(height: 8),
            Text(
              'Share code: ${game.roomCode}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: game.roomCode!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Code copied')),
                  );
                },
                child: const Text('[copy]'),
              ),
            ),
          ],
          const SizedBox(height: 24),
          MenuActionButton(
            label: 'Cancel',
            onPressed: () => game.leave(),
          ),
        ] else ...[
          MenuActionButton(
            label: 'Quick Play',
            enabled: !game.busy,
            onPressed: game.quickPlay,
          ),
          const SizedBox(height: 12),
          MenuActionButton(
            label: 'Create Room',
            enabled: !game.busy,
            onPressed: game.createRoom,
          ),
          const SizedBox(height: 24),
          Text(
            'Join with code',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: joinController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 5,
                  decoration: const InputDecoration(
                    counterText: '',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                ),
                onPressed: game.busy
                    ? null
                    : () => game.joinRoom(joinController.text),
                child: const Text('Join'),
              ),
            ],
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.55),
                  ),
            ),
          ],
        ],
      ],
    );
  }
}

class _GameBody extends StatelessWidget {
  final GraffitiProvider game;
  final SettingsProvider settings;

  const _GameBody({required this.game, required this.settings});

  @override
  Widget build(BuildContext context) {
    final controlsEnabled = game.controlsEnabled;
    final outcome = game.outcome;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: game.hasCellSelection ? game.clearSelection : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
        children: [
          Row(
            children: [
              TimerDisplay(time: game.formatElapsed()),
              const Spacer(),
              MistakeDisplay(
                mistakes: game.myMistakes,
                maxMistakes: GraffitiFirebaseService.maxMistakes,
              ),
              const Spacer(),
              _GraffitiScore(
                you: game.myCorrect,
                opponent: game.oppCorrect,
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
                final belowFixed = toolbarGap + GameToolbar.height + pickerGap;
                final pickerRows = xlPicker ? xlSwatchCells * 3 : 1.0;
                final cellFromWidth =
                    (constraints.maxWidth - boardBorder * 2) / 9;
                final cellFromHeight = (constraints.maxHeight -
                        belowFixed -
                        boardBorder * 2) /
                    (9 + pickerRows);
                final cellSize = math.min(cellFromWidth, cellFromHeight);
                final boardSize = cellSize * 9 + boardBorder * 2;
                final swatchSize =
                    xlPicker ? cellSize * xlSwatchCells : cellSize;
                final pickerHeight = swatchSize * (xlPicker ? 3.0 : 1.0);
                final overlayLabel = switch (outcome) {
                  GraffitiOutcome.win => '[VICTORY]',
                  GraffitiOutcome.lose || GraffitiOutcome.defeat => '[DEFEAT]',
                  GraffitiOutcome.draw => '[DRAW]',
                  GraffitiOutcome.none when game.eliminated => '[spectating]',
                  GraffitiOutcome.none => null,
                };

                return Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: boardSize,
                    child: Column(
                      children: [
                        SizedBox(
                          width: boardSize,
                          height: boardSize,
                          child: GraffitiGrid(
                            game: game,
                            palette: game.activePalette,
                          ),
                        ),
                        const SizedBox(height: toolbarGap),
                        IgnorePointer(
                          ignoring: !controlsEnabled,
                          child: GestureDetector(
                            onTap: () {},
                            behavior: HitTestBehavior.opaque,
                            child: GameToolbar(
                              canUndo: controlsEnabled && game.canUndo,
                              noteMode: game.noteMode,
                              bulkNoteSelect: game.bulkNoteSelect,
                              canErase: controlsEnabled && game.canEraseSelected,
                              onUndo: game.undo,
                              onErase: game.clearSelectedCell,
                              onToggleNote: game.toggleNoteMode,
                              onNoteLongPress:
                                  game.canEnterBulkNoteSelectFromToolbar
                                      ? game.enterBulkNoteSelectFromToolbar
                                      : null,
                            ),
                          ),
                        ),
                        const SizedBox(height: pickerGap),
                        if (overlayLabel != null)
                          SizedBox(
                            height: pickerHeight,
                            child: Center(
                              child: Text(
                                overlayLabel,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface,
                                    ),
                              ),
                            ),
                          )
                        else
                          IgnorePointer(
                            ignoring: !controlsEnabled,
                            child: ColorPicker(
                              swatchSize: swatchSize,
                              visible: true,
                              xlMode: xlPicker,
                              palette: game.activePalette,
                              onColorSelected: game.inputColor,
                              onNoteAdded: game.addNote,
                              onNoteRemoved: game.removeNote,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
    );
  }
}

class _GraffitiScore extends StatefulWidget {
  final int you;
  final int opponent;

  const _GraffitiScore({
    required this.you,
    required this.opponent,
  });

  @override
  State<_GraffitiScore> createState() => _GraffitiScoreState();
}

class _GraffitiScoreState extends State<_GraffitiScore>
    with TickerProviderStateMixin {
  static const _peak = 1.22;
  static const _duration = Duration(milliseconds: 320);

  late final AnimationController _youController;
  late final AnimationController _oppController;
  late final Animation<double> _youScale;
  late final Animation<double> _oppScale;
  late int _prevYou;
  late int _prevOpp;

  @override
  void initState() {
    super.initState();
    _prevYou = widget.you;
    _prevOpp = widget.opponent;
    _youController = AnimationController(vsync: this, duration: _duration);
    _oppController = AnimationController(vsync: this, duration: _duration);
    _youScale = _bounce(_youController);
    _oppScale = _bounce(_oppController);
  }

  Animation<double> _bounce(AnimationController controller) {
    return TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: _peak).chain(
          CurveTween(curve: Curves.easeOutCubic),
        ),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: _peak, end: 1.0).chain(
          CurveTween(curve: Curves.easeInCubic),
        ),
        weight: 1.15,
      ),
    ]).animate(controller);
  }

  @override
  void didUpdateWidget(covariant _GraffitiScore oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.you > _prevYou) {
      _youController.forward(from: 0);
    }
    if (widget.opponent > _prevOpp) {
      _oppController.forward(from: 0);
    }
    _prevYou = widget.you;
    _prevOpp = widget.opponent;
  }

  @override
  void dispose() {
    _youController.dispose();
    _oppController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
        );
    return AnimatedBuilder(
      animation: Listenable.merge([_youScale, _oppScale]),
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.scale(
              scale: _youScale.value,
              child: Text('${widget.you}', style: style),
            ),
            Text(' - ', style: style),
            Transform.scale(
              scale: _oppScale.value,
              child: Text('${widget.opponent}', style: style),
            ),
          ],
        );
      },
    );
  }
}

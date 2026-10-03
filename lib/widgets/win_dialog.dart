import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/player_xp.dart';
import '../providers/graffiti_provider.dart';
import '../providers/stats_provider.dart';
import 'menu_select_sound.dart';
import 'xp_gain_panel.dart';

const _resultTransitionDuration = Duration(milliseconds: 200);

Widget _resultTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final pop = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
  return FadeTransition(
    opacity: pop,
    child: ScaleTransition(
      scale: Tween<double>(begin: 0, end: 1).animate(pop),
      child: child,
    ),
  );
}

class VictoryPanel extends StatelessWidget {
  final String time;
  final VoidCallback onClose;
  final VoidCallback onNewGame;
  final bool showNewGame;
  final String? leaderboardLabel;
  final VoidCallback? onLeaderboard;
  final XpAward? xp;

  const VictoryPanel({
    super.key,
    required this.time,
    required this.onClose,
    required this.onNewGame,
    this.showNewGame = true,
    this.leaderboardLabel,
    this.onLeaderboard,
    this.xp,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Colors.white : Colors.black;
    final onInk = dark ? Colors.black : Colors.white;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Victory',
        textAlign: TextAlign.center,
        style: TextStyle(color: ink),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _VictoryIcon(dark: dark),
            const SizedBox(height: 16),
            Text(
              time,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: ink),
            ),
            if (xp != null) ...[
              const SizedBox(height: 16),
              XpGainPanel(award: xp!, ink: ink),
            ],
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        if (showNewGame)
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ink,
              foregroundColor: onInk,
            ),
            onPressed: withMenuSelect(context, () {
              onClose();
              onNewGame();
            }),
            child: const Text('Next game'),
          ),
        if (leaderboardLabel != null && onLeaderboard != null)
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ink,
              foregroundColor: onInk,
            ),
            onPressed: withMenuSelect(context, onLeaderboard!),
            child: Text(leaderboardLabel!),
          ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: ink),
          onPressed: onClose,
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class DefeatPanel extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback onNewGame;
  final bool showNewGame;
  final VoidCallback? onTryAgain;
  final int maxMistakes;

  const DefeatPanel({
    super.key,
    required this.onClose,
    required this.onNewGame,
    this.showNewGame = true,
    this.onTryAgain,
    this.maxMistakes = 3,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Colors.white : Colors.black;
    final onInk = dark ? Colors.black : Colors.white;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Defeat',
        textAlign: TextAlign.center,
        style: TextStyle(color: ink),
      ),
      content: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < maxMistakes; i++)
            Icon(Icons.close, size: 48, weight: 700, color: ink),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        if (onTryAgain != null)
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ink,
              foregroundColor: onInk,
            ),
            onPressed: withMenuSelect(context, () {
              onClose();
              onTryAgain!();
            }),
            child: const Text('Try again'),
          )
        else if (showNewGame)
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ink,
              foregroundColor: onInk,
            ),
            onPressed: withMenuSelect(context, () {
              onClose();
              onNewGame();
            }),
            child: const Text('New Game'),
          ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: ink),
          onPressed: onClose,
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// In-route dimmer + centered result card. Avoids [showGeneralDialog] overlays,
/// which go blank on web when the game rebuilds under [WebLayout].
class ResultScrim extends StatelessWidget {
  final Widget child;

  const ResultScrim({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          const ModalBarrier(dismissible: false, color: Colors.black54),
          Center(child: child),
        ],
      ),
    );
  }
}

Future<void> showWinDialog(
  BuildContext context, {
  required String time,
  required VoidCallback onNewGame,
  bool showNewGame = true,
  String? leaderboardLabel,
  VoidCallback? onLeaderboard,
  XpAward? xp,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Win',
    barrierColor: Colors.black54,
    transitionDuration: _resultTransitionDuration,
    transitionBuilder: _resultTransition,
    pageBuilder: (context, animation, secondaryAnimation) {
      return VictoryPanel(
        time: time,
        showNewGame: showNewGame,
        leaderboardLabel: leaderboardLabel,
        onLeaderboard: onLeaderboard,
        xp: xp,
        onNewGame: onNewGame,
        onClose: () => Navigator.of(context).pop(),
      );
    },
  );
}

class _VictoryIcon extends StatelessWidget {
  final bool dark;

  const _VictoryIcon({required this.dark});

  @override
  Widget build(BuildContext context) {
    final gem = Image.asset(
      'assets/icons/victory_icon.png',
      height: 52,
      filterQuality: FilterQuality.none,
    );
    if (!dark) return gem;
    // Invert so the baked black outline reads on a dark dialog.
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        -1,
        0,
        0,
        0,
        255,
        0,
        -1,
        0,
        0,
        255,
        0,
        0,
        -1,
        0,
        255,
        0,
        0,
        0,
        1,
        0,
      ]),
      child: gem,
    );
  }
}

Future<void> showLoseDialog(
  BuildContext context, {
  required VoidCallback onNewGame,
  bool showNewGame = true,
  VoidCallback? onTryAgain,
  int maxMistakes = 3,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Lose',
    barrierColor: Colors.black54,
    transitionDuration: _resultTransitionDuration,
    transitionBuilder: _resultTransition,
    pageBuilder: (context, animation, secondaryAnimation) {
      return DefeatPanel(
        showNewGame: showNewGame,
        onTryAgain: onTryAgain,
        onNewGame: onNewGame,
        maxMistakes: maxMistakes,
        onClose: () => Navigator.of(context).pop(),
      );
    },
  );
}

Future<void> showGraffitiResultDialog(BuildContext context) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'GraffitiResult',
    barrierColor: Colors.black54,
    transitionDuration: _resultTransitionDuration,
    transitionBuilder: _resultTransition,
    pageBuilder: (context, animation, secondaryAnimation) {
      return const _GraffitiResultDialog();
    },
  );
}

class _GraffitiResultDialog extends StatefulWidget {
  const _GraffitiResultDialog();

  @override
  State<_GraffitiResultDialog> createState() => _GraffitiResultDialogState();
}

class _GraffitiResultDialogState extends State<_GraffitiResultDialog> {
  GraffitiProvider? _game;
  bool _popped = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_game != null) return;
    _game = context.read<GraffitiProvider>();
    _game!.addListener(_onGame);
  }

  void _onGame() {
    final game = _game;
    if (game == null || !mounted || _popped) return;
    if (game.phase != GraffitiPhase.finished) {
      _popped = true;
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _game?.removeListener(_onGame);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = context.watch<GraffitiProvider>();
    final stats = context.watch<StatsProvider>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Colors.white : Colors.black;
    final onInk = dark ? Colors.black : Colors.white;
    final outcome = game.outcome;
    final waiting = game.iWantRematch;
    final rematchEnabled = game.rematchAvailable && !waiting;
    final xp = stats.lastXpAward;
    final showXp =
        xp != null &&
        (xp.sourceLabel == 'Graffiti' || xp.sourceLabel == '[Graffiti]') &&
        (outcome == GraffitiOutcome.win ||
            outcome == GraffitiOutcome.lose ||
            outcome == GraffitiOutcome.defeat ||
            outcome == GraffitiOutcome.draw);

    final title = switch (outcome) {
      GraffitiOutcome.win => 'Victory',
      GraffitiOutcome.draw => 'Draw',
      GraffitiOutcome.lose ||
      GraffitiOutcome.defeat ||
      GraffitiOutcome.none => 'Defeat',
    };

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        title,
        textAlign: TextAlign.center,
        style: TextStyle(color: ink),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (outcome == GraffitiOutcome.win) ...[
              _VictoryIcon(dark: dark),
              const SizedBox(height: 16),
            ] else if (outcome == GraffitiOutcome.lose ||
                outcome == GraffitiOutcome.defeat) ...[
              Icon(
                Icons.close,
                size: 52,
                weight: 700,
                color: ink,
              ),
              const SizedBox(height: 16),
            ],
            Text(
              game.formatElapsed(),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: ink),
            ),
            const SizedBox(height: 8),
            Text(
              '${game.myCorrect} - ${game.oppCorrect}',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: ink),
            ),
            if (showXp) ...[
              const SizedBox(height: 16),
              XpGainPanel(award: xp, ink: ink),
            ],
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: ink,
            foregroundColor: onInk,
            disabledBackgroundColor: ink.withValues(alpha: 0.35),
            disabledForegroundColor: onInk.withValues(alpha: 0.7),
          ),
          onPressed: rematchEnabled
              ? withMenuSelect(context, () {
                  game.requestRematch();
                })
              : null,
          child: Text(
            game.solo ? 'Opponent left' : (waiting ? 'Waiting…' : 'Rematch'),
          ),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: ink),
          onPressed: withMenuSelect(context, () {
            game.cancelRematch();
            if (_popped) return;
            _popped = true;
            Navigator.of(context).pop();
          }),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

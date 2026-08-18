import 'package:flutter/material.dart';

import '../models/player_xp.dart';
import 'menu_select_sound.dart';
import 'xp_gain_panel.dart';

const _resultTransitionDuration = Duration(milliseconds: 200);

Widget _resultTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final pop = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
  );
  return FadeTransition(
    opacity: pop,
    child: ScaleTransition(
      scale: Tween<double>(begin: 0, end: 1).animate(pop),
      child: child,
    ),
  );
}

Future<void> showWinDialog(
  BuildContext context, {
  required String time,
  required VoidCallback onNewGame,
  bool showNewGame = true,
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
      final dark = Theme.of(context).brightness == Brightness.dark;
      final ink = dark ? Colors.white : Colors.black;
      final onInk = dark ? Colors.black : Colors.white;

      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
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
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: ink,
                    ),
              ),
              if (xp != null) ...[
                const SizedBox(height: 16),
                XpGainPanel(award: xp, ink: ink),
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
                Navigator.of(context).pop();
                onNewGame();
              }),
              child: const Text('Next game'),
            ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: ink),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
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
        -1, 0, 0, 0, 255,
        0, -1, 0, 0, 255,
        0, 0, -1, 0, 255,
        0, 0, 0, 1, 0,
      ]),
      child: gem,
    );
  }
}

Future<void> showLoseDialog(
  BuildContext context, {
  required VoidCallback onNewGame,
  bool showNewGame = true,
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
      final dark = Theme.of(context).brightness == Brightness.dark;
      final ink = dark ? Colors.white : Colors.black;
      final onInk = dark ? Colors.black : Colors.white;

      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          'Defeat',
          textAlign: TextAlign.center,
          style: TextStyle(color: ink),
        ),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < maxMistakes; i++)
              Icon(
                Icons.close,
                size: 48,
                weight: 700,
                color: ink,
              ),
          ],
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
                Navigator.of(context).pop();
                onNewGame();
              }),
              child: const Text('New Game'),
            ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: ink),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

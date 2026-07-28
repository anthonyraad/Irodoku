import 'package:flutter/material.dart';

Future<void> showWinDialog(
  BuildContext context, {
  required String time,
  required VoidCallback onNewGame,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Win',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (context, animation, secondaryAnimation) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      final ink = dark ? Colors.white : Colors.black;
      final onInk = dark ? Colors.black : Colors.white;

      return ScaleTransition(
        scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
        child: FadeTransition(
          opacity: animation,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              'Victory',
              textAlign: TextAlign.center,
              style: TextStyle(color: ink),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 48,
                  color: ink,
                ),
                const SizedBox(height: 16),
                Text(
                  time,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: ink,
                      ),
                ),
              ],
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: ink,
                  foregroundColor: onInk,
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  onNewGame();
                },
                child: const Text('New Game'),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: ink),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> showLoseDialog(
  BuildContext context, {
  required VoidCallback onNewGame,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Lose',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (context, animation, secondaryAnimation) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      final ink = dark ? Colors.white : Colors.black;
      final onInk = dark ? Colors.black : Colors.white;

      return ScaleTransition(
        scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
        child: FadeTransition(
          opacity: animation,
          child: AlertDialog(
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
                for (var i = 0; i < 3; i++)
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
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: ink,
                  foregroundColor: onInk,
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  onNewGame();
                },
                child: const Text('New Game'),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: ink),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

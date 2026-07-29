import 'package:flutter/material.dart';

import 'typing_title.dart';

/// Minimal confirm used when starting a new game would discard mid-match progress.
Future<bool?> showStartNewGameDialog(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final ink = dark ? Colors.white : Colors.black;
  final onInk = dark ? Colors.black : Colors.white;

  return showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: SizedBox(
          width: double.infinity,
          child: TypingTitle(
            text: 'Start new game?',
            textAlign: TextAlign.center,
            style: TextStyle(color: ink),
            // Faster than the app-bar title so the modal feels snappy.
            charDelay: const Duration(milliseconds: 18),
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: ink),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ink,
              foregroundColor: onInk,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes'),
          ),
        ],
      );
    },
  );
}

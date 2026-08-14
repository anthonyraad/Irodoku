import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../services/sound_service.dart';

/// Menu / modal tap sting, if sound is on and [SoundService] is in the tree.
void playMenuSelectSound(BuildContext context) {
  final settings = context.read<SettingsProvider>();
  if (!settings.soundEnabled) return;
  unawaited(context.read<SoundService>().playMenuSelect());
}

/// Plays the menu sting, then [onPressed].
VoidCallback withMenuSelect(BuildContext context, VoidCallback onPressed) {
  return () {
    playMenuSelectSound(context);
    onPressed();
  };
}

/// Same as [withMenuSelect], or null when [onPressed] is null.
VoidCallback? withMenuSelectOrNull(
  BuildContext context,
  VoidCallback? onPressed,
) {
  if (onPressed == null) return null;
  return withMenuSelect(context, onPressed);
}

/// App-bar back that plays the menu sting.
class MenuBackButton extends StatelessWidget {
  const MenuBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const BackButtonIcon(),
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: withMenuSelect(context, () {
        Navigator.maybePop(context);
      }),
    );
  }
}

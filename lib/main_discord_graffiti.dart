import 'package:flutter/material.dart';

import 'core/organic_swatch_shader.dart';
import 'discord_graffiti/graffiti_discord_shell.dart';
import 'services/preferences_service.dart';
import 'sudoku/master_board_bank.dart';
import 'widgets/age_gate.dart';

/// Entrypoint for the [Graffiti] Discord Activity (separate Discord app).
///
/// Build: `bash web_discord_graffiti/build.sh` (Pages: /Irodoku/discord-graffiti/).
/// Does not set DiscordMode (that is the Pocket Daily Iro Activity).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AgeGate.inDiscordActivity = true; // Discord users are 13+: no age step
  await OrganicSwatchShader.ensureLoaded();
  try {
    await MasterBoardBank.load();
  } catch (e) {
    debugPrint('Master board bank unavailable: $e');
  }
  final preferences = await PreferencesService.create();
  runApp(
    GraffitiNetOverlay(child: DiscordGraffitiApp(preferences: preferences)),
  );
}

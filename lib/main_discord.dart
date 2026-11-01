import 'package:flutter/material.dart';

import 'discord/discord_mode.dart';
import 'discord/discord_shell.dart';
import 'core/organic_swatch_shader.dart';
import 'services/preferences_service.dart';
import 'sudoku/master_board_bank.dart';

/// Entrypoint for the Discord Activity ("Pocket Daily Iro").
///
/// Build: `flutter build web -t lib/main_discord.dart --dart-define=DISCORD=true`
/// (see `discord/build_web.sh`).
Future<void> main() async {
  DiscordMode.enabled = true;
  WidgetsFlutterBinding.ensureInitialized();
  await OrganicSwatchShader.ensureLoaded();
  try {
    await MasterBoardBank.load();
  } catch (e) {
    debugPrint('Master board bank unavailable: $e');
  }
  final preferences = await PreferencesService.create();
  runApp(DiscordIrodokuApp(preferences: preferences));
}

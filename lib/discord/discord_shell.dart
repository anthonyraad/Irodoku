import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../models/daily_irodoku.dart';
import '../providers/game_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/game_screen.dart';
import '../services/preferences_service.dart';
import 'discord_bridge.dart';
import 'discord_mode.dart';

/// Root of the Discord Activity: same providers/theme as [IrodokuApp], but
/// the home is today's Pocket Daily with no Main Menu.
class DiscordIrodokuApp extends StatelessWidget {
  final PreferencesService preferences;
  const DiscordIrodokuApp({super.key, required this.preferences});

  @override
  Widget build(BuildContext context) =>
      IrodokuApp(preferences: preferences, home: const DiscordPocketDaily());
}

class DiscordPocketDaily extends StatefulWidget {
  const DiscordPocketDaily({super.key});

  @override
  State<DiscordPocketDaily> createState() => _DiscordPocketDailyState();
}

class _DiscordPocketDailyState extends State<DiscordPocketDaily> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    final game = context.read<GameProvider>();
    final auth = DiscordBridge.init();
    // The Activity runs in Discord's iframe with fresh storage, so the
    // first-run tutorial flag is set — but the Daily route never shows that
    // overlay, and GameProvider holds the clock until it is dismissed. Mark
    // it done so the timer runs from the moment the puzzle is shown.
    await context.read<SettingsProvider>().completeFirstRunTutorial();
    await game.bootstrap();
    await game.startPocketDailyGame(force: true);
    DiscordMode.username = await auth;
    final dayKey = game.dailyDayKey ?? DailyIrodoku.pocketForDate().dayKey;
    if (!game.isGameOver) await DiscordBridge.startRun(dayKey);
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return const GameScreen(isDailyRoute: true);
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'core/web_layout.dart';
import 'providers/game_provider.dart';
import 'providers/iroen_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/stats_provider.dart';
import 'screens/game_screen.dart';
import 'services/preferences_service.dart';

class IrodokuApp extends StatelessWidget {
  final PreferencesService preferences;

  const IrodokuApp({super.key, required this.preferences});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<PreferencesService>.value(value: preferences),
        ChangeNotifierProvider(
          create: (_) => StatsProvider(preferences),
        ),
        ChangeNotifierProvider(
          create: (context) => SettingsProvider(
            preferences,
            stats: context.read<StatsProvider>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => GameProvider(
            settings: context.read<SettingsProvider>(),
            stats: context.read<StatsProvider>(),
            preferences: preferences,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => IroenProvider(preferences: preferences),
        ),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: 'Irodoku',
            debugShowCheckedModeBanner: false,
            theme: IrodokuTheme.light(),
            darkTheme: IrodokuTheme.dark(),
            themeMode: settings.darkMode ? ThemeMode.dark : ThemeMode.light,
            builder: WebLayout.wrap,
            home: const GameScreen(),
          );
        },
      ),
    );
  }
}

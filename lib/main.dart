import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/organic_swatch_shader.dart';
import 'services/preferences_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await OrganicSwatchShader.ensureLoaded();

  final preferences = await PreferencesService.create();
  runApp(IrodokuApp(preferences: preferences));
}

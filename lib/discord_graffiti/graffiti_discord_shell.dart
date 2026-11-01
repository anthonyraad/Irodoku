import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../core/irodoku_page_route.dart';
import '../core/theme.dart';
import '../firebase_options.dart';
import '../providers/settings_provider.dart';
import '../screens/graffiti_screen.dart';
import '../services/graffiti_firebase_service.dart';
import '../services/preferences_service.dart';
import '../widgets/menu_action_button.dart';
import 'graffiti_bridge.dart';
import 'graffiti_discord_auth.dart';

/// Root of the [Graffiti] Discord Activity: same providers/theme as
/// [IrodokuApp], home is the Graffiti picker (9×9 / 6×6) with no other modes.
class DiscordGraffitiApp extends StatelessWidget {
  final PreferencesService preferences;
  const DiscordGraffitiApp({super.key, required this.preferences});

  @override
  Widget build(BuildContext context) => IrodokuApp(
    preferences: preferences,
    home: const GraffitiDiscordHome(),
  );
}

/// Shared boot/debug state for the overlay.
class GraffitiDiscordStatus {
  GraffitiDiscordStatus._();
  static final ValueNotifier<String> auth = ValueNotifier('booting');
  static final ValueNotifier<bool?> rtdbConnected = ValueNotifier(null);
}

class GraffitiDiscordHome extends StatefulWidget {
  const GraffitiDiscordHome({super.key});

  @override
  State<GraffitiDiscordHome> createState() => _GraffitiDiscordHomeState();
}

class _GraffitiDiscordHomeState extends State<GraffitiDiscordHome> {
  bool _ready = false;
  String? _name;
  StreamSubscription<dynamic>? _connSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    final settings = context.read<SettingsProvider>();
    await settings.completeFirstRunTutorial();
    final status = GraffitiDiscordStatus.auth;
    try {
      if (!await GraffitiDiscordBridge.firebaseReady()) {
        status.value = 'firebase js failed to load';
      }
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
      }
      // Never hang the lobby on Discord auth; fall back to anonymous.
      final raw = await GraffitiDiscordBridge.init().timeout(
        const Duration(seconds: 25),
        onTimeout: () {
          GraffitiDiscordBridge.note('discord auth timed out');
          return null;
        },
      );
      final auth = GraffitiDiscordAuth.tryParse(raw);
      if (auth != null) {
        final cred = await FirebaseAuth.instance.signInWithCustomToken(
          auth.token,
        );
        status.value = 'discord ${cred.user?.uid ?? '?'}';
        if (auth.name.isNotEmpty) {
          await settings.setDisplayName(auth.name);
          _name = auth.name;
        }
      } else {
        status.value = GraffitiDiscordBridge.inDiscord
            ? 'discord auth failed -> anonymous'
            : 'browser -> anonymous';
      }
    } catch (e) {
      status.value = 'auth error: $e';
      GraffitiDiscordBridge.note('auth: $e');
    }
    // Anonymous fallback + marks the service ready.
    final ok = await GraffitiFirebaseService.ensureInitialized();
    if (ok) {
      if (!status.value.startsWith('discord ')) {
        status.value = '${status.value} (${GraffitiFirebaseService.playerId})';
      }
      _connSub = GraffitiFirebaseService.database
          .ref('.info/connected')
          .onValue
          .listen(
            (e) => GraffitiDiscordStatus.rtdbConnected.value =
                e.snapshot.value == true,
            onError: (Object e) => GraffitiDiscordBridge.note('.info: $e'),
          );
    } else {
      status.value = '${status.value}; firebase init failed';
    }
    _name ??= settings.displayName.isEmpty ? null : settings.displayName;
    if (mounted) setState(() => _ready = true);
  }

  void _open(bool pocket) {
    Navigator.of(context).push(
      IrodokuPageRoute(builder: (_) => GraffitiScreen(pocket: pocket)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: IrodokuTheme.settingsTheme(Theme.of(context)),
      child: Builder(
        builder: (context) => Scaffold(
          body: Stack(
            children: [
              SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: !_ready
                        ? const CircularProgressIndicator()
                        : Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Graffiti',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineMedium,
                                ),
                                if (_name != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Playing as $_name',
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                                const SizedBox(height: 24),
                                MenuActionButton(
                                  label: 'Graffiti - 9x9',
                                  onPressed: () => _open(false),
                                ),
                                const SizedBox(height: 12),
                                MenuActionButton(
                                  label: '[Graffiti] - 6x6',
                                  onPressed: () => _open(true),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small always-on-top connection readout (tap to expand/collapse). Lets the
/// first live Discord launch double as the Firebase-through-proxy test.
class GraffitiNetOverlay extends StatefulWidget {
  final Widget child;
  const GraffitiNetOverlay({super.key, required this.child});

  @override
  State<GraffitiNetOverlay> createState() => _GraffitiNetOverlayState();
}

class _GraffitiNetOverlayState extends State<GraffitiNetOverlay> {
  Timer? _tick;
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final raw = GraffitiDiscordBridge.netJson();
    final conn = GraffitiDiscordStatus.rtdbConnected.value;
    final line = describeNet(raw, rtdbConnected: conn);
    var errors = '';
    try {
      final m = raw == null ? null : jsonDecode(raw);
      if (m is Map && m['errors'] is List && (m['errors'] as List).isNotEmpty) {
        errors = (m['errors'] as List).join('\n');
      }
    } catch (_) {}
    final color = conn == true
        ? Colors.greenAccent
        : (conn == false ? Colors.orangeAccent : Colors.white70);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          widget.child,
          Positioned(
            left: 4,
            bottom: 4,
            child: GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 340),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _expanded
                      ? [
                          line,
                          GraffitiDiscordStatus.auth.value,
                          if (errors.isNotEmpty) errors,
                        ].join('\n')
                      : 'net',
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontFamily: 'Balatro', // bundled; Discord CSP blocks fonts.gstatic.com
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

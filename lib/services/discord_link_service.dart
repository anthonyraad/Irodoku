import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../discord/discord_mode.dart';
import 'graffiti_firebase_service.dart';

/// Android "Sync Discord": links this Firebase uid to a Discord account via
/// the irodoku-discord Worker (`/link/*`). Link records live at
/// `irodoku_links/android/{uid}` (owner-readable, Worker-written).
class DiscordLinkService extends ChangeNotifier {
  DiscordLinkService._();
  static final DiscordLinkService instance = DiscordLinkService._();

  static const workerBase = 'https://irodoku-discord.raadscapes.workers.dev';
  static const linksPath = 'irodoku_links/android';
  static const _prefId = 'discord_link_id';
  static const _prefName = 'discord_link_name';

  String? _discordId;
  String? _name;
  bool _busy = false;
  bool _started = false;
  StreamSubscription<Uri>? _linkSub;
  final _errors = StreamController<String>.broadcast();

  /// Discord user id when linked (also the Pocket Daily leaderboard key).
  String? get discordId => _discordId;
  String? get name => _name;
  bool get linked => _discordId != null;
  bool get busy => _busy;

  /// Link failures (deep-link `error=` codes or request failures).
  Stream<String> get errors => _errors.stream;

  /// Only the Android app links (not the Discord Activity / web builds).
  static bool get supported =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      !DiscordMode.enabled;

  /// Pocket Daily key for this player: Discord id when linked, else anon uid.
  String? pocketKey(String? uid) => _discordId ?? uid;

  /// Start listening for `irodoku://discord-linked` and load link state.
  void start() {
    if (_started || !supported) return;
    _started = true;
    final appLinks = AppLinks();
    _linkSub = appLinks.uriLinkStream.listen(_onUri, onError: (_) {});
    unawaited(_loadCached());
  }

  /// Cached link (so unlinked players never trigger Firebase at startup).
  Future<void> _loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_prefId);
      if (id != null && id.isNotEmpty) {
        _discordId = id;
        _name = prefs.getString(_prefName);
        notifyListeners();
        await refresh();
      }
    } catch (_) {}
  }

  Future<void> _saveCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_discordId == null) {
        await prefs.remove(_prefId);
        await prefs.remove(_prefName);
      } else {
        await prefs.setString(_prefId, _discordId!);
        await prefs.setString(_prefName, _name ?? '');
      }
    } catch (_) {}
  }

  /// Refresh from RTDB only if Firebase is already up or a link is cached.
  Future<void> refreshIfActive() async {
    if (!supported) return;
    if (Firebase.apps.isNotEmpty || linked) await refresh();
  }

  void _onUri(Uri uri) {
    if (uri.scheme != 'irodoku' || uri.host != 'discord-linked') return;
    final error = uri.queryParameters['error'];
    if (error != null && error.isNotEmpty) {
      _setBusy(false);
      _errors.add(error);
      return;
    }
    unawaited(refresh().whenComplete(() => _setBusy(false)));
  }

  void _setBusy(bool v) {
    if (_busy == v) return;
    _busy = v;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (!supported) return;
    final ready = await GraffitiFirebaseService.ensureInitialized();
    if (!ready) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap =
          await GraffitiFirebaseService.database.ref('$linksPath/$uid').get();
      final v = snap.value;
      String? id;
      String? name;
      if (v is Map) {
        final rawId = v['discordId']?.toString();
        if (rawId != null && rawId.isNotEmpty) {
          id = rawId;
          name = v['name']?.toString();
        }
      }
      if (id == _discordId && name == _name) return;
      _discordId = id;
      _name = name;
      notifyListeners();
      await _saveCached();
    } catch (_) {}
  }

  Future<String?> _idToken() async {
    final ready = await GraffitiFirebaseService.ensureInitialized();
    if (!ready) return null;
    return FirebaseAuth.instance.currentUser?.getIdToken();
  }

  Future<http.Response?> _post(String path) async {
    final token = await _idToken();
    if (token == null) return null;
    return http
        .post(
          Uri.parse('$workerBase$path'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 20));
  }

  /// Opens Discord authorization in the browser; result arrives as a deep link.
  Future<void> startLink() async {
    if (_busy) return;
    _setBusy(true);
    try {
      final res = await _post('/link/start');
      final url = res != null && res.statusCode == 200
          ? (jsonDecode(res.body) as Map)['url']?.toString()
          : null;
      if (url == null) throw StateError('start_failed');
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) throw StateError('launch_failed');
      // Busy clears when the deep link returns (or on next start()).
      _setBusy(false);
    } catch (_) {
      _setBusy(false);
      _errors.add('start_failed');
    }
  }

  Future<bool> disconnect() async {
    if (_busy) return false;
    _setBusy(true);
    try {
      final res = await _post('/link/disconnect');
      if (res == null || res.statusCode != 200) throw StateError('failed');
      _discordId = null;
      _name = null;
      notifyListeners();
      await _saveCached();
      return true;
    } catch (_) {
      _errors.add('disconnect_failed');
      return false;
    } finally {
      _setBusy(false);
    }
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }
}

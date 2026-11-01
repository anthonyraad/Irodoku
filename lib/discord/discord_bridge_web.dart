import 'dart:js_interop';

/// `window.IroDiscord`, defined by `web_discord/discord_bridge.js`.
@JS('IroDiscord')
external _IroDiscord? get _bridge;

extension type _IroDiscord._(JSObject _) implements JSObject {
  external JSPromise<JSString?> init();
  external JSPromise<JSAny?> startRun(JSString dayKey);
  external JSPromise<JSBoolean> submitScore(JSString dayKey, JSNumber ms);
  external JSPromise<JSString?> leaderboard(JSString dayKey);
}

/// Dart side of the Discord Embedded App SDK bridge.
class DiscordBridge {
  DiscordBridge._();

  /// Runs ready → authorize → /api/token → authenticate. Returns username.
  static Future<String?> init() async {
    final b = _bridge;
    if (b == null) return null;
    try {
      return (await b.init().toDart)?.toDart;
    } catch (_) {
      return null;
    }
  }

  static Future<void> startRun(String dayKey) async {
    try {
      await _bridge?.startRun(dayKey.toJS).toDart;
    } catch (_) {}
  }

  static Future<bool> submitScore(String dayKey, int ms) async {
    final b = _bridge;
    if (b == null) return false;
    try {
      return (await b.submitScore(dayKey.toJS, ms.toJS).toDart).toDart;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> leaderboardJson(String dayKey) async {
    try {
      return (await _bridge?.leaderboard(dayKey.toJS).toDart)?.toDart;
    } catch (_) {
      return null;
    }
  }
}

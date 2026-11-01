import 'dart:js_interop';

/// `window.IroGraffiti`, defined by `web_discord_graffiti/graffiti_bridge.js`.
@JS('IroGraffiti')
external _IroGraffiti? get _bridge;

extension type _IroGraffiti._(JSObject _) implements JSObject {
  external JSBoolean inDiscord();
  external JSPromise<JSBoolean> firebaseReady();
  external JSPromise<JSString?> init();
  external JSPromise<JSString?> reportResult(JSString code);
  external JSString net();
  external void note(JSString message);
}

/// Dart side of the [Graffiti] Discord Activity bridge.
class GraffitiDiscordBridge {
  GraffitiDiscordBridge._();

  static bool get inDiscord {
    try {
      return _bridge?.inDiscord().toDart ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Waits for the self-hosted Firebase JS SDK (must precede initializeApp,
  /// or FlutterFire would inject blocked gstatic scripts).
  static Future<bool> firebaseReady() async {
    final b = _bridge;
    if (b == null) return true;
    try {
      return (await b.firebaseReady().toDart).toDart;
    } catch (_) {
      return false;
    }
  }

  /// Discord auth -> `/api/firebase-token`. JSON `{token, uid, name}` or null.
  static Future<String?> init() async {
    final b = _bridge;
    if (b == null) return null;
    try {
      return (await b.init().toDart)?.toDart;
    } catch (_) {
      return null;
    }
  }

  /// POST /api/result for a finished room. Worker response JSON or null.
  static Future<String?> reportResult(String code) async {
    final b = _bridge;
    if (b == null) return null;
    try {
      return (await b.reportResult(code.toJS).toDart)?.toDart;
    } catch (_) {
      return null;
    }
  }

  static String? netJson() {
    try {
      return _bridge?.net().toDart;
    } catch (_) {
      return null;
    }
  }

  static void note(String message) {
    try {
      _bridge?.note(message.toJS);
    } catch (_) {}
  }
}

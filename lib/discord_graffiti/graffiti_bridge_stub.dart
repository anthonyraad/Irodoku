/// Non-web stand-in for `web_discord_graffiti/graffiti_bridge.js`.
class GraffitiDiscordBridge {
  GraffitiDiscordBridge._();
  static bool get inDiscord => false;
  static Future<bool> firebaseReady() async => true;
  static Future<String?> init() async => null;
  static String? netJson() => null;
  static void note(String message) {}
}

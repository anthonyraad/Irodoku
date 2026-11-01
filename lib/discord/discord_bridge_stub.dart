/// Non-web fallback: the Discord bridge only exists in the web build.
class DiscordBridge {
  DiscordBridge._();
  static Future<String?> init() async => null;
  static Future<String?> startRun(String dayKey) async => null;
  static Future<bool> submitScore(String dayKey, int ms) async => false;
  static Future<String?> leaderboardJson(String dayKey) async => null;
}

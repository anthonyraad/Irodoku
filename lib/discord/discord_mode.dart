/// Discord Activity mode ("Pocket Daily Iro").
///
/// Enabled by `lib/main_discord.dart` (or `--dart-define=DISCORD=true`).
/// In this mode the app boots straight into today's 6×6 Pocket Daily, hides
/// the Main Menu, Google sign-in and progress sync, and sends scores to the
/// Activity's own backend instead of talking to Firebase directly.
class DiscordMode {
  DiscordMode._();

  static bool enabled = const bool.fromEnvironment('DISCORD');

  /// Discord username once the Embedded App SDK has authenticated.
  static String? username;
}

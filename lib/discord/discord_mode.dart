import 'package:flutter/foundation.dart';

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

  /// Flipped once today's Daily is finished (here or in an earlier session);
  /// the shell then swaps the puzzle for the leaderboard so it can't be
  /// replayed.
  static final ValueNotifier<bool> showLeaderboard = ValueNotifier(false);

  /// This player's finished time for today, if known.
  static int? myMs;

  /// In-flight `/api/score` POST for today's finish. The leaderboard waits on
  /// it so it never reads Firebase before this player's time is written.
  static Future<void>? pendingScore;
}

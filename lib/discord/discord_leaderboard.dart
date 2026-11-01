import 'dart:convert';

import 'package:flutter/material.dart';

import 'discord_bridge.dart';
import 'discord_mode.dart';

/// Today's Pocket rankings from the Activity backend (GET /api/leaderboard).
Future<void> showDiscordLeaderboard(BuildContext context, String dayKey) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('[Rankings]'),
      content: SizedBox(
        width: 280,
        child: SingleChildScrollView(
          child: DiscordLeaderboardList(dayKey: dayKey),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

/// Full-screen leaderboard shown once today's Daily is done. There is no way
/// back to the puzzle from here: one attempt per day.
class DiscordLeaderboardScreen extends StatelessWidget {
  final String dayKey;
  const DiscordLeaderboardScreen({super.key, required this.dayKey});

  @override
  Widget build(BuildContext context) {
    final mine = DiscordMode.myMs;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text("[Today's Leaderboard]"),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (mine != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Your time: ${formatDiscordMs(mine)}',
                        key: const Key('discord-my-time'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      "You've finished today's Daily Iro. "
                      'Come back tomorrow for a new one!',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  DiscordLeaderboardList(dayKey: dayKey),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DiscordLeaderboardList extends StatefulWidget {
  final String dayKey;
  const DiscordLeaderboardList({super.key, required this.dayKey});

  @override
  State<DiscordLeaderboardList> createState() => _DiscordLeaderboardListState();
}

class _DiscordLeaderboardListState extends State<DiscordLeaderboardList> {
  late final Future<String?> _data = DiscordBridge.leaderboardJson(
    widget.dayKey,
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _data,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        List<dynamic> rows = const [];
        try {
          rows = (jsonDecode(snap.data ?? '{}')['top'] as List?) ?? const [];
        } catch (_) {}
        if (rows.isEmpty) return const Text('No times yet today.');
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < rows.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(width: 28, child: Text('${i + 1}')),
                    Expanded(child: Text('${rows[i]['name']}')),
                    Text(formatDiscordMs(rows[i]['ms'] as int)),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

String formatDiscordMs(int ms) {
  final s = ms ~/ 1000;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

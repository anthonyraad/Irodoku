import 'dart:convert';

import 'package:flutter/material.dart';

import 'discord_bridge.dart';

/// Today's Pocket rankings from the Activity backend (GET /api/leaderboard).
Future<void> showDiscordLeaderboard(BuildContext context, String dayKey) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('[Rankings]'),
      content: SizedBox(
        width: 280,
        child: FutureBuilder<String?>(
          future: DiscordBridge.leaderboardJson(dayKey),
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(
                  height: 80, child: Center(child: CircularProgressIndicator()));
            }
            List<dynamic> rows = const [];
            try {
              rows = (jsonDecode(snap.data ?? '{}')['top'] as List?) ?? const [];
            } catch (_) {}
            if (rows.isEmpty) return const Text('No times yet today.');
            return ListView(
              shrinkWrap: true,
              children: [
                for (var i = 0; i < rows.length; i++)
                  ListTile(
                    dense: true,
                    leading: Text('${i + 1}'),
                    title: Text('${rows[i]['name']}'),
                    trailing: Text(_fmt(rows[i]['ms'] as int)),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
      ],
    ),
  );
}

String _fmt(int ms) {
  final s = ms ~/ 1000;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

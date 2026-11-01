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

class DiscordLeaderboardRow {
  final int rank;
  final String name;
  final int ms;
  const DiscordLeaderboardRow(this.rank, this.name, this.ms);
}

/// Parses `GET /api/leaderboard` → `{day, top: [{name, ms}]}`.
/// Returns null when the response is missing or an error payload (so the UI
/// can show an error rather than "no times").
List<DiscordLeaderboardRow>? parseDiscordLeaderboard(String? raw) {
  if (raw == null) return null;
  Object? m;
  try {
    m = jsonDecode(raw);
  } catch (_) {
    return null;
  }
  if (m is! Map || m['top'] is! List) return null;
  final rows = <({String name, int ms})>[];
  for (final e in m['top'] as List) {
    if (e is! Map) continue;
    final ms = e['ms'] is num
        ? (e['ms'] as num).toInt()
        : int.tryParse('${e['ms']}');
    if (ms == null) continue;
    rows.add((name: '${e['name'] ?? 'Player'}', ms: ms));
  }
  rows.sort((a, b) => a.ms.compareTo(b.ms));
  return [
    for (var i = 0; i < rows.length; i++)
      DiscordLeaderboardRow(i + 1, rows[i].name, rows[i].ms),
  ];
}

/// Index of the current player's row: name match first, then their time.
int? discordMyRowIndex(
  List<DiscordLeaderboardRow> rows, {
  String? username,
  int? myMs,
}) {
  String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (username != null && norm(username).isNotEmpty) {
    final u = norm(username);
    for (var i = 0; i < rows.length; i++) {
      final n = norm(rows[i].name);
      if (n.isNotEmpty && (u == n || u.startsWith(n))) return i;
    }
  }
  if (myMs != null) {
    for (var i = 0; i < rows.length; i++) {
      if ((rows[i].ms - myMs).abs() < 1000) return i;
    }
  }
  return null;
}

typedef DiscordLeaderboardFetch = Future<String?> Function(String dayKey);

class DiscordLeaderboardList extends StatefulWidget {
  final String dayKey;
  final DiscordLeaderboardFetch? fetch;
  const DiscordLeaderboardList({super.key, required this.dayKey, this.fetch});

  @override
  State<DiscordLeaderboardList> createState() => _DiscordLeaderboardListState();
}

class _DiscordLeaderboardListState extends State<DiscordLeaderboardList> {
  bool _loading = true;
  bool _error = false;
  List<DiscordLeaderboardRow> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    // Don't read before our own /api/score write lands (that race made a
    // fresh finish show "No times yet today").
    try {
      await DiscordMode.pendingScore?.timeout(const Duration(seconds: 10));
    } catch (_) {}
    final fetch = widget.fetch ?? DiscordBridge.leaderboardJson;
    var rows = parseDiscordLeaderboard(await fetch(widget.dayKey));
    // We know we finished: an empty/failed read is stale — retry once.
    if ((rows == null || rows.isEmpty) && DiscordMode.myMs != null) {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      rows = parseDiscordLeaderboard(await fetch(widget.dayKey)) ?? rows;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = rows == null;
      _rows = rows ?? const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 80,
        child: Center(
          child: CircularProgressIndicator(key: Key('discord-lb-loading')),
        ),
      );
    }
    if (_error) {
      return Column(
        key: const Key('discord-lb-error'),
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Couldn't load today's leaderboard."),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ],
      );
    }
    if (_rows.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('No times yet today.', key: Key('discord-lb-empty')),
          TextButton(onPressed: _load, child: const Text('Refresh')),
        ],
      );
    }
    final me = discordMyRowIndex(
      _rows,
      username: DiscordMode.username,
      myMs: DiscordMode.myMs,
    );
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _rows.length; i++)
          Container(
            key: Key('discord-lb-row-$i'),
            color: i == me
                ? theme.colorScheme.primary.withValues(alpha: 0.18)
                : null,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            child: Row(
              children: [
                SizedBox(width: 28, child: Text('${_rows[i].rank}')),
                Expanded(
                  child: Text(
                    i == me ? '${_rows[i].name} (you)' : _rows[i].name,
                    style: i == me
                        ? const TextStyle(fontWeight: FontWeight.bold)
                        : null,
                  ),
                ),
                Text(formatDiscordMs(_rows[i].ms)),
              ],
            ),
          ),
      ],
    );
  }
}

String formatDiscordMs(int ms) {
  final s = ms ~/ 1000;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irodoku/discord/discord_leaderboard.dart';
import 'package:irodoku/discord/discord_mode.dart';

Widget _wrap(Widget w) => MaterialApp(home: Scaffold(body: w));

void main() {
  setUp(() {
    DiscordMode.myMs = null;
    DiscordMode.username = null;
    DiscordMode.pendingScore = null;
  });

  test('parses live worker payload', () {
    final rows = parseDiscordLeaderboard(
      '{"day":"2026-10-31","top":[{"name":"b","ms":"140000"},{"name":"raadscapes","ms":131000}]}',
    )!;
    expect(rows.map((r) => r.name), ['raadscapes', 'b']);
    expect(rows.first.rank, 1);
    expect(parseDiscordLeaderboard(null), isNull);
    expect(parseDiscordLeaderboard('{"error":"db_unavailable"}'), isNull);
    expect(parseDiscordLeaderboard('{"day":"x","top":[]}'), isEmpty);
  });

  test('finds my row by name then time', () {
    final rows = parseDiscordLeaderboard(
      '{"top":[{"name":"a","ms":100000},{"name":"raadscapes","ms":131000}]}',
    )!;
    expect(discordMyRowIndex(rows, username: 'RaadScapes'), 1);
    expect(discordMyRowIndex(rows, myMs: 100400), 0);
    expect(discordMyRowIndex(rows, username: 'zzz'), isNull);
  });

  testWidgets('waits for pending score, then lists rows highlighted',
      (t) async {
    final score = Completer<void>();
    DiscordMode.pendingScore = score.future;
    DiscordMode.myMs = 131000;
    var calls = 0;
    await t.pumpWidget(_wrap(DiscordLeaderboardList(
      dayKey: '2026-10-31',
      fetch: (_) async {
        calls++;
        return '{"day":"2026-10-31","top":[{"name":"raadscapes","ms":131000}]}';
      },
    )));
    expect(find.byKey(const Key('discord-lb-loading')), findsOneWidget);
    expect(calls, 0);
    score.complete();
    await t.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('raadscapes (you)'), findsOneWidget);
    expect(find.text('2:11'), findsOneWidget);
    expect(find.text('No times yet today.'), findsNothing);
  });

  testWidgets('fetch failure shows error, not empty', (t) async {
    await t.pumpWidget(_wrap(DiscordLeaderboardList(
      dayKey: '2026-10-31',
      fetch: (_) async => null,
    )));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('discord-lb-error')), findsOneWidget);
    expect(find.text('No times yet today.'), findsNothing);
  });

  testWidgets('genuinely empty day shows empty state', (t) async {
    await t.pumpWidget(_wrap(DiscordLeaderboardList(
      dayKey: '2026-10-31',
      fetch: (_) async => '{"day":"2026-10-31","top":[]}',
    )));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('discord-lb-empty')), findsOneWidget);
  });

  testWidgets('retries once when finished but first read is empty',
      (t) async {
    DiscordMode.myMs = 131000;
    var calls = 0;
    await t.pumpWidget(_wrap(DiscordLeaderboardList(
      dayKey: '2026-10-31',
      fetch: (_) async => ++calls == 1
          ? '{"top":[]}'
          : '{"top":[{"name":"raadscapes","ms":131000}]}',
    )));
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('raadscapes (you)'), findsOneWidget);
  });
}

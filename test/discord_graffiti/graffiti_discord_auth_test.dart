import 'package:flutter_test/flutter_test.dart';
import 'package:irodoku/discord_graffiti/graffiti_discord_auth.dart';
import 'package:irodoku/models/daily_leaderboard.dart';

void main() {
  test('parses a firebase-token response', () {
    final a = GraffitiDiscordAuth.tryParse(
      '{"token":"a.b.c","uid":"discord_42","name":"Tony"}',
    )!;
    expect(a.token, 'a.b.c');
    expect(a.uid, 'discord_42');
    expect(DisplayName.trySanitize(a.name), 'Tony');
  });

  test('rejects bad responses', () {
    expect(GraffitiDiscordAuth.tryParse(null), isNull);
    expect(GraffitiDiscordAuth.tryParse('nope'), isNull);
    expect(GraffitiDiscordAuth.tryParse('{"token":"x","uid":"abc"}'), isNull);
    expect(GraffitiDiscordAuth.tryParse('{"uid":"discord_1"}'), isNull);
  });

  test('describeNet summarizes transport', () {
    expect(
      describeNet('{"ws":"open","longPolls":0}', rtdbConnected: true),
      'rtdb CONNECTED | websocket',
    );
    expect(
      describeNet('{"ws":"error","wsErrors":2,"longPolls":3,"lastClose":"1006"}',
          rtdbConnected: false),
      'rtdb offline | long-poll(3) | wsErr:2 | close:1006',
    );
    expect(describeNet(null), 'rtdb ? | ws:none');
  });
}

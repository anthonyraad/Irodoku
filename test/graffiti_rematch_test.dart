import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irodoku/screens/graffiti_screen.dart';
import 'package:irodoku/services/graffiti_firebase_service.dart';

void main() {
  test('bothWantRematch requires true from each seated player', () {
    const host = 'host';
    const guest = 'guest';
    expect(GraffitiFirebaseService.bothWantRematch({}, host, guest), isFalse);
    expect(
      GraffitiFirebaseService.bothWantRematch({host: true}, host, guest),
      isFalse,
    );
    expect(
      GraffitiFirebaseService.bothWantRematch(
        {host: true, guest: false},
        host,
        guest,
      ),
      isFalse,
    );
    expect(
      GraffitiFirebaseService.bothWantRematch(
        {host: true, guest: true},
        host,
        guest,
      ),
      isTrue,
    );
  });

  test('lockout grows 3s, 5s, 7s, then caps at 10s', () {
    expect(GraffitiFirebaseService.lockoutSecondsForMistake(0), 0);
    expect(GraffitiFirebaseService.lockoutSecondsForMistake(1), 3);
    expect(GraffitiFirebaseService.lockoutSecondsForMistake(2), 5);
    expect(GraffitiFirebaseService.lockoutSecondsForMistake(3), 7);
    expect(GraffitiFirebaseService.lockoutSecondsForMistake(4), 10);
    expect(GraffitiFirebaseService.lockoutSecondsForMistake(8), 10);
  });

  test('appBarTrailing prefers a set opponent name over the room code', () {
    expect(
      GraffitiFirebaseService.appBarTrailing(
        opponentName: 'Ada',
        roomCode: 'AB3DE',
      ),
      'Ada',
    );
    expect(
      GraffitiFirebaseService.appBarTrailing(
        opponentName: null,
        roomCode: 'AB3DE',
      ),
      'AB3DE',
    );
    expect(
      GraffitiFirebaseService.appBarTrailing(
        opponentName: 'x',
        roomCode: 'AB3DE',
      ),
      'AB3DE',
    );
    expect(
      GraffitiFirebaseService.appBarTrailing(
        opponentName: '  ',
        roomCode: 'AB3DE',
      ),
      'AB3DE',
    );
  });

  test('playerNameFromRoom reads names across waiting, play, and rematch', () {
    const opp = 'guest';
    const host = 'host';
    final waiting = {
      'gameState': 'waiting',
      'names': {opp: 'Ink_42'},
    };
    expect(GraffitiFirebaseService.playerNameFromRoom(waiting, opp), 'Ink_42');
    expect(GraffitiFirebaseService.playerNameFromRoom(waiting, host), isNull);

    final unnamed = {
      'gameState': 'playing',
      'players': {host: true, opp: true},
    };
    expect(GraffitiFirebaseService.playerNameFromRoom(unnamed, opp), isNull);

    final rematchPlaying = {
      'gameState': 'playing',
      'players': {host: true, opp: true},
      'names': {host: 'Ada', opp: 'Ink_42'},
    };
    expect(
      GraffitiFirebaseService.playerNameFromRoom(rematchPlaying, opp),
      'Ink_42',
    );
    expect(
      GraffitiFirebaseService.appBarTrailing(
        opponentName: GraffitiFirebaseService.playerNameFromRoom(
          rematchPlaying,
          opp,
        ),
        roomCode: 'AB3DE',
      ),
      'Ink_42',
    );
  });

  testWidgets('Graffiti app bar shows opponent name instead of room code', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GraffitiAppBarTrailing(opponentName: 'Ada', roomCode: 'AB3DE'),
        ),
      ),
    );
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('AB3DE'), findsNothing);
  });

  testWidgets('Graffiti app bar keeps room code when opponent has no name', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GraffitiAppBarTrailing(roomCode: 'AB3DE'),
        ),
      ),
    );
    expect(find.text('AB3DE'), findsOneWidget);
  });
}

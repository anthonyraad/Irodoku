import 'package:flutter_test/flutter_test.dart';
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

  test('lockout grows 5s, 10s, then caps at 15s', () {
    expect(GraffitiFirebaseService.lockoutSecondsForMistake(0), 0);
    expect(GraffitiFirebaseService.lockoutSecondsForMistake(1), 5);
    expect(GraffitiFirebaseService.lockoutSecondsForMistake(2), 10);
    expect(GraffitiFirebaseService.lockoutSecondsForMistake(3), 15);
    expect(GraffitiFirebaseService.lockoutSecondsForMistake(8), 15);
  });
}

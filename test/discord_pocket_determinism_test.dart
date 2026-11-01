// Pocket Daily must be identical on the Dart VM (mobile) and dart2js (web /
// Discord). Run both: `flutter test test/discord_pocket_determinism_test.dart`
// and `flutter test --platform chrome test/discord_pocket_determinism_test.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:irodoku/models/daily_irodoku.dart';
import 'package:irodoku/providers/game_provider.dart';

/// Golden fingerprints recorded on the Dart VM; web must match exactly.
const _expected = <String, String>{
  '2026-01-01':
      '2026-01-01|1596312160|easy|pkmn|neon|000430000002004000500600600200030150|256431341562164325523614615243432156',
  '2026-07-04':
      '2026-07-04|1748818617|medium|neon|world11|600100100040000003001200000020005601|643152152346264513531264316425425631',
  '2026-10-31':
      '2026-10-31|463710833|medium|neon|pkmn2|000000302014100020500030040052000001|415263362514136425524136641352253641',
  '2027-02-28':
      '2027-02-28|270447301|hard|sky|world11|510302004000002000600003000060060500|516342324615132456645123453261261534',
};

String fingerprint(DateTime date) {
  final c = DailyIrodoku.pocketForDate(date);
  final boards = generatePocketIsolate(c.seed);
  return '${c.dayKey}|${c.seed}|${c.difficulty.name}|${c.palette.name}|'
      '${c.secondPalette.name}|${boards[0].join()}|${boards[1].join()}';
}

void main() {
  final dates = [
    DateTime.utc(2026, 1, 1, 12),
    DateTime.utc(2026, 7, 4, 20),
    DateTime.utc(2026, 11, 1, 3), // still 2026-10-31 in UTC-8
    DateTime.utc(2027, 2, 28, 9),
  ];
  test('Pocket daily is platform-deterministic', () {
    for (final d in dates) {
      final fp = fingerprint(d);
      // ignore: avoid_print
      print('FP ${DailyIrodoku.dayKeyFor(d)} $fp');
      final want = _expected[DailyIrodoku.dayKeyFor(d)];
      expect(fp, want);
    }
  });
}

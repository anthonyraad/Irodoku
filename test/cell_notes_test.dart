import 'package:flutter_test/flutter_test.dart';
import 'package:irodoku/models/cell.dart';

void main() {
  test('withNoteAdded stores note and clears committed value', () {
    const cell = Cell(value: 3);
    final noted = cell.withNoteAdded(5);

    expect(noted.value, 0);
    expect(noted.notes, contains(5));
    expect(noted.hasNotes, isTrue);
  });

  test('withNoteRemoved clears only that note', () {
    final cell = const Cell().withNoteAdded(1).withNoteAdded(9);
    final next = cell.withNoteRemoved(1);

    expect(next.notes, equals({9}));
  });
}

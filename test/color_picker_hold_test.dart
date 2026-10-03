import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irodoku/core/color_cycle.dart';
import 'package:irodoku/models/game_palette.dart';
import 'package:irodoku/widgets/color_picker.dart';

void main() {
  Future<void> pumpPicker(
    WidgetTester tester, {
    required List<int> taps,
    required List<int> notesAdded,
    List<int>? holds,
    List<int>? holdEnds,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ColorPicker(
              swatchSize: 40,
              visible: true,
              palette: GamePalette.standard,
              onColorSelected: taps.add,
              onNoteAdded: notesAdded.add,
              onNoteRemoved: (_) {},
              onColorHoldStart: holds?.add,
              onColorHoldEnd: holdEnds == null
                  ? null
                  : () => holdEnds.add(1),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('short tap still selects and does not hold', (tester) async {
    final taps = <int>[];
    final notes = <int>[];
    final holds = <int>[];
    final holdEnds = <int>[];
    await pumpPicker(
      tester,
      taps: taps,
      notesAdded: notes,
      holds: holds,
      holdEnds: holdEnds,
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('picker-swatch-3'))),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pump();

    expect(taps, [3]);
    expect(holds, isEmpty);
    expect(holdEnds, isEmpty);
    expect(notes, isEmpty);
  });

  testWidgets('hold past 360ms starts sweep and skips tap on lift',
      (tester) async {
    final taps = <int>[];
    final notes = <int>[];
    final holds = <int>[];
    final holdEnds = <int>[];
    await pumpPicker(
      tester,
      taps: taps,
      notesAdded: notes,
      holds: holds,
      holdEnds: holdEnds,
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('picker-swatch-2'))),
    );
    await tester.pump(ColorCycle.holdStartDelay);
    expect(holds, [2]);
    expect(taps, isEmpty);

    await gesture.up();
    await tester.pump();
    expect(taps, isEmpty);
    expect(holdEnds, [1]);
    expect(notes, isEmpty);
  });

  testWidgets('swipe down still notes and does not hold', (tester) async {
    final taps = <int>[];
    final notes = <int>[];
    final holds = <int>[];
    final holdEnds = <int>[];
    await pumpPicker(
      tester,
      taps: taps,
      notesAdded: notes,
      holds: holds,
      holdEnds: holdEnds,
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('picker-swatch-5'))),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(notes, [5]);
    expect(holds, isEmpty);
    expect(holdEnds, isEmpty);
    expect(taps, isEmpty);
  });

  testWidgets('without hold callbacks a long press still taps (Iroen)',
      (tester) async {
    final taps = <int>[];
    final notes = <int>[];
    await pumpPicker(tester, taps: taps, notesAdded: notes);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('picker-swatch-1'))),
    );
    await tester.pump(ColorCycle.holdStartDelay);
    await gesture.up();
    await tester.pump();

    expect(taps, [1]);
    expect(notes, isEmpty);
  });
}

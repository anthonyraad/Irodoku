import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irodoku/core/color_cycle.dart';
import 'package:irodoku/core/palette.dart';
import 'package:irodoku/models/cell.dart';
import 'package:irodoku/models/game_palette.dart';
import 'package:irodoku/models/palette_swatch.dart';

void main() {
  test('cellMatchesFilter includes fills and notes of that color', () {
    expect(ColorCycle.cellMatchesFilter(const Cell(value: 4), 4), isTrue);
    expect(ColorCycle.cellMatchesFilter(const Cell(value: 4), 7), isFalse);

    final noted = const Cell().withNoteAdded(3);
    expect(ColorCycle.cellMatchesFilter(noted, 3), isTrue);
    expect(ColorCycle.cellMatchesFilter(noted, 1), isFalse);

    expect(ColorCycle.cellMatchesFilter(const Cell(), 2), isFalse);
  });

  test('valueMatchesFilter only cycles the held color', () {
    expect(ColorCycle.valueMatchesFilter(3, 3), isTrue);
    expect(ColorCycle.valueMatchesFilter(7, 3), isFalse);
    expect(ColorCycle.valueMatchesFilter(7, null), isTrue);
  });

  test('staggeredPhase at t=0 is the original swatch phase', () {
    expect(ColorCycle.staggeredPhase(0, 4, 4), 0);
    expect(ColorCycle.staggeredPhase(1, 0, 0), 1);
  });

  test('linear hold sweep t=0 and t=1 are the original color', () {
    const palette = GamePalette.standard;
    final original = IrodokuPalette.swatchForValue(3, palette)!;
    for (final t in [0.0, 1.0]) {
      final swatch = ColorCycle.displaySwatch(
        3,
        t,
        stepCount: 4,
        palette: palette,
        linear: true,
      );
      expect(swatch.start, original.start);
    }
  });

  test('linear hold sweep midpoint is the farthest adjacent slot, not a wrap',
      () {
    const palette = GamePalette.standard;
    final list = IrodokuPalette.swatchesFor(palette);
    final swatch = ColorCycle.displaySwatch(
      1,
      0.5,
      stepCount: 4,
      palette: palette,
      linear: true,
    );
    expect(swatch.start.r, closeTo(list.last.start.r, 0.002));
    expect(swatch.start.g, closeTo(list.last.start.g, 0.002));
    expect(swatch.start.b, closeTo(list.last.start.b, 0.002));
  });

  test('hold sweep lerps RGB between neighbors instead of spinning hue', () {
    final red = PaletteSwatch.solid(const Color(0xFFFF0000));
    final cyan = PaletteSwatch.solid(const Color(0xFF00FFFF));
    final swatch = ColorCycle.displaySwatch(
      1,
      0.25,
      stepCount: 4,
      palette: GamePalette.standard,
      swatches: [red, cyan],
      linear: true,
    );
    expect(swatch.start.r, closeTo(0.5, 0.06));
    expect(swatch.start.g, closeTo(0.5, 0.06));
    expect(swatch.start.b, closeTo(0.5, 0.06));
  });

  testWidgets('hold cycle restarts after one pass while still active',
      (tester) async {
    late PickerHoldSweep sweep;
    await tester.pumpWidget(
      MaterialApp(
        home: _SweepHost(onCreated: (value) => sweep = value),
      ),
    );

    sweep.sync(active: true);
    await tester.pump();
    expect(sweep.cycle.isAnimating, isTrue);

    await tester.pump(ColorCycle.holdCycleDuration);
    expect(sweep.cycle.isAnimating, isTrue);
    final atTurnaround = sweep.cycle.value;
    await tester.pump(const Duration(milliseconds: 200));
    expect(sweep.cycle.isAnimating, isTrue);
    expect(sweep.cycle.value, isNot(atTurnaround));
  });
}

class _SweepHost extends StatefulWidget {
  const _SweepHost({required this.onCreated});

  final void Function(PickerHoldSweep sweep) onCreated;

  @override
  State<_SweepHost> createState() => _SweepHostState();
}

class _SweepHostState extends State<_SweepHost>
    with TickerProviderStateMixin {
  late final PickerHoldSweep _sweep;

  @override
  void initState() {
    super.initState();
    _sweep = PickerHoldSweep(this);
    widget.onCreated(_sweep);
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

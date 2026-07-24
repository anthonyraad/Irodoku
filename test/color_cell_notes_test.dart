import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irodoku/models/cell.dart';
import 'package:irodoku/widgets/color_cell.dart';

void main() {
  testWidgets('ColorCell with notes builds a CustomPaint layer', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 90,
            height: 90,
            child: ColorCell(
              cell: Cell(notes: {1, 5, 9}),
              isSelected: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ColorCell), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}

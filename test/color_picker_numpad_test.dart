import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irodoku/widgets/color_picker.dart';

void main() {
  test('numpad layout maps keys to picker colors', () {
    const cases = <(LogicalKeyboardKey, int)>[
      (LogicalKeyboardKey.digit7, 1),
      (LogicalKeyboardKey.numpad7, 1),
      (LogicalKeyboardKey.digit8, 2),
      (LogicalKeyboardKey.numpad8, 2),
      (LogicalKeyboardKey.digit9, 3),
      (LogicalKeyboardKey.numpad9, 3),
      (LogicalKeyboardKey.digit4, 4),
      (LogicalKeyboardKey.numpad4, 4),
      (LogicalKeyboardKey.digit5, 5),
      (LogicalKeyboardKey.numpad5, 5),
      (LogicalKeyboardKey.digit6, 6),
      (LogicalKeyboardKey.numpad6, 6),
      (LogicalKeyboardKey.digit1, 7),
      (LogicalKeyboardKey.numpad1, 7),
      (LogicalKeyboardKey.digit2, 8),
      (LogicalKeyboardKey.numpad2, 8),
      (LogicalKeyboardKey.digit3, 9),
      (LogicalKeyboardKey.numpad3, 9),
      (LogicalKeyboardKey.keyQ, 1),
      (LogicalKeyboardKey.keyW, 2),
      (LogicalKeyboardKey.keyE, 3),
      (LogicalKeyboardKey.keyA, 4),
      (LogicalKeyboardKey.keyS, 5),
      (LogicalKeyboardKey.keyD, 6),
      (LogicalKeyboardKey.keyZ, 7),
      (LogicalKeyboardKey.keyX, 8),
      (LogicalKeyboardKey.keyC, 9),
    ];
    for (final (key, value) in cases) {
      expect(colorValueForNumpadKey(key), value);
    }
  });

  test('unused keys and Pocket overflow are ignored', () {
    expect(colorValueForNumpadKey(LogicalKeyboardKey.digit0), isNull);
    expect(colorValueForNumpadKey(LogicalKeyboardKey.numpad0), isNull);
    expect(colorValueForNumpadKey(LogicalKeyboardKey.space), isNull);
    expect(
      colorValueForNumpadKey(LogicalKeyboardKey.digit1, maxColor: 6),
      isNull,
    );
    expect(
      colorValueForNumpadKey(LogicalKeyboardKey.numpad7, maxColor: 6),
      1,
    );
    expect(
      colorValueForNumpadKey(LogicalKeyboardKey.keyQ, maxColor: 6),
      1,
    );
    expect(
      colorValueForNumpadKey(LogicalKeyboardKey.keyZ, maxColor: 6),
      isNull,
    );
  });
}

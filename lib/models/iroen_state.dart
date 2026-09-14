import 'cell.dart';
import '../sudoku/sudoku_board.dart';

int _asInt(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

class IroenState {
  static const int detailSize = 27;

  final List<int> detail;
  /// Picker values 1–9 whose palette texture is stripped to a solid fill.
  final Set<int> flatSlots;

  const IroenState({
    required this.detail,
    this.flatSlots = const {},
  });

  Map<String, Object?> toJson() {
    return {
      'version': 2,
      'detail': detail,
      if (flatSlots.isNotEmpty) 'flatSlots': (flatSlots.toList()..sort()),
    };
  }

  factory IroenState.fromJson(Map<String, dynamic> json) {
    final version = _asInt(json['version'], 1);
    if (version >= 2) {
      final detailRaw = (json['detail'] as List<dynamic>? ?? const [])
          .map((e) => _asInt(e))
          .toList();
      if (detailRaw.length != detailSize * detailSize) {
        throw const FormatException('Invalid Iroen detail payload');
      }
      return IroenState(
        detail: detailRaw,
        flatSlots: parseFlatSlots(json['flatSlots']),
      );
    }

    final cellMaps = (json['cells'] as List<dynamic>? ?? const []);
    final cells = <Cell>[];
    for (final raw in cellMaps) {
      final map = Map<String, dynamic>.from(raw as Map);
      cells.add(
        Cell(
          value: map['v'] as int? ?? 0,
          notes: _notesFromMap(map),
        ),
      );
    }

    if (cells.length != SudokuBoard.size * SudokuBoard.size) {
      throw const FormatException('Invalid Iroen state payload');
    }

    return IroenState.fromLegacyCells(cells);
  }

  factory IroenState.fromLegacyCells(List<Cell> cells) {
    final detail = List<int>.filled(detailSize * detailSize, 0);
    for (var row = 0; row < SudokuBoard.size; row++) {
      for (var col = 0; col < SudokuBoard.size; col++) {
        final value = cells[row * SudokuBoard.size + col].value;
        if (value == 0) continue;
        for (var dr = 0; dr < 3; dr++) {
          for (var dc = 0; dc < 3; dc++) {
            detail[(row * 3 + dr) * detailSize + (col * 3 + dc)] = value;
          }
        }
      }
    }
    return IroenState(detail: detail);
  }

  static Set<int> parseFlatSlots(dynamic raw) {
    if (raw is! List) return const {};
    return {
      for (final item in raw)
        if (_asInt(item) >= 1 && _asInt(item) <= 9) _asInt(item),
    };
  }

  static Set<int> _notesFromMap(Map<String, dynamic> map) {
    final rawNotes = map['n'];
    if (rawNotes is List) {
      return {
        for (final n in rawNotes)
          if (n is int && n >= 1 && n <= 9) n,
      };
    }
    return const {};
  }
}

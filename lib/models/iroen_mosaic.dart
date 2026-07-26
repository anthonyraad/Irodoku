import 'game_palette.dart';
import 'iroen_state.dart';

/// A named snapshot of an Iroen canvas for the gallery.
class IroenMosaic {
  final String id;
  final String name;
  final List<int> detail;
  final int updatedAtMs;
  final GamePalette palette;

  const IroenMosaic({
    required this.id,
    required this.name,
    required this.detail,
    required this.updatedAtMs,
    this.palette = GamePalette.standard,
  });

  IroenState get asState => IroenState(detail: detail);

  bool get isEmpty => detail.every((value) => value == 0);

  /// 9×9 overview: each cell uses the first non-zero of its 3×3 block.
  List<int> overviewValues() {
    const size = IroenState.detailSize;
    return [
      for (var row = 0; row < 9; row++)
        for (var col = 0; col < 9; col++)
          _blockRepresentative(row, col, size),
    ];
  }

  int _blockRepresentative(int row, int col, int size) {
    final baseRow = row * 3;
    final baseCol = col * 3;
    for (var dr = 0; dr < 3; dr++) {
      for (var dc = 0; dc < 3; dc++) {
        final value = detail[(baseRow + dr) * size + (baseCol + dc)];
        if (value != 0) return value;
      }
    }
    return 0;
  }

  IroenMosaic copyWith({
    String? id,
    String? name,
    List<int>? detail,
    int? updatedAtMs,
    GamePalette? palette,
  }) {
    return IroenMosaic(
      id: id ?? this.id,
      name: name ?? this.name,
      detail: detail ?? this.detail,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      palette: palette ?? this.palette,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'detail': detail,
        'updatedAtMs': updatedAtMs,
        'palette': palette.storageKey,
      };

  factory IroenMosaic.fromJson(Map<String, dynamic> json) {
    final detailRaw = (json['detail'] as List<dynamic>? ?? const [])
        .map((e) => e as int? ?? 0)
        .toList();
    if (detailRaw.length != IroenState.detailSize * IroenState.detailSize) {
      throw const FormatException('Invalid Iroen mosaic detail');
    }
    return IroenMosaic(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Mosaic',
      detail: detailRaw,
      updatedAtMs: json['updatedAtMs'] as int? ?? 0,
      palette: GamePalette.fromStorageKey(json['palette'] as String?),
    );
  }
}

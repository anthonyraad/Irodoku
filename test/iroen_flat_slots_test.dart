import 'package:flutter_test/flutter_test.dart';
import 'package:irodoku/core/palette.dart';
import 'package:irodoku/models/game_palette.dart';
import 'package:irodoku/models/iroen_mosaic.dart';
import 'package:irodoku/models/iroen_state.dart';
import 'package:irodoku/models/palette_swatch.dart';

void main() {
  test('flattenSlots turns textured swatches into solids', () {
    final glass = IrodokuPalette.swatchesFor(GamePalette.glass);
    expect(glass[0].style, isNot(PaletteSwatchStyle.solid));

    final flattened = IrodokuPalette.swatchesFor(
      GamePalette.glass,
      flatSlots: {1, 5},
    );
    expect(flattened[0].style, PaletteSwatchStyle.solid);
    expect(flattened[0].start, glass[0].representative);
    expect(flattened[4].style, PaletteSwatchStyle.solid);
    expect(flattened[1].style, glass[1].style);
  });

  test('IroenState and mosaic JSON keep flatSlots and stay backward compatible',
      () {
    final detail = List<int>.filled(
      IroenState.detailSize * IroenState.detailSize,
      0,
    );
    detail[0] = 3;
    final state = IroenState(detail: detail, flatSlots: {2, 9});
    final restored = IroenState.fromJson(state.toJson());
    expect(restored.detail[0], 3);
    expect(restored.flatSlots, {2, 9});

    final legacy = IroenState.fromJson({
      'version': 2,
      'detail': detail,
    });
    expect(legacy.flatSlots, isEmpty);

    final mosaic = IroenMosaic(
      id: 'm1',
      name: 'Test',
      detail: detail,
      updatedAtMs: 1,
      palette: GamePalette.sky,
      flatSlots: {4},
    );
    final loaded = IroenMosaic.fromJson(mosaic.toJson());
    expect(loaded.flatSlots, {4});
    expect(loaded.palette, GamePalette.sky);

    final oldMosaic = IroenMosaic.fromJson({
      'id': 'old',
      'name': 'Old',
      'detail': detail,
      'updatedAtMs': 1,
      'palette': GamePalette.neon.storageKey,
    });
    expect(oldMosaic.flatSlots, isEmpty);
  });
}

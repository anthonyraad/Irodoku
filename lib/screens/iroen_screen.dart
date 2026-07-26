import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/iroen_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/color_picker.dart';
import '../widgets/iroen_gallery_sheet.dart';
import '../widgets/iroen_grid.dart';
import '../widgets/iroen_toolbar.dart';
import '../widgets/typing_title.dart';

class IroenScreen extends StatelessWidget {
  const IroenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<IroenProvider, SettingsProvider>(
      builder: (context, iroen, settings, _) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: iroen.hasCellSelection ? iroen.clearSelection : null,
          child: Scaffold(
            appBar: AppBar(
              title: const TypingTitle(text: 'Iroen'),
              actions: [
                IconButton(
                  tooltip: 'Mosaics',
                  icon: Badge(
                    isLabelVisible: iroen.gallery.isNotEmpty,
                    backgroundColor:
                        Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : Colors.black,
                    textColor: Theme.of(context).brightness == Brightness.dark
                        ? Colors.black
                        : Colors.white,
                    label: Text('${iroen.gallery.length}'),
                    child: const Icon(Icons.collections_bookmark_outlined),
                  ),
                  onPressed: () => showIroenGallerySheet(
                    context: context,
                    iroen: iroen,
                    settings: settings,
                  ),
                ),
              ],
            ),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const boardBorder = 2.5;
                    const pickerGap = 12.0;
                    const toolbarGap = 8.0;
                    final xlPicker = settings.xlPicker;
                    const xlSwatchCells = 3 * 0.85 * 0.85;
                    const belowFixed =
                        toolbarGap + IroenToolbar.height + pickerGap;
                    final pickerRowCount =
                        xlPicker ? xlSwatchCells * 3 : 1.0;
                    final cellFromWidth =
                        (constraints.maxWidth - boardBorder * 2) / 9;
                    final cellFromHeight = (constraints.maxHeight -
                            belowFixed -
                            boardBorder * 2) /
                        (9 + pickerRowCount);
                    final cellSize = math.min(cellFromWidth, cellFromHeight);
                    final boardSize = cellSize * 9 + boardBorder * 2;
                    final swatchSize =
                        xlPicker ? cellSize * xlSwatchCells : cellSize;

                    return Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: boardSize,
                        child: Column(
                          children: [
                            SizedBox(
                              width: boardSize,
                              height: boardSize,
                              child: IroenGrid(
                                iroen: iroen,
                                palette: settings.palette,
                              ),
                            ),
                            const SizedBox(height: toolbarGap),
                            GestureDetector(
                              onTap: () {},
                              behavior: HitTestBehavior.opaque,
                              child: IroenToolbar(
                                canUndo: iroen.canUndo,
                                bulkNoteSelect: iroen.bulkNoteSelect,
                                canErase: iroen.canEraseSelection,
                                zoomActive: iroen.zoomButtonActive,
                                onUndo: iroen.undo,
                                onErase: iroen.clearSelectedCell,
                                onToggleBulk: iroen.toggleBulkSelectMode,
                                onBulkLongPress:
                                    iroen.canEnterBulkNoteSelectFromToolbar
                                        ? iroen.enterBulkNoteSelectFromToolbar
                                        : null,
                                onToggleZoom: iroen.toggleZoom,
                              ),
                            ),
                            const SizedBox(height: pickerGap),
                            ColorPicker(
                              swatchSize: swatchSize,
                              xlMode: xlPicker,
                              palette: settings.palette,
                              visible: true,
                              onColorSelected: iroen.applyPickerColor,
                              onNoteAdded: (_) {},
                              onNoteRemoved: (_) {},
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

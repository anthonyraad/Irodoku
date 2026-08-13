import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/game_palette.dart';
import '../providers/graffiti_provider.dart';
import '../sudoku/sudoku_board.dart';
import 'color_cell.dart';

class GraffitiGrid extends StatelessWidget {
  final GraffitiProvider game;
  final GamePalette palette;

  const GraffitiGrid({
    super.key,
    required this.game,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final thick = IrodokuTheme.thickGridLine(IrodokuTheme.boardBrightness);
    final thin = IrodokuTheme.thinGridLine(IrodokuTheme.boardBrightness);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: thick, width: 2.5),
      ),
      child: Column(
        children: [
          for (var r = 0; r < SudokuBoard.size; r++)
            Expanded(
              child: Row(
                children: [
                  for (var c = 0; c < SudokuBoard.size; c++)
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(
                              color: (c + 1) % 3 == 0 && c < 8 ? thick : thin,
                              width: (c + 1) % 3 == 0 && c < 8 ? 2 : 0.6,
                            ),
                            bottom: BorderSide(
                              color: (r + 1) % 3 == 0 && r < 8 ? thick : thin,
                              width: (r + 1) % 3 == 0 && r < 8 ? 2 : 0.6,
                            ),
                          ),
                        ),
                        child: ColorCell(
                          cell: game.cells[r][c],
                          isSelected: game.selectedRow == r &&
                              game.selectedCol == c,
                          isRelated: game.isRelated(r, c),
                          isSameColor: game.isSameColor(r, c),
                          palette: palette,
                          row: r,
                          col: c,
                          onTap: () => game.selectCell(r, c),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

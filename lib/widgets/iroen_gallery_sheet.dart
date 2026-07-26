import 'package:flutter/material.dart';

import '../core/palette.dart';
import '../core/theme.dart';
import '../models/game_palette.dart';
import '../models/iroen_mosaic.dart';
import '../models/palette_swatch.dart';
import '../providers/iroen_provider.dart';
import '../providers/settings_provider.dart';

ThemeData _mosaicsMonoTheme(BuildContext context) {
  final base = Theme.of(context);
  final dark = base.brightness == Brightness.dark;
  final ink = dark ? const Color(0xFFE8E8E8) : Colors.black;
  final onInk = dark ? Colors.black : Colors.white;
  final wash = dark ? const Color(0xFF3A3A3A) : const Color(0xFFE0E0E0);
  final onWash = dark ? const Color(0xFFF0F0F0) : const Color(0xFF1A1A1A);

  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: ink,
      onPrimary: onInk,
      primaryContainer: wash,
      onPrimaryContainer: onWash,
      secondary: ink,
      onSecondary: onInk,
      secondaryContainer: wash,
      onSecondaryContainer: onWash,
      tertiary: ink,
      onTertiary: onInk,
      tertiaryContainer: wash,
      onTertiaryContainer: onWash,
    ),
  );
}

Future<void> showIroenGallerySheet({
  required BuildContext context,
  required IroenProvider iroen,
  required SettingsProvider settings,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return Theme(
        data: _mosaicsMonoTheme(context),
        child: ListenableBuilder(
          listenable: Listenable.merge([iroen, settings]),
          builder: (context, _) {
            return _IroenGallerySheet(iroen: iroen, settings: settings);
          },
        ),
      );
    },
  );
}

class _IroenGallerySheet extends StatelessWidget {
  final IroenProvider iroen;
  final SettingsProvider settings;

  const _IroenGallerySheet({
    required this.iroen,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mosaics = iroen.gallery;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Mosaics',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Save snapshots of your canvas, then tap one to load it.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: iroen.canSaveToGallery
                        ? () => _save(context)
                        : null,
                    icon: const Icon(Icons.save_outlined, size: 20),
                    label: Text(
                      iroen.activeMosaicId == null ? 'Save' : 'Update',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: iroen.canSaveAsNew
                        ? () => _saveAsNew(context)
                        : null,
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('Save as new'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _confirmNewCanvas(context),
              icon: const Icon(Icons.note_add_outlined, size: 20),
              label: const Text('New blank canvas'),
            ),
            const SizedBox(height: 16),
            if (mosaics.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Text(
                  'No saved mosaics yet.\nPaint something, then tap Save.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.42,
                ),
                child: GridView.builder(
                  shrinkWrap: true,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: mosaics.length,
                  itemBuilder: (context, index) {
                    final mosaic = mosaics[index];
                    final isActive = mosaic.id == iroen.activeMosaicId;
                    return _MosaicCard(
                      mosaic: mosaic,
                      isActive: isActive,
                      onTap: () => _load(context, mosaic),
                      onLongPress: () => _mosaicMenu(context, mosaic),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(BuildContext context) async {
    final updating = iroen.activeMosaicId != null &&
        iroen.gallery.any((m) => m.id == iroen.activeMosaicId);
    final mosaic = await iroen.saveToGallery(settings.palette);
    if (!context.mounted || mosaic == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          updating ? 'Updated “${mosaic.name}”' : 'Saved “${mosaic.name}”',
        ),
        duration: const Duration(milliseconds: 1400),
      ),
    );
  }

  Future<void> _saveAsNew(BuildContext context) async {
    final mosaic = await iroen.saveAsNew(settings.palette);
    if (!context.mounted || mosaic == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved “${mosaic.name}”'),
        duration: const Duration(milliseconds: 1400),
      ),
    );
  }

  Future<void> _load(BuildContext context, IroenMosaic mosaic) async {
    if (mosaic.id == iroen.activeMosaicId &&
        settings.palette == mosaic.palette) {
      Navigator.pop(context);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Load mosaic?'),
        content: Text('Replace the current canvas with “${mosaic.name}”?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Load'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final loaded = await iroen.loadMosaic(mosaic.id);
    if (loaded != null) {
      await settings.setPalette(loaded.palette, force: true);
    }
    if (!context.mounted) return;
    Navigator.pop(context);
  }

  Future<void> _confirmNewCanvas(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New blank canvas?'),
        content: const Text(
          'Clear the current canvas. Saved mosaics are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await iroen.newCanvas();
    if (!context.mounted) return;
    Navigator.pop(context);
  }

  Future<void> _mosaicMenu(BuildContext context, IroenMosaic mosaic) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('Rename'),
                onTap: () => Navigator.pop(context, 'rename'),
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Delete',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ],
          ),
        );
      },
    );
    if (!context.mounted || action == null) return;
    if (action == 'rename') {
      await _rename(context, mosaic);
    } else if (action == 'delete') {
      await _delete(context, mosaic);
    }
  }

  Future<void> _rename(BuildContext context, IroenMosaic mosaic) async {
    final controller = TextEditingController(text: mosaic.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename mosaic'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Name',
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !context.mounted) return;
    await iroen.renameMosaic(mosaic.id, name);
  }

  Future<void> _delete(BuildContext context, IroenMosaic mosaic) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete mosaic?'),
        content: Text('“${mosaic.name}” will be removed permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await iroen.deleteMosaic(mosaic.id);
  }
}

class _MosaicCard extends StatelessWidget {
  final IroenMosaic mosaic;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _MosaicCard({
    required this.mosaic,
    required this.isActive,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final line = IrodokuTheme.thinGridLine(IrodokuTheme.boardBrightness);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive ? accent : line.withValues(alpha: 0.5),
              width: isActive ? 2.2 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: Column(
              children: [
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CustomPaint(
                        painter: _MosaicThumbPainter(
                          values: mosaic.overviewValues(),
                          palette: mosaic.palette,
                          emptyFill: IrodokuTheme.emptyCellFill(
                            IrodokuTheme.boardBrightness,
                          ),
                          line: line,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  mosaic.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MosaicThumbPainter extends CustomPainter {
  final List<int> values;
  final GamePalette palette;
  final Color emptyFill;
  final Color line;

  const _MosaicThumbPainter({
    required this.values,
    required this.palette,
    required this.emptyFill,
    required this.line,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 9;
    canvas.drawRect(Offset.zero & size, Paint()..color = emptyFill);

    for (var i = 0; i < values.length && i < 81; i++) {
      final value = values[i];
      if (value == 0) continue;
      final swatch = IrodokuPalette.swatchForValue(value, palette);
      if (swatch == null) continue;
      final row = i ~/ 9;
      final col = i % 9;
      final rect = Rect.fromLTWH(col * cell, row * cell, cell, cell);
      drawSwatchRect(canvas, rect, swatch);
    }

    final gridPaint = Paint()
      ..color = line.withValues(alpha: 0.35)
      ..strokeWidth = 0.6;
    for (var i = 1; i < 9; i++) {
      final x = i * cell;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      canvas.drawLine(Offset(0, x), Offset(size.width, x), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MosaicThumbPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.palette != palette ||
        oldDelegate.emptyFill != emptyFill ||
        oldDelegate.line != line;
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/palette.dart';
import '../core/theme.dart';
import '../models/difficulty.dart';
import '../models/game_palette.dart';
import '../models/game_stats.dart';
import '../providers/game_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/stats_provider.dart';
import '../widgets/menu_action_button.dart';
import '../widgets/start_new_game_dialog.dart';
import '../widgets/typing_title.dart';

/// Standalone Settings page: difficulty, sound, dark mode, and palette.
class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: IrodokuTheme.settingsTheme(Theme.of(context)),
      child: Scaffold(
        appBar: AppBar(
          title: const TypingTitle(text: 'Settings'),
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            const ConfigSettingsPanel(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: MenuActionButton(
                label: 'How to Play',
                onPressed: () => showHowToPlayDialog(context),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: MenuActionButton(
                label: 'Controls',
                onPressed: () => showControlsHelpDialog(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showHowToPlayDialog(BuildContext context) {
  final baseStyle = Theme.of(context).textTheme.bodyMedium;
  final bold = baseStyle?.copyWith(fontWeight: FontWeight.w700);
  final palette = context.read<SettingsProvider>().palette;
  final paletteColors = IrodokuPalette.colorsFor(palette);

  return _showHelpDialog(
    context: context,
    title: 'How to Play',
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            style: baseStyle,
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: _PaletteSweepLabel(
                  text: 'Irodoku',
                  style: bold,
                  colors: paletteColors,
                ),
              ),
              const TextSpan(
                text:
                    ' is Sudoku played with colors. A 9×9 board is divided into nine 3×3 boxes.\n\nEach row, column, and box must contain each of the nine colors exactly once. Some colors start filled; the player fills the rest.\n',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _helpBulletRich(
          baseStyle,
          TextSpan(text: 'Tap a cell, then tap a color', style: bold),
          ' from the picker (or use notes for candidates)',
        ),
        _helpBulletRich(
          baseStyle,
          TextSpan(text: 'Three mistakes end the game', style: bold),
          '. A wrong fill counts as a mistake; a correct fill locks the color',
        ),
      ],
    ),
  );
}

/// Bold label that sweeps the active palette colors after a short delay.
class _PaletteSweepLabel extends StatefulWidget {
  static const _delay = Duration(milliseconds: 400);
  static const _duration = Duration(milliseconds: 1035); // prior 828ms + 25%

  final String text;
  final TextStyle? style;
  final List<Color> colors;

  const _PaletteSweepLabel({
    required this.text,
    required this.colors,
    this.style,
  });

  @override
  State<_PaletteSweepLabel> createState() => _PaletteSweepLabelState();
}

class _PaletteSweepLabelState extends State<_PaletteSweepLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _PaletteSweepLabel._duration,
    );
    _delayTimer = Timer(_PaletteSweepLabel._delay, () {
      if (!mounted) return;
      _controller.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final colors = widget.colors;
    final ink = style?.color ??
        Theme.of(context).colorScheme.onSurface;
    // Always paint through ShaderMask so pre/post glyphs match mid-animation.
    final maskedStyle = style?.copyWith(color: Colors.white);
    if (colors.length < 2) {
      return Text(widget.text, style: style);
    }

    // Lead + trail ink so the sweep eases out of / into black.
    final sweepColors = <Color>[ink, ink, ink, ...colors, ink, ink, ink];

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final raw = _controller.value;
        final t = Curves.easeInOutCubic.transform(raw);

        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            if (raw <= 0 || raw >= 1) {
              return LinearGradient(
                colors: [ink, ink],
              ).createShader(bounds);
            }

            // Slide far enough that both leading and trailing ink fully cover
            // the word (including the leftmost "I").
            return LinearGradient(
              begin: Alignment(2.0 - 5.8 * t, 0),
              end: Alignment(4.6 - 5.8 * t, 0),
              colors: sweepColors,
            ).createShader(bounds);
          },
          child: Text(widget.text, style: maskedStyle),
        );
      },
    );
  }
}

Future<void> showControlsHelpDialog(BuildContext context) {
  final baseStyle = Theme.of(context).textTheme.bodyMedium;
  final bold = baseStyle?.copyWith(fontWeight: FontWeight.w700);

  Widget bullet(InlineSpan lead, String rest) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: baseStyle),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: baseStyle,
                children: [
                  lead,
                  TextSpan(text: rest),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget section(String title, List<Widget> bullets) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: bold),
          const SizedBox(height: 8),
          ...bullets,
        ],
      ),
    );
  }

  return _showHelpDialog(
    context: context,
    title: 'Controls',
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        section('Cells', [
          bullet(TextSpan(text: 'Tap a cell', style: bold), ' to select'),
          bullet(
            TextSpan(text: 'Hold down', style: bold),
            ' to multi-select',
          ),
          bullet(
            TextSpan(text: 'Tap an empty space', style: bold),
            ' to deselect',
          ),
        ]),
        section('Colors', [
          bullet(
            TextSpan(text: 'Tap a color', style: bold),
            ' to apply',
          ),
          bullet(
            TextSpan(text: 'Swipe down', style: bold),
            ' to note a color',
          ),
          bullet(
            TextSpan(text: 'Swipe up', style: bold),
            ' to remove note',
          ),
        ]),
        section('Actions', [
          bullet(
            TextSpan(text: 'Undo', style: bold),
            ' - take back your last move',
          ),
          bullet(
            TextSpan(text: 'Erase', style: bold),
            ' - clear selected cell(s)',
          ),
          bullet(
            TextSpan(text: 'Note', style: bold),
            ' - enable Note mode / hold down for multi-select',
          ),
        ]),
      ],
    ),
  );
}

Widget _helpBulletRich(
  TextStyle? style,
  InlineSpan lead,
  String rest,
) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('•  ', style: style),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: style,
              children: [
                lead,
                TextSpan(text: rest),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

Future<void> _showHelpDialog({
  required BuildContext context,
  required String title,
  required Widget body,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        titlePadding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
        title: SizedBox(
          width: double.infinity,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Padding(
                // Keep descenders (e.g. "y" in Play) from being clipped.
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        height: 1.25,
                      ),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.black),
                ),
              ),
            ],
          ),
        ),
        content: SingleChildScrollView(child: body),
      );
    },
  );
}

/// Shared Config controls used by Main Menu and [AppSettingsScreen].
class ConfigSettingsPanel extends StatelessWidget {
  /// Sound / Dark mode toggles (Settings page only; hidden on Main Menu).
  final bool showSoundAndDarkMode;

  const ConfigSettingsPanel({
    super.key,
    this.showSoundAndDarkMode = true,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer3<SettingsProvider, StatsProvider, GameProvider>(
      builder: (context, settings, statsProvider, game, _) {
        final stats = statsProvider.stats;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Difficulty'),
              trailing: DropdownButtonHideUnderline(
                child: DropdownButton<Difficulty>(
                  value: settings.difficulty,
                  alignment: AlignmentDirectional.centerEnd,
                  items: [
                    for (final difficulty in Difficulty.values)
                      DropdownMenuItem(
                        value: difficulty,
                        child: _LockedMenuItem(
                          label: difficulty.label,
                          unlocked: statsProvider.isUnlocked(difficulty),
                        ),
                      ),
                  ],
                  selectedItemBuilder: (context) => [
                    for (final difficulty in Difficulty.values)
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Text(difficulty.label),
                      ),
                  ],
                  onChanged: (difficulty) {
                    if (difficulty == null) return;
                    if (!statsProvider.isUnlocked(difficulty)) {
                      _showUnlockSnackBar(context, difficulty, stats);
                      return;
                    }
                    if (difficulty == settings.difficulty) return;
                    _onDifficultyChosen(context, settings, difficulty);
                  },
                ),
              ),
            ),
            if (showSoundAndDarkMode) ...[
              _CompactSwitchRow(
                label: 'Sound',
                value: settings.soundEnabled,
                onChanged: settings.setSoundEnabled,
              ),
              _CompactSwitchRow(
                label: 'Dark mode',
                value: settings.darkMode,
                onChanged: settings.setDarkMode,
              ),
            ],
            ListTile(
              title: const Text('Palette'),
              trailing: DropdownButtonHideUnderline(
                child: DropdownButton<GamePalette>(
                  value: settings.palette,
                  alignment: AlignmentDirectional.centerEnd,
                  items: [
                    for (final palette in GamePalette.menuValues)
                      DropdownMenuItem(
                        value: palette,
                        child: _LockedMenuItem(
                          label: palette.label,
                          unlocked: statsProvider.isPaletteUnlocked(palette),
                        ),
                      ),
                  ],
                  selectedItemBuilder: (context) => [
                    for (final palette in GamePalette.menuValues)
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Text(palette.label),
                      ),
                  ],
                  onChanged: (palette) {
                    if (palette == null) return;
                    if (!statsProvider.isPaletteUnlocked(palette)) {
                      _showPaletteLockedSnackBar(context, palette);
                      return;
                    }
                    if (palette == settings.palette) return;
                    _onPaletteChosen(context, settings, palette);
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: _PalettePreviewRow(palette: settings.palette),
            ),
          ],
        );
      },
    );
  }
}

Future<void> _onDifficultyChosen(
  BuildContext context,
  SettingsProvider settings,
  Difficulty difficulty,
) async {
  final game = context.read<GameProvider>();
  await settings.setDifficulty(difficulty);
  if (!context.mounted) return;
  if (game.isGenerating) return;

  // Daily still live under Main Menu — only update the setting so parked
  // Classic/Chromatic progress is not wiped.
  if (game.isDaily) return;

  final preserveDaily = game.hasResumableDaily;

  // Mid-game: ask before discarding progress.
  if (game.hasInteracted && !game.isGameOver) {
    final startNew = await showStartNewGameDialog(context);
    if (!context.mounted) return;
    if (startNew == true) {
      await game.startNewGame(preserveHeldDaily: preserveDaily);
    }
    return;
  }

  // Untouched board (or finished game): apply immediately.
  if (game.hasActiveGame || game.isGameOver) {
    await game.startNewGame(preserveHeldDaily: preserveDaily);
  }
}

Future<void> _onPaletteChosen(
  BuildContext context,
  SettingsProvider settings,
  GamePalette palette,
) async {
  final game = context.read<GameProvider>();
  if (game.isGenerating) return;

  // Daily / Chromatic nested under menu: update the saved Config palette only.
  // Live Chromatic hops use a session palette and must not be overwritten here.
  if (game.isDaily || settings.chromatic) {
    await settings.setPalette(palette);
    return;
  }

  final preserveDaily = game.hasResumableDaily;

  // Mid-game: palette stays put unless the user starts a new puzzle.
  if (game.hasInteracted && !game.isGameOver) {
    final startNew = await showStartNewGameDialog(context);
    if (!context.mounted) return;
    if (startNew != true) return;
    await game.startNewGame(preserveHeldDaily: preserveDaily);
    await settings.setPalette(palette);
    return;
  }

  await settings.setPalette(palette);
}

void _showUnlockSnackBar(
  BuildContext context,
  Difficulty difficulty,
  GameStats stats,
) {
  final prerequisite = difficulty.unlockPrerequisite;
  if (prerequisite == null) return;
  final have = stats.winsFor(prerequisite);
  final need = Difficulty.unlockWinsRequired;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: SizedBox(
          width: double.infinity,
          child: Text.rich(
            TextSpan(
              style: Theme.of(context).snackBarTheme.contentTextStyle ??
                  TextStyle(
                    color: Theme.of(context).colorScheme.onInverseSurface,
                  ),
              children: [
                TextSpan(text: 'Win $need '),
                TextSpan(
                  text: prerequisite.label,
                  style: const TextStyle(
                    color: Colors.lightBlueAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: ' games ($have/$need)'),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
}

void _showPaletteLockedSnackBar(BuildContext context, GamePalette palette) {
  const highlightStyle = TextStyle(
    color: Colors.lightBlueAccent,
    fontWeight: FontWeight.w600,
  );
  final baseStyle = Theme.of(context).snackBarTheme.contentTextStyle ??
      TextStyle(color: Theme.of(context).colorScheme.onInverseSurface);

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: SizedBox(
          width: double.infinity,
          child: Text.rich(
            TextSpan(
              style: baseStyle,
              children: [
                for (final part in palette.unlockRequirementParts)
                  TextSpan(
                    text: part.text,
                    style: part.highlight ? highlightStyle : null,
                  ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
}

class _CompactSwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _CompactSwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Match Difficulty / Palette ListTile height (no dense/compact).
    return ListTile(
      title: Text(label),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
      ),
      onTap: () => onChanged(!value),
    );
  }
}

class _LockedMenuItem extends StatelessWidget {
  final String label;
  final bool unlocked;

  const _LockedMenuItem({
    required this.label,
    required this.unlocked,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.38);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: unlocked
              ? null
              : Theme.of(context).textTheme.bodyMedium?.copyWith(color: muted),
        ),
        if (!unlocked) ...[
          const SizedBox(width: 8),
          Icon(Icons.lock_outline, size: 16, color: muted),
        ],
      ],
    );
  }
}

class _PalettePreviewRow extends StatelessWidget {
  final GamePalette palette;

  const _PalettePreviewRow({required this.palette});

  @override
  Widget build(BuildContext context) {
    final line = IrodokuTheme.thinGridLine(IrodokuTheme.boardBrightness);
    final swatches = IrodokuPalette.swatchesFor(palette);

    return LayoutBuilder(
      builder: (context, constraints) {
        final swatchSize = constraints.maxWidth / 9;

        return SizedBox(
          height: swatchSize,
          child: Row(
            children: [
              for (var i = 0; i < 9; i++)
                SizedBox(
                  width: swatchSize,
                  height: swatchSize,
                  child: DecoratedBox(
                    decoration: swatches[i].boxDecoration(
                      border: Border.all(
                        color:
                            IrodokuPalette.outlineForValue(i + 1, palette) ??
                            line,
                        width: IrodokuPalette.outlineForValue(i + 1, palette) !=
                                null
                            ? 1.5
                            : 0.6,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

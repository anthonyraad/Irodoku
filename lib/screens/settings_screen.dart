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
import '../widgets/typing_title.dart';
import 'iroen_screen.dart';
import 'stats_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _titlePlayToken = 0;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: IrodokuTheme.settingsTheme(Theme.of(context)),
      child: Scaffold(
        appBar: AppBar(
          title: TypingTitle(
            text: 'Settings',
            playToken: _titlePlayToken,
          ),
        ),
        body: Consumer2<SettingsProvider, StatsProvider>(
        builder: (context, settings, statsProvider, _) {
          final stats = statsProvider.stats;
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
              const _SectionHeader(title: 'Config'),
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
              SwitchListTile(
                title: const Text('Sound'),
                value: settings.soundEnabled,
                onChanged: settings.setSoundEnabled,
              ),
              SwitchListTile(
                title: const Text('XL'),
                value: settings.xlPicker,
                onChanged: settings.setXlPicker,
              ),
              SwitchListTile(
                title: const Text('Dark mode'),
                value: settings.darkMode,
                onChanged: settings.setDarkMode,
              ),
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
                      settings.setPalette(palette);
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: _PalettePreviewRow(palette: settings.palette),
              ),
              const Divider(height: 32),
              const _SectionHeader(title: 'Progress'),
              ListTile(
                leading: const Icon(Icons.bar_chart_rounded),
                title: const Text('Stats'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const StatsScreen()),
                  );
                  if (!mounted) return;
                  setState(() => _titlePlayToken++);
                },
              ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Center(
                    child: _IroenButton(
                      unlocked: statsProvider.isIroenUnlocked,
                      onPressed: () {
                        if (!statsProvider.isIroenUnlocked) {
                          _showIroenLockedSnackBar(context, stats);
                          return;
                        }
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const IroenScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      ),
    );
  }

  void _showIroenLockedSnackBar(BuildContext context, GameStats stats) {
    const need = GameStats.iroenUnlockWinsRequired;
    final have = stats.gamesWon;
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
                  const TextSpan(text: 'Win '),
                  TextSpan(
                    text: '$need',
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

  Future<void> _onDifficultyChosen(
    BuildContext context,
    SettingsProvider settings,
    Difficulty difficulty,
  ) async {
    final game = context.read<GameProvider>();
    await settings.setDifficulty(difficulty);
    if (!context.mounted) return;
    if (game.isGenerating) return;

    // Mid-game: ask before discarding progress.
    if (game.hasInteracted && !game.isGameOver) {
      final startNew = await _confirmStartNewGame(context);
      if (!context.mounted) return;
      if (startNew == true) {
        await game.startNewGame();
      }
      return;
    }

    // Untouched board (or finished game): apply immediately.
    if (game.hasActiveGame || game.isGameOver) {
      await game.startNewGame();
    }
  }

  Future<bool?> _confirmStartNewGame(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? Colors.white : Colors.black;
    final onInk = dark ? Colors.black : Colors.white;

    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Start new game?',
            textAlign: TextAlign.center,
            style: TextStyle(color: ink),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              style: TextButton.styleFrom(foregroundColor: ink),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: ink,
                foregroundColor: onInk,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );
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

class _IroenButton extends StatelessWidget {
  static const _borderRadius = BorderRadius.all(Radius.circular(4));

  final bool unlocked;
  final VoidCallback onPressed;

  const _IroenButton({
    required this.unlocked,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.38);
    final borderColor = unlocked ? scheme.outline : muted;

    return IntrinsicWidth(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: _borderRadius,
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.16),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: _borderRadius,
            side: BorderSide(color: borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: unlocked
                  ? Text(
                      'Iroen',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: scheme.primary,
                          ),
                    )
                  : Icon(
                      Icons.lock_outline,
                      size: 22,
                      color: scheme.onSurface.withValues(alpha: 0.55),
                    ),
            ),
          ),
        ),
      ),
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

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

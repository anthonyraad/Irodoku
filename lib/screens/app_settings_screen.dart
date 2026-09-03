import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/palette.dart';
import '../core/theme.dart';
import '../models/difficulty.dart';
import '../models/game_palette.dart';
import '../models/game_stats.dart';
import '../models/iro_mix.dart';
import '../providers/achievements_provider.dart';
import '../providers/game_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/stats_provider.dart';
import '../widgets/menu_action_button.dart';
import '../widgets/menu_select_sound.dart';
import '../widgets/palette_sweep_mask.dart';
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
          leading: const MenuBackButton(),
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

  Widget irodokuLabel() => _PaletteSweepLabel(
        text: 'Irodoku',
        style: bold,
        colors: paletteColors,
      );

  final classicPage = Column(
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
              child: irodokuLabel(),
            ),
            const TextSpan(
              text:
                  ' is Sudoku played with colors. A 9×9 board is divided into nine 3×3 boxes.\n\nEach row, column, and box must contain each of the nine colors exactly once. Some colors start filled; the player fills the rest.\n\n',
            ),
            TextSpan(text: 'Tap a cell, then tap a color', style: bold),
            const TextSpan(
              text: ' from the picker (or use notes for candidates)',
            ),
          ],
        ),
      ),
    ],
  );

  final pocketPage = Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text.rich(
        TextSpan(
          style: baseStyle,
          children: [
            TextSpan(text: 'Pocket Irodoku', style: bold),
            const TextSpan(
              text:
                  ' is played with a 6×6 board that is divided into six 2×3 boxes.\n\nEach row, column, and box must contain each of the 6 colors exactly once. Otherwise, the same Irodoku rules and controls apply.\n\nAccess Pocket mode for Irodoku, Graffiti, and more by ',
            ),
            TextSpan(
              text: 'swiping right on the Irodoku button',
              style: bold,
            ),
            const TextSpan(text: ' from the main menu.'),
          ],
        ),
      ),
    ],
  );

  return showDialog<void>(
    context: context,
    builder: (context) => _HowToPlayDialog(
      classicPage: classicPage,
      pocketPage: pocketPage,
    ),
  );
}

/// Bold label that sweeps the active palette colors after a short delay.
class _PaletteSweepLabel extends StatefulWidget {
  static const _delay = Duration(milliseconds: 400);

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
      duration: PaletteSweepMask.duration,
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

    return PaletteSweepMask(
      colors: colors,
      ink: ink,
      progress: _controller,
      child: Text(widget.text, style: maskedStyle),
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

class _HowToPlayDialog extends StatefulWidget {
  final Widget classicPage;
  final Widget pocketPage;

  const _HowToPlayDialog({
    required this.classicPage,
    required this.pocketPage,
  });

  @override
  State<_HowToPlayDialog> createState() => _HowToPlayDialogState();
}

class _HowToPlayDialogState extends State<_HowToPlayDialog> {
  static const _minDistance = 28.0;
  static const _minVelocity = 180.0;
  static const _pageDuration = Duration(milliseconds: 240);

  late final PageController _page;
  int _index = 0;
  double _dragDx = 0;

  @override
  void initState() {
    super.initState();
    _page = PageController();
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    final clamped = index.clamp(0, 1);
    if (clamped == _index) return;
    _page.animateToPage(
      clamped,
      duration: _pageDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final swipeLeft = _dragDx < -_minDistance || velocity < -_minVelocity;
    final swipeRight = _dragDx > _minDistance || velocity > _minVelocity;
    _dragDx = 0;
    if (swipeLeft) {
      _goTo(_index + 1);
    } else if (swipeRight) {
      _goTo(_index - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    final height =
        (MediaQuery.sizeOf(context).height * 0.42).clamp(220.0, 340.0);
    final pages = [widget.classicPage, widget.pocketPage];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => _dragDx = 0,
      onHorizontalDragUpdate: (details) => _dragDx += details.delta.dx,
      onHorizontalDragEnd: _onDragEnd,
      child: AlertDialog(
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
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'How to Play',
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
        content: SizedBox(
          width: double.maxFinite,
          height: height,
          child: Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _page,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (index) => setState(() => _index = index),
                  children: [
                    for (final page in pages)
                      SingleChildScrollView(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: page,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < pages.length; i++)
                    GestureDetector(
                      onTap: () => _goTo(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 4,
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _index
                                ? ink
                                : ink.withValues(alpha: 0.28),
                          ),
                          child: const SizedBox(width: 8, height: 8),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared Config controls used by Main Menu and [AppSettingsScreen].
class ConfigSettingsPanel extends StatelessWidget {
  /// Sound / Dark mode toggles (Settings page only; hidden on Main Menu).
  final bool showSoundAndDarkMode;

  /// Main Menu [Pocket] swipe: replace the difficulty dropdown with a grey XX.
  final bool difficultyLocked;

  /// Fired after a difficulty change is committed (Main Menu pulse).
  final VoidCallback? onDifficultyApplied;

  const ConfigSettingsPanel({
    super.key,
    this.showSoundAndDarkMode = true,
    this.difficultyLocked = false,
    this.onDifficultyApplied,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer4<SettingsProvider, StatsProvider, GameProvider,
        AchievementsProvider>(
      builder: (context, settings, statsProvider, game, _, _) {
        final stats = statsProvider.stats;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Difficulty'),
              trailing: _DifficultyTrailing(
                locked: difficultyLocked,
                settings: settings,
                statsProvider: statsProvider,
                stats: stats,
                onDifficultyApplied: onDifficultyApplied,
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
                    if (settings.isIroUnlocked)
                      const DropdownMenuItem(
                        value: GamePalette.iro,
                        child: Text('Iro'),
                      ),
                  ],
                  selectedItemBuilder: (context) => [
                    for (final palette in GamePalette.menuValues)
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Text(palette.label),
                      ),
                    if (settings.isIroUnlocked)
                      const Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Text('Iro'),
                      ),
                  ],
                  onChanged: (palette) {
                    if (palette == null) return;
                    if (palette == GamePalette.iro) {
                      if (!settings.isIroUnlocked) return;
                    } else if (!statsProvider.isPaletteUnlocked(palette)) {
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

/// Difficulty dropdown whose caret scales away when Pocket locks the control.
class _DifficultyTrailing extends StatefulWidget {
  final bool locked;
  final SettingsProvider settings;
  final StatsProvider statsProvider;
  final GameStats stats;
  final VoidCallback? onDifficultyApplied;

  const _DifficultyTrailing({
    required this.locked,
    required this.settings,
    required this.statsProvider,
    required this.stats,
    this.onDifficultyApplied,
  });

  @override
  State<_DifficultyTrailing> createState() => _DifficultyTrailingState();
}

class _DifficultyTrailingState extends State<_DifficultyTrailing>
    with SingleTickerProviderStateMixin {
  static const _caretSize = 24.0;
  static const _caretDuration = Duration(milliseconds: 210);

  late final AnimationController _caret;
  late final Animation<double> _caretScale;

  @override
  void initState() {
    super.initState();
    _caret = AnimationController(
      vsync: this,
      duration: _caretDuration,
      value: widget.locked ? 0 : 1,
    );
    _caretScale = CurvedAnimation(
      parent: _caret,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void didUpdateWidget(covariant _DifficultyTrailing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.locked == widget.locked) return;
    if (widget.locked) {
      _caret.reverse();
    } else {
      _caret.forward();
    }
  }

  @override
  void dispose() {
    _caret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final xxStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: Theme.of(context)
              .colorScheme
              .onSurface
              .withValues(alpha: 0.35),
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.locked)
          Text('XX', style: xxStyle)
        else
          DropdownButtonHideUnderline(
            child: DropdownButton<Difficulty>(
              value: widget.settings.difficulty,
              alignment: AlignmentDirectional.centerEnd,
              iconSize: _caretSize,
              icon: ScaleTransition(
                scale: _caretScale,
                child: Icon(
                  Icons.arrow_drop_down,
                  size: _caretSize,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              items: [
                for (final difficulty in Difficulty.values)
                  DropdownMenuItem(
                    value: difficulty,
                    child: _LockedMenuItem(
                      label: difficulty.label,
                      unlocked: widget.statsProvider.isUnlocked(difficulty),
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
                if (!widget.statsProvider.isUnlocked(difficulty)) {
                  _showUnlockSnackBar(
                    context,
                    difficulty,
                    widget.stats,
                  );
                  return;
                }
                if (difficulty == widget.settings.difficulty) return;
                _onDifficultyChosen(
                  context,
                  widget.settings,
                  difficulty,
                  onApplied: widget.onDifficultyApplied,
                );
              },
            ),
          ),
        if (widget.locked)
          SizedBox(
            width: _caretSize,
            height: _caretSize,
            child: ScaleTransition(
              scale: _caretScale,
              child: Icon(
                Icons.arrow_drop_down,
                size: _caretSize,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
      ],
    );
  }
}

Future<void> _onDifficultyChosen(
  BuildContext context,
  SettingsProvider settings,
  Difficulty difficulty, {
  VoidCallback? onApplied,
}) async {
  final game = context.read<GameProvider>();
  if (game.isGenerating) return;

  final preserveDaily = game.hasResumableDaily;
  final liveClassicOrChromatic =
      !game.isDaily && !game.isPocket;

  // Mid-game Classic/Chromatic: keep the old difficulty unless they start over.
  if (liveClassicOrChromatic &&
      game.hasInteracted &&
      !game.isGameOver) {
    final startNew = await showStartNewGameDialog(context);
    if (!context.mounted || startNew != true) return;
    await settings.setDifficulty(difficulty);
    onApplied?.call();
    if (!context.mounted) return;
    await game.startNewGame(preserveHeldDaily: preserveDaily);
    return;
  }

  await settings.setDifficulty(difficulty);
  onApplied?.call();
  if (!context.mounted) return;

  // Daily / Pocket: only the setting changes so parked Classic/Chromatic
  // progress is not wiped. Untouched or finished Classic/Chromatic regenerate.
  if (liveClassicOrChromatic &&
      (game.hasActiveGame || game.isGameOver)) {
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
  if (game.isDaily || game.isPocket || settings.chromatic) {
    await settings.setPalette(palette);
    return;
  }

  final preserveDaily = game.hasResumableDaily;

  // Mid-game: palette stays put unless the user starts a new puzzle.
  if (game.hasInteracted && !game.isGameOver) {
    final startNew = await showStartNewGameDialog(context);
    if (!context.mounted) return;
    if (startNew != true) return;
    await settings.setPalette(palette);
    await game.startNewGame(preserveHeldDaily: preserveDaily);
    return;
  }

  await settings.setPalette(palette);
  game.syncIroMixToConfigPalette();
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
      trailing: _BlockySwitch(
        value: value,
        onChanged: onChanged,
      ),
      onTap: () => onChanged(!value),
    );
  }
}

/// Square, thick-bordered toggle matching Main Menu button chrome.
class _BlockySwitch extends StatelessWidget {
  static const _width = 52.0;
  static const _height = 28.0;
  static const _thumb = 18.0;
  static const _pad = 2.5;
  static const _borderWidth = 2.5;
  static const _radius = BorderRadius.all(Radius.circular(2));
  static const _anim = Duration(milliseconds: 140);

  final bool value;
  final ValueChanged<bool> onChanged;

  const _BlockySwitch({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = scheme.onSurface;
    final trackFill = value ? ink : scheme.surface;
    final thumbFill = value ? scheme.surface : ink;

    return Semantics(
      toggled: value,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: _anim,
          curve: Curves.easeOut,
          width: _width,
          height: _height,
          padding: const EdgeInsets.all(_pad),
          decoration: BoxDecoration(
            color: trackFill,
            borderRadius: _radius,
            border: Border.all(color: ink, width: _borderWidth),
          ),
          child: AnimatedAlign(
            duration: _anim,
            curve: Curves.easeOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: _thumb,
              height: _thumb,
              decoration: BoxDecoration(
                color: thumbFill,
                borderRadius: const BorderRadius.all(Radius.circular(1)),
                border: value
                    ? null
                    : Border.all(color: ink, width: 1.5),
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

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
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
      ),
    );
  }
}

class _PalettePreviewRow extends StatefulWidget {
  final GamePalette palette;

  const _PalettePreviewRow({required this.palette});

  @override
  State<_PalettePreviewRow> createState() => _PalettePreviewRowState();
}

class _PalettePreviewRowState extends State<_PalettePreviewRow> {
  IroMix? _mix;

  @override
  void initState() {
    super.initState();
    _remixIfIro();
  }

  @override
  void didUpdateWidget(_PalettePreviewRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.palette != widget.palette) {
      _remixIfIro();
    }
  }

  void _remixIfIro() {
    _mix = widget.palette == GamePalette.iro ? IroMix.random() : null;
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final line = IrodokuTheme.thinGridLine(IrodokuTheme.boardBrightness);
    final mix = _mix;
    final swatches = mix?.swatches ?? IrodokuPalette.swatchesFor(palette);
    final sources = mix?.sources;

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
                        color: IrodokuPalette.outlineForSlot(
                              i + 1,
                              palette,
                              sources,
                            ) ??
                            line,
                        width: IrodokuPalette.outlineForSlot(
                                  i + 1,
                                  palette,
                                  sources,
                                ) !=
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

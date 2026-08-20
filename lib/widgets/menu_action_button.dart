import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/palette.dart';
import '../providers/settings_provider.dart';
import 'menu_select_sound.dart';
import 'palette_sweep_mask.dart';

/// Bordered Main Menu-style action button (Classic, Stats, Settings, etc.).
class MenuActionButton extends StatelessWidget {
  static const _borderRadius = BorderRadius.all(Radius.circular(8));

  final String label;
  final String? badge;
  final bool enabled;
  final bool muted;
  final bool locked;
  final VoidCallback onPressed;
  /// 0–1 progress; when set, the label shakes horizontally as it runs.
  final Animation<double>? labelShake;
  /// 0–1 progress; when set, the label sweeps the selected Config palette.
  final Animation<double>? labelSweep;
  /// 0–1 progress; when set, the badge pill sweeps the selected Config palette.
  final Animation<double>? badgeSweep;

  const MenuActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.badge,
    this.enabled = true,
    this.muted = false,
    this.locked = false,
    this.labelShake,
    this.labelSweep,
    this.badgeSweep,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final interactive = enabled;
    // Match the old Daily Iro button: muted fill/border when finished or locked.
    final visuallyMuted = muted || locked || !interactive;
    final ink = scheme.onSurface.withValues(alpha: visuallyMuted ? 0.55 : 1);
    final border = visuallyMuted ? scheme.outlineVariant : scheme.onSurface;
    final fill =
        visuallyMuted ? scheme.surfaceContainerHighest : scheme.surface;

    final labelStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          color: ink,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        );
    final lineHeight =
        (labelStyle?.fontSize ?? 16) * (labelStyle?.height ?? 1.3);

    return SizedBox(
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: _borderRadius,
              boxShadow: interactive && !visuallyMuted
                  ? [
                      BoxShadow(
                        color: scheme.shadow.withValues(alpha: 0.26),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: fill,
              shape: RoundedRectangleBorder(
                borderRadius: _borderRadius,
                side: BorderSide(color: border, width: 2.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: interactive
                    ? () {
                        playMenuSelectSound(context);
                        onPressed();
                      }
                    : null,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: SizedBox(
                          height: lineHeight,
                          width: double.infinity,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: _sweepingLabel(ink, labelStyle),
                          ),
                        ),
                      ),
                      if (locked) ...[
                        const SizedBox(width: 10),
                        Icon(Icons.lock_outline, size: 20, color: ink),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (badge != null && badge!.isNotEmpty)
            Positioned(
              top: -8,
              right: -6,
              child: IgnorePointer(
                child: _MenuActionBadge(
                  label: badge!,
                  sweep: badgeSweep,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sweepingLabel(Color ink, TextStyle? labelStyle) {
    Widget painted() {
      return _shakingLabel(
        _MenuActionLabel(
          label: label,
          color: ink,
          struckThrough: muted,
          style: labelStyle,
        ),
      );
    }

    final sweep = labelSweep;
    if (sweep == null) {
      return painted();
    }

    return _shakingLabel(
      PaletteSweepFillText(
        text: label,
        style: labelStyle,
        ink: ink,
        progress: sweep,
        startT: PaletteSweepMask.menuStartT,
      ),
    );
  }

  Widget _shakingLabel(Widget child) {
    final shake = labelShake;
    if (shake == null) return child;
    return AnimatedBuilder(
      animation: shake,
      builder: (context, child) {
        final t = shake.value;
        final dx = math.sin(t * math.pi * 5) * 4 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: child,
    );
  }
}

/// Label with an optional strikethrough raised into the letter mid-height.
class _MenuActionLabel extends StatelessWidget {
  final String label;
  final Color color;
  final bool struckThrough;
  final TextStyle? style;

  const _MenuActionLabel({
    required this.label,
    required this.color,
    required this.struckThrough,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      textAlign: TextAlign.center,
      maxLines: 1,
      softWrap: false,
      style: style,
    );
    if (!struckThrough) return text;

    return Stack(
      alignment: Alignment.center,
      children: [
        text,
        // Default TextDecoration.lineThrough sits low; nudge into x-height.
        Positioned.fill(
          child: IgnorePointer(
            child: Align(
              alignment: const Alignment(0, 0.09),
              child: ColoredBox(
                color: color,
                child: const SizedBox(height: 1.5, width: double.infinity),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuActionBadge extends StatelessWidget {
  final String label;
  final Animation<double>? sweep;

  const _MenuActionBadge({required this.label, this.sweep});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = scheme.onSurface;
    final text = Padding(
      padding: const EdgeInsets.fromLTRB(7, 2, 7, 3),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.surface,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              height: 1.1,
            ),
      ),
    );
    final progress = sweep;
    if (progress == null) {
      return _badgeShell(scheme: scheme, color: fill, child: text);
    }

    final colors = IrodokuPalette.colorsFor(
      context.watch<SettingsProvider>().palette,
    );
    return AnimatedBuilder(
      animation: progress,
      builder: (context, child) {
        final raw = progress.value;
        final sweeping = raw > 0 && raw < 1 && colors.length >= 2;
        return _badgeShell(
          scheme: scheme,
          color: fill,
          gradient: sweeping
              ? PaletteSweepMask.diagonalGradient(
                  colors: colors,
                  ink: fill,
                  raw: raw,
                  startT: PaletteSweepMask.menuStartT,
                )
              : null,
          child: child!,
        );
      },
      child: text,
    );
  }

  Widget _badgeShell({
    required ColorScheme scheme,
    required Color color,
    required Widget child,
    Gradient? gradient,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: gradient == null ? color : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.surface, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.22),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
  }
}

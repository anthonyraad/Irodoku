import 'package:flutter/material.dart';

import 'menu_select_sound.dart';

/// Bordered Main Menu-style action button (Classic, Stats, Settings, etc.).
class MenuActionButton extends StatelessWidget {
  static const _borderRadius = BorderRadius.all(Radius.circular(8));

  final String label;
  final String? trailing;
  final bool enabled;
  final bool muted;
  final bool locked;
  final VoidCallback onPressed;

  const MenuActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.trailing,
    this.enabled = true,
    this.muted = false,
    this.locked = false,
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
      child: DecoratedBox(
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
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: SizedBox(
                      height: lineHeight,
                      width: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _MenuActionLabel(
                          label: label,
                          color: ink,
                          struckThrough: muted,
                          style: labelStyle,
                        ),
                      ),
                    ),
                  ),
                  if (locked) ...[
                    const SizedBox(width: 10),
                    Icon(Icons.lock_outline, size: 20, color: ink),
                  ] else if (trailing != null) ...[
                    const SizedBox(width: 10),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        trailing!,
                        maxLines: 1,
                        softWrap: false,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: ink,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
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

import 'package:flutter/material.dart';

import '../models/hyperchroma.dart';
import 'sketch_icon.dart';

/// Pause cover for Hyperchroma. The clock and sketch count stay in the HUD.
class HyperchromaShop extends StatelessWidget {
  final int sketches;
  final ValueChanged<HyperchromaEffect> onBuy;

  const HyperchromaShop({
    super.key,
    required this.sketches,
    required this.onBuy,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final effect in HyperchromaEffect.values) ...[
                      if (effect != HyperchromaEffect.values.first)
                        const SizedBox(height: 8),
                      _EffectCard(
                        effect: effect,
                        enabled: sketches >= effect.cost,
                        onBuy: () => onBuy(effect),
                        scheme: scheme,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EffectCard extends StatelessWidget {
  final HyperchromaEffect effect;
  final bool enabled;
  final VoidCallback onBuy;
  final ColorScheme scheme;

  const _EffectCard({
    required this.effect,
    required this.enabled,
    required this.onBuy,
    required this.scheme,
  });

  @override
  Widget build(BuildContext context) {
    final ink = scheme.onSurface.withValues(alpha: enabled ? 1 : 0.45);
    final border = enabled ? scheme.onSurface : scheme.outlineVariant;
    final fill = enabled ? scheme.surface : scheme.surfaceContainerHighest;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        boxShadow: enabled
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
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          side: BorderSide(color: border, width: 2.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onBuy : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        effect.title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: ink,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    Opacity(
                      opacity: enabled ? 1 : 0.45,
                      child: const SketchIcon(),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${effect.cost}x',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  effect.description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: ink.withValues(alpha: enabled ? 0.8 : 0.45),
                    height: 1.25,
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

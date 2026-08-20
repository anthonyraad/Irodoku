import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/palette.dart';
import '../providers/settings_provider.dart';

/// Slides [colors] across [child], bookended by [ink] so the sweep eases
/// out of and back into the resting glyph color.
///
/// [child] must be painted white ([BlendMode.srcIn] tints it).
class PaletteSweepMask extends StatelessWidget {
  static const duration = Duration(milliseconds: 1035);

  /// Skips this much of the curved sweep so color reaches the glyphs sooner.
  static const menuStartT = 0.18;

  final Widget child;
  final List<Color> colors;
  final Color ink;
  final Animation<double> progress;
  /// 0–1. Applied after the curve; 0 keeps the How to Play timing.
  final double startT;

  const PaletteSweepMask({
    super.key,
    required this.child,
    required this.colors,
    required this.ink,
    required this.progress,
    this.startT = 0,
  });

  static double _sweepT(double raw, double startT) {
    final curved = Curves.easeInOutCubic.transform(raw.clamp(0.0, 1.0));
    return startT + (1.0 - startT) * curved;
  }

  static List<Color> _stops(List<Color> colors, Color ink) =>
      <Color>[ink, ink, ink, ...colors, ink, ink, ink];

  static LinearGradient gradient({
    required List<Color> colors,
    required Color ink,
    required double raw,
    double startT = 0,
  }) {
    final t = _sweepT(raw, startT);
    return LinearGradient(
      begin: Alignment(2.0 - 5.8 * t, 0),
      end: Alignment(4.6 - 5.8 * t, 0),
      colors: _stops(colors, ink),
    );
  }

  /// Same bookended palette band as [gradient], traveling top-left → bottom-right.
  static LinearGradient diagonalGradient({
    required List<Color> colors,
    required Color ink,
    required double raw,
    double startT = 0,
  }) {
    final t = _sweepT(raw, startT);
    return LinearGradient(
      begin: Alignment(-4.6 + 5.8 * t, -4.6 + 5.8 * t),
      end: Alignment(-2.0 + 5.8 * t, -2.0 + 5.8 * t),
      colors: _stops(colors, ink),
    );
  }

  static Shader createShader({
    required Rect bounds,
    required List<Color> colors,
    required Color ink,
    required double raw,
    double startT = 0,
  }) {
    return gradient(
      colors: colors,
      ink: ink,
      raw: raw,
      startT: startT,
    ).createShader(bounds);
  }

  /// Solid color of the How to Play sweep at alignment [x] (-1 left, +1 right).
  static Color sampleAt({
    required double x,
    required double raw,
    required List<Color> colors,
    required Color ink,
    double startT = 0,
  }) {
    final t = _sweepT(raw, startT);
    final begin = 2.0 - 5.8 * t;
    final end = 4.6 - 5.8 * t;
    final span = end - begin;
    if (span.abs() < 1e-6) return ink;
    final u = ((x - begin) / span).clamp(0.0, 1.0);
    final stops = _stops(colors, ink);
    final pos = u * (stops.length - 1);
    final i = pos.floor().clamp(0, stops.length - 2);
    return Color.lerp(stops[i], stops[i + 1], pos - i)!;
  }

  @override
  Widget build(BuildContext context) {
    if (colors.length < 2) return child;

    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) {
        final raw = progress.value;

        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            if (raw <= 0 || raw >= 1) {
              return LinearGradient(
                colors: [ink, ink],
              ).createShader(bounds);
            }

            return createShader(
              bounds: bounds,
              colors: colors,
              ink: ink,
              raw: raw,
              startT: startT,
            );
          },
          child: child,
        );
      },
    );
  }
}

/// Menu-button sweep: same [Text] rasterization as the other buttons.
/// Each glyph keeps a solid [TextStyle.color] so weight never changes.
/// Colors always come from the Config palette currently selected.
class PaletteSweepFillText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final Color ink;
  final Animation<double> progress;
  final double startT;
  final TextAlign textAlign;

  const PaletteSweepFillText({
    super.key,
    required this.text,
    required this.style,
    required this.ink,
    required this.progress,
    this.startT = 0,
    this.textAlign = TextAlign.center,
  });

  @override
  Widget build(BuildContext context) {
    final colors = IrodokuPalette.colorsFor(
      context.watch<SettingsProvider>().palette,
    );
    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) {
        final raw = progress.value;
        final base = style ?? TextStyle(color: ink);
        if (raw <= 0 || raw >= 1 || colors.length < 2 || text.isEmpty) {
          return Text(
            text,
            textAlign: textAlign,
            maxLines: 1,
            softWrap: false,
            style: base,
          );
        }

        final n = text.length;
        return Text.rich(
          TextSpan(
            style: base,
            children: [
              for (var i = 0; i < n; i++)
                TextSpan(
                  text: text[i],
                  style: TextStyle(
                    color: PaletteSweepMask.sampleAt(
                      x: -1.0 + 2.0 * ((i + 0.5) / n),
                      raw: raw,
                      colors: colors,
                      ink: ink,
                      startT: startT,
                    ),
                  ),
                ),
            ],
          ),
          textAlign: textAlign,
          maxLines: 1,
          softWrap: false,
        );
      },
    );
  }
}

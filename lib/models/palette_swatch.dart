import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/cel_shade_swatch.dart';
import '../core/comic_swatch.dart';
import '../core/gloss_swatch_shader.dart';
import '../core/marble_swatch.dart';
import '../core/organic_swatch_motion.dart';
import '../core/organic_swatch_shader.dart';

enum PaletteSwatchStyle {
  solid,
  organic,
  neon,
  gloss,
  celShade,
  marble,
}

/// A fill style for one palette slot (solid, organic gradient, or neon texture).
class PaletteSwatch {
  final Color start;
  final Color stop;
  final Alignment begin;
  final Alignment end;
  /// Per-slot variation for shader fills; ignored for solid swatches.
  final int swirlSeed;
  final PaletteSwatchStyle style;
  /// When true, fill motion is driven by [OrganicSwatchMotion].
  final bool animated;
  /// Organic warp/contrast strength (1.0 = Glass default).
  final double intensity;
  /// Multiplier on motion clock when [animated] (1.0 = Glass default).
  final double motionSpeed;

  const PaletteSwatch({
    required this.start,
    required this.stop,
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
    this.swirlSeed = 0,
    this.style = PaletteSwatchStyle.solid,
    this.animated = false,
    this.intensity = 1.0,
    this.motionSpeed = 1.0,
  });

  factory PaletteSwatch.solid(Color color) =>
      PaletteSwatch(start: color, stop: color);

  factory PaletteSwatch.organic({
    required Color start,
    required Color stop,
    int swirlSeed = 0,
    bool animated = false,
    double intensity = 1.0,
    double motionSpeed = 1.0,
  }) =>
      PaletteSwatch(
        start: start,
        stop: stop,
        swirlSeed: swirlSeed,
        style: PaletteSwatchStyle.organic,
        animated: animated,
        intensity: intensity,
        motionSpeed: motionSpeed,
      );

  /// Neon palette: flat color with comic-book halftone / cel highlight overlays.
  factory PaletteSwatch.neon(Color color, {int swirlSeed = 0}) =>
      PaletteSwatch(
        start: color,
        stop: color,
        swirlSeed: swirlSeed,
        style: PaletteSwatchStyle.neon,
      );

  factory PaletteSwatch.gloss(Color color, {int swirlSeed = 0}) =>
      PaletteSwatch(
        start: color,
        stop: color,
        swirlSeed: swirlSeed,
        style: PaletteSwatchStyle.gloss,
      );

  factory PaletteSwatch.celShade(Color color, {int swirlSeed = 0}) =>
      PaletteSwatch(
        start: color,
        stop: color,
        swirlSeed: swirlSeed,
        style: PaletteSwatchStyle.celShade,
      );

  /// Standard palette: flat color with soft marble cloud / vein overlays.
  factory PaletteSwatch.marble(Color color, {int swirlSeed = 0}) =>
      PaletteSwatch(
        start: color,
        stop: color,
        swirlSeed: swirlSeed,
        style: PaletteSwatchStyle.marble,
      );

  bool get isOrganic =>
      style == PaletteSwatchStyle.organic ||
      (style == PaletteSwatchStyle.solid && start != stop);

  bool get isNeon => style == PaletteSwatchStyle.neon;

  bool get isGloss => style == PaletteSwatchStyle.gloss;

  bool get isCelShade => style == PaletteSwatchStyle.celShade;

  bool get isMarble => style == PaletteSwatchStyle.marble;

  bool get isGradient => isOrganic && start != stop;

  bool get usesShader =>
      isOrganic || isNeon || isGloss || isCelShade || isMarble;

  /// Midpoint blend used for same-color wash and animation lerps.
  Color get representative => isGradient ? blend(start, stop, 0.5) : start;

  /// Blends through HSL so complementary pairs don't turn muddy in RGB space.
  static Color blend(Color from, Color to, double t) {
    final clamped = t.clamp(0.0, 1.0);
    final a = HSLColor.fromColor(from);
    final b = HSLColor.fromColor(to);

    final deltaHue = _shortestHueDelta(a.hue, b.hue);
    final hue = (a.hue + deltaHue * clamped) % 360;

    return HSLColor.fromAHSL(
      a.alpha + (b.alpha - a.alpha) * clamped,
      hue,
      a.saturation + (b.saturation - a.saturation) * clamped,
      a.lightness + (b.lightness - a.lightness) * clamped,
    ).toColor();
  }

  static double _shortestHueDelta(double from, double to) {
    var delta = to - from;
    while (delta > 180) {
      delta -= 360;
    }
    while (delta < -180) {
      delta += 360;
    }
    return delta;
  }

  Decoration decoration({BoxBorder? border}) {
    if (!usesShader) {
      return BoxDecoration(color: start, border: border);
    }
    return _ShaderSwatchDecoration(swatch: this, border: border);
  }

  /// Back-compat alias for widget backgrounds.
  Decoration boxDecoration({BoxBorder? border}) => decoration(border: border);

  Shader? shaderForRect(Rect rect) {
    if (isGloss) {
      return GlossSwatchShader.forRect(rect, this);
    }
    if (!isOrganic) return null;
    return OrganicSwatchShader.forRect(rect, this) ??
        _fallbackShaderForRect(rect);
  }

  Shader _fallbackShaderForRect(Rect rect) {
    final angle = swirlSeed * 0.91;
    final center = rect.center +
        Offset(
          math.cos(angle) * rect.width * 0.12,
          math.sin(angle) * rect.height * 0.1,
        );
    return ui.Gradient.radial(
      center,
      rect.shortestSide * 0.85,
      [
        blend(start, stop, 0.08),
        blend(start, stop, 0.42),
        blend(start, stop, 0.78),
        stop,
      ],
      [0.0, 0.35, 0.72, 1.0],
    );
  }

  static PaletteSwatch lerp(PaletteSwatch a, PaletteSwatch b, double t) {
    final clamped = t.clamp(0.0, 1.0);
    final style = clamped < 0.5 ? a.style : b.style;
    return PaletteSwatch(
      start: Color.lerp(a.start, b.start, clamped)!,
      stop: Color.lerp(a.stop, b.stop, clamped)!,
      begin: Alignment.lerp(a.begin, b.begin, clamped)!,
      end: Alignment.lerp(a.end, b.end, clamped)!,
      swirlSeed: (a.swirlSeed + (b.swirlSeed - a.swirlSeed) * clamped).round(),
      style: style,
      animated: clamped < 0.5 ? a.animated : b.animated,
      intensity: a.intensity + (b.intensity - a.intensity) * clamped,
      motionSpeed:
          a.motionSpeed + (b.motionSpeed - a.motionSpeed) * clamped,
    );
  }
}

class _ShaderSwatchDecoration extends Decoration {
  const _ShaderSwatchDecoration({required this.swatch, this.border});

  final PaletteSwatch swatch;
  final BoxBorder? border;

  @override
  bool operator ==(Object other) {
    return other is _ShaderSwatchDecoration &&
        other.swatch == swatch &&
        other.border == border;
  }

  @override
  int get hashCode => Object.hash(swatch, border);

  @override
  bool hitTest(Size size, Offset position, {TextDirection? textDirection}) =>
      true;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) {
    return _ShaderSwatchPainter(this, onChanged);
  }
}

class _ShaderSwatchPainter extends BoxPainter {
  _ShaderSwatchPainter(this.decoration, VoidCallback? onChanged)
      : super(onChanged) {
    if (decoration.swatch.animated) {
      OrganicSwatchMotion.retain();
      OrganicSwatchMotion.listenable.addListener(_onMotion);
    }
  }

  final _ShaderSwatchDecoration decoration;

  void _onMotion() => onChanged?.call();

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.isEmpty) return;

    final rect = offset & size;
    drawSwatchRect(canvas, rect, decoration.swatch);

    decoration.border?.paint(
      canvas,
      rect,
      shape: BoxShape.rectangle,
      textDirection: configuration.textDirection ?? TextDirection.ltr,
    );
  }

  @override
  void dispose() {
    if (decoration.swatch.animated) {
      OrganicSwatchMotion.listenable.removeListener(_onMotion);
      OrganicSwatchMotion.release();
    }
    super.dispose();
  }
}

void drawSwatchRect(Canvas canvas, Rect rect, PaletteSwatch swatch) {
  if (swatch.isCelShade) {
    CelShadeSwatch.paint(canvas, rect, swatch);
    return;
  }
  if (swatch.isNeon) {
    ComicSwatch.paint(canvas, rect, swatch);
    return;
  }
  if (swatch.isMarble) {
    MarbleSwatch.paint(canvas, rect, swatch);
    return;
  }

  if (!swatch.usesShader) {
    canvas.drawRect(rect, Paint()..color = swatch.start);
    return;
  }

  final shader = swatch.shaderForRect(rect);
  if (shader != null) {
    canvas.drawRect(rect, Paint()..shader = shader);
  } else {
    canvas.drawRect(rect, Paint()..color = swatch.start);
  }
}

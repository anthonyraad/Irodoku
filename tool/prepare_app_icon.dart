import 'dart:io';

import 'package:image/image.dart';

/// Nearest-neighbor upscale + pad for a crisp launcher icon master.
void main() {
  final sourceFile = File('assets/icon/app_icon.png');
  final source = decodeImage(sourceFile.readAsBytesSync());
  if (source == null) {
    stderr.writeln('Failed to decode assets/icon/app_icon.png');
    exit(1);
  }

  // Trim near-white margins so the glyph fills the icon better.
  final trimmed = trim(
    source,
    mode: TrimMode.transparent,
    // Also trim near-white edges from the export background.
  );

  var glyph = trimmed;
  // If trim didn't help much (opaque white bg), crop by content bounding box.
  glyph = _cropToContent(glyph);

  const size = 1024;
  const paddingRatio = 0.18;
  const contentScale = 1.3; // 30% larger glyph vs. default padding fit
  final maxGlyph = (size * (1 - paddingRatio * 2) * contentScale)
      .round()
      .clamp(1, size);
  final maxDim = glyph.width > glyph.height ? glyph.width : glyph.height;
  final scale = (maxGlyph / maxDim).clamp(1.0, 128.0);
  final scaled = copyResize(
    glyph,
    width: (glyph.width * scale).round(),
    height: (glyph.height * scale).round(),
    interpolation: Interpolation.nearest,
  );

  final canvas = Image(width: size, height: size);
  fill(canvas, color: ColorRgba8(255, 255, 255, 255));
  final ox = ((size - scaled.width) / 2).round();
  final oy = ((size - scaled.height) / 2).round();
  compositeImage(canvas, scaled, dstX: ox, dstY: oy);

  File('assets/icon/app_icon.png').writeAsBytesSync(encodePng(canvas));
  stdout.writeln(
    'Prepared ${size}x$size icon (scale ${scale.toStringAsFixed(2)}x, glyph ${scaled.width}x${scaled.height}, contentScale $contentScale)',
  );
}

Image _cropToContent(Image src) {
  var minX = src.width;
  var minY = src.height;
  var maxX = 0;
  var maxY = 0;

  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final p = src.getPixel(x, y);
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();
      final a = p.a.toInt();
      final isBackground = a < 16 || (r > 245 && g > 245 && b > 245);
      if (!isBackground) {
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
  }

  if (maxX < minX || maxY < minY) return src;
  return copyCrop(
    src,
    x: minX,
    y: minY,
    width: maxX - minX + 1,
    height: maxY - minY + 1,
  );
}

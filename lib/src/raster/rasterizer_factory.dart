/// Picks a [Rasterizer] for a given source: pure-Dart [ImageRasterizer] for
/// raster sources, pure-Dart [SvgRasterizer] for SVG. Both are always available,
/// so the only null case is a genuinely unsupported extension.
library;

import 'package:path/path.dart' as p;

import 'image_rasterizer.dart';
import 'rasterizer.dart';
import 'svg_rasterizer.dart';

class RasterizerFactory {
  RasterizerFactory();

  static const _image = ImageRasterizer();
  static const _svg = SvgRasterizer();

  /// Returns a backend that can rasterise [sourcePath], or null.
  Rasterizer? forSource(String sourcePath) {
    final ext = p.extension(sourcePath).toLowerCase();
    if (_image.supports(ext)) return _image;
    if (_svg.supports(ext)) return _svg;
    return null;
  }

  /// Human-readable note about the SVG backend (for `doctor`/logs).
  String get svgBackendStatus => 'SVG via ${_svg.name}';
}

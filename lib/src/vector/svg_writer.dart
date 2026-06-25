/// Serialises an [SvgDocument] back to SVG, and composes a flattened
/// foreground-over-background SVG. Used to feed the process rasteriser a single
/// square SVG for the legacy mipmaps + Play Store icon (which are raster).
library;

import '../config/config.dart';
import '../geometry/adaptive_geometry.dart';
import '../graphic/svg_document.dart';

class SvgWriter {
  /// Composes a [size]×[size] SVG: a solid [backgroundHex] behind the
  /// foreground, with the foreground fit (with a small margin) into the canvas.
  static String compose(
    SvgDocument foreground, {
    required String backgroundHex,
    double size = 108,
    double fillFraction = 0.85,
  }) {
    final inset = (1 - fillFraction) / 2 * 100;
    final fit = AdaptiveGeometry.fit(
      foreground.artBounds(),
      SafeZone.inset(inset),
      foreground.viewportWidth > foreground.viewportHeight
          ? foreground.viewportWidth
          : foreground.viewportHeight,
    );
    // AdaptiveGeometry targets a 108 canvas; rescale to `size`.
    final k = size / AdaptiveGeometry.canvas;
    final scale = fit.scale * k;
    final tx = fit.translateX * k;
    final ty = fit.translateY * k;

    final body = StringBuffer();
    _writeNodes(body, foreground.children);

    return '<svg xmlns="http://www.w3.org/2000/svg" '
        'viewBox="0 0 ${_n(size)} ${_n(size)}" '
        'width="${_n(size)}" height="${_n(size)}">'
        '<rect x="0" y="0" width="${_n(size)}" height="${_n(size)}" '
        'fill="$backgroundHex"/>'
        '<g transform="translate(${_n(tx)} ${_n(ty)}) scale(${_n(scale)})">'
        '$body</g></svg>';
  }

  static void _writeNodes(StringBuffer b, List<SvgNode> nodes) {
    for (final n in nodes) {
      switch (n) {
        case SvgGroup g:
          final t = (g.rawTransform != null && g.rawTransform!.isNotEmpty)
              ? ' transform="${g.rawTransform}"'
              : '';
          b.write('<g$t>');
          _writeNodes(b, g.children);
          b.write('</g>');
        case SvgPath p:
          b.write('<path d="${p.pathData}"');
          if (p.fill.isNone) {
            b.write(' fill="none"');
          } else {
            b.write(' fill="${p.fill.rgbHex}"');
            if (p.fillAlpha < 0.999) {
              b.write(' fill-opacity="${_n(p.fillAlpha)}"');
            }
          }
          if (!p.stroke.isNone && p.strokeWidth > 0) {
            b.write(
                ' stroke="${p.stroke.rgbHex}" stroke-width="${_n(p.strokeWidth)}"');
            if (p.strokeAlpha < 0.999) {
              b.write(' stroke-opacity="${_n(p.strokeAlpha)}"');
            }
          }
          b.write('/>');
      }
    }
  }

  static String _n(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v
        .toStringAsFixed(4)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }
}

/// Pure-Dart SVG → PNG rasteriser.
///
/// Renders the subset of SVG that [SvgDocument] models: groups, transforms,
/// `<path>` and the basic shapes (all normalised to path data), solid fills and
/// strokes, with no Flutter engine and no system tools. This is what lets a
/// single SVG drive *every* output: the adaptive layers go out as vector
/// (VectorDrawable), while the legacy mipmaps and the 512² store icon are
/// rasterised here.
///
/// How it works: every path is flattened to device-space polylines (cubics,
/// quadratics and arcs subdivided to a sub-pixel tolerance), then scan-filled
/// with non-zero winding into a 4× supersampled buffer. The buffer is
/// box-averaged down with premultiplied alpha, which is what produces clean
/// anti-aliased edges. Strokes are expanded to segment quads plus round
/// joins/caps and filled the same way. Gradient fills are evaluated per pixel
/// and clip paths mask the fill to their region; filters/masks aren't modelled
/// (the parser drops those with a warning).
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../graphic/bounds.dart';
import '../graphic/matrix2d.dart';
import '../graphic/path_data.dart';
import '../graphic/svg_document.dart';
import 'rasterizer.dart';

class SvgRasterizer implements Rasterizer {
  const SvgRasterizer({this.supersample = 4});

  /// Linear supersampling factor; final coverage uses `supersample²` samples.
  final int supersample;

  @override
  String get name => 'svg (pure Dart)';

  @override
  bool get available => true;

  @override
  bool supports(String extension) => extension.toLowerCase() == '.svg';

  @override
  bool renderToPng({
    required String sourcePath,
    required int sizePx,
    required String outPath,
  }) =>
      render(svgPath: sourcePath, sizePx: sizePx, outPath: outPath);

  /// Renders [svgPath] into a [sizePx]² PNG at [outPath]. When [backgroundArgb]
  /// is non-null the canvas is pre-filled opaque with it (the legacy "card");
  /// otherwise it stays transparent.
  ///
  /// [fitFraction] controls framing: `null` maps the whole viewBox onto the
  /// canvas (use for finished, full-bleed icons); a value like `0.95` instead
  /// scales the *art's bounding box* to that fraction of the canvas, centred,
  /// so a logo with generous internal margins fills the icon properly (more
  /// pixels per feature = crisp, not a small soft logo lost in padding).
  ///
  /// [fitArtBounds] chooses what [fitFraction] scales: `true` (the `auto` fit)
  /// measures the real art and trims the source's padding; `false` (the `as_is`
  /// fit) scales the whole viewBox to that fraction, keeping authored padding.
  ///
  /// Returns false if the file is missing or can't be parsed.
  bool render({
    required String svgPath,
    required int sizePx,
    required String outPath,
    int? backgroundArgb,
    double? fitFraction,
    bool fitArtBounds = true,
  }) {
    final file = File(svgPath);
    if (!file.existsSync()) return false;
    final SvgDocument doc;
    try {
      doc = SvgDocument.parse(file.readAsStringSync());
    } on Exception {
      return false;
    }
    final image = rasterize(doc, sizePx,
        backgroundArgb: backgroundArgb,
        fitFraction: fitFraction,
        fitArtBounds: fitArtBounds);
    File(outPath)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(img.encodePng(image));
    return true;
  }

  /// Rasterises [doc] to a [sizePx]² image. Exposed for testing.
  img.Image rasterize(SvgDocument doc, int sizePx,
      {int? backgroundArgb, double? fitFraction, bool fitArtBounds = true}) {
    final ss = supersample;
    final hi = sizePx * ss;
    final buf = Uint8List(hi * hi * 4);
    if (backgroundArgb != null) {
      final r = (backgroundArgb >> 16) & 0xFF;
      final g = (backgroundArgb >> 8) & 0xFF;
      final b = backgroundArgb & 0xFF;
      for (var i = 0; i < buf.length; i += 4) {
        buf[i] = r;
        buf[i + 1] = g;
        buf[i + 2] = b;
        buf[i + 3] = 255;
      }
    }

    final base = _baseTransform(doc, hi, fitFraction, fitArtBounds);
    final raster = _Raster(buf, hi);
    _paint(doc.children, base, raster, null);
    return _downsample(buf, hi, sizePx, ss);
  }

  /// The local→device transform for an [hi]² (supersampled) canvas. Fits the
  /// art bounding box (or, when [fitArtBounds] is false, the whole viewBox) to
  /// [fitFraction] of the canvas when given; otherwise maps the viewBox
  /// uniformly to fill it. All centre the result.
  static Matrix2D _baseTransform(
      SvgDocument doc, int hi, double? fitFraction, bool fitArtBounds) {
    if (fitFraction != null) {
      final Bounds? box = fitArtBounds ? doc.artBounds() : doc.viewBox;
      if (box != null && box.longestSide > 0) {
        final s = hi * fitFraction / box.longestSide;
        return Matrix2D(
            s, 0, 0, s, hi / 2 - s * box.centerX, hi / 2 - s * box.centerY);
      }
    }
    final vw = doc.viewportWidth <= 0 ? 1.0 : doc.viewportWidth;
    final vh = doc.viewportHeight <= 0 ? 1.0 : doc.viewportHeight;
    final s = hi / (vw > vh ? vw : vh);
    // Fold the viewBox origin into the translate so offset art still centres.
    return Matrix2D(s, 0, 0, s, (hi - vw * s) / 2 - s * doc.viewBoxMinX,
        (hi - vh * s) / 2 - s * doc.viewBoxMinY);
  }

  void _paint(
      List<SvgNode> nodes, Matrix2D m, _Raster raster, Uint8List? clip) {
    for (final node in nodes) {
      switch (node) {
        case SvgGroup g:
          final cm = m.multiply(g.transform);
          var childClip = clip;
          if (g.clipPathData != null) {
            childClip = _intersect(
                clip, raster.mask(_Flattener(cm).flatten(g.clipPathData!)));
          }
          _paint(g.children, cm, raster, childClip);
        case SvgPath p:
          var pathClip = clip;
          if (p.clipPathData != null) {
            pathClip = _intersect(
                clip, raster.mask(_Flattener(m).flatten(p.clipPathData!)));
          }
          final subpaths = _Flattener(m).flatten(p.pathData);
          if (subpaths.isEmpty) continue;
          final grad = p.fillGradient;
          if (grad != null && grad.stops.isNotEmpty && p.fillAlpha > 0) {
            final bounds = p.explicitBounds ?? PathData.bounds(p.pathData);
            raster.fillGradient(
                subpaths, _DeviceGradient(grad, m, bounds), p.fillAlpha,
                clip: pathClip);
          } else if (!p.fill.isNone && p.fillAlpha > 0) {
            raster.fill(subpaths, p.fill.argb, p.fillAlpha,
                closeAll: true, clip: pathClip);
          }
          if (!p.stroke.isNone && p.strokeAlpha > 0 && p.strokeWidth > 0) {
            final wDev = p.strokeWidth * _avgScale(m);
            final outline = _strokeOutline(subpaths, wDev);
            if (outline.isNotEmpty) {
              raster.fill(outline, p.stroke.argb, p.strokeAlpha,
                  closeAll: true, clip: pathClip);
            }
          }
      }
    }
  }

  /// Intersects clip coverage masks (both 0/255). Mutates and returns [b].
  static Uint8List _intersect(Uint8List? a, Uint8List b) {
    if (a == null) return b;
    for (var i = 0; i < b.length; i++) {
      if (a[i] == 0) b[i] = 0;
    }
    return b;
  }

  static double _avgScale(Matrix2D m) =>
      math.sqrt((m.a * m.d - m.b * m.c).abs());

  /// Premultiplied box-average from the [hi]² buffer down to [size]².
  static img.Image _downsample(Uint8List buf, int hi, int size, int ss) {
    final out = Uint8List(size * size * 4);
    final n = ss * ss;
    for (var oy = 0; oy < size; oy++) {
      for (var ox = 0; ox < size; ox++) {
        var pr = 0.0, pg = 0.0, pb = 0.0, pa = 0.0;
        final baseY = oy * ss, baseX = ox * ss;
        for (var sy = 0; sy < ss; sy++) {
          var idx = ((baseY + sy) * hi + baseX) * 4;
          for (var sx = 0; sx < ss; sx++) {
            final a = buf[idx + 3] / 255.0;
            pr += buf[idx] * a;
            pg += buf[idx + 1] * a;
            pb += buf[idx + 2] * a;
            pa += a;
            idx += 4;
          }
        }
        final o = (oy * size + ox) * 4;
        if (pa > 0) {
          out[o] = (pr / pa).round().clamp(0, 255);
          out[o + 1] = (pg / pa).round().clamp(0, 255);
          out[o + 2] = (pb / pa).round().clamp(0, 255);
          out[o + 3] = (pa / n * 255).round().clamp(0, 255);
        }
      }
    }
    return img.Image.fromBytes(
      width: size,
      height: size,
      bytes: out.buffer,
      numChannels: 4,
    );
  }

  /// Expands [subpaths] (device-space polylines) into filled stroke geometry:
  /// one quad per segment plus a round join/cap polygon at every vertex. All
  /// polygons are oriented consistently so a single non-zero-winding fill paints
  /// their union (overlaps are filled once, never double-blended).
  static List<_Poly> _strokeOutline(List<_Poly> subpaths, double width) {
    final half = width / 2;
    if (half <= 0) return const [];
    final out = <_Poly>[];
    for (final sp in subpaths) {
      final xs = sp.xs, ys = sp.ys;
      final count = xs.length;
      if (count == 0) continue;
      if (count == 1) {
        out.add(_circle(xs[0], ys[0], half));
        continue;
      }
      final lastSeg = sp.closed && count > 2 ? count : count - 1;
      for (var i = 0; i < lastSeg; i++) {
        final a = i, b = (i + 1) % count;
        final dx = xs[b] - xs[a], dy = ys[b] - ys[a];
        final len = math.sqrt(dx * dx + dy * dy);
        if (len < 1e-6) continue;
        final nx = -dy / len * half, ny = dx / len * half;
        out.add(_oriented(_Poly(
          [xs[a] + nx, xs[b] + nx, xs[b] - nx, xs[a] - nx],
          [ys[a] + ny, ys[b] + ny, ys[b] - ny, ys[a] - ny],
        )));
      }
      // Round joins + caps: a disc at every vertex covers gaps and ends.
      for (var i = 0; i < count; i++) {
        out.add(_circle(xs[i], ys[i], half));
      }
    }
    return out;
  }

  static _Poly _circle(double cx, double cy, double r) {
    const seg = 24;
    final xs = <double>[], ys = <double>[];
    for (var i = 0; i < seg; i++) {
      final a = i / seg * 2 * math.pi;
      xs.add(cx + r * math.cos(a));
      ys.add(cy + r * math.sin(a));
    }
    return _Poly(xs, ys);
  }

  /// Forces a polygon to positive signed area, so every stroke polygon shares
  /// the same winding direction.
  static _Poly _oriented(_Poly p) {
    var area = 0.0;
    final xs = p.xs, ys = p.ys;
    for (var i = 0; i < xs.length; i++) {
      final j = (i + 1) % xs.length;
      area += xs[i] * ys[j] - xs[j] * ys[i];
    }
    if (area < 0) {
      return _Poly(xs.reversed.toList(), ys.reversed.toList());
    }
    return p;
  }
}

/// A device-space polyline (one subpath). [closed] matters only for stroking;
/// filling always treats subpaths as implicitly closed.
class _Poly {
  _Poly(this.xs, this.ys);
  final List<double> xs;
  final List<double> ys;
  bool closed = false;
}

/// Scan-fills polygons into a flat RGBA buffer with non-zero winding and
/// straight-alpha over-compositing.
class _Raster {
  _Raster(this.buf, this.size);
  final Uint8List buf;
  final int size;

  /// Walks the non-zero-winding fill of [polys], calling [span] with each run of
  /// covered pixels `(y, xStart, xEnd)` (both inclusive). The shared core of
  /// solid fill, gradient fill and clip-mask building.
  void _scan(List<_Poly> polys, bool closeAll,
      void Function(int y, int xa, int xb) span) {
    final ex0 = <double>[],
        ey0 = <double>[],
        ex1 = <double>[],
        ey1 = <double>[];
    var yMin = double.infinity, yMax = double.negativeInfinity;
    for (final p in polys) {
      final xs = p.xs, ys = p.ys;
      final n = xs.length;
      if (n < 2) continue;
      for (var i = 0; i < n; i++) {
        final j = i + 1;
        if (j == n && !closeAll) break;
        final k = j % n;
        final x0 = xs[i], y0 = ys[i], x1 = xs[k], y1 = ys[k];
        if (y0 == y1) continue; // horizontal edges contribute nothing
        ex0.add(x0);
        ey0.add(y0);
        ex1.add(x1);
        ey1.add(y1);
        if (y0 < yMin) yMin = y0;
        if (y1 < yMin) yMin = y1;
        if (y0 > yMax) yMax = y0;
        if (y1 > yMax) yMax = y1;
      }
    }
    if (ex0.isEmpty) return;

    final rowStart = math.max(0, yMin.floor());
    final rowEnd = math.min(size - 1, yMax.ceil());
    final xsCross = <double>[];
    final dirCross = <int>[];
    for (var y = rowStart; y <= rowEnd; y++) {
      final yc = y + 0.5;
      xsCross.clear();
      dirCross.clear();
      for (var e = 0; e < ex0.length; e++) {
        final y0 = ey0[e], y1 = ey1[e];
        if ((y0 <= yc && y1 > yc) || (y1 <= yc && y0 > yc)) {
          final t = (yc - y0) / (y1 - y0);
          xsCross.add(ex0[e] + t * (ex1[e] - ex0[e]));
          dirCross.add(y0 < y1 ? 1 : -1);
        }
      }
      if (xsCross.length < 2) continue;
      // Sort crossings by x, carrying their winding direction.
      final order = List<int>.generate(xsCross.length, (i) => i)
        ..sort((a, b) => xsCross[a].compareTo(xsCross[b]));
      var wind = 0;
      for (var oi = 0; oi + 1 < order.length; oi++) {
        wind += dirCross[order[oi]];
        if (wind == 0) continue;
        final xa = xsCross[order[oi]];
        final xb = xsCross[order[oi + 1]];
        // Cover pixels whose centre lies in [xa, xb).
        final start = math.max(0, (xa - 0.5).ceil());
        final end = math.min(size - 1, (xb - 0.5).floor());
        if (end >= start) span(y, start, end);
      }
    }
  }

  void fill(List<_Poly> polys, int argb, double alpha,
      {required bool closeAll, Uint8List? clip}) {
    final sr = (argb >> 16) & 0xFF;
    final sg = (argb >> 8) & 0xFF;
    final sb = argb & 0xFF;
    _scan(polys, closeAll, (y, xa, xb) {
      var idx = (y * size + xa) * 4;
      var mi = y * size + xa;
      for (var x = xa; x <= xb; x++) {
        var a = alpha;
        if (clip != null) a *= clip[mi] / 255.0;
        if (a > 0) _over(idx, sr, sg, sb, a);
        idx += 4;
        mi++;
      }
    });
  }

  void fillGradient(List<_Poly> polys, _DeviceGradient g, double alpha,
      {Uint8List? clip}) {
    _scan(polys, true, (y, xa, xb) {
      var mi = y * size + xa;
      for (var x = xa; x <= xb; x++) {
        final c = g.colorAt(x + 0.5, y + 0.5);
        var a = ((c >> 24) & 0xFF) / 255.0 * alpha;
        if (clip != null) a *= clip[mi] / 255.0;
        if (a > 0) {
          _over(mi * 4, (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF, a);
        }
        mi++;
      }
    });
  }

  /// Builds a 0/255 coverage mask for [polys] (a clip region).
  Uint8List mask(List<_Poly> polys) {
    final m = Uint8List(size * size);
    _scan(polys, true, (y, xa, xb) {
      for (var x = xa; x <= xb; x++) {
        m[y * size + x] = 255;
      }
    });
    return m;
  }

  void _over(int idx, int sr, int sg, int sb, double sa) {
    if (sa >= 1.0 && buf[idx + 3] == 255) {
      buf[idx] = sr;
      buf[idx + 1] = sg;
      buf[idx + 2] = sb;
      return;
    }
    final da = buf[idx + 3] / 255.0;
    final oa = sa + da * (1 - sa);
    if (oa <= 0) return;
    buf[idx] =
        ((sr * sa + buf[idx] * da * (1 - sa)) / oa).round().clamp(0, 255);
    buf[idx + 1] =
        ((sg * sa + buf[idx + 1] * da * (1 - sa)) / oa).round().clamp(0, 255);
    buf[idx + 2] =
        ((sb * sa + buf[idx + 2] * da * (1 - sa)) / oa).round().clamp(0, 255);
    buf[idx + 3] = (oa * 255).round().clamp(0, 255);
  }
}

/// Flattens an SVG path `d` string into device-space polylines, applying the
/// supplied local→device [matrix]. Cubics/quadratics use recursive de Casteljau
/// to a sub-pixel tolerance; arcs are converted to centre form and sampled.
class _Flattener {
  _Flattener(this.matrix) {
    _tol = 0.3 / math.max(1e-6, SvgRasterizer._avgScale(matrix));
  }

  final Matrix2D matrix;
  late final double _tol;

  final List<_Poly> _subs = [];
  _Poly? _cur;
  double _cx = 0, _cy = 0, _sx = 0, _sy = 0;
  double _lastCx = 0, _lastCy = 0; // reflected control point (C/S)
  double _lastQx = 0, _lastQy = 0; // reflected control point (Q/T)
  String _prev = '';

  List<_Poly> flatten(String d) {
    final s = _Scan(d);
    var cmd = '';
    while (!s.atEnd) {
      if (s.commandAhead) cmd = s.command();
      final rel = cmd == cmd.toLowerCase();
      switch (cmd.toUpperCase()) {
        case 'M':
          var x = s.number(), y = s.number();
          if (rel) {
            x += _cx;
            y += _cy;
          }
          _moveTo(x, y);
          cmd = rel ? 'l' : 'L';
        case 'L':
          var x = s.number(), y = s.number();
          if (rel) {
            x += _cx;
            y += _cy;
          }
          _lineTo(x, y);
        case 'H':
          var x = s.number();
          if (rel) x += _cx;
          _lineTo(x, _cy);
        case 'V':
          var y = s.number();
          if (rel) y += _cy;
          _lineTo(_cx, y);
        case 'C':
          var x1 = s.number(), y1 = s.number();
          var x2 = s.number(), y2 = s.number();
          var x = s.number(), y = s.number();
          if (rel) {
            x1 += _cx;
            y1 += _cy;
            x2 += _cx;
            y2 += _cy;
            x += _cx;
            y += _cy;
          }
          _cubic(x1, y1, x2, y2, x, y);
        case 'S':
          var x2 = s.number(), y2 = s.number();
          var x = s.number(), y = s.number();
          if (rel) {
            x2 += _cx;
            y2 += _cy;
            x += _cx;
            y += _cy;
          }
          final reflect = 'CS'.contains(_prev.toUpperCase());
          final x1 = reflect ? 2 * _cx - _lastCx : _cx;
          final y1 = reflect ? 2 * _cy - _lastCy : _cy;
          _cubic(x1, y1, x2, y2, x, y);
        case 'Q':
          var x1 = s.number(), y1 = s.number();
          var x = s.number(), y = s.number();
          if (rel) {
            x1 += _cx;
            y1 += _cy;
            x += _cx;
            y += _cy;
          }
          _quad(x1, y1, x, y);
        case 'T':
          var x = s.number(), y = s.number();
          if (rel) {
            x += _cx;
            y += _cy;
          }
          final reflect = 'QT'.contains(_prev.toUpperCase());
          final x1 = reflect ? 2 * _cx - _lastQx : _cx;
          final y1 = reflect ? 2 * _cy - _lastQy : _cy;
          _quad(x1, y1, x, y);
        case 'A':
          final rx = s.number(), ry = s.number();
          final rot = s.number();
          final large = s.number() != 0;
          final sweep = s.number() != 0;
          var x = s.number(), y = s.number();
          if (rel) {
            x += _cx;
            y += _cy;
          }
          _arc(rx, ry, rot, large, sweep, x, y);
        case 'Z':
          _close();
        default:
          return _finish();
      }
      _prev = cmd;
    }
    return _finish();
  }

  void _moveTo(double x, double y) {
    _cur = _Poly([], [])..closed = false;
    _subs.add(_cur!);
    _push(x, y);
    _cx = x;
    _cy = y;
    _sx = x;
    _sy = y;
  }

  void _lineTo(double x, double y) {
    if (_cur == null) {
      _cur = _Poly([], []);
      _subs.add(_cur!);
    }
    if (_cur!.xs.isEmpty) _push(_cx, _cy);
    _push(x, y);
    _cx = x;
    _cy = y;
  }

  void _close() {
    if (_cur != null) {
      _cur!.closed = true;
      _cx = _sx;
      _cy = _sy;
    }
  }

  void _push(double x, double y) {
    final d = matrix.apply(x, y);
    _cur!.xs.add(d.x);
    _cur!.ys.add(d.y);
  }

  void _cubic(double x1, double y1, double x2, double y2, double x, double y) {
    if (_cur == null || _cur!.xs.isEmpty) _push(_cx, _cy);
    _subdivCubic(_cx, _cy, x1, y1, x2, y2, x, y, 0);
    _lastCx = x2;
    _lastCy = y2;
    _cx = x;
    _cy = y;
  }

  void _subdivCubic(double x0, double y0, double x1, double y1, double x2,
      double y2, double x3, double y3, int depth) {
    if (depth >= 18 || _flatCubic(x0, y0, x1, y1, x2, y2, x3, y3)) {
      _push(x3, y3);
      return;
    }
    final x01 = (x0 + x1) / 2, y01 = (y0 + y1) / 2;
    final x12 = (x1 + x2) / 2, y12 = (y1 + y2) / 2;
    final x23 = (x2 + x3) / 2, y23 = (y2 + y3) / 2;
    final xa = (x01 + x12) / 2, ya = (y01 + y12) / 2;
    final xb = (x12 + x23) / 2, yb = (y12 + y23) / 2;
    final xm = (xa + xb) / 2, ym = (ya + yb) / 2;
    _subdivCubic(x0, y0, x01, y01, xa, ya, xm, ym, depth + 1);
    _subdivCubic(xm, ym, xb, yb, x23, y23, x3, y3, depth + 1);
  }

  bool _flatCubic(double x0, double y0, double x1, double y1, double x2,
      double y2, double x3, double y3) {
    final d1 = _distToLine(x1, y1, x0, y0, x3, y3);
    final d2 = _distToLine(x2, y2, x0, y0, x3, y3);
    return math.max(d1, d2) <= _tol;
  }

  void _quad(double x1, double y1, double x, double y) {
    if (_cur == null || _cur!.xs.isEmpty) _push(_cx, _cy);
    _subdivQuad(_cx, _cy, x1, y1, x, y, 0);
    _lastQx = x1;
    _lastQy = y1;
    _cx = x;
    _cy = y;
  }

  void _subdivQuad(double x0, double y0, double x1, double y1, double x2,
      double y2, int depth) {
    if (depth >= 18 || _distToLine(x1, y1, x0, y0, x2, y2) <= _tol) {
      _push(x2, y2);
      return;
    }
    final x01 = (x0 + x1) / 2, y01 = (y0 + y1) / 2;
    final x12 = (x1 + x2) / 2, y12 = (y1 + y2) / 2;
    final xm = (x01 + x12) / 2, ym = (y01 + y12) / 2;
    _subdivQuad(x0, y0, x01, y01, xm, ym, depth + 1);
    _subdivQuad(xm, ym, x12, y12, x2, y2, depth + 1);
  }

  void _arc(double rx, double ry, double rotDeg, bool large, bool sweep,
      double x, double y) {
    if (_cur == null || _cur!.xs.isEmpty) _push(_cx, _cy);
    final x0 = _cx, y0 = _cy;
    if (rx == 0 || ry == 0 || (x0 == x && y0 == y)) {
      _lineTo(x, y);
      return;
    }
    rx = rx.abs();
    ry = ry.abs();
    final phi = rotDeg * math.pi / 180;
    final cosP = math.cos(phi), sinP = math.sin(phi);
    final dx = (x0 - x) / 2, dy = (y0 - y) / 2;
    final x1p = cosP * dx + sinP * dy;
    final y1p = -sinP * dx + cosP * dy;
    var rxs = rx * rx, rys = ry * ry;
    final x1ps = x1p * x1p, y1ps = y1p * y1p;
    final lambda = x1ps / rxs + y1ps / rys;
    if (lambda > 1) {
      final s = math.sqrt(lambda);
      rx *= s;
      ry *= s;
      rxs = rx * rx;
      rys = ry * ry;
    }
    final sign = large != sweep ? 1.0 : -1.0;
    var num = rxs * rys - rxs * y1ps - rys * x1ps;
    if (num < 0) num = 0;
    final denom = rxs * y1ps + rys * x1ps;
    final co = denom == 0 ? 0.0 : sign * math.sqrt(num / denom);
    final cxp = co * rx * y1p / ry;
    final cyp = -co * ry * x1p / rx;
    final cxc = cosP * cxp - sinP * cyp + (x0 + x) / 2;
    final cyc = sinP * cxp + cosP * cyp + (y0 + y) / 2;

    double angle(double ux, double uy, double vx, double vy) {
      final dot = ux * vx + uy * vy;
      final len = math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy));
      var a = math.acos(len == 0 ? 1.0 : (dot / len).clamp(-1.0, 1.0));
      if (ux * vy - uy * vx < 0) a = -a;
      return a;
    }

    final ux = (x1p - cxp) / rx, uy = (y1p - cyp) / ry;
    final vx = (-x1p - cxp) / rx, vy = (-y1p - cyp) / ry;
    final theta1 = angle(1, 0, ux, uy);
    var dTheta = angle(ux, uy, vx, vy);
    if (!sweep && dTheta > 0) dTheta -= 2 * math.pi;
    if (sweep && dTheta < 0) dTheta += 2 * math.pi;

    final rMax = math.max(rx, ry);
    final step = 2 * math.acos(math.max(0.0, 1 - _tol / rMax));
    final n = math.max(2, (dTheta.abs() / math.max(1e-3, step)).ceil());
    for (var i = 1; i <= n; i++) {
      final t = theta1 + dTheta * i / n;
      final cosT = math.cos(t), sinT = math.sin(t);
      final ex = cosP * rx * cosT - sinP * ry * sinT + cxc;
      final ey = sinP * rx * cosT + cosP * ry * sinT + cyc;
      _push(ex, ey);
    }
    _cx = x;
    _cy = y;
  }

  List<_Poly> _finish() => _subs.where((p) => p.xs.length >= 2).toList();

  static double _distToLine(
      double px, double py, double ax, double ay, double bx, double by) {
    final dx = bx - ax, dy = by - ay;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-9) {
      final ddx = px - ax, ddy = py - ay;
      return math.sqrt(ddx * ddx + ddy * ddy);
    }
    return ((px - ax) * dy - (py - ay) * dx).abs() / len;
  }
}

/// A forgiving SVG path-data / number scanner.
class _Scan {
  _Scan(this.s);
  final String s;
  int i = 0;

  void _skip() {
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c == 0x20 || c == 0x2C || c == 0x09 || c == 0x0A || c == 0x0D) {
        i++;
      } else {
        break;
      }
    }
  }

  bool get atEnd {
    _skip();
    return i >= s.length;
  }

  bool get commandAhead {
    _skip();
    if (i >= s.length) return false;
    final c = s.codeUnitAt(i);
    return (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
  }

  String command() {
    _skip();
    return s[i++];
  }

  double number() {
    _skip();
    final start = i;
    if (i < s.length && (s[i] == '+' || s[i] == '-')) i++;
    while (i < s.length && _digit(s.codeUnitAt(i))) {
      i++;
    }
    if (i < s.length && s[i] == '.') {
      i++;
      while (i < s.length && _digit(s.codeUnitAt(i))) {
        i++;
      }
    }
    if (i < s.length && (s[i] == 'e' || s[i] == 'E')) {
      i++;
      if (i < s.length && (s[i] == '+' || s[i] == '-')) i++;
      while (i < s.length && _digit(s.codeUnitAt(i))) {
        i++;
      }
    }
    return start == i ? 0 : double.parse(s.substring(start, i));
  }

  static bool _digit(int u) => u >= 0x30 && u <= 0x39;
}

/// A gradient resolved to device space for per-pixel evaluation. Endpoints (or
/// centre + radius) are mapped through the `gradientTransform` then the
/// local→device matrix; stops are pre-sorted with their alpha baked in.
class _DeviceGradient {
  _DeviceGradient(SvgGradient g, Matrix2D device, Bounds? bounds)
      : linear = g.linear,
        tileMode = g.tileMode {
    final minX = bounds?.minX ?? 0.0, minY = bounds?.minY ?? 0.0;
    final w = bounds?.width ?? 1.0, h = bounds?.height ?? 1.0;
    double mx(double v) => g.userSpace ? v : minX + v * w;
    double my(double v) => g.userSpace ? v : minY + v * h;
    final full = device.multiply(g.transform); // gradientTransform, then device
    if (g.linear) {
      final p1 = full.apply(mx(g.x1), my(g.y1));
      final p2 = full.apply(mx(g.x2), my(g.y2));
      _p1x = p1.x;
      _p1y = p1.y;
      _p2x = p2.x;
      _p2y = p2.y;
    } else {
      final c = full.apply(mx(g.cx), my(g.cy));
      final rPre = g.userSpace ? g.r : g.r * (w + h) / 2;
      final edge = full.apply(mx(g.cx) + rPre, my(g.cy));
      _cx = c.x;
      _cy = c.y;
      _r = math
          .sqrt(math.pow(edge.x - c.x, 2) + math.pow(edge.y - c.y, 2))
          .toDouble();
    }
    final sorted = [...g.stops]..sort((a, b) => a.offset.compareTo(b.offset));
    _offs = [for (final s in sorted) s.offset];
    _cols = [for (final s in sorted) s.color.argb];
  }

  final bool linear;
  final String tileMode;
  double _p1x = 0, _p1y = 0, _p2x = 0, _p2y = 0;
  double _cx = 0, _cy = 0, _r = 0;
  late final List<double> _offs;
  late final List<int> _cols;

  /// The 0xAARRGGBB colour at device pixel centre ([x], [y]).
  int colorAt(double x, double y) {
    if (_offs.isEmpty) return 0;
    double t;
    if (linear) {
      final vx = _p2x - _p1x, vy = _p2y - _p1y;
      final len2 = vx * vx + vy * vy;
      t = len2 <= 0 ? 0 : ((x - _p1x) * vx + (y - _p1y) * vy) / len2;
    } else {
      final dx = x - _cx, dy = y - _cy;
      t = _r <= 0 ? 0 : math.sqrt(dx * dx + dy * dy) / _r;
    }
    return _lookup(_tile(t));
  }

  double _tile(double t) => switch (tileMode) {
        'repeated' => t - t.floor(),
        'mirror' => () {
            final m = t.abs() % 2.0;
            return m > 1.0 ? 2.0 - m : m;
          }(),
        _ => t.clamp(0.0, 1.0),
      };

  int _lookup(double t) {
    if (t <= _offs.first) return _cols.first;
    if (t >= _offs.last) return _cols.last;
    for (var i = 0; i + 1 < _offs.length; i++) {
      if (t <= _offs[i + 1]) {
        final span = _offs[i + 1] - _offs[i];
        final f = span <= 0 ? 0.0 : (t - _offs[i]) / span;
        return _lerp(_cols[i], _cols[i + 1], f);
      }
    }
    return _cols.last;
  }

  static int _lerp(int c0, int c1, double f) {
    int ch(int shift) {
      final a = (c0 >> shift) & 0xFF, b = (c1 >> shift) & 0xFF;
      return (a + (b - a) * f).round().clamp(0, 255);
    }

    return (ch(24) << 24) | (ch(16) << 16) | (ch(8) << 8) | ch(0);
  }
}

/// A minimal SVG model + parser, scoped to what icon/logo art actually uses.
///
/// Supported: `<svg>` (viewBox/width/height), `<g>` (transform, opacity),
/// `<path>`, and the basic shapes `<rect>` (incl. rounded), `<circle>`,
/// `<ellipse>`, `<line>`, `<polygon>`, `<polyline>` — each normalised to path
/// data. Fills/strokes resolve presentation attributes and inline `style`, with
/// SVG inheritance. Unsupported constructs (gradients, filters, masks, text,
/// images, `<use>`) are dropped, and the parser records [warnings] for them so
/// the caller can surface what was skipped.
library;

import 'package:xml/xml.dart';

import 'bounds.dart';
import 'matrix2d.dart';
import 'path_data.dart';
import 'svg_color.dart';

sealed class SvgNode {}

class SvgGroup extends SvgNode {
  SvgGroup(
      {required this.transform, this.rawTransform, required this.children});
  final Matrix2D transform;
  final String? rawTransform;
  final List<SvgNode> children;
}

class SvgPath extends SvgNode {
  SvgPath({
    required this.pathData,
    required this.fill,
    required this.fillAlpha,
    required this.stroke,
    required this.strokeAlpha,
    required this.strokeWidth,
    this.name,
    this.explicitBounds,
  });
  final String pathData;
  final SvgColor fill;
  final double fillAlpha;
  final SvgColor stroke;
  final double strokeAlpha;
  final double strokeWidth;
  final String? name;

  /// Exact local bounds for shapes we synthesise (rect/circle/ellipse/line/
  /// poly). `null` for raw `<path>` data, where bounds are derived from the
  /// path commands. Avoids the conservative arc over-estimate inflating the fit.
  final Bounds? explicitBounds;
}

class SvgDocument {
  SvgDocument({
    required this.viewportWidth,
    required this.viewportHeight,
    required this.children,
    this.warnings = const [],
  });

  final double viewportWidth;
  final double viewportHeight;
  final List<SvgNode> children;
  final List<String> warnings;

  /// Union of all path bounds in viewBox coordinate space (after applying each
  /// node's transforms). `null` if the document is empty.
  Bounds? artBounds() => _bounds(children, Matrix2D.identity);

  static Bounds? _bounds(List<SvgNode> nodes, Matrix2D acc) {
    Bounds? box;
    for (final n in nodes) {
      switch (n) {
        case SvgGroup g:
          box =
              Bounds.union(box, _bounds(g.children, acc.multiply(g.transform)));
        case SvgPath p:
          final local = p.explicitBounds ?? PathData.bounds(p.pathData);
          if (local != null) box = Bounds.union(box, local.transformed(acc));
      }
    }
    return box;
  }

  static SvgDocument parse(String svg) {
    final doc = XmlDocument.parse(svg);
    final root = doc.rootElement;
    final warnings = <String>[];

    double viewW, viewH;
    final viewBox = root.getAttribute('viewBox');
    if (viewBox != null) {
      final parts =
          viewBox.trim().split(RegExp(r'[\s,]+')).map(double.parse).toList();
      viewW = parts[2];
      viewH = parts[3];
    } else {
      viewW = _len(root.getAttribute('width')) ?? 24;
      viewH = _len(root.getAttribute('height')) ?? 24;
    }

    final ctx = _Paint.initial();
    final children = <SvgNode>[];
    for (final el in root.childElements) {
      final node = _parseElement(el, ctx, warnings);
      if (node != null) children.add(node);
    }

    return SvgDocument(
      viewportWidth: viewW,
      viewportHeight: viewH,
      children: children,
      warnings: warnings,
    );
  }

  static SvgNode? _parseElement(
      XmlElement el, _Paint inherited, List<String> warnings) {
    final ctx = inherited.inherit(el);
    final tag = el.name.local;
    switch (tag) {
      case 'g':
        final kids = <SvgNode>[];
        for (final c in el.childElements) {
          final node = _parseElement(c, ctx, warnings);
          if (node != null) kids.add(node);
        }
        if (kids.isEmpty) return null;
        final raw = el.getAttribute('transform');
        return SvgGroup(
          transform: Matrix2D.parse(raw),
          rawTransform: raw,
          children: kids,
        );
      case 'path':
        final d = el.getAttribute('d');
        if (d == null || d.trim().isEmpty) return null;
        return _shape(d, el, ctx);
      case 'rect':
        final s = _rectToPath(el);
        return _shape(s.d, el, ctx, bounds: s.bounds);
      case 'circle':
        final s = _circleToPath(el);
        return _shape(s.d, el, ctx, bounds: s.bounds);
      case 'ellipse':
        final s = _ellipseToPath(el);
        return _shape(s.d, el, ctx, bounds: s.bounds);
      case 'line':
        final s = _lineToPath(el);
        return _shape(s.d, el, ctx, bounds: s.bounds);
      case 'polygon':
        final s = _polyToPath(el, close: true);
        return _shape(s.d, el, ctx, bounds: s.bounds);
      case 'polyline':
        final s = _polyToPath(el, close: false);
        return _shape(s.d, el, ctx, bounds: s.bounds);
      case 'defs':
      case 'metadata':
      case 'title':
      case 'desc':
      case 'style':
        return null; // intentionally ignored
      case 'use':
      case 'text':
      case 'image':
      case 'mask':
      case 'filter':
        warnings.add('Unsupported <$tag> dropped.');
        return null;
      default:
        return null;
    }
  }

  static SvgPath? _shape(String? d, XmlElement el, _Paint ctx,
      {Bounds? bounds}) {
    if (d == null || d.isEmpty) return null;
    // A shape with neither fill nor stroke paints nothing — skip it.
    if (ctx.fill.isNone && ctx.stroke.isNone) return null;
    return SvgPath(
      pathData: d,
      fill: ctx.fill,
      fillAlpha: ctx.fill.opacity * ctx.fillOpacity * ctx.opacity,
      stroke: ctx.stroke,
      strokeAlpha: ctx.stroke.opacity * ctx.strokeOpacity * ctx.opacity,
      strokeWidth: ctx.strokeWidth,
      name: el.getAttribute('id'),
      explicitBounds: bounds,
    );
  }

  // ---- shape → path conversions (each returns exact local bounds) ----

  static ({String d, Bounds bounds}) _rectToPath(XmlElement el) {
    final x = _len(el.getAttribute('x')) ?? 0;
    final y = _len(el.getAttribute('y')) ?? 0;
    final w = _len(el.getAttribute('width')) ?? 0;
    final h = _len(el.getAttribute('height')) ?? 0;
    var rx = _len(el.getAttribute('rx'));
    var ry = _len(el.getAttribute('ry'));
    rx ??= ry;
    ry ??= rx;
    rx ??= 0;
    ry ??= 0;
    rx = rx.clamp(0, w / 2);
    ry = ry.clamp(0, h / 2);
    final bounds = Bounds(x, y, x + w, y + h);
    if (rx == 0 || ry == 0) {
      return (d: 'M$x,$y h$w v$h h${-w} Z', bounds: bounds);
    }
    final b = StringBuffer();
    b.write('M${x + rx},$y ');
    b.write('H${x + w - rx} ');
    b.write('A$rx,$ry 0 0 1 ${x + w},${y + ry} ');
    b.write('V${y + h - ry} ');
    b.write('A$rx,$ry 0 0 1 ${x + w - rx},${y + h} ');
    b.write('H${x + rx} ');
    b.write('A$rx,$ry 0 0 1 $x,${y + h - ry} ');
    b.write('V${y + ry} ');
    b.write('A$rx,$ry 0 0 1 ${x + rx},$y Z');
    return (d: b.toString(), bounds: bounds);
  }

  static ({String d, Bounds bounds}) _circleToPath(XmlElement el) {
    final cx = _len(el.getAttribute('cx')) ?? 0;
    final cy = _len(el.getAttribute('cy')) ?? 0;
    final r = _len(el.getAttribute('r')) ?? 0;
    return _ellipse(cx, cy, r, r);
  }

  static ({String d, Bounds bounds}) _ellipseToPath(XmlElement el) {
    final cx = _len(el.getAttribute('cx')) ?? 0;
    final cy = _len(el.getAttribute('cy')) ?? 0;
    final rx = _len(el.getAttribute('rx')) ?? 0;
    final ry = _len(el.getAttribute('ry')) ?? 0;
    return _ellipse(cx, cy, rx, ry);
  }

  static ({String d, Bounds bounds}) _ellipse(
      double cx, double cy, double rx, double ry) {
    final d = 'M${cx - rx},$cy '
        'A$rx,$ry 0 1 0 ${cx + rx},$cy '
        'A$rx,$ry 0 1 0 ${cx - rx},$cy Z';
    return (d: d, bounds: Bounds(cx - rx, cy - ry, cx + rx, cy + ry));
  }

  static ({String d, Bounds bounds}) _lineToPath(XmlElement el) {
    final x1 = _len(el.getAttribute('x1')) ?? 0;
    final y1 = _len(el.getAttribute('y1')) ?? 0;
    final x2 = _len(el.getAttribute('x2')) ?? 0;
    final y2 = _len(el.getAttribute('y2')) ?? 0;
    return (
      d: 'M$x1,$y1 L$x2,$y2',
      bounds: Bounds(x1 < x2 ? x1 : x2, y1 < y2 ? y1 : y2, x1 > x2 ? x1 : x2,
          y1 > y2 ? y1 : y2),
    );
  }

  static ({String d, Bounds bounds}) _polyToPath(XmlElement el,
      {required bool close}) {
    final raw = el.getAttribute('points') ?? '';
    final nums = raw
        .trim()
        .split(RegExp(r'[\s,]+'))
        .where((s) => s.isNotEmpty)
        .map(double.parse)
        .toList();
    if (nums.length < 4) {
      return (d: '', bounds: Bounds(0, 0, 0, 0));
    }
    final b = StringBuffer('M${nums[0]},${nums[1]}');
    final box = Bounds.fromPoint(nums[0], nums[1]);
    for (var i = 2; i + 1 < nums.length; i += 2) {
      b.write(' L${nums[i]},${nums[i + 1]}');
      box.includePoint(nums[i], nums[i + 1]);
    }
    if (close) b.write(' Z');
    return (d: b.toString(), bounds: box);
  }

  static double? _len(String? v) {
    if (v == null) return null;
    final m = RegExp(r'-?[\d.]+').firstMatch(v);
    return m == null ? null : double.tryParse(m.group(0)!);
  }
}

/// Resolved paint state, propagated with SVG inheritance.
class _Paint {
  _Paint({
    required this.fill,
    required this.fillOpacity,
    required this.stroke,
    required this.strokeOpacity,
    required this.strokeWidth,
    required this.opacity,
  });

  factory _Paint.initial() => _Paint(
        fill: SvgColor.black, // SVG default fill is black
        fillOpacity: 1,
        stroke: SvgColor.none,
        strokeOpacity: 1,
        strokeWidth: 1,
        opacity: 1,
      );

  final SvgColor fill;
  final double fillOpacity;
  final SvgColor stroke;
  final double strokeOpacity;
  final double strokeWidth;
  final double opacity;

  /// Derives the child context for [el], applying its presentation attributes
  /// and inline `style`.
  _Paint inherit(XmlElement el) {
    final style = _parseStyle(el.getAttribute('style'));
    String? prop(String name) => style[name] ?? el.getAttribute(name);

    final fillRaw = prop('fill');
    final strokeRaw = prop('stroke');
    return _Paint(
      fill: fillRaw == null ? fill : SvgColor.parse(fillRaw),
      fillOpacity: _opacity(prop('fill-opacity')) ?? fillOpacity,
      stroke: strokeRaw == null ? stroke : SvgColor.parse(strokeRaw),
      strokeOpacity: _opacity(prop('stroke-opacity')) ?? strokeOpacity,
      strokeWidth: SvgDocument._len(prop('stroke-width')) ?? strokeWidth,
      opacity: _opacity(prop('opacity')) ?? 1,
    );
  }

  static double? _opacity(String? v) =>
      v == null ? null : double.tryParse(v.trim());

  static Map<String, String> _parseStyle(String? style) {
    if (style == null) return const {};
    final out = <String, String>{};
    for (final decl in style.split(';')) {
      final i = decl.indexOf(':');
      if (i <= 0) continue;
      out[decl.substring(0, i).trim()] = decl.substring(i + 1).trim();
    }
    return out;
  }
}

/// A minimal SVG model + parser, scoped to what icon/logo art actually uses.
///
/// Supported: `<svg>` (viewBox/width/height), `<g>` (transform, opacity),
/// `<path>`, and the basic shapes `<rect>` (incl. rounded), `<circle>`,
/// `<ellipse>`, `<line>`, `<polygon>`, `<polyline>`, each normalised to path
/// data. Fills/strokes resolve presentation attributes and inline `style`, with
/// SVG inheritance, plus `<linearGradient>`/`<radialGradient>` fills and
/// `clip-path` (resolved from `<defs>`). Unsupported constructs (filters, masks,
/// text, images, `<use>`) are dropped, and the parser records [warnings] for
/// them so the caller can surface what was skipped.
library;

import 'package:xml/xml.dart';

import 'bounds.dart';
import 'matrix2d.dart';
import 'path_data.dart';
import 'svg_color.dart';

sealed class SvgNode {}

class SvgGroup extends SvgNode {
  SvgGroup(
      {required this.transform,
      this.rawTransform,
      required this.children,
      this.clipPathData});
  final Matrix2D transform;
  final String? rawTransform;
  final List<SvgNode> children;

  /// Clip geometry (SVG path data in this group's local coordinate space) from
  /// a `clip-path="url(#id)"`, or null. Every child is masked to it.
  final String? clipPathData;
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
    this.fillGradient,
    this.clipPathData,
  });
  final String pathData;
  final SvgColor fill;
  final double fillAlpha;
  final SvgColor stroke;
  final double strokeAlpha;
  final double strokeWidth;
  final String? name;

  /// A gradient `fill="url(#id)"`, resolved from `<defs>`. When set it takes
  /// precedence over [fill] (which stays as a flat fallback for renderers that
  /// can't do gradients).
  final SvgGradient? fillGradient;

  /// Clip geometry (local-space path data) from a `clip-path="url(#id)"`, or
  /// null.
  final String? clipPathData;

  /// Exact local bounds for shapes we synthesise (rect/circle/ellipse/line/
  /// poly). `null` for raw `<path>` data, where bounds are derived from the
  /// path commands. Avoids the conservative arc over-estimate inflating the fit.
  final Bounds? explicitBounds;
}

/// One colour stop of a gradient. [offset] is 0..1; [color] carries the
/// stop-opacity baked into its alpha.
class GradientStop {
  const GradientStop(this.offset, this.color);
  final double offset;
  final SvgColor color;
}

/// A resolved linear or radial gradient. Coordinates are in the gradient's own
/// units ([userSpace] ? user space : 0..1 of the filled shape's bounding box);
/// [transform] is the `gradientTransform`. [tileMode] is `clamp`, `repeated`, or
/// `mirror`.
class SvgGradient {
  const SvgGradient({
    required this.linear,
    required this.stops,
    required this.userSpace,
    required this.transform,
    required this.tileMode,
    this.x1 = 0,
    this.y1 = 0,
    this.x2 = 1,
    this.y2 = 0,
    this.cx = 0.5,
    this.cy = 0.5,
    this.r = 0.5,
  });

  final bool linear;
  final List<GradientStop> stops;
  final bool userSpace;
  final Matrix2D transform;
  final String tileMode;
  final double x1, y1, x2, y2; // linear endpoints
  final double cx, cy, r; // radial centre + radius

  /// Same gradient with a replaced [transform], used to fold a referencing
  /// shape's own `transform` into a `userSpaceOnUse` gradient (whose coordinates
  /// live in that shape's user space).
  SvgGradient withTransform(Matrix2D t) => SvgGradient(
        linear: linear,
        stops: stops,
        userSpace: userSpace,
        transform: t,
        tileMode: tileMode,
        x1: x1,
        y1: y1,
        x2: x2,
        y2: y2,
        cx: cx,
        cy: cy,
        r: r,
      );
}

class SvgDocument {
  SvgDocument({
    required this.viewportWidth,
    required this.viewportHeight,
    required this.children,
    this.viewBoxMinX = 0,
    this.viewBoxMinY = 0,
    this.warnings = const [],
  });

  final double viewportWidth;
  final double viewportHeight;

  /// viewBox origin (its `min-x`/`min-y`). Non-zero for art authored away from
  /// (0,0) (common in Illustrator exports, e.g. `viewBox="205 15 494 494"`).
  final double viewBoxMinX;
  final double viewBoxMinY;

  /// The full viewBox rectangle in content coordinates.
  Bounds get viewBox => Bounds(viewBoxMinX, viewBoxMinY,
      viewBoxMinX + viewportWidth, viewBoxMinY + viewportHeight);

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
          final childAcc = acc.multiply(g.transform);
          var childBox = _bounds(g.children, childAcc);
          // A clip-path only keeps the art inside it visible, so it must not let
          // huge clipped-away geometry (e.g. a full-bleed texture masked to a
          // small circle) inflate the measured bounds.
          childBox = _clip(childBox, g.clipPathData, childAcc);
          box = Bounds.union(box, childBox);
        case SvgPath p:
          var local = p.explicitBounds ?? PathData.bounds(p.pathData);
          if (local != null) {
            local = local.transformed(acc);
            local = _clip(local, p.clipPathData, acc);
            box = Bounds.union(box, local);
          }
      }
    }
    return box;
  }

  /// Intersects [box] with a `clip-path`'s bounds (in the same space, via [acc]),
  /// or returns [box] unchanged when there is no clip.
  static Bounds? _clip(Bounds? box, String? clipData, Matrix2D acc) {
    if (box == null || clipData == null) return box;
    final clip = PathData.bounds(clipData);
    if (clip == null) return box;
    return Bounds.intersect(box, clip.transformed(acc));
  }

  static SvgDocument parse(String svg) {
    final doc = XmlDocument.parse(svg);
    final root = doc.rootElement;
    final warnings = <String>[];

    double viewW, viewH, minX = 0, minY = 0;
    final viewBox = root.getAttribute('viewBox');
    if (viewBox != null) {
      final parts =
          viewBox.trim().split(RegExp(r'[\s,]+')).map(double.parse).toList();
      minX = parts[0];
      minY = parts[1];
      viewW = parts[2];
      viewH = parts[3];
    } else {
      viewW = _len(root.getAttribute('width')) ?? 24;
      viewH = _len(root.getAttribute('height')) ?? 24;
    }

    final defs = _Defs.collect(root, warnings);
    final ctx = _Paint.initial();
    final children = <SvgNode>[];
    for (final el in root.childElements) {
      final node = _parseElement(el, ctx, defs, warnings);
      if (node != null) children.add(node);
    }

    return SvgDocument(
      viewportWidth: viewW,
      viewportHeight: viewH,
      viewBoxMinX: minX,
      viewBoxMinY: minY,
      children: children,
      warnings: warnings,
    );
  }

  static SvgNode? _parseElement(
      XmlElement el, _Paint inherited, _Defs defs, List<String> warnings) {
    final ctx = inherited.inherit(el, defs);
    final tag = el.name.local;
    final clip = _clipRef(el, defs);
    switch (tag) {
      case 'g':
        final kids = <SvgNode>[];
        for (final c in el.childElements) {
          final node = _parseElement(c, ctx, defs, warnings);
          if (node != null) kids.add(node);
        }
        if (kids.isEmpty) return null;
        final raw = el.getAttribute('transform');
        return SvgGroup(
          transform: Matrix2D.parse(raw),
          rawTransform: raw,
          children: kids,
          clipPathData: clip,
        );
      case 'path':
        final d = el.getAttribute('d');
        if (d == null || d.trim().isEmpty) return null;
        return _shape(d, el, ctx, clip: clip);
      case 'rect':
        final s = _rectToPath(el);
        return _shape(s.d, el, ctx, bounds: s.bounds, clip: clip);
      case 'circle':
        final s = _circleToPath(el);
        return _shape(s.d, el, ctx, bounds: s.bounds, clip: clip);
      case 'ellipse':
        final s = _ellipseToPath(el);
        return _shape(s.d, el, ctx, bounds: s.bounds, clip: clip);
      case 'line':
        final s = _lineToPath(el);
        return _shape(s.d, el, ctx, bounds: s.bounds, clip: clip);
      case 'polygon':
        final s = _polyToPath(el, close: true);
        return _shape(s.d, el, ctx, bounds: s.bounds, clip: clip);
      case 'polyline':
        final s = _polyToPath(el, close: false);
        return _shape(s.d, el, ctx, bounds: s.bounds, clip: clip);
      case 'defs':
      case 'metadata':
      case 'title':
      case 'desc':
      case 'style':
      case 'linearGradient':
      case 'radialGradient':
      case 'clipPath':
        return null; // handled elsewhere or intentionally ignored
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

  /// Resolves a `clip-path="url(#id)"` on [el] to the referenced clip geometry.
  static String? _clipRef(XmlElement el, _Defs defs) {
    final style = _Paint._parseStyle(el.getAttribute('style'));
    final raw = style['clip-path'] ?? el.getAttribute('clip-path');
    if (raw == null) return null;
    final m = RegExp(r'url\(#([^)]+)\)').firstMatch(raw);
    return m == null ? null : defs.clips[m.group(1)];
  }

  static SvgPath? _shape(String? d, XmlElement el, _Paint ctx,
      {Bounds? bounds, String? clip}) {
    if (d == null || d.isEmpty) return null;
    // A shape with no fill (flat or gradient) and no stroke paints nothing.
    if (ctx.fill.isNone && ctx.stroke.isNone && ctx.fillGradient == null) {
      return null;
    }
    // A shape's own `transform` establishes the user space its geometry AND its
    // paint live in: bake it into the path, and fold it into a `userSpaceOnUse`
    // gradient (defined in that same space) so the fill stays aligned with the
    // art. Without this, a rotated shape keeps an unrotated gradient. (An
    // objectBoundingBox gradient is re-derived from the transformed bbox by the
    // consumers, so it must not be folded in here.)
    final t = Matrix2D.parse(el.getAttribute('transform'));
    var pathData = d;
    var gradient = ctx.fillGradient;
    var explicit = bounds;
    if (!t.isIdentity) {
      pathData = PathData.transform(d, t);
      if (gradient != null && gradient.userSpace) {
        gradient = gradient.withTransform(t.multiply(gradient.transform));
      }
      // Drop the pre-transform bbox: measuring it and rotating the corners
      // over-estimates (a rotated axis-aligned box grows ~√2). The baked path is
      // bounded accurately on demand instead.
      explicit = null;
    }
    // A gradient's stops carry their own alpha, so the path-level fill alpha is
    // just the group/fill-opacity envelope; a flat fill also folds in its colour
    // alpha.
    final fillAlpha = ctx.fillGradient != null
        ? ctx.fillOpacity * ctx.opacity
        : ctx.fill.opacity * ctx.fillOpacity * ctx.opacity;
    return SvgPath(
      pathData: pathData,
      fill: ctx.fill,
      fillAlpha: fillAlpha,
      fillGradient: gradient,
      stroke: ctx.stroke,
      strokeAlpha: ctx.stroke.opacity * ctx.strokeOpacity * ctx.opacity,
      strokeWidth: ctx.strokeWidth,
      name: el.getAttribute('id'),
      explicitBounds: explicit,
      clipPathData: clip,
    );
  }

  /// Raw path `d` for any supported shape element (no paint), for clip geometry.
  static String? _shapeData(XmlElement el) => switch (el.name.local) {
        'path' => el.getAttribute('d'),
        'rect' => _rectToPath(el).d,
        'circle' => _circleToPath(el).d,
        'ellipse' => _ellipseToPath(el).d,
        'polygon' => _polyToPath(el, close: true).d,
        'polyline' => _polyToPath(el, close: false).d,
        'line' => _lineToPath(el).d,
        _ => null,
      };

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
    // Cubic corners, not `A` arcs, for the same renderer-compatibility reason as
    // circles (see [_ellipse]).
    const k = 0.5522847498307936;
    final ox = rx * k, oy = ry * k;
    final b = StringBuffer();
    b.write('M${x + rx},$y ');
    b.write('H${x + w - rx} ');
    b.write(
        'C${x + w - rx + ox},$y ${x + w},${y + ry - oy} ${x + w},${y + ry} ');
    b.write('V${y + h - ry} ');
    b.write('C${x + w},${y + h - ry + oy} '
        '${x + w - rx + ox},${y + h} ${x + w - rx},${y + h} ');
    b.write('H${x + rx} ');
    b.write('C${x + rx - ox},${y + h} $x,${y + h - ry + oy} $x,${y + h - ry} ');
    b.write('V${y + ry} ');
    b.write('C$x,${y + ry - oy} ${x + rx - ox},$y ${x + rx},$y ');
    b.write('Z');
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
    // Four cubic Béziers, not two arcs: some VectorDrawable/Compose renderers
    // drop `A` arc commands (especially rotated ones), which would make a
    // gradient-filled circle vanish and an arc `<clip-path>` fail to clip.
    // kappa ≈ 4/3·(√2−1) places the control points for a circular quadrant.
    const k = 0.5522847498307936;
    final ox = rx * k, oy = ry * k;
    final d = 'M${cx + rx},$cy '
        'C${cx + rx},${cy + oy} ${cx + ox},${cy + ry} $cx,${cy + ry} '
        'C${cx - ox},${cy + ry} ${cx - rx},${cy + oy} ${cx - rx},$cy '
        'C${cx - rx},${cy - oy} ${cx - ox},${cy - ry} $cx,${cy - ry} '
        'C${cx + ox},${cy - ry} ${cx + rx},${cy - oy} ${cx + rx},$cy Z';
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
    required this.fillGradient,
    required this.fillOpacity,
    required this.stroke,
    required this.strokeOpacity,
    required this.strokeWidth,
    required this.opacity,
  });

  factory _Paint.initial() => _Paint(
        fill: SvgColor.black, // SVG default fill is black
        fillGradient: null,
        fillOpacity: 1,
        stroke: SvgColor.none,
        strokeOpacity: 1,
        strokeWidth: 1,
        opacity: 1,
      );

  final SvgColor fill;
  final SvgGradient? fillGradient;
  final double fillOpacity;
  final SvgColor stroke;
  final double strokeOpacity;
  final double strokeWidth;
  final double opacity;

  /// Derives the child context for [el], resolving `fill`/`stroke` (including a
  /// gradient `fill="url(#id)"` against [defs]), opacity and stroke width.
  _Paint inherit(XmlElement el, _Defs defs) {
    final style = _parseStyle(el.getAttribute('style'));
    String? prop(String name) => style[name] ?? el.getAttribute(name);

    final fillRaw = prop('fill');
    var newFill = fill;
    var newGrad = fillGradient;
    if (fillRaw != null) {
      final url = RegExp(r'url\(#([^)]+)\)').firstMatch(fillRaw);
      if (url != null) {
        newGrad = defs.gradients[url.group(1)];
        newFill = newGrad != null ? _Defs.flatOf(newGrad) : SvgColor.black;
      } else {
        newFill = SvgColor.parse(fillRaw);
        newGrad = null;
      }
    }

    final strokeRaw = prop('stroke');
    return _Paint(
      fill: newFill,
      fillGradient: newGrad,
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

/// Gradients and clip paths gathered from `<defs>` (or anywhere in the tree),
/// keyed by id, so `url(#id)` references can be resolved during parsing.
class _Defs {
  _Defs(this.gradients, this.clips);
  final Map<String, SvgGradient> gradients;

  /// id → clip geometry as a single user-space path `d` (each shape's own
  /// transform already baked in).
  final Map<String, String> clips;

  static _Defs collect(XmlElement root, List<String> warnings) {
    final gradEls = <String, XmlElement>{};
    final clipEls = <String, XmlElement>{};
    for (final el in root.descendants.whereType<XmlElement>()) {
      final id = el.getAttribute('id');
      if (id == null) continue;
      switch (el.name.local) {
        case 'linearGradient':
        case 'radialGradient':
          gradEls[id] = el;
        case 'clipPath':
          clipEls[id] = el;
      }
    }
    final gradients = <String, SvgGradient>{};
    for (final id in gradEls.keys) {
      final g = _gradient(id, gradEls, <String>{});
      if (g != null) gradients[id] = g;
    }
    final clips = <String, String>{};
    clipEls.forEach((id, el) {
      final d = _clipData(el, warnings);
      if (d != null) clips[id] = d;
    });
    return _Defs(gradients, clips);
  }

  /// Resolves a gradient by id, following `href`/`xlink:href` inheritance for
  /// stops and unspecified attributes. [seen] guards against reference cycles.
  static SvgGradient? _gradient(
      String id, Map<String, XmlElement> els, Set<String> seen) {
    final el = els[id];
    if (el == null || !seen.add(id)) return null;
    final href = el.getAttribute('href') ?? el.getAttribute('xlink:href');
    final parent = (href != null && href.startsWith('#'))
        ? _gradient(href.substring(1), els, seen)
        : null;
    final linear = el.name.local == 'linearGradient';

    var stops = el.childElements
        .where((c) => c.name.local == 'stop')
        .map(_stop)
        .toList();
    if (stops.isEmpty) stops = parent?.stops ?? const [];

    final unitsAttr = el.getAttribute('gradientUnits');
    final userSpace = unitsAttr != null
        ? unitsAttr == 'userSpaceOnUse'
        : (parent?.userSpace ?? false);
    final tAttr = el.getAttribute('gradientTransform');
    final transform = tAttr != null
        ? Matrix2D.parse(tAttr)
        : (parent?.transform ?? Matrix2D.identity);
    final tileMode =
        _tile(el.getAttribute('spreadMethod')) ?? parent?.tileMode ?? 'clamp';

    double coord(String name, double dflt, double? inherited) {
      final v = el.getAttribute(name);
      return v != null ? _num(v) : (inherited ?? dflt);
    }

    if (linear) {
      return SvgGradient(
        linear: true,
        stops: stops,
        userSpace: userSpace,
        transform: transform,
        tileMode: tileMode,
        x1: coord('x1', 0, parent?.x1),
        y1: coord('y1', 0, parent?.y1),
        x2: coord('x2', userSpace ? 0 : 1, parent?.x2),
        y2: coord('y2', 0, parent?.y2),
      );
    }
    return SvgGradient(
      linear: false,
      stops: stops,
      userSpace: userSpace,
      transform: transform,
      tileMode: tileMode,
      cx: coord('cx', userSpace ? 0 : 0.5, parent?.cx),
      cy: coord('cy', userSpace ? 0 : 0.5, parent?.cy),
      r: coord('r', userSpace ? 0 : 0.5, parent?.r),
    );
  }

  static GradientStop _stop(XmlElement el) {
    final style = _Paint._parseStyle(el.getAttribute('style'));
    String? prop(String n) => style[n] ?? el.getAttribute(n);
    final offRaw = (prop('offset') ?? '0').trim();
    final offset = (offRaw.endsWith('%')
            ? (double.tryParse(offRaw.substring(0, offRaw.length - 1)) ?? 0) /
                100
            : double.tryParse(offRaw) ?? 0)
        .clamp(0.0, 1.0);
    final base = SvgColor.parse(prop('stop-color') ?? '#000000');
    final op = double.tryParse(prop('stop-opacity') ?? '1') ?? 1;
    final a = (base.opacity * op * 255).round().clamp(0, 255);
    return GradientStop(
        offset, SvgColor.fromArgb((a << 24) | (base.argb & 0xFFFFFF)));
  }

  static String? _clipData(XmlElement el, List<String> warnings) {
    if (el.getAttribute('clipPathUnits') == 'objectBoundingBox') {
      warnings.add('clipPathUnits="objectBoundingBox" not supported; '
          'clip approximated in user space.');
    }
    final parts = <String>[];
    for (final c in el.childElements) {
      final d = SvgDocument._shapeData(c);
      if (d == null || d.trim().isEmpty) continue;
      final t = Matrix2D.parse(c.getAttribute('transform'));
      parts.add(t.isIdentity ? d : PathData.transform(d, t));
    }
    return parts.isEmpty ? null : parts.join(' ');
  }

  /// A representative flat colour for a gradient: the average of the stop RGB
  /// (opaque), or black when there are no stops. Used as the fallback fill for
  /// contexts that don't paint the gradient.
  static SvgColor flatOf(SvgGradient g) {
    if (g.stops.isEmpty) return SvgColor.black;
    var r = 0, gg = 0, b = 0;
    for (final s in g.stops) {
      r += (s.color.argb >> 16) & 0xFF;
      gg += (s.color.argb >> 8) & 0xFF;
      b += s.color.argb & 0xFF;
    }
    final n = g.stops.length;
    return SvgColor.fromArgb(
        0xFF000000 | ((r ~/ n) << 16) | ((gg ~/ n) << 8) | (b ~/ n));
  }

  static String? _tile(String? spread) => switch (spread) {
        'reflect' => 'mirror',
        'repeat' => 'repeated',
        'pad' => 'clamp',
        _ => null,
      };

  static double _num(String v) {
    final t = v.trim();
    if (t.endsWith('%')) {
      return (double.tryParse(t.substring(0, t.length - 1)) ?? 0) / 100;
    }
    return double.tryParse(RegExp(r'-?[\d.]+').firstMatch(t)?.group(0) ?? '') ??
        0;
  }
}

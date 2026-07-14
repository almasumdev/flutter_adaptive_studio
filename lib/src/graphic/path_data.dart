/// Lightweight SVG path-data utilities.
///
/// We do NOT re-emit path data: VectorDrawable's `android:pathData` accepts the
/// exact same `d` grammar (including relative commands), so paths pass through
/// verbatim. What we DO need is a bounding box, to fit foreground art into the
/// adaptive-icon safe zone. The box is computed conservatively (control points
/// and arc radii are included) so the fit never clips real geometry.
library;

import 'dart:math' as math;

import 'bounds.dart';
import 'matrix2d.dart';

class PathData {
  /// Rewrites an SVG path `d` string with every coordinate mapped through the
  /// affine [m]. Points (M/L/H/V/C/S/Q/T) transform exactly; `H`/`V` become `L`
  /// since an axis-aligned segment may not stay axis-aligned. Arc (`A`) radii and
  /// x-rotation are transformed via the matrix's similarity part (exact for
  /// translate/rotate/uniform-scale, a close approximation otherwise), with the
  /// sweep flag flipped on a reflection. Used to bake a clip shape's own
  /// transform into a single clip path in user space.
  static String transform(String d, Matrix2D m) {
    final decomp = m.decompose();
    final scale = math.sqrt((m.a * m.d - m.b * m.c).abs());
    final reflected = (m.a * m.d - m.b * m.c) < 0;
    final rot = decomp.rotation;
    final b = StringBuffer();
    final s = _Scanner(d);
    var cx = 0.0, cy = 0.0, sx = 0.0, sy = 0.0;
    void moveOut(String cmd, ({double x, double y}) p) =>
        b.write('$cmd${_n(p.x)},${_n(p.y)} ');
    var cmd = '';
    while (!s.atEnd) {
      if (s.isCommandAhead()) cmd = s.readCommand();
      final rel = cmd == cmd.toLowerCase();
      switch (cmd.toUpperCase()) {
        case 'M':
          var x = s.num(), y = s.num();
          if (rel) {
            x += cx;
            y += cy;
          }
          cx = x;
          cy = y;
          sx = x;
          sy = y;
          moveOut('M', m.apply(x, y));
          cmd = rel ? 'l' : 'L';
        case 'L':
          var x = s.num(), y = s.num();
          if (rel) {
            x += cx;
            y += cy;
          }
          cx = x;
          cy = y;
          moveOut('L', m.apply(x, y));
        case 'H':
          var x = s.num();
          if (rel) x += cx;
          cx = x;
          moveOut('L', m.apply(x, cy));
        case 'V':
          var y = s.num();
          if (rel) y += cy;
          cy = y;
          moveOut('L', m.apply(cx, y));
        case 'C':
          final p = _readPoints(s, 3, rel, cx, cy);
          final a = m.apply(p[0], p[1]),
              c = m.apply(p[2], p[3]),
              e = m.apply(p[4], p[5]);
          b.write('C${_n(a.x)},${_n(a.y)} ${_n(c.x)},${_n(c.y)} '
              '${_n(e.x)},${_n(e.y)} ');
          cx = p[4];
          cy = p[5];
        case 'S':
        case 'Q':
          final p = _readPoints(s, 2, rel, cx, cy);
          final a = m.apply(p[0], p[1]), e = m.apply(p[2], p[3]);
          b.write('${cmd.toUpperCase()}${_n(a.x)},${_n(a.y)} '
              '${_n(e.x)},${_n(e.y)} ');
          cx = p[2];
          cy = p[3];
        case 'T':
          var x = s.num(), y = s.num();
          if (rel) {
            x += cx;
            y += cy;
          }
          cx = x;
          cy = y;
          moveOut('T', m.apply(x, y));
        case 'A':
          final rx = s.num(), ry = s.num();
          final rot0 = s.num();
          final large = s.num();
          var sweep = s.num();
          var x = s.num(), y = s.num();
          if (rel) {
            x += cx;
            y += cy;
          }
          if (reflected) sweep = sweep == 0 ? 1 : 0;
          final e = m.apply(x, y);
          b.write('A${_n(rx * scale)},${_n(ry * scale)} ${_n(rot0 + rot)} '
              '${large.toInt()} ${sweep.toInt()} ${_n(e.x)},${_n(e.y)} ');
          cx = x;
          cy = y;
        case 'Z':
          b.write('Z ');
          cx = sx;
          cy = sy;
        default:
          return b.toString().trim();
      }
    }
    return b.toString().trim();
  }

  static String _n(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(3).replaceAll(RegExp(r'0+$'), '').replaceAll(
          RegExp(r'\.$'),
          '',
        );
  }

  /// Computes a conservative bounding box for an SVG path `d` string.
  /// Returns `null` if the path has no drawable points.
  static Bounds? bounds(String d) {
    final s = _Scanner(d);
    Bounds? box;
    var cx = 0.0, cy = 0.0; // current point
    var sx = 0.0, sy = 0.0; // subpath start
    void add(double x, double y) {
      box = box == null ? Bounds.fromPoint(x, y) : (box!..includePoint(x, y));
    }

    var cmd = '';
    while (!s.atEnd) {
      if (s.isCommandAhead()) cmd = s.readCommand();
      final rel = cmd == cmd.toLowerCase();
      final u = cmd.toUpperCase();
      switch (u) {
        case 'M':
          var x = s.num(), y = s.num();
          if (rel) {
            x += cx;
            y += cy;
          }
          cx = x;
          cy = y;
          sx = x;
          sy = y;
          add(x, y);
          cmd = rel ? 'l' : 'L'; // subsequent pairs are implicit lineto
        case 'L':
          var x = s.num(), y = s.num();
          if (rel) {
            x += cx;
            y += cy;
          }
          cx = x;
          cy = y;
          add(x, y);
        case 'H':
          var x = s.num();
          if (rel) x += cx;
          cx = x;
          add(x, cy);
        case 'V':
          var y = s.num();
          if (rel) y += cy;
          cy = y;
          add(cx, y);
        case 'C':
          final p = _readPoints(s, 3, rel, cx, cy);
          // Tight bounds via the curve's real extrema, not the control hull
          // (which over-bounds a circle drawn as four cubics once it's rotated).
          _addCubic(cx, cy, p[0], p[1], p[2], p[3], p[4], p[5], add);
          cx = p[4];
          cy = p[5];
        case 'S':
        case 'Q':
          final p = _readPoints(s, 2, rel, cx, cy);
          add(p[0], p[1]);
          add(p[2], p[3]);
          cx = p[2];
          cy = p[3];
        case 'T':
          var x = s.num(), y = s.num();
          if (rel) {
            x += cx;
            y += cy;
          }
          cx = x;
          cy = y;
          add(x, y);
        case 'A':
          final rx = s.num().abs(), ry = s.num().abs();
          final phi = s.num();
          final large = s.num();
          final sweep = s.num();
          var x = s.num(), y = s.num();
          if (rel) {
            x += cx;
            y += cy;
          }
          _addArc(cx, cy, rx, ry, phi, large != 0, sweep != 0, x, y, add);
          cx = x;
          cy = y;
        case 'Z':
          cx = sx;
          cy = sy;
        default:
          // Unknown token: bail rather than loop forever.
          return box;
      }
    }
    return box;
  }

  /// Adds points sampled along an SVG elliptical arc so the bounding box
  /// reflects the arc's real extent. The endpoint-only estimate (start/end
  /// expanded by the radii) grossly over-bounds a circle, which would inflate
  /// `artBounds` and shrink a circle-heavy logo to a dot in the icon canvas.
  static void _addArc(
      double x0,
      double y0,
      double rx,
      double ry,
      double phiDeg,
      bool largeArc,
      bool sweep,
      double x1,
      double y1,
      void Function(double, double) add) {
    add(x1, y1);
    if (rx == 0 || ry == 0 || (x0 == x1 && y0 == y1)) return; // degenerate
    final phi = phiDeg * math.pi / 180;
    final cosP = math.cos(phi), sinP = math.sin(phi);
    // Endpoint → centre parameterization (SVG impl notes F.6.5).
    final dx = (x0 - x1) / 2, dy = (y0 - y1) / 2;
    final x1p = cosP * dx + sinP * dy;
    final y1p = -sinP * dx + cosP * dy;
    var rxx = rx, ryy = ry;
    final lambda = (x1p * x1p) / (rxx * rxx) + (y1p * y1p) / (ryy * ryy);
    if (lambda > 1) {
      final k = math.sqrt(lambda);
      rxx *= k;
      ryy *= k;
    }
    final sign = largeArc != sweep ? 1.0 : -1.0;
    var numer =
        rxx * rxx * ryy * ryy - rxx * rxx * y1p * y1p - ryy * ryy * x1p * x1p;
    final denom = rxx * rxx * y1p * y1p + ryy * ryy * x1p * x1p;
    if (numer < 0) numer = 0;
    final co = denom == 0 ? 0.0 : sign * math.sqrt(numer / denom);
    final cxp = co * (rxx * y1p / ryy);
    final cyp = co * (-ryy * x1p / rxx);
    final cx = cosP * cxp - sinP * cyp + (x0 + x1) / 2;
    final cy = sinP * cxp + cosP * cyp + (y0 + y1) / 2;

    double vecAngle(double ux, double uy, double vx, double vy) {
      final len = math.sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy));
      var a = len == 0 ? 0.0 : math.acos((ux * vx + uy * vy) / len);
      if (ux * vy - uy * vx < 0) a = -a;
      return a;
    }

    final ux = (x1p - cxp) / rxx, uy = (y1p - cyp) / ryy;
    final vx = (-x1p - cxp) / rxx, vy = (-y1p - cyp) / ryy;
    final theta1 = vecAngle(1, 0, ux, uy);
    var dtheta = vecAngle(ux, uy, vx, vy);
    if (!sweep && dtheta > 0) dtheta -= 2 * math.pi;
    if (sweep && dtheta < 0) dtheta += 2 * math.pi;
    // 32 samples bound a circle to well under 1%, ample for a safe-zone fit.
    const steps = 32;
    for (var i = 0; i <= steps; i++) {
      final t = theta1 + dtheta * i / steps;
      add(cx + rxx * math.cos(t) * cosP - ryy * math.sin(t) * sinP,
          cy + rxx * math.cos(t) * sinP + ryy * math.sin(t) * cosP);
    }
  }

  /// Adds a cubic Bézier's true bounding extent: the endpoints plus any axis
  /// extrema (where the derivative is zero) inside the segment. Bounding by the
  /// control hull instead would over-size a rotated circle-as-cubics.
  static void _addCubic(double x0, double y0, double x1, double y1, double x2,
      double y2, double x3, double y3, void Function(double, double) add) {
    add(x0, y0);
    add(x3, y3);
    for (final t in _cubicExtrema(x0, x1, x2, x3)) {
      add(_cubicAt(x0, x1, x2, x3, t), _cubicAt(y0, y1, y2, y3, t));
    }
    for (final t in _cubicExtrema(y0, y1, y2, y3)) {
      add(_cubicAt(x0, x1, x2, x3, t), _cubicAt(y0, y1, y2, y3, t));
    }
  }

  static double _cubicAt(double p0, double p1, double p2, double p3, double t) {
    final u = 1 - t;
    return u * u * u * p0 +
        3 * u * u * t * p1 +
        3 * u * t * t * p2 +
        t * t * t * p3;
  }

  /// Roots in (0,1) of the cubic's derivative along one axis: `a·t² + b·t + c`.
  static List<double> _cubicExtrema(
      double p0, double p1, double p2, double p3) {
    final a = -p0 + 3 * p1 - 3 * p2 + p3;
    final b = 2 * (p0 - 2 * p1 + p2);
    final c = p1 - p0;
    final out = <double>[];
    void keep(double t) {
      if (t > 1e-9 && t < 1 - 1e-9) out.add(t);
    }

    if (a.abs() < 1e-12) {
      if (b.abs() > 1e-12) keep(-c / b);
    } else {
      final disc = b * b - 4 * a * c;
      if (disc >= 0) {
        final sq = math.sqrt(disc);
        keep((-b + sq) / (2 * a));
        keep((-b - sq) / (2 * a));
      }
    }
    return out;
  }

  /// Reads [count] coordinate pairs, applying relative offset to each pair.
  static List<double> _readPoints(
      _Scanner s, int count, bool rel, double cx, double cy) {
    final out = <double>[];
    for (var i = 0; i < count; i++) {
      var x = s.num(), y = s.num();
      if (rel) {
        x += cx;
        y += cy;
      }
      out
        ..add(x)
        ..add(y);
    }
    return out;
  }
}

/// A forgiving scanner for SVG path-data / number lists.
class _Scanner {
  _Scanner(this.s);
  final String s;
  int i = 0;

  void _skipSep() {
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
    _skipSep();
    return i >= s.length;
  }

  bool isCommandAhead() {
    _skipSep();
    if (i >= s.length) return false;
    final c = s[i];
    return RegExp(r'[a-zA-Z]').hasMatch(c);
  }

  String readCommand() {
    _skipSep();
    return s[i++];
  }

  double num() {
    _skipSep();
    final start = i;
    if (i < s.length && (s[i] == '+' || s[i] == '-')) i++;
    while (i < s.length && _isDigit(s[i])) {
      i++;
    }
    if (i < s.length && s[i] == '.') {
      i++;
      while (i < s.length && _isDigit(s[i])) {
        i++;
      }
    }
    if (i < s.length && (s[i] == 'e' || s[i] == 'E')) {
      i++;
      if (i < s.length && (s[i] == '+' || s[i] == '-')) i++;
      while (i < s.length && _isDigit(s[i])) {
        i++;
      }
    }
    return double.parse(s.substring(start, i));
  }

  static bool _isDigit(String c) {
    final u = c.codeUnitAt(0);
    return u >= 0x30 && u <= 0x39;
  }
}

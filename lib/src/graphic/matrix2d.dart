/// A 2D affine transform: `[a c e; b d f; 0 0 1]`.
///
/// Used both to compute art bounding boxes in root coordinate space and to
/// validate that an SVG `transform` decomposes into something a VectorDrawable
/// `<group>` can represent.
library;

import 'dart:math' as math;

class Matrix2D {
  const Matrix2D(this.a, this.b, this.c, this.d, this.e, this.f);

  final double a, b, c, d, e, f;

  static const Matrix2D identity = Matrix2D(1, 0, 0, 1, 0, 0);

  /// `this * other` (apply [other] first, then [this]).
  Matrix2D multiply(Matrix2D o) => Matrix2D(
        a * o.a + c * o.b,
        b * o.a + d * o.b,
        a * o.c + c * o.d,
        b * o.c + d * o.d,
        a * o.e + c * o.f + e,
        b * o.e + d * o.f + f,
      );

  ({double x, double y}) apply(double x, double y) =>
      (x: a * x + c * y + e, y: b * x + d * y + f);

  static Matrix2D translate(double tx, double ty) =>
      Matrix2D(1, 0, 0, 1, tx, ty);

  static Matrix2D scale(double sx, double sy) => Matrix2D(sx, 0, 0, sy, 0, 0);

  static Matrix2D rotate(double degrees, [double cx = 0, double cy = 0]) {
    final r = degrees * math.pi / 180.0;
    final cos = math.cos(r), sin = math.sin(r);
    final rot = Matrix2D(cos, sin, -sin, cos, 0, 0);
    if (cx == 0 && cy == 0) return rot;
    return translate(cx, cy).multiply(rot).multiply(translate(-cx, -cy));
  }

  /// Parses an SVG `transform` attribute (`translate`, `scale`, `rotate`,
  /// `matrix`, `skewX`, `skewY`) into a single matrix. Unknown functions are
  /// ignored.
  static Matrix2D parse(String? transform) {
    if (transform == null || transform.trim().isEmpty) return identity;
    var result = identity;
    final re = RegExp(r'(\w+)\s*\(([^)]*)\)');
    for (final m in re.allMatches(transform)) {
      final fn = m.group(1)!;
      final args = m
          .group(2)!
          .split(RegExp(r'[\s,]+'))
          .where((s) => s.isNotEmpty)
          .map(double.parse)
          .toList();
      final next = switch (fn) {
        'translate' => translate(args[0], args.length > 1 ? args[1] : 0),
        'scale' => scale(args[0], args.length > 1 ? args[1] : args[0]),
        'rotate' => args.length >= 3
            ? rotate(args[0], args[1], args[2])
            : rotate(args[0]),
        'matrix' =>
          Matrix2D(args[0], args[1], args[2], args[3], args[4], args[5]),
        'skewX' => Matrix2D(1, 0, math.tan(args[0] * math.pi / 180), 1, 0, 0),
        'skewY' => Matrix2D(1, math.tan(args[0] * math.pi / 180), 0, 1, 0, 0),
        _ => identity,
      };
      result = result.multiply(next);
    }
    return result;
  }

  bool get isIdentity =>
      a == 1 && b == 0 && c == 0 && d == 1 && e == 0 && f == 0;

  /// Decomposes into translate · rotate · scale, the form a VectorDrawable
  /// `<group>` (pivot 0) can represent exactly. [shear] is the normalised skew
  /// component; if it is non-trivial the matrix isn't a pure TRS and the caller
  /// should warn (VectorDrawable groups can't express shear).
  ({
    double translateX,
    double translateY,
    double rotation,
    double scaleX,
    double scaleY,
    double shear,
  }) decompose() {
    final sx = math.sqrt(a * a + b * b);
    if (sx == 0) {
      return (
        translateX: e,
        translateY: f,
        rotation: 0,
        scaleX: 0,
        scaleY: math.sqrt(c * c + d * d),
        shear: 0,
      );
    }
    final r11 = a / sx, r21 = b / sx;
    final shear = r11 * c + r21 * d;
    final cc = c - r11 * shear, dd = d - r21 * shear;
    var sy = math.sqrt(cc * cc + dd * dd);
    final det = a * d - b * c;
    if (det < 0) sy = -sy;
    final rotation = math.atan2(r21, r11) * 180 / math.pi;
    return (
      translateX: e,
      translateY: f,
      rotation: rotation,
      scaleX: sx,
      scaleY: sy,
      shear: sy == 0 ? 0 : shear / sy,
    );
  }
}

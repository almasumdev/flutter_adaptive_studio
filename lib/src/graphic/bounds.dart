/// An axis-aligned bounding box with affine-transform support.
library;

import 'matrix2d.dart';

class Bounds {
  Bounds(this.minX, this.minY, this.maxX, this.maxY);

  double minX, minY, maxX, maxY;

  static Bounds? empty() => null;

  double get width => maxX - minX;
  double get height => maxY - minY;
  double get centerX => (minX + maxX) / 2;
  double get centerY => (minY + maxY) / 2;
  double get longestSide => width > height ? width : height;

  void includePoint(double x, double y) {
    if (x < minX) minX = x;
    if (y < minY) minY = y;
    if (x > maxX) maxX = x;
    if (y > maxY) maxY = y;
  }

  static Bounds fromPoint(double x, double y) => Bounds(x, y, x, y);

  /// Transforms the four corners by [m] and returns their bounding box. (For a
  /// rotation this is a conservative over-estimate, which is what we want for a
  /// "never clip" safe-zone fit.)
  Bounds transformed(Matrix2D m) {
    final pts = [
      m.apply(minX, minY),
      m.apply(maxX, minY),
      m.apply(maxX, maxY),
      m.apply(minX, maxY),
    ];
    final out = Bounds.fromPoint(pts.first.x, pts.first.y);
    for (final pt in pts.skip(1)) {
      out.includePoint(pt.x, pt.y);
    }
    return out;
  }

  static Bounds? union(Bounds? a, Bounds? b) {
    if (a == null) return b;
    if (b == null) return a;
    return Bounds(
      a.minX < b.minX ? a.minX : b.minX,
      a.minY < b.minY ? a.minY : b.minY,
      a.maxX > b.maxX ? a.maxX : b.maxX,
      a.maxY > b.maxY ? a.maxY : b.maxY,
    );
  }

  /// Overlap of two boxes, or `null` if they don't overlap. Used to bound art to
  /// the region a `clip-path` actually keeps visible.
  static Bounds? intersect(Bounds? a, Bounds? b) {
    if (a == null || b == null) return null;
    final nx = a.minX > b.minX ? a.minX : b.minX;
    final ny = a.minY > b.minY ? a.minY : b.minY;
    final xx = a.maxX < b.maxX ? a.maxX : b.maxX;
    final xy = a.maxY < b.maxY ? a.maxY : b.maxY;
    if (xx < nx || xy < ny) return null;
    return Bounds(nx, ny, xx, xy);
  }

  @override
  String toString() => 'Bounds($minX, $minY → $maxX, $maxY  $width x $height)';
}

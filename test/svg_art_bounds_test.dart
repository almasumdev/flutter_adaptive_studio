import 'package:flutter_adaptive_studio/src/graphic/path_data.dart';
import 'package:flutter_adaptive_studio/src/graphic/svg_document.dart';
import 'package:test/test.dart';

/// `artBounds` drives the safe-zone fit, so it must be tight. Two ways it used
/// to blow up (shrinking a logo to a dot in the icon): an arc bounded by its
/// endpoints-plus-radii, and a `clip-path` that let clipped-away geometry count.
void main() {
  group('arc bounding is tight', () {
    test('a circle path bounds to its circle, not endpoints ± radii', () {
      // Circle centred (50,50) r=50, as two arcs (what circle→path emits).
      final b =
          PathData.bounds('M0,50 A50,50 0 1 0 100,50 A50,50 0 1 0 0,50 Z');
      expect(b, isNotNull);
      // Tight box is (0,0)->(100,100). The old endpoint±radius estimate gave
      // (-50,0)->(150,100), i.e. width 200.
      expect(b!.minX, closeTo(0, 1));
      expect(b.maxX, closeTo(100, 1));
      expect(b.minY, closeTo(0, 1));
      expect(b.maxY, closeTo(100, 1));
    });
  });

  group('artBounds', () {
    test('a rotated circle is not √2-inflated', () {
      // A circle rotated about its centre is still the same circle: its bounds
      // must stay ~80 wide, not grow to ~113 (80·√2) from rotating a bbox.
      final doc = SvgDocument.parse(
          '<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">'
          '<circle cx="50" cy="50" r="40" transform="rotate(45 50 50)" '
          'fill="#000"/></svg>');
      final b = doc.artBounds()!;
      expect(b.width, closeTo(80, 2));
      expect(b.height, closeTo(80, 2));
    });

    test('a circle becomes cubic béziers, not arcs, and bounds tightly', () {
      // Some VectorDrawable/Compose renderers drop `A` arc commands, so circles
      // must emit cubics; the bound must still be the true 80-wide circle.
      final doc = SvgDocument.parse(
          '<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">'
          '<circle cx="50" cy="50" r="40" fill="#000"/></svg>');
      final path = doc.children.single as SvgPath;
      expect(path.pathData, contains('C'));
      expect(path.pathData, isNot(contains('A')));
      final b = doc.artBounds()!;
      expect(b.width, closeTo(80, 1));
      expect(b.height, closeTo(80, 1));
    });

    test('a rounded rect uses cubic corners, not arcs', () {
      final doc = SvgDocument.parse(
          '<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">'
          '<rect x="10" y="10" width="80" height="80" rx="15" fill="#000"/>'
          '</svg>');
      final path = doc.children.single as SvgPath;
      expect(path.pathData, isNot(contains('A')));
      expect(path.pathData, contains('C'));
    });

    test('clipped-away geometry does not inflate the bounds', () {
      // A huge rect clipped to a small central circle contributes only the
      // clipped region, so the art measures ~the circle, not the whole rect.
      final doc = SvgDocument.parse(
          '<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">'
          '<defs><clipPath id="c">'
          '<circle cx="50" cy="50" r="20"/></clipPath></defs>'
          '<g clip-path="url(#c)">'
          '<rect x="-500" y="-500" width="1000" height="1000" fill="#000"/>'
          '</g></svg>');
      final b = doc.artBounds()!;
      // The r=20 clip circle spans (30,30)->(70,70); without clip-awareness the
      // rect alone would report a 1000-wide box.
      expect(b.width, lessThan(60));
      expect(b.minX, greaterThan(20));
      expect(b.maxX, lessThan(80));
    });
  });
}

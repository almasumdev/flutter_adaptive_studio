import 'package:flutter_adaptive_studio/src/config/config.dart';
import 'package:flutter_adaptive_studio/src/geometry/adaptive_geometry.dart';
import 'package:flutter_adaptive_studio/src/graphic/bounds.dart';
import 'package:flutter_adaptive_studio/src/graphic/svg_color.dart';
import 'package:flutter_adaptive_studio/src/graphic/svg_document.dart';
import 'package:flutter_adaptive_studio/src/vector/vector_drawable_writer.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

void main() {
  group('SvgColor', () {
    test('parses #rrggbb to opaque android hex', () {
      final c = SvgColor.parse('#3e9aa6');
      expect(c.androidHex, '#3E9AA6');
      expect(c.opacity, 1.0);
      expect(c.isNone, isFalse);
    });

    test('parses SVG #rrggbbaa (alpha last) to android #aarrggbb', () {
      final c = SvgColor.parse('#ff000080'); // red @ 50% in SVG order
      expect(c.androidHex, '#80FF0000'); // Android wants alpha first
      expect(c.alpha, 0x80);
    });

    test('parses shorthand #rgb', () {
      expect(SvgColor.parse('#f00').androidHex, '#FF0000');
    });

    test('none / transparent are "none"', () {
      expect(SvgColor.parse('none').isNone, isTrue);
      expect(SvgColor.parse('transparent').isNone, isTrue);
    });

    test('rgb() function', () {
      expect(SvgColor.parse('rgb(62,154,166)').androidHex, '#3E9AA6');
    });
  });

  group('SvgDocument bounds', () {
    test('exact bounds for circle (no arc over-estimate)', () {
      final doc = SvgDocument.parse(
        '<svg viewBox="0 0 100 100"><circle cx="50" cy="50" r="20" '
        'fill="#000"/></svg>',
      );
      final b = doc.artBounds()!;
      expect(b.minX, closeTo(30, 0.001));
      expect(b.maxX, closeTo(70, 0.001));
      expect(b.minY, closeTo(30, 0.001));
      expect(b.maxY, closeTo(70, 0.001));
    });

    test('group transform is applied to bounds', () {
      final doc = SvgDocument.parse(
        '<svg viewBox="0 0 100 100"><g transform="translate(10 5)">'
        '<rect x="0" y="0" width="20" height="20" fill="#000"/></g></svg>',
      );
      final b = doc.artBounds()!;
      expect(b.minX, closeTo(10, 0.001));
      expect(b.minY, closeTo(5, 0.001));
      expect(b.maxX, closeTo(30, 0.001));
      expect(b.maxY, closeTo(25, 0.001));
    });
  });

  group('AdaptiveGeometry', () {
    test('fit applies the default 15% padding inside the 72dp safe square', () {
      final fit = AdaptiveGeometry.fit(
          Bounds(0, 0, 100, 100), const SafeZone.fit(), 100);
      // 72 * (1 - 0.15) = 61.2 → scale 0.612 for a 100-unit longest side.
      expect(fit.scale, closeTo(0.612, 0.0001));
      // centre (50,50) → canvas centre (54,54): t = 54 - 0.612*50 = 23.4.
      expect(fit.translateX, closeTo(23.4, 0.0001));
      expect(fit.translateY, closeTo(23.4, 0.0001));
    });

    test('inset:0 fills the full 72dp safe square (no padding)', () {
      final fit = AdaptiveGeometry.fit(
          Bounds(0, 0, 100, 100), const SafeZone.inset(0), 100);
      expect(fit.scale, closeTo(0.72, 0.0001));
    });

    test('a custom inset percentage pads relative to the safe square', () {
      final fit = AdaptiveGeometry.fit(
          Bounds(0, 0, 100, 100), const SafeZone.inset(25), 100);
      // 72 * (1 - 0.25) = 54 → scale 0.54.
      expect(fit.scale, closeTo(0.54, 0.0001));
    });

    test('none mode fills the whole 108 canvas', () {
      final fit = AdaptiveGeometry.fit(
          Bounds(0, 0, 100, 100), const SafeZone.none(), 100);
      expect(fit.scale, closeTo(1.08, 0.0001));
    });
  });

  group('VectorDrawableWriter', () {
    test('emits a vector with 108 viewport, fit group and path fill', () {
      final doc = SvgDocument.parse(
        '<svg viewBox="0 0 100 100"><rect x="10" y="10" width="80" '
        'height="80" rx="8" fill="#3e9aa6"/></svg>',
      );
      final fit =
          AdaptiveGeometry.fit(doc.artBounds(), const SafeZone.fit(), 100);
      final xml = VectorDrawableWriter()
          .build(doc, viewport: AdaptiveGeometry.canvas, fit: fit);

      final parsed = XmlDocument.parse(xml);
      final vector = parsed.rootElement;
      expect(vector.name.local, 'vector');
      expect(vector.getAttribute('android:viewportWidth'), '108');

      final group =
          vector.childElements.firstWhere((e) => e.name.local == 'group');
      expect(group.getAttribute('android:scaleX'), isNotNull);

      final path =
          group.childElements.firstWhere((e) => e.name.local == 'path');
      expect(path.getAttribute('android:fillColor'), '#3E9AA6');
      expect(path.getAttribute('android:pathData'), isNotNull);
    });

    test('a fill="none" stroke-only path keeps its stroke', () {
      final doc = SvgDocument.parse(
        '<svg viewBox="0 0 100 100"><path d="M10 10 L90 90" fill="none" '
        'stroke="#fff" stroke-width="4"/></svg>',
      );
      final xml = VectorDrawableWriter().build(doc, viewport: 100);
      final path = XmlDocument.parse(xml)
          .rootElement
          .descendantElements
          .firstWhere((e) => e.name.local == 'path');
      expect(path.getAttribute('android:strokeColor'), '#FFFFFF');
      expect(path.getAttribute('android:strokeWidth'), '4');
      expect(path.getAttribute('android:fillColor'), isNull);
    });
  });
}

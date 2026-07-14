import 'package:flutter_adaptive_studio/src/geometry/adaptive_geometry.dart';
import 'package:flutter_adaptive_studio/src/graphic/svg_document.dart';
import 'package:flutter_adaptive_studio/src/raster/svg_rasterizer.dart';
import 'package:flutter_adaptive_studio/src/vector/vector_drawable_writer.dart';
import 'package:test/test.dart';

/// Gradients and clip paths are first-class: the parser resolves `url(#id)`
/// fills and `clip-path` refs, the VectorDrawable writer emits real
/// `aapt:attr <gradient>` and `<clip-path>`, and the rasteriser paints both.
void main() {
  String vd(SvgDocument doc) => VectorDrawableWriter().build(doc,
      viewport: 100,
      fit: const AdaptiveFit(scale: 1, translateX: 0, translateY: 0),
      sizeDp: 100);

  group('linear gradient', () {
    const svg = '''
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="100" y2="0"
        gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#FF0000"/>
      <stop offset="1" stop-color="#0000FF"/>
    </linearGradient>
  </defs>
  <rect x="0" y="0" width="100" height="100" fill="url(#g)"/>
</svg>''';

    test('parses into a gradient fill (not a flat black fill)', () {
      final doc = SvgDocument.parse(svg);
      final path = doc.children.single as SvgPath;
      expect(path.fillGradient, isNotNull);
      expect(path.fillGradient!.linear, isTrue);
      expect(path.fillGradient!.stops, hasLength(2));
      expect(doc.warnings, isEmpty);
    });

    test('emits an aapt:attr <gradient> with stops in the VectorDrawable', () {
      final xml = vd(SvgDocument.parse(svg));
      expect(xml, contains('xmlns:aapt="http://schemas.android.com/aapt"'));
      expect(xml, contains('<aapt:attr name="android:fillColor">'));
      expect(xml, contains('android:type="linear"'));
      expect(xml, contains('android:color="#FF0000"'));
      expect(xml, contains('android:color="#0000FF"'));
      // No flat black fill fell through.
      expect(xml, isNot(contains('android:fillColor="#000000"')));
    });

    test('rasterises a red-to-blue transition across the shape', () {
      final img = const SvgRasterizer().rasterize(SvgDocument.parse(svg), 100);
      final left = img.getPixel(8, 50);
      final right = img.getPixel(92, 50);
      expect(left.r, greaterThan(left.b), reason: 'left edge is red-dominant');
      expect(right.b, greaterThan(right.r),
          reason: 'right edge is blue-dominant');
    });
  });

  group('clip path', () {
    const svg = '''
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <clipPath id="c"><circle cx="50" cy="50" r="20"/></clipPath>
  </defs>
  <g clip-path="url(#c)">
    <rect x="0" y="0" width="100" height="100" fill="#000000"/>
  </g>
</svg>''';

    test('emits a <clip-path> in the VectorDrawable', () {
      final xml = vd(SvgDocument.parse(svg));
      expect(xml, contains('<clip-path'));
      expect(xml, contains('android:pathData='));
    });

    test('rasterises with pixels outside the clip circle transparent', () {
      final img = const SvgRasterizer().rasterize(SvgDocument.parse(svg), 100);
      // Inside the r=20 circle at the centre: opaque.
      expect(img.getPixel(50, 50).a, greaterThan(200));
      // A corner is inside the rect but outside the clip circle: transparent.
      expect(img.getPixel(5, 5).a, lessThan(20));
    });
  });

  test('a gradient <stop> honours stop-opacity in the emitted colour', () {
    const svg = '''
<svg viewBox="0 0 10 10" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="10" y2="0">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0"/>
      <stop offset="1" stop-color="#FFFFFF"/>
    </linearGradient>
  </defs>
  <rect width="10" height="10" fill="url(#g)"/>
</svg>''';
    final doc = SvgDocument.parse(svg);
    final grad = (doc.children.single as SvgPath).fillGradient!;
    // First stop is fully transparent white (#00FFFFFF), second opaque.
    expect(grad.stops.first.color.androidHex, '#00FFFFFF');
    expect(grad.stops.last.color.androidHex, '#FFFFFF');
  });

  group("a shape's own transform folds into its userSpaceOnUse gradient", () {
    // A vertical gradient on a rect rotated 90° must come out horizontal: the
    // element transform establishes the user space the gradient lives in. (This
    // is the play_btn coin case, where rotate(-45) circles carry rotate(45)
    // gradients that should cancel to vertical.)
    const svg = '''
<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="g" x1="50" y1="0" x2="50" y2="100"
        gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#FF0000"/>
      <stop offset="1" stop-color="#0000FF"/>
    </linearGradient>
  </defs>
  <rect x="0" y="0" width="100" height="100" fill="url(#g)"
      transform="rotate(90 50 50)"/>
</svg>''';

    double attr(String xml, String name) =>
        double.parse(RegExp('$name="([-\\d.]+)"').firstMatch(xml)!.group(1)!);

    test('the emitted gradient endpoints are rotated to horizontal', () {
      final xml = vd(SvgDocument.parse(svg));
      // Rotated 90° about the centre: the vertical (50,0)->(50,100) becomes the
      // horizontal (100,50)->(0,50).
      expect(attr(xml, 'android:startY'), closeTo(50, 0.5));
      expect(attr(xml, 'android:endY'), closeTo(50, 0.5));
      expect((attr(xml, 'android:startX') - attr(xml, 'android:endX')).abs(),
          greaterThan(50));
    });

    test('the rasterised fill runs top-to-bottom after the rotation', () {
      final img = const SvgRasterizer().rasterize(SvgDocument.parse(svg), 100);
      // Vertical source, rotated 90° → red now at one horizontal end.
      final top = img.getPixel(50, 8);
      final bottom = img.getPixel(50, 92);
      expect((top.r - bottom.r).abs() + (top.b - bottom.b).abs(), lessThan(40),
          reason: 'a horizontal gradient barely varies top-to-bottom');
      final left = img.getPixel(8, 50);
      final right = img.getPixel(92, 50);
      // The red stop (offset 0) rotates to x=100, so the right edge is red.
      expect(right.r, greaterThan(left.r),
          reason: 'red end is on the right after rotate(90)');
    });
  });

  group('a non-zero viewBox origin is honoured', () {
    test('parse captures the viewBox min-x/min-y', () {
      final doc = SvgDocument.parse(
          '<svg viewBox="10 20 100 100" xmlns="http://www.w3.org/2000/svg">'
          '<rect x="10" y="20" width="100" height="100" fill="#000"/></svg>');
      expect(doc.viewBoxMinX, 10);
      expect(doc.viewBoxMinY, 20);
      expect(doc.viewBox.centerX, 60);
      expect(doc.viewBox.centerY, 70);
    });

    test('viewBox-fill rendering shifts offset art into frame', () {
      // A red rect that exactly fills a viewBox offset far from the origin.
      final doc = SvgDocument.parse(
          '<svg viewBox="100 100 100 100" xmlns="http://www.w3.org/2000/svg">'
          '<rect x="100" y="100" width="100" height="100" fill="#FF0000"/>'
          '</svg>');
      final img = const SvgRasterizer().rasterize(doc, 50);
      // The rect fills the viewBox, so the centre (and corners) are opaque red,
      // not shifted off-canvas.
      expect(img.getPixel(25, 25).a, greaterThan(200));
      expect(img.getPixel(25, 25).r, greaterThan(200));
      expect(img.getPixel(2, 2).a, greaterThan(200));
    });
  });
}

import 'dart:io';

import 'package:flutter_adaptive_studio/flutter_adaptive_studio.dart';
import 'package:flutter_adaptive_studio/src/raster/svg_rasterizer.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The pure-Dart SVG rasteriser: shapes, fills, strokes, transforms, the
/// background-fill "card", and the end-to-end legacy/store pipeline driven from
/// an SVG (no system tool).
void main() {
  const r = SvgRasterizer();

  test('fills a rect that covers the whole viewBox', () {
    final doc = SvgDocument.parse(
        '<svg viewBox="0 0 100 100"><rect x="0" y="0" width="100" height="100" '
        'fill="#FF0000"/></svg>');
    final im = r.rasterize(doc, 64);
    final c = im.getPixel(32, 32);
    expect(c.r, 255);
    expect(c.g, 0);
    expect(c.b, 0);
    expect(c.a, 255);
  });

  test('background colour shows through transparent areas', () {
    final doc = SvgDocument.parse(
        '<svg viewBox="0 0 100 100"><circle cx="50" cy="50" r="20" '
        'fill="#000000"/></svg>');
    final im = r.rasterize(doc, 64, backgroundArgb: 0xFFFFFF);
    final corner = im.getPixel(2, 2); // outside the circle → white card
    expect(corner.r, 255);
    expect(corner.g, 255);
    expect(corner.b, 255);
    expect(corner.a, 255);
    expect(im.getPixel(32, 32).r, lessThan(20)); // centre is the black circle
  });

  test('no background leaves the area outside shapes transparent', () {
    final doc = SvgDocument.parse(
        '<svg viewBox="0 0 100 100"><circle cx="50" cy="50" r="20" '
        'fill="#3E9AA6"/></svg>');
    final im = r.rasterize(doc, 64);
    expect(im.getPixel(2, 2).a, 0); // transparent corner
    expect(im.getPixel(32, 32).a, 255); // opaque centre
  });

  test('edges are anti-aliased (partial coverage, not a hard cut)', () {
    final doc = SvgDocument.parse(
        '<svg viewBox="0 0 100 100"><circle cx="50" cy="50" r="40" '
        'fill="#000000"/></svg>');
    final im = r.rasterize(doc, 128, backgroundArgb: 0xFFFFFF);
    // Scan a row through the centre; a circle edge must produce a grey pixel
    // (neither pure white bg nor pure black fill).
    var sawPartial = false;
    for (var x = 0; x < im.width; x++) {
      final g = im.getPixel(x, 64).r;
      if (g > 30 && g < 225) {
        sawPartial = true;
        break;
      }
    }
    expect(sawPartial, isTrue);
  });

  test('renders a stroked open path without throwing and paints pixels', () {
    final doc = SvgDocument.parse(
        '<svg viewBox="0 0 100 100"><path d="M20 50 L40 70 L80 30" fill="none" '
        'stroke="#123456" stroke-width="8"/></svg>');
    final im = r.rasterize(doc, 64);
    var painted = 0;
    for (final px in im) {
      if (px.a > 0) painted++;
    }
    expect(painted, greaterThan(0));
  });

  test('applies group transforms', () {
    // Same 10×10 rect, translated +40,+40 by a group → lands in the lower half.
    final doc = SvgDocument.parse(
        '<svg viewBox="0 0 100 100"><g transform="translate(40 40)">'
        '<rect x="0" y="0" width="10" height="10" fill="#FF0000"/></g></svg>');
    final im = r.rasterize(doc, 100);
    expect(im.getPixel(45, 45).a, 255); // translated location is painted
    expect(im.getPixel(5, 5).a, 0); // original (untranslated) location is empty
  });

  test('SVG foreground drives legacy mipmaps + store icon (no PNG, no tool)',
      () {
    final project = Directory.systemTemp.createTempSync('fas_svg_');
    addTearDown(() => project.deleteSync(recursive: true));

    final main = p.join(project.path, 'android', 'app', 'src', 'main');
    File(p.join(main, 'AndroidManifest.xml'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
          '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
          '<application android:icon="@mipmap/ic_launcher"/></manifest>');
    File(p.join(project.path, 'assets', 'logo.svg'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('<svg viewBox="0 0 100 100">'
          '<rect x="15" y="15" width="70" height="70" rx="12" fill="#3E9AA6"/>'
          '</svg>');
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    icon:
      adaptive:
        foreground: assets/logo.svg
        background: "#FFFFFF"
        safe_zone: none
      legacy: true
      play_store: true
''');

    AdaptiveStudio(
      projectRoot: project.path,
      logger: Logger(level: LogLevel.quiet),
    ).run();

    final png = File(p.join(main, 'res', 'mipmap-xxxhdpi', 'ic_launcher.png'));
    expect(png.existsSync(), isTrue);
    final im = img.decodeImage(png.readAsBytesSync())!;
    expect(im.width, 192);
    expect(im.getPixel(96, 96).a, 255); // centre painted (teal over white card)
    expect(File(p.join(main, 'ic_launcher-playstore.png')).existsSync(), isTrue,
        reason: 'Play Store icon lives in src/main');

    // Regression: the flat teal interior must stay flat — no box-average grid
    // (rendering per-density directly instead of resizing a master). A 16×16
    // interior patch of a solid fill should be a single colour.
    final colors = <String>{};
    for (var y = 88; y < 104; y++) {
      for (var x = 88; x < 104; x++) {
        final px = im.getPixel(x, y);
        colors.add('${px.r},${px.g},${px.b}');
      }
    }
    expect(colors.length, lessThanOrEqualTo(2),
        reason: 'flat fill should not show a resampling grid: $colors');
  });
}

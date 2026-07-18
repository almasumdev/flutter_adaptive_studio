import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// `safe_zone: as_is` keeps the foreground source's own framing: the whole
/// viewBox (SVG) or full bitmap (raster) is mapped into the safe square, so the
/// art's authored padding survives instead of being trimmed. Every other mode
/// (`fit`/`inset`/`none`) measures the real art and trims that padding.
void main() {
  late Directory project;
  String res(String rel) =>
      p.join(project.path, 'android', 'app', 'src', 'main', 'res', rel);
  File cfg() => File(p.join(project.path, 'flutter_adaptive_studio.yaml'));

  setUp(() {
    project = Directory.systemTemp.createTempSync('fas_safezone_');
    final main = p.join(project.path, 'android', 'app', 'src', 'main');
    File(p.join(main, 'AndroidManifest.xml'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
          '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
          '<application android:icon="@mipmap/ic_launcher"/></manifest>');
    Directory(p.join(project.path, 'assets')).createSync();
    // A 40x40 mark centred in a 100x100 viewBox: 30 units of padding all round.
    File(p.join(project.path, 'assets', 'logo.svg')).writeAsStringSync(
        '<svg viewBox="0 0 100 100">'
        '<rect x="30" y="30" width="40" height="40" fill="#123456"/></svg>');
    // The same shape as a padded raster: a 40x40 opaque square inside a 100x100
    // transparent canvas.
    final png = img.Image(width: 100, height: 100, numChannels: 4);
    img.fillRect(png,
        x1: 30, y1: 30, x2: 69, y2: 69, color: img.ColorRgba8(18, 52, 86, 255));
    File(p.join(project.path, 'assets', 'logo.png'))
        .writeAsBytesSync(img.encodePng(png));
  });

  tearDown(() => project.deleteSync(recursive: true));

  void gen(String source, String safeZone) {
    cfg().writeAsStringSync('''
flutter_adaptive_studio:
  android:
    icon:
      adaptive:
        foreground: $source
        background: "#EEEEEE"
        safe_zone: $safeZone
''');
    AdaptiveStudio(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();
  }

  String genForegroundVd(String source, String safeZone) {
    gen(source, safeZone);
    return File(res('drawable/ic_launcher_foreground.xml')).readAsStringSync();
  }

  double scaleX(String vd) {
    final m = RegExp(r'scaleX="([\d.]+)"').firstMatch(vd);
    return m == null ? 1.0 : double.parse(m.group(1)!);
  }

  test('SVG as_is maps the whole viewBox (scale = safeSquare / viewBox)', () {
    final asIs = genForegroundVd('assets/logo.svg', 'as_is');
    // 72dp safe square / 100-unit viewBox longest side = 0.72.
    expect(scaleX(asIs), closeTo(72 / 100, 0.01));
  });

  test('SVG as_is keeps the padding, so the art is smaller than fit', () {
    final fit = scaleX(genForegroundVd('assets/logo.svg', 'fit'));
    final asIs = scaleX(genForegroundVd('assets/logo.svg', 'as_is'));
    // `fit` trims the 30-unit padding and scales the 40-unit mark up to the safe
    // zone; `as_is` scales the whole 100-unit viewBox, so it comes out smaller.
    expect(asIs, lessThan(fit));
  });

  test('raster as_is keeps transparent margins; fit trims them', () {
    // Regenerate for each mode and measure the opaque content in a density PNG.
    int contentWidth(String safeZone) {
      gen('assets/logo.png', safeZone);
      final png = img.decodeImage(
          File(res('drawable-xxhdpi/ic_launcher_foreground.png'))
              .readAsBytesSync())!;
      final t = img.findTrim(png, mode: img.TrimMode.transparent);
      return t[2];
    }

    final fitW = contentWidth('fit');
    final asIsW = contentWidth('as_is');
    // `fit` trims the transparent border so the 40x40 mark fills the safe zone;
    // `as_is` keeps the border, so the same mark lands markedly smaller.
    expect(asIsW, lessThan(fitW));
  });

  // ---- The legacy/store foreground is the SAME size as the adaptive
  //      foreground, for every safe_zone mode (as_is must fill the safe square,
  //      not the whole tile). ----

  String mainFile(String rel) =>
      p.join(project.path, 'android', 'app', 'src', 'main', rel);

  void genRaster(String safeZone) {
    cfg().writeAsStringSync('''
flutter_adaptive_studio:
  android:
    icon:
      legacy: true
      play_store: true
      adaptive:
        foreground: assets/logo.svg
        background: "#FFFFFF"
        safe_zone: $safeZone
        foreground_format: raster
''');
    AdaptiveStudio(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();
  }

  /// Horizontal fraction of the dark (#123456) mark in [im].
  double markFraction(img.Image im) {
    var minX = im.width, maxX = -1;
    for (var y = 0; y < im.height; y++) {
      for (var x = 0; x < im.width; x++) {
        final px = im.getPixel(x, y);
        if (px.a > 200 && px.r < 100 && px.g < 100) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
        }
      }
    }
    return maxX < 0 ? 0 : (maxX - minX + 1) / im.width;
  }

  for (final mode in const ['as_is', 'fit', 'none']) {
    test(
        '$mode: the Play Store foreground matches the adaptive foreground size',
        () {
      genRaster(mode);
      final fg = markFraction(img.decodeImage(
          File(res('drawable-xxhdpi/ic_launcher_foreground.png'))
              .readAsBytesSync())!);
      final store = markFraction(img.decodeImage(
          File(mainFile('ic_launcher-playstore.png')).readAsBytesSync())!);
      expect(fg, greaterThan(0), reason: 'the mark should be present');
      expect(store, closeTo(fg, 0.04),
          reason: '$mode must scale the mark the same in the adaptive '
              'foreground and the Play Store icon');
    });
  }
}

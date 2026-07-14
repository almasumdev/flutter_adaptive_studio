import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// `foreground_format: raster` bakes an SVG adaptive foreground to per-density
/// PNGs (gradients/clips rendered into pixels) instead of a VectorDrawable, so
/// gradient art renders in previewers and non-Android targets that don't resolve
/// VectorDrawable `aapt:attr` gradients.
void main() {
  late Directory project;
  String res(String rel) =>
      p.join(project.path, 'android', 'app', 'src', 'main', 'res', rel);

  setUp(() {
    project = Directory.systemTemp.createTempSync('fas_fgfmt_');
    final main = p.join(project.path, 'android', 'app', 'src', 'main');
    File(p.join(main, 'AndroidManifest.xml'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
          '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
          '<application android:icon="@mipmap/ic_launcher"/></manifest>');
    Directory(p.join(project.path, 'assets')).createSync();
    // A gradient-filled circle (the case VD renders only via aapt:attr).
    File(p.join(project.path, 'assets', 'logo.svg')).writeAsStringSync(
        '<svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">'
        '<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="100" '
        'gradientUnits="userSpaceOnUse">'
        '<stop offset="0" stop-color="#FF0000"/>'
        '<stop offset="1" stop-color="#0000FF"/></linearGradient></defs>'
        '<circle cx="50" cy="50" r="45" fill="url(#g)"/></svg>');
  });

  tearDown(() => project.deleteSync(recursive: true));

  void gen(String format) {
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    icon:
      adaptive:
        foreground: assets/logo.svg
        background: "#FFFFFF"
        foreground_format: $format
''');
    AdaptiveStudio(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();
  }

  test('raster: density PNGs, no foreground VectorDrawable, adaptive ref', () {
    gen('raster');
    // Per-density PNGs written, no drawable/*.xml vector for the foreground.
    expect(File(res('drawable-mdpi/ic_launcher_foreground.png')).existsSync(),
        isTrue);
    expect(
        File(res('drawable-xxxhdpi/ic_launcher_foreground.png')).existsSync(),
        isTrue);
    expect(
        File(res('drawable/ic_launcher_foreground.xml')).existsSync(), isFalse);
    // The adaptive XML still references the same drawable name.
    final xml =
        File(res('mipmap-anydpi-v26/ic_launcher.xml')).readAsStringSync();
    expect(xml, contains('@drawable/ic_launcher_foreground'));
  });

  test('raster: the gradient is baked into the pixels', () {
    gen('raster');
    final png = img.decodeImage(
        File(res('drawable-xxhdpi/ic_launcher_foreground.png'))
            .readAsBytesSync())!;
    // Top of the circle is red-dominant, bottom is blue-dominant (the gradient),
    // proving it was rendered, not dropped.
    img.Pixel firstOpaque(int x, int step) {
      for (var y = step > 0 ? 0 : png.height - 1;
          y >= 0 && y < png.height;
          y += step) {
        final px = png.getPixel(x, y);
        if (px.a > 200) return px;
      }
      return png.getPixel(x, png.height ~/ 2);
    }

    final top = firstOpaque(png.width ~/ 2, 1);
    final bottom = firstOpaque(png.width ~/ 2, -1);
    expect(top.r, greaterThan(top.b), reason: 'top is red');
    expect(bottom.b, greaterThan(bottom.r), reason: 'bottom is blue');
  });

  test('vector (default): still emits a VectorDrawable, no density PNGs', () {
    gen('vector');
    expect(
        File(res('drawable/ic_launcher_foreground.xml')).existsSync(), isTrue);
    expect(File(res('drawable-mdpi/ic_launcher_foreground.png')).existsSync(),
        isFalse);
  });
}

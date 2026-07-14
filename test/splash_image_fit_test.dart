import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// `image_fit` controls how the centre splash logo is framed. `auto` (default)
/// measures the real art and fills the Android-12 safe circle, trimming the
/// source's own padding; `as_is` keeps the whole viewBox (SVG) or full bitmap
/// (raster), so authored padding survives and the logo can sit smaller.
void main() {
  late Directory project;
  String res(String rel) =>
      p.join(project.path, 'android', 'app', 'src', 'main', 'res', rel);
  File cfg() => File(p.join(project.path, 'flutter_adaptive_studio.yaml'));

  setUp(() {
    project = Directory.systemTemp.createTempSync('fas_imgfit_');
    final main = p.join(project.path, 'android', 'app', 'src', 'main');
    File(p.join(main, 'AndroidManifest.xml'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
          '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
          '<application android:icon="@mipmap/ic_launcher"/></manifest>');
    Directory(p.join(project.path, 'assets')).createSync();
    // 40x40 mark centred in a 100x100 viewBox: 30 units of padding all round.
    File(p.join(project.path, 'assets', 'logo.svg')).writeAsStringSync(
        '<svg viewBox="0 0 100 100">'
        '<rect x="30" y="30" width="40" height="40" fill="#123456"/></svg>');
    // The same shape as a padded raster: a 100x100 opaque square inside a
    // 200x200 transparent canvas.
    final png = img.Image(width: 200, height: 200, numChannels: 4);
    img.fillRect(png,
        x1: 50,
        y1: 50,
        x2: 149,
        y2: 149,
        color: img.ColorRgba8(18, 52, 86, 255));
    File(p.join(project.path, 'assets', 'logo.png'))
        .writeAsBytesSync(img.encodePng(png));
  });

  tearDown(() => project.deleteSync(recursive: true));

  void gen(String source, String imageFit) {
    cfg().writeAsStringSync('''
flutter_adaptive_studio:
  android:
    icon:
      adaptive: {foreground: assets/logo.svg, background: "#EEEEEE"}
    splash:
      background: "#EEEEEE"
      image: $source
      image_fit: $imageFit
''');
    AdaptiveStudio(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();
  }

  double scaleX(String vd) {
    final m = RegExp(r'scaleX="([\d.]+)"').firstMatch(vd);
    return m == null ? 1.0 : double.parse(m.group(1)!);
  }

  test('SVG as_is fits the whole viewBox into the safe circle', () {
    gen('assets/logo.svg', 'as_is');
    final vd = File(res('drawable/splash_icon.xml')).readAsStringSync();
    // No icon background → 288 canvas, ⌀192 safe circle. as_is fits the 100-unit
    // viewBox longest side to 192: scale = 1.92.
    expect(scaleX(vd), closeTo(192 / 100, 0.02));
  });

  test('SVG as_is keeps the padding, so the logo is smaller than auto', () {
    gen('assets/logo.svg', 'auto');
    final autoS =
        scaleX(File(res('drawable/splash_icon.xml')).readAsStringSync());
    gen('assets/logo.svg', 'as_is');
    final asIsS =
        scaleX(File(res('drawable/splash_icon.xml')).readAsStringSync());
    // auto inscribes the trimmed 40x40 art's diagonal in ⌀192 (big scale);
    // as_is scales the whole 100-unit viewBox, so it is markedly smaller.
    expect(asIsS, lessThan(autoS));
  });

  test('raster as_is keeps the transparent margin; auto trims it', () {
    gen('assets/logo.png', 'auto');
    final autoPng = img.decodeImage(
        File(res('drawable-nodpi/splash_icon.png')).readAsBytesSync())!;
    gen('assets/logo.png', 'as_is');
    final asIsPng = img.decodeImage(
        File(res('drawable-nodpi/splash_icon.png')).readAsBytesSync())!;
    // auto trims the 50px border → the 100x100 mark; as_is keeps the full 200².
    expect(autoPng.width, 100);
    expect(asIsPng.width, 200);
  });
}

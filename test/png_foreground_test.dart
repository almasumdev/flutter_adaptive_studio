import 'dart:io';

import 'package:flutter_adaptive_studio/flutter_adaptive_studio.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A PNG (raster) adaptive foreground should produce density-bucketed,
/// safe-zone-fit foreground PNGs — not be rejected.
void main() {
  test('raster foreground → density PNGs + adaptive xml reference', () {
    final project = Directory.systemTemp.createTempSync('fas_png_');
    addTearDown(() => project.deleteSync(recursive: true));

    final main = p.join(project.path, 'android', 'app', 'src', 'main');
    File(p.join(main, 'AndroidManifest.xml'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
          '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
          '<application android:icon="@mipmap/ic_launcher"/></manifest>');

    // A 96×96 opaque logo.
    final logo = img.Image(width: 96, height: 96, numChannels: 4)
      ..clear(img.ColorRgba8(62, 154, 166, 255));
    File(p.join(project.path, 'assets', 'logo.png'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(img.encodePng(logo));

    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    icon:
      adaptive:
        foreground: assets/logo.png
        background: "#E4ECE8"
        safe_zone: fit
''');

    final report = AdaptiveStudio(
      projectRoot: project.path,
      logger: Logger(level: LogLevel.quiet),
    ).run();
    expect(report, isNotNull);

    String res(String rel) => p.join(main, 'res', rel);
    // Density PNGs written and sized to the 108dp layer canvas.
    expect(File(res('drawable-mdpi/ic_launcher_foreground.png')).existsSync(),
        isTrue);
    final xxh = File(res('drawable-xxhdpi/ic_launcher_foreground.png'));
    expect(xxh.existsSync(), isTrue);
    final decoded = img.decodeImage(xxh.readAsBytesSync())!;
    expect(decoded.width, 108 * 3); // 324px canvas

    // The art is fit to the 72dp safe zone, so corners are transparent.
    expect(decoded.getPixel(0, 0).a, 0);

    // Adaptive XML references the foreground drawable.
    final xml =
        File(res('mipmap-anydpi-v26/ic_launcher.xml')).readAsStringSync();
    expect(xml, contains('@drawable/ic_launcher_foreground'));
  });
}

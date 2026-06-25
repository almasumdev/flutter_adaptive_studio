import 'dart:io';

import 'package:flutter_adaptive_studio/flutter_adaptive_studio.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// `icon.legacy_padding` tunes the inset of the composed legacy/store art
/// independently of `adaptive.safe_zone`. Holding the safe zone constant, a
/// larger `legacy_padding` must shrink the art inside the legacy mipmap.
void main() {
  /// Generates a legacy `ic_launcher.png` (xxxhdpi) from a full-bleed red logo
  /// on a white background and returns how many red (art) pixels it contains.
  int redPixelsFor(int? legacyPadding) {
    final project = Directory.systemTemp.createTempSync('fas_legacypad_');
    addTearDown(() => project.deleteSync(recursive: true));

    final main = p.join(project.path, 'android', 'app', 'src', 'main');
    File(p.join(main, 'AndroidManifest.xml'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
          '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
          '<application android:icon="@mipmap/ic_launcher"/></manifest>');

    File(p.join(project.path, 'assets', 'logo.svg'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
          '<svg viewBox="0 0 100 100"><rect width="100" height="100" '
          'fill="#FF0000"/></svg>');

    final padLine =
        legacyPadding == null ? '' : '      legacy_padding: $legacyPadding\n';
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    icon:
      legacy: true
$padLine      adaptive:
        foreground: assets/logo.svg
        background: "#FFFFFF"
        safe_zone: fit
''');

    AdaptiveStudio(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();

    final png = File(p.join(main, 'res', 'mipmap-xxxhdpi', 'ic_launcher.png'));
    expect(png.existsSync(), isTrue, reason: 'legacy mipmap should be emitted');
    final image = img.decodeImage(png.readAsBytesSync())!;

    var red = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final px = image.getPixel(x, y);
        if (px.r > 200 && px.g < 80 && px.b < 80) red++;
      }
    }
    return red;
  }

  test('larger legacy_padding shrinks the composed art', () {
    final tight = redPixelsFor(5); // almost full-bleed art
    final loose = redPixelsFor(40); // heavily inset art
    expect(tight, greaterThan(0));
    expect(loose, greaterThan(0));
    expect(loose, lessThan(tight),
        reason: 'more legacy_padding must leave less art in the tile');
  });

  test('legacy_padding overrides the adaptive safe zone', () {
    // safe_zone is `fit` (≈15%) in both runs; only legacy_padding differs, so
    // any change in the art size proves the override is what took effect.
    final viaDefault = redPixelsFor(null); // follows the safe zone (~15%)
    final viaOverride = redPixelsFor(45); // far more inset than the safe zone
    expect(viaOverride, lessThan(viaDefault));
  });
}

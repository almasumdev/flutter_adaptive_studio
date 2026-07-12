import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// `play_store_padding` insets the 512² Play Store PNG on its own, without
/// touching the legacy mipmaps (which keep following `legacy_padding` /
/// `safe_zone`).
void main() {
  late Directory project;
  String mainFile(String rel) =>
      p.join(project.path, 'android', 'app', 'src', 'main', rel);
  File cfg() => File(p.join(project.path, 'flutter_adaptive_studio.yaml'));

  setUp(() {
    project = Directory.systemTemp.createTempSync('fas_pspad_');
    Directory(p.join(project.path, 'android', 'app', 'src', 'main'))
        .createSync(recursive: true);
    File(mainFile('AndroidManifest.xml')).writeAsStringSync(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '  <application android:icon="@mipmap/ic_launcher"/>\n'
        '</manifest>\n');
    Directory(p.join(project.path, 'assets')).createSync();
    // A full-bleed red mark on the (white) icon background, so the inset is
    // directly measurable as the red area's width in the 512 canvas.
    File(p.join(project.path, 'assets', 'logo.svg')).writeAsStringSync(
        '<svg viewBox="0 0 100 100">'
        '<rect x="0" y="0" width="100" height="100" fill="#FF0000"/></svg>');
  });

  tearDown(() => project.deleteSync(recursive: true));

  void gen(String extraIconLines) {
    cfg().writeAsStringSync('''
flutter_adaptive_studio:
  android:
    icon:
      play_store: true
      adaptive:
        foreground: assets/logo.svg
        background: "#FFFFFF"
$extraIconLines
''');
    AdaptiveStudio(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();
  }

  /// Width fraction (0..1) of the non-white art in the Play Store PNG.
  double artWidthFraction() {
    final im = img.decodeImage(
        File(mainFile('ic_launcher-playstore.png')).readAsBytesSync())!;
    var minX = im.width, maxX = -1;
    for (var y = 0; y < im.height; y++) {
      for (var x = 0; x < im.width; x++) {
        // The red mark drives the green channel well below the white surround.
        if (im.getPixel(x, y).g < 200) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
        }
      }
    }
    return maxX < 0 ? 0 : (maxX - minX + 1) / im.width;
  }

  test('play_store_padding changes the store icon but not the legacy mipmaps',
      () {
    gen('      legacy: true');
    final storeDefault =
        File(mainFile('ic_launcher-playstore.png')).readAsBytesSync();
    final mipmapDefault =
        File(mainFile('res/mipmap-xxxhdpi/ic_launcher.png')).readAsBytesSync();

    gen('      legacy: true\n      play_store_padding: 40');
    final storePadded =
        File(mainFile('ic_launcher-playstore.png')).readAsBytesSync();
    final mipmapPadded =
        File(mainFile('res/mipmap-xxxhdpi/ic_launcher.png')).readAsBytesSync();

    // The Play Store icon was re-inset...
    expect(storePadded, isNot(equals(storeDefault)));
    // ...while the legacy mipmap is byte-identical: the padding is independent.
    expect(mipmapPadded, equals(mipmapDefault));
  });

  test('a larger play_store_padding shrinks the Play Store art', () {
    gen('      play_store_padding: 10');
    final small = artWidthFraction();
    gen('      play_store_padding: 45');
    final large = artWidthFraction();

    expect(large, lessThan(small));
    // 45% padding leaves the mark filling roughly 55% of the canvas.
    expect(large, closeTo(0.55, 0.06));
  });
}

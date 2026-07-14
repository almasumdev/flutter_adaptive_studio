import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The splash centre icon is emitted as a vector (`drawable/splash_icon.xml`)
/// from an SVG, or a `drawable-nodpi/splash_icon.png` raster from a bitmap.
/// Switching the source between the two forms must delete the previous form,
/// because a `nodpi` raster WINS Android resource resolution over a plain
/// `drawable/` vector: a stale `drawable-nodpi/splash_icon.png` left behind would
/// keep rendering as the splash no matter what the new `.xml` contains.
void main() {
  late Directory project;
  String res(String rel) =>
      p.join(project.path, 'android', 'app', 'src', 'main', 'res', rel);

  setUp(() {
    project = Directory.systemTemp.createTempSync('fas_stale_');
    Directory(p.join(project.path, 'android', 'app', 'src', 'main'))
        .createSync(recursive: true);
    File(p.join(project.path, 'android', 'app', 'src', 'main',
            'AndroidManifest.xml'))
        .writeAsStringSync(
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
            '<application android:icon="@mipmap/ic_launcher"/></manifest>');
    // A raster splash image and an SVG splash image to switch between.
    final assets = Directory(p.join(project.path, 'assets'))
      ..createSync(recursive: true);
    final png = img.Image(width: 64, height: 64, numChannels: 4);
    img.fill(png, color: img.ColorRgba8(255, 0, 0, 255));
    File(p.join(assets.path, 'logo.png')).writeAsBytesSync(img.encodePng(png));
    File(p.join(assets.path, 'logo.svg')).writeAsStringSync(
        '<svg viewBox="0 0 100 100"><circle cx="50" cy="50" r="40" '
        'fill="#3355FF"/></svg>');
  });

  tearDown(() => project.deleteSync(recursive: true));

  void generate(String image) {
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    splash:
      background: "#FFFFFF"
      image: $image
''');
    AdaptiveStudio(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();
  }

  test('switching a raster splash image to an SVG removes the stale nodpi PNG',
      () {
    generate('assets/logo.png');
    expect(File(res(p.join('drawable-nodpi', 'splash_icon.png'))).existsSync(),
        isTrue,
        reason: 'a raster splash image writes the nodpi PNG');

    generate('assets/logo.svg');
    expect(
        File(res(p.join('drawable', 'splash_icon.xml'))).existsSync(), isTrue,
        reason: 'an SVG splash image writes the vector');
    expect(File(res(p.join('drawable-nodpi', 'splash_icon.png'))).existsSync(),
        isFalse,
        reason: 'the stale nodpi PNG must be removed so it cannot shadow the '
            'new vector in resource resolution');
  });

  test('switching an SVG splash image to a raster removes the stale vector XML',
      () {
    generate('assets/logo.svg');
    expect(
        File(res(p.join('drawable', 'splash_icon.xml'))).existsSync(), isTrue);

    generate('assets/logo.png');
    expect(File(res(p.join('drawable-nodpi', 'splash_icon.png'))).existsSync(),
        isTrue);
    expect(
        File(res(p.join('drawable', 'splash_icon.xml'))).existsSync(), isFalse,
        reason: 'the stale vector must be removed when a raster replaces it');
  });
}

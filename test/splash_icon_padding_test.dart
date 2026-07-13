import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_adaptive_studio/generator.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// `icon_padding` insets the **native** splash icon (the API 31+ VectorDrawable
/// and the pre-31 raster), independent of the in-app `logo_padding`. A safe
/// default inset kicks in when `icon_background` is set, because the OS then
/// renders the icon through the adaptive-icon pipeline (scaled up + masked to
/// the launcher shape) and a tall logo drawn to the raw keyline gets clipped.
void main() {
  late Directory project;
  String mainRes(String rel) =>
      p.join(project.path, 'android', 'app', 'src', 'main', 'res', rel);

  setUp(() {
    project = Directory.systemTemp.createTempSync('fas_iconpad_');
    Directory(p.join(project.path, 'android', 'app', 'src', 'main'))
        .createSync(recursive: true);
    File(p.join(project.path, 'android', 'app', 'src', 'main',
            'AndroidManifest.xml'))
        .writeAsStringSync(
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
            '<application android:icon="@mipmap/ic_launcher"/></manifest>');
    // A tall mark (aspect 0.3): its height dominates the keyline, so any inset
    // is directly measurable as a smaller scale.
    File(p.join(project.path, 'assets', 'tall.svg'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('<svg viewBox="0 0 60 200">'
          '<rect x="0" y="0" width="60" height="200" fill="#3355FF"/></svg>');
  });

  tearDown(() => project.deleteSync(recursive: true));

  /// Generates the splash and returns the API 31+ vector's group `scaleX`.
  double vectorScale(String splashLines) {
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    splash:
      background: "#FFFFFF"
      image: assets/tall.svg
$splashLines
''');
    AdaptiveStudio(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();
    final xml =
        File(mainRes(p.join('drawable', 'splash_icon.xml'))).readAsStringSync();
    final m = RegExp(r'scaleX="([\d.]+)"').firstMatch(xml);
    expect(m, isNotNull, reason: 'expected a scaled group in splash_icon.xml');
    return double.parse(m!.group(1)!);
  }

  test(
      'icon_background applies a safe default inset (smaller than raw keyline)',
      () {
    final raw = vectorScale('      icon_background: "#EEEEEE"\n'
        '      icon_padding: 0');
    final defaulted = vectorScale('      icon_background: "#EEEEEE"');
    expect(defaulted, lessThan(raw),
        reason: 'a backgrounded splash icon must inset by default');
    // Default is 40%: the scale should be ~0.6x the un-inset keyline scale.
    expect(defaulted / raw, closeTo(0.6, 0.02));
  });

  test('icon_padding: 0 opts out of the default inset', () {
    // With no background there is no default inset, so padding 0 == unset.
    final unset = vectorScale('');
    final zero = vectorScale('      icon_padding: 0');
    expect(zero, closeTo(unset, 1e-6));
  });

  test('a larger icon_padding shrinks the native splash icon further', () {
    final small = vectorScale('      icon_padding: 10');
    final large = vectorScale('      icon_padding: 50');
    expect(large, lessThan(small));
  });

  test('no icon_background leaves the keyline un-inset by default', () {
    // 288 canvas, ⌀192 keyline, no default inset: the tall mark's bounding-box
    // diagonal is inscribed in ⌀192, so scale == 192 / diagonal(60, 200).
    final scale = vectorScale('');
    final diagonal = math.sqrt(60 * 60 + 200 * 200);
    expect(scale, closeTo(192 / diagonal, 0.001),
        reason: 'raw keyline inscribes the bbox diagonal in ⌀192');
  });

  test('the pre-31 raster shrinks with icon_padding too', () {
    int artHeight() {
      final png = img.decodeImage(
          File(mainRes(p.join('drawable-xxxhdpi', 'splash_icon_legacy.png')))
              .readAsBytesSync())!;
      var minY = png.height, maxY = -1;
      for (var y = 0; y < png.height; y++) {
        for (var x = 0; x < png.width; x++) {
          if (png.getPixel(x, y).a > 16) {
            if (y < minY) minY = y;
            if (y > maxY) maxY = y;
          }
        }
      }
      return maxY - minY + 1;
    }

    vectorScale('      icon_padding: 10');
    final small = artHeight();
    vectorScale('      icon_padding: 60');
    final large = artHeight();
    expect(large, lessThan(small),
        reason: 'more icon_padding => less art in the pre-31 raster');
  });
}

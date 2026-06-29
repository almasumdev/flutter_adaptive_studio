import 'dart:convert';
import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The in-app splash logo is sized to the **native splash keyline** (the art's
/// bbox inscribed in the 2/3 safe circle of a 288 dp canvas, or 240 dp / ⌀160
/// when an `icon_background` is set), and `logo_padding` insets it further. The
/// in-app splash also holds only where there's no native splash to hand off
/// from (Android < 31) unless opted into all versions.
void main() {
  /// Generates an in-app splash from a square logo and returns the generated
  /// `fas_splash.g.dart` source.
  String generate(String splashYaml) {
    final project = Directory.systemTemp.createTempSync('fas_logosize_');
    addTearDown(() {
      if (project.existsSync()) project.deleteSync(recursive: true);
    });
    Directory(p.join(project.path, 'android', 'app', 'src', 'main'))
        .createSync(recursive: true);
    File(p.join(project.path, 'assets', 'logo.svg'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('<svg viewBox="0 0 100 100"><rect x="20" y="20" '
          'width="60" height="60" rx="8" fill="#3e9aa6"/></svg>');
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync(splashYaml);

    AdaptiveStudio(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();
    // No lib/ here, so the config lands at the project root.
    final lib = File(p.join(project.path, 'lib', 'fas_splash.g.dart'));
    final root = File(p.join(project.path, 'fas_splash.g.dart'));
    return (lib.existsSync() ? lib : root).readAsStringSync();
  }

  /// Non-transparent pixel count of the embedded `logo: _b64('…')` art.
  int logoArtPixels(String cfg) {
    final m = RegExp(r"logo: _b64\('([^']*)'\)").firstMatch(cfg);
    expect(m, isNotNull, reason: 'expected an embedded logo');
    final png = img.decodeImage(base64Decode(m!.group(1)!))!;
    var n = 0;
    for (var y = 0; y < png.height; y++) {
      for (var x = 0; x < png.width; x++) {
        if (png.getPixel(x, y).a > 8) n++;
      }
    }
    return n;
  }

  test('logo box matches the native keyline canvas — 288 dp by default', () {
    final cfg = generate('''
flutter_adaptive_studio:
  android:
    splash:
      background: "#FFFFFF"
      image: assets/logo.svg
''');
    expect(cfg, contains('logoSize: 288'));
  });

  test('an icon_background switches the canvas to 240 dp (⌀160 keyline)', () {
    final cfg = generate('''
flutter_adaptive_studio:
  android:
    splash:
      background: "#FFFFFF"
      icon_background: "#FFFFFF"
      image: assets/logo.svg
''');
    expect(cfg, contains('logoSize: 240'));
  });

  test('logo_padding insets the embedded logo art (less art than 0)', () {
    String yaml(int pad) => '''
flutter_adaptive_studio:
  android:
    splash:
      background: "#FFFFFF"
      image: assets/logo.svg
      logo_padding: $pad
''';
    final tight = logoArtPixels(generate(yaml(0)));
    final loose = logoArtPixels(generate(yaml(40)));
    expect(tight, greaterThan(0));
    expect(loose, greaterThan(0));
    expect(loose, lessThan(tight),
        reason: 'more logo_padding must leave less art');
  });

  test('the baked-in gate holds only on confirmed Android < 31', () {
    final cfg = generate('''
flutter_adaptive_studio:
  android:
    splash:
      background: "#FFFFFF"
      image: assets/logo.svg
''');
    // New gate: iOS / unknown SDK (null) does NOT hold by default.
    expect(cfg, contains('sdk != null && sdk < 31'));
    expect(cfg, isNot(contains('sdk == null || sdk < 31')));
  });
}

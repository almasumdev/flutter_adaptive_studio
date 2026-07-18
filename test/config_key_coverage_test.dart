import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Behavioural coverage for config keys the audit flagged as wired-but-untested:
/// `splash.gravity` (incl. the `fill` fix), `icon.effect`, `icon.icon_name`,
/// and `android.min_sdk` legacy gating.
void main() {
  late Directory project;
  String mainDir(String rel) =>
      p.join(project.path, 'android', 'app', 'src', 'main', rel);
  File cfg() => File(p.join(project.path, 'flutter_adaptive_studio.yaml'));

  setUp(() {
    project = Directory.systemTemp.createTempSync('fas_keycov_');
    File(mainDir('AndroidManifest.xml'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
          '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
          '<application android:icon="@mipmap/ic_launcher"/></manifest>');
    Directory(p.join(project.path, 'assets')).createSync();
    File(p.join(project.path, 'assets', 'logo.svg')).writeAsStringSync(
        '<svg viewBox="0 0 100 100"><rect x="20" y="20" width="60" '
        'height="60" fill="#123456"/></svg>');
  });

  tearDown(() => project.deleteSync(recursive: true));

  void gen(String yaml) {
    cfg().writeAsStringSync(yaml);
    AdaptiveStudio(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();
  }

  /// Concatenates every emitted drawable XML (any density), so a test can assert
  /// on the pre-31 windowBackground layer-list without hard-coding its filename.
  String allDrawableXml() {
    final sb = StringBuffer();
    final res = Directory(mainDir('res'));
    if (!res.existsSync()) return '';
    for (final f in res.listSync(recursive: true)) {
      if (f is File && f.path.endsWith('.xml')) {
        sb.writeln(f.readAsStringSync());
      }
    }
    return sb.toString();
  }

  group('splash.gravity', () {
    String splashCfg(String gravity) => '''
flutter_adaptive_studio:
  android:
    splash:
      background: "#FFFFFF"
      image: assets/logo.svg
      gravity: $gravity
''';

    test('a positional gravity pins the logo to the 192dp box', () {
      gen(splashCfg('center'));
      final xml = allDrawableXml();
      expect(xml, contains('android:gravity="center"'));
      expect(xml, contains('android:width="192dp"'),
          reason: 'a positional gravity keeps the fixed logo box');
    });

    test('gravity: fill drops the fixed box so the logo can stretch', () {
      gen(splashCfg('fill'));
      final xml = allDrawableXml();
      expect(xml, contains('android:gravity="fill"'));
      expect(xml, isNot(contains('192dp')),
          reason: 'fill must not pin width/height, or it cannot stretch');
    });

    test('gravity: fill_horizontal drops only the width', () {
      gen(splashCfg('fill_horizontal'));
      final xml = allDrawableXml();
      expect(xml, contains('android:gravity="fill_horizontal"'));
      expect(xml, isNot(contains('android:width="192dp"')),
          reason: 'fill_horizontal frees the width');
      expect(xml, contains('android:height="192dp"'),
          reason: 'but keeps the height pinned');
    });
  });

  group('icon.icon_name', () {
    test('a custom icon_name drives the emitted resource names + manifest', () {
      gen('''
flutter_adaptive_studio:
  android:
    icon:
      icon_name: brand_mark
      adaptive:
        foreground: assets/logo.svg
        background: "#FFFFFF"
''');
      expect(File(mainDir('res/mipmap-anydpi-v26/brand_mark.xml')).existsSync(),
          isTrue,
          reason: 'the adaptive XML uses the custom name');
      expect(
          File(mainDir('res/drawable/brand_mark_foreground.xml')).existsSync(),
          isTrue,
          reason: 'the foreground drawable uses the custom name');
      final manifest = File(mainDir('AndroidManifest.xml')).readAsStringSync();
      expect(manifest, contains('@mipmap/brand_mark'),
          reason: 'the manifest points at the custom icon');
    });
  });

  group('icon.effect', () {
    test('effect: elevate changes the legacy mipmap', () {
      String cfgFor(String effect) => '''
flutter_adaptive_studio:
  android:
    icon:
      legacy: true
      effect: $effect
      adaptive:
        foreground: assets/logo.svg
        background: "#FFFFFF"
''';
      gen(cfgFor('none'));
      final plain =
          File(mainDir('res/mipmap-xxxhdpi/ic_launcher.png')).readAsBytesSync();
      gen(cfgFor('elevate'));
      final elevated =
          File(mainDir('res/mipmap-xxxhdpi/ic_launcher.png')).readAsBytesSync();
      expect(elevated, isNot(equals(plain)),
          reason: 'the elevate drop-shadow must change the mipmap pixels');
    });
  });

  group('android.min_sdk', () {
    // A fresh project per case: min_sdk only *gates* emission, it doesn't prune a
    // legacy PNG a previous run wrote, so reusing one project would leak state.
    bool legacyEmitted(int minSdk) {
      final proj = Directory.systemTemp.createTempSync('fas_minsdk_');
      addTearDown(() => proj.deleteSync(recursive: true));
      final main = p.join(proj.path, 'android', 'app', 'src', 'main');
      File(p.join(main, 'AndroidManifest.xml'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
            '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
            '<application android:icon="@mipmap/ic_launcher"/></manifest>');
      File(p.join(proj.path, 'assets', 'logo.svg'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('<svg viewBox="0 0 100 100"><rect x="20" y="20" '
            'width="60" height="60" fill="#123456"/></svg>');
      File(p.join(proj.path, 'flutter_adaptive_studio.yaml'))
          .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    min_sdk: $minSdk
    icon:
      adaptive:
        foreground: assets/logo.svg
        background: "#FFFFFF"
''');
      AdaptiveStudio(
              projectRoot: proj.path, logger: Logger(level: LogLevel.quiet))
          .run();
      // The pre-26 legacy mipmap is a raster PNG at the density root (adaptive
      // uses mipmap-anydpi-v26 + drawable, not a mipmap-*/ic_launcher.png).
      return File(p.join(main, 'res/mipmap-xxxhdpi/ic_launcher.png'))
          .existsSync();
    }

    test('min_sdk < 26 emits legacy mipmaps; >= 26 suppresses them', () {
      expect(legacyEmitted(21), isTrue,
          reason: 'pre-26 minSdk needs the legacy mipmaps');
      expect(legacyEmitted(26), isFalse,
          reason: 'minSdk 26+ has no need for legacy mipmaps');
    });
  });
}

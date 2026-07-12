import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// `branding_fit` controls how an SVG `branding:` image is framed into the
/// 200x80dp slot: `auto` (default) trims the wordmark and fills the slot;
/// `as_is` maps the whole viewBox, so the SVG's own aspect ratio and inner
/// padding survive.
void main() {
  late Directory project;
  String res(String rel) =>
      p.join(project.path, 'android', 'app', 'src', 'main', 'res', rel);
  File cfg() => File(p.join(project.path, 'flutter_adaptive_studio.yaml'));

  setUp(() {
    project = Directory.systemTemp.createTempSync('fas_brandfit_');
    final main =
        Directory(p.join(project.path, 'android', 'app', 'src', 'main'))
          ..createSync(recursive: true);
    File(p.join(main.path, 'AndroidManifest.xml')).writeAsStringSync(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '  <application android:icon="@mipmap/ic_launcher">\n'
        '    <activity android:name=".MainActivity" android:exported="true">\n'
        '      <intent-filter>\n'
        '        <action android:name="android.intent.action.MAIN"/>\n'
        '        <category android:name="android.intent.category.LAUNCHER"/>\n'
        '      </intent-filter>\n'
        '    </activity>\n'
        '  </application>\n'
        '</manifest>\n');
    // Branding SVG with deliberate inner padding: a 160x60 mark centred in a
    // 200x100 viewBox (a 20-unit margin all round).
    Directory(p.join(project.path, 'assets')).createSync();
    File(p.join(project.path, 'assets', 'wordmark.svg')).writeAsStringSync(
        '<svg viewBox="0 0 200 100">'
        '<rect x="20" y="20" width="160" height="60" fill="#123456"/></svg>');
  });

  tearDown(() => project.deleteSync(recursive: true));

  String genBranding(String fit) {
    cfg().writeAsStringSync('''
flutter_adaptive_studio:
  android:
    icon:
      adaptive: {foreground: assets/wordmark.svg, background: "#EEEEEE"}
    splash:
      background: "#EEEEEE"
      image: assets/wordmark.svg
      branding: assets/wordmark.svg
      branding_fit: $fit
''');
    AdaptiveStudio(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();
    return File(res('drawable/splash_branding.xml')).readAsStringSync();
  }

  double scaleX(String vd) {
    final m = RegExp(r'scaleX="([\d.]+)"').firstMatch(vd);
    return m == null ? 1.0 : double.parse(m.group(1)!);
  }

  test('as_is preserves the SVG viewBox padding (mark smaller than auto)', () {
    final autoVd = genBranding('auto');
    final asIsVd = genBranding('as_is');

    // Different framing means a different drawable: the option is wired through.
    expect(asIsVd, isNot(equals(autoVd)));
    // as_is keeps the 20-unit padding, so the mark is scaled smaller than auto,
    // which trims the padding and fills the slot.
    expect(scaleX(asIsVd), lessThan(scaleX(autoVd)));
    // The SVG legacy raster path ran for the pre-31 layer too.
    expect(File(res('drawable-mdpi/splash_branding_legacy.png')).existsSync(),
        isTrue);
  });

  test('default (auto) trims the padding and fills the slot', () {
    // The 160-wide mark is scaled to ~90% of the 200-wide slot, so its group
    // scale comfortably exceeds the as_is viewBox mapping (min(1.0, 0.8) = 0.8).
    expect(scaleX(genBranding('auto')), greaterThan(0.9));
  });
}

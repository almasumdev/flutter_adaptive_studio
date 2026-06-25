import 'dart:io';

import 'package:flutter_adaptive_studio/flutter_adaptive_studio.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory project;
  String res(String rel) =>
      p.join(project.path, 'android', 'app', 'src', 'main', 'res', rel);

  setUp(() {
    project = Directory.systemTemp.createTempSync('fas_themed_');
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
    final assets = Directory(p.join(project.path, 'assets'))..createSync();
    for (final n in ['logo', 'logo_dark']) {
      File(p.join(assets.path, '$n.svg')).writeAsStringSync(
          '<svg viewBox="0 0 100 100"><rect x="20" y="20" width="60" '
          'height="60" rx="8" fill="#3e9aa6"/></svg>');
    }
  });

  tearDown(() => project.deleteSync(recursive: true));

  test('themed.background / background_dark override the adaptive background',
      () {
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    icon:
      adaptive:
        foreground: assets/logo.svg
        background: "#EEEEEE"
      themed:
        light: assets/logo.svg
        dark: assets/logo_dark.svg
        background: "#FBFAF5"
        background_dark: "#0E1A1C"
''');
    AdaptiveStudio(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();

    final colors = File(res('values/colors.xml')).readAsStringSync();
    expect(colors, contains('name="ic_launcher_light_background">#FBFAF5'));
    expect(colors, contains('name="ic_launcher_dark_background">#0E1A1C'));

    // Each variant's adaptive icon points at its own background colour.
    expect(
        File(res('mipmap-anydpi-v26/ic_launcher_light.xml')).readAsStringSync(),
        contains('@color/ic_launcher_light_background'));
    expect(
        File(res('mipmap-anydpi-v26/ic_launcher_dark.xml')).readAsStringSync(),
        contains('@color/ic_launcher_dark_background'));
  });

  test('themed background falls back to adaptive.background when unset', () {
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    icon:
      adaptive:
        foreground: assets/logo.svg
        background: "#123456"
      themed:
        light: assets/logo.svg
        dark: assets/logo_dark.svg
        background_dark: "#000000"
''');
    AdaptiveStudio(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();

    final colors = File(res('values/colors.xml')).readAsStringSync();
    // No themed.background → light inherits the adaptive background.
    expect(colors, contains('name="ic_launcher_light_background">#123456'));
    // Dark uses its explicit override.
    expect(colors, contains('name="ic_launcher_dark_background">#000000'));
  });
}

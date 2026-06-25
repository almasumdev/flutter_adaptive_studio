import 'dart:io';

import 'package:flutter_adaptive_studio/flutter_adaptive_studio.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// background_image (full-bleed, pre-31 + fallback) and screen_orientation
/// (main-manifest mutation).
void main() {
  late Directory project;
  String res(String rel) =>
      p.join(project.path, 'android', 'app', 'src', 'main', 'res', rel);
  String manifestPath() => p.join(
      project.path, 'android', 'app', 'src', 'main', 'AndroidManifest.xml');

  setUp(() {
    project = Directory.systemTemp.createTempSync('fas_splash_extras_');
    Directory(p.join(project.path, 'android', 'app', 'src', 'main'))
        .createSync(recursive: true);
    final assets = Directory(p.join(project.path, 'assets'))..createSync();
    File(p.join(assets.path, 'logo.svg')).writeAsStringSync(
        '<svg viewBox="0 0 100 100"><rect x="20" y="20" width="60" '
        'height="60" fill="#3e9aa6"/></svg>');
    File(p.join(assets.path, 'bg.svg')).writeAsStringSync(
        '<svg viewBox="0 0 400 800"><rect x="0" y="0" width="400" '
        'height="800" fill="#101820"/></svg>');
  });

  tearDown(() => project.deleteSync(recursive: true));

  test('background_image: pre-31 fill layer + fallback, never on API 31+', () {
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    splash:
      background: "#FFFFFF"
      background_image: assets/bg.svg
      image: assets/logo.svg
''');
    AdaptiveStudio(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();

    // A fill drawable is emitted and layered into the pre-31 splash.
    expect(File(res('drawable/splash_bg.xml')).existsSync(), isTrue);
    final launch =
        File(res('drawable/launch_background.xml')).readAsStringSync();
    expect(launch, contains('@drawable/splash_bg'));
    // The API 31+ theme takes a colour only — it must NOT reference the image.
    expect(File(res('values-v31/styles.xml')).readAsStringSync(),
        isNot(contains('splash_bg')));
    // The Flutter fallback draws it full-bleed.
    final glue = File(p.join(project.path, 'flutter_adaptive_studio', 'splash',
            'fas_splash.dart'))
        .readAsStringSync();
    expect(glue, contains('Positioned.fill'));
    expect(glue, contains('BoxFit.cover'));
  });

  test('screen_orientation locks the launcher activity in the main manifest',
      () {
    File(manifestPath()).writeAsStringSync('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="x">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
''');
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    splash:
      background: "#FFFFFF"
      image: assets/logo.svg
      screen_orientation: portrait
''');
    AdaptiveStudio(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();

    expect(File(manifestPath()).readAsStringSync(),
        contains('android:screenOrientation="portrait"'));
  });
}

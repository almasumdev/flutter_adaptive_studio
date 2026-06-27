import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
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

    // The SVG background is RASTERISED (not a vector) for the pre-31 layer — a
    // VectorDrawable can't paint in windowBackground on API 21–23. It lands as a
    // nodpi bitmap, and the pre-31 splash layers it in.
    expect(File(res('drawable-nodpi/splash_bg.png')).existsSync(), isTrue);
    expect(File(res('drawable/splash_bg.xml')).existsSync(), isFalse);
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

  test('system bars: status/nav colours, transparent, icon brightness', () {
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    splash:
      background: "#FFFFFF"
      background_dark: "#000000"
      image: assets/logo.svg
      status_bar_color: "#E4ECE8"
      status_bar_color_dark: "#0C1413"
      navigation_bar_color: transparent
      navigation_bar_icon_brightness: light
''');
    AdaptiveStudio(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();

    final styles = File(res('values/styles.xml')).readAsStringSync();
    // Opaque status bar → @color reference; transparent nav bar → framework colour.
    expect(styles, contains('android:statusBarColor'));
    expect(styles, contains('@color/splash_status_bar'));
    expect(styles, contains('android:navigationBarColor'));
    expect(styles, contains('@android:color/transparent'));
    // Needed for the colours to take effect.
    expect(styles, contains('android:windowDrawsSystemBarBackgrounds'));
    // #E4ECE8 is light → dark icons → windowLightStatusBar=true (auto-derived).
    expect(
        styles,
        contains(RegExp(
            r'windowLightStatusBar[^>]*>\s*true|windowLightStatusBar">true')));
    // Explicit light icons on the nav bar → windowLightNavigationBar=false.
    expect(styles, contains('android:windowLightNavigationBar'));

    // The opaque colour is emitted; the transparent bar needs no resource.
    final colors = File(res('values/colors.xml')).readAsStringSync();
    expect(colors, contains('splash_status_bar'));
    expect(colors, contains('#E4ECE8'));
    expect(colors, isNot(contains('splash_navigation_bar')));

    // Dark mode: the -night colour is emitted and brightness flips for the dark
    // status bar (#0C1413 dark → light icons → windowLightStatusBar=false).
    expect(File(res('values-night/colors.xml')).readAsStringSync(),
        contains('#0C1413'));
    final nightStyles = File(res('values-night/styles.xml')).readAsStringSync();
    expect(nightStyles, contains('android:statusBarColor'));

    // The API 31+ theme carries the same system-bar items.
    expect(File(res('values-v31/styles.xml')).readAsStringSync(),
        contains('android:statusBarColor'));
  });
}

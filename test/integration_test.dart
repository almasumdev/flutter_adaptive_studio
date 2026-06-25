import 'dart:io';

import 'package:flutter_adaptive_studio/flutter_adaptive_studio.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// End-to-end: scaffold a throwaway project, generate, assert the key Android
/// artifacts, then revert and assert they're gone.
void main() {
  late Directory project;
  String res(String rel) =>
      p.join(project.path, 'android', 'app', 'src', 'main', 'res', rel);

  setUp(() {
    project = Directory.systemTemp.createTempSync('fas_int_');
    final main = p.join(project.path, 'android', 'app', 'src', 'main');
    File(p.join(main, 'AndroidManifest.xml'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <application android:icon="@mipmap/ic_launcher">
    <activity android:name=".MainActivity">
      <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
      </intent-filter>
    </activity>
  </application>
</manifest>''');

    File(p.join(project.path, 'assets', 'logo.svg'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '<svg viewBox="0 0 100 100"><circle cx="50" cy="50" r="40" '
        'fill="#3e9aa6"/></svg>',
      );
    // A ready-made AnimatedVectorDrawable, used verbatim (no conversion).
    File(p.join(project.path, 'assets', 'anim.xml')).writeAsStringSync(
      '<animated-vector xmlns:android="http://schemas.android.com/apk/res/android" '
      'android:drawable="@drawable/v"><target android:name="g" '
      'android:animation="@animator/a"/></animated-vector>',
    );

    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    icon:
      adaptive:
        foreground: assets/logo.svg
        background: "#E4ECE8"
      round: true
    splash:
      background: "#E4ECE8"
      animated_icon: assets/anim.xml
      duration: 800
''');
  });

  tearDown(() => project.deleteSync(recursive: true));

  test('generate produces icon + splash artifacts, revert removes them', () {
    final report = AdaptiveStudio(
      projectRoot: project.path,
      logger: Logger(level: LogLevel.quiet),
    ).run();

    expect(report, isNotNull);
    // Icons
    expect(File(res('mipmap-anydpi-v26/ic_launcher.xml')).existsSync(), isTrue);
    expect(File(res('mipmap-anydpi-v26/ic_launcher_round.xml')).existsSync(),
        isTrue);
    expect(
        File(res('drawable/ic_launcher_foreground.xml')).existsSync(), isTrue);
    expect(File(res('values/colors.xml')).existsSync(), isTrue);
    // Splash (AVD used verbatim + theme)
    final avd = File(res('drawable/splash_icon.xml')).readAsStringSync();
    expect(avd, contains('animated-vector')); // copied through unchanged
    expect(File(res('values-v31/styles.xml')).existsSync(), isTrue);

    // The v31 theme must reference the AVD + duration (not a static PNG).
    final v31 = File(res('values-v31/styles.xml')).readAsStringSync();
    expect(v31, contains('windowSplashScreenAnimatedIcon'));
    expect(v31, contains('@drawable/splash_icon'));
    expect(v31, contains('windowSplashScreenAnimationDuration'));

    // Revert removes owned files.
    Reverter(projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();
    expect(
        File(res('mipmap-anydpi-v26/ic_launcher.xml')).existsSync(), isFalse);
    expect(File(res('drawable/splash_icon.xml')).existsSync(), isFalse);
    expect(File(res('values-v31/styles.xml')).existsSync(), isFalse);
  });
}

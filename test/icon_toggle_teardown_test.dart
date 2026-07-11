import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Turning a sub-feature off (round, monochrome, splash) must not leave inert
/// or, worse, still-active output behind. These guard the incremental teardown
/// on `generate` (see also themed_icons_test.dart for the themed feature).
void main() {
  late Directory project;
  String res(String rel) =>
      p.join(project.path, 'android', 'app', 'src', 'main', 'res', rel);
  File manifestFile() => File(p.join(
      project.path, 'android', 'app', 'src', 'main', 'AndroidManifest.xml'));
  File cfg() => File(p.join(project.path, 'flutter_adaptive_studio.yaml'));

  void writeManifest([String appAttrs = 'android:icon="@mipmap/ic_launcher"']) {
    manifestFile().writeAsStringSync(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '  <application $appAttrs>\n'
        '    <activity android:name=".MainActivity" android:exported="true">\n'
        '      <intent-filter>\n'
        '        <action android:name="android.intent.action.MAIN"/>\n'
        '        <category android:name="android.intent.category.LAUNCHER"/>\n'
        '      </intent-filter>\n'
        '    </activity>\n'
        '  </application>\n'
        '</manifest>\n');
  }

  setUp(() {
    project = Directory.systemTemp.createTempSync('fas_toggle_');
    Directory(p.join(project.path, 'android', 'app', 'src', 'main'))
        .createSync(recursive: true);
    writeManifest();
    final assets = Directory(p.join(project.path, 'assets'))..createSync();
    for (final n in ['logo', 'mono']) {
      File(p.join(assets.path, '$n.svg')).writeAsStringSync(
          '<svg viewBox="0 0 100 100"><rect x="20" y="20" width="60" '
          'height="60" rx="8" fill="#3e9aa6"/></svg>');
    }
  });

  tearDown(() => project.deleteSync(recursive: true));

  GenerationReport gen() => AdaptiveStudio(
          projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
      .run()!;

  group('round toggle teardown', () {
    test(
        'round:true then round:false drops the roundIcon attr and round mipmaps',
        () {
      cfg().writeAsStringSync('''
flutter_adaptive_studio:
  android:
    icon:
      round: true
      adaptive: {foreground: assets/logo.svg, background: "#EEEEEE"}
''');
      gen();
      expect(manifestFile().readAsStringSync(), contains('android:roundIcon'));
      expect(File(res('mipmap-anydpi-v26/ic_launcher_round.xml')).existsSync(),
          isTrue);

      cfg().writeAsStringSync('''
flutter_adaptive_studio:
  android:
    icon:
      round: false
      adaptive: {foreground: assets/logo.svg, background: "#EEEEEE"}
''');
      final report = gen();

      // round:false must actually disable the round icon, not leave it live.
      expect(manifestFile().readAsStringSync(),
          isNot(contains('android:roundIcon')));
      expect(File(res('mipmap-anydpi-v26/ic_launcher_round.xml')).existsSync(),
          isFalse);
      expect(report.removed.join('\n'), contains('round disabled'));
    });

    test('a user-owned custom roundIcon is left untouched by round:false', () {
      writeManifest('android:icon="@mipmap/ic_launcher" '
          'android:roundIcon="@mipmap/my_custom_round"');
      cfg().writeAsStringSync('''
flutter_adaptive_studio:
  android:
    icon:
      round: false
      adaptive: {foreground: assets/logo.svg, background: "#EEEEEE"}
''');
      gen();
      expect(manifestFile().readAsStringSync(),
          contains('@mipmap/my_custom_round'),
          reason: 'only the roundIcon value we generate is stripped');
    });
  });

  group('monochrome toggle teardown', () {
    test('dropping monochrome prunes the orphaned monochrome drawable', () {
      cfg().writeAsStringSync('''
flutter_adaptive_studio:
  android:
    icon:
      adaptive:
        foreground: assets/logo.svg
        background: "#EEEEEE"
        monochrome: assets/mono.svg
''');
      gen();
      expect(File(res('drawable/ic_launcher_monochrome.xml')).existsSync(),
          isTrue);

      cfg().writeAsStringSync('''
flutter_adaptive_studio:
  android:
    icon:
      adaptive: {foreground: assets/logo.svg, background: "#EEEEEE"}
''');
      gen();
      expect(File(res('drawable/ic_launcher_monochrome.xml')).existsSync(),
          isFalse);
      // The regenerated adaptive icon no longer references it either.
      expect(File(res('mipmap-anydpi-v26/ic_launcher.xml')).readAsStringSync(),
          isNot(contains('monochrome')));
    });
  });

  group('splash toggle teardown', () {
    test('removing the splash config warns about the leftover splash files',
        () {
      cfg().writeAsStringSync('''
flutter_adaptive_studio:
  android:
    icon:
      adaptive: {foreground: assets/logo.svg, background: "#EEEEEE"}
    splash:
      background: "#EEEEEE"
      image: assets/logo.svg
''');
      gen();
      expect(File(res('values-v31/styles.xml')).existsSync(), isTrue);

      cfg().writeAsStringSync('''
flutter_adaptive_studio:
  android:
    icon:
      adaptive: {foreground: assets/logo.svg, background: "#EEEEEE"}
''');
      final report = gen();

      // Left in place (wired into shared styles/manifest) but surfaced.
      expect(File(res('values-v31/styles.xml')).existsSync(), isTrue);
      final warn = report.warnings.join('\n');
      expect(warn, contains('Splash is not configured'));
      expect(warn, contains('revert'));
    });
  });
}

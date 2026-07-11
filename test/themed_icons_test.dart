import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
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

  group('teardown when the themed feature is turned off', () {
    const cfgWith = '''
flutter_adaptive_studio:
  android:
    icon:
      round: true
      adaptive:
        foreground: assets/logo.svg
        background: "#EEEEEE"
      themed:
        light: assets/logo.svg
        dark: assets/logo_dark.svg
        background: "#FBFAF5"
        background_dark: "#0E1A1C"
''';
    const cfgWithout = '''
flutter_adaptive_studio:
  android:
    icon:
      round: true
      adaptive:
        foreground: assets/logo.svg
        background: "#EEEEEE"
''';
    const owned = [
      'mipmap-anydpi-v26/ic_launcher_light.xml',
      'mipmap-anydpi-v26/ic_launcher_light_round.xml',
      'mipmap-anydpi-v26/ic_launcher_dark.xml',
      'mipmap-anydpi-v26/ic_launcher_dark_round.xml',
      'drawable/ic_launcher_light_foreground.xml',
      'drawable/ic_launcher_dark_foreground.xml',
    ];
    const baseManifest =
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '  <application android:icon="@mipmap/ic_launcher">\n'
        '    <activity android:name=".MainActivity" android:exported="true">\n'
        '      <intent-filter>\n'
        '        <action android:name="android.intent.action.MAIN"/>\n'
        '        <category android:name="android.intent.category.LAUNCHER"/>\n'
        '      </intent-filter>\n'
        '    </activity>\n'
        '  </application>\n'
        '</manifest>\n';

    File cfg() => File(p.join(project.path, 'flutter_adaptive_studio.yaml'));
    File manifest() => File(p.join(
        project.path, 'android', 'app', 'src', 'main', 'AndroidManifest.xml'));
    void generate([Logger? logger]) => AdaptiveStudio(
            projectRoot: project.path,
            logger: logger ?? Logger(level: LogLevel.quiet))
        .run();

    test(
        'aliases still present: owned files are KEPT (build-safe) and a warning '
        'names the manifest + colours remnants', () {
      cfg().writeAsStringSync(cfgWith);
      generate();
      for (final f in owned) {
        expect(File(res(f)).existsSync(), isTrue,
            reason: 'setup: $f should exist after generating with themed');
      }

      cfg().writeAsStringSync(cfgWithout);
      final report = AdaptiveStudio(
              projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
          .run()!;

      // Not pruned: the aliases still reference @mipmap/ic_launcher_light|dark,
      // so deleting the mipmaps would dangle that ref and break the build.
      for (final f in owned) {
        expect(File(res(f)).existsSync(), isTrue,
            reason: '$f must be kept while an alias references it');
      }
      // The previously-silent cruft is now surfaced, naming what to remove.
      final warn = report.warnings.join('\n');
      expect(warn, contains('activity-alias'));
      expect(warn, contains('.FasIconLight'));
      expect(warn, contains('.FasIconDark'));
      expect(warn, contains('ic_launcher_light_background'));
    });

    test('aliases already removed (via VCS): owned files ARE pruned', () {
      cfg().writeAsStringSync(cfgWith);
      generate();

      // Simulate the user restoring the shared manifest from version control:
      // with the aliases gone, the owned mipmaps are now truly orphaned.
      manifest().writeAsStringSync(baseManifest);

      cfg().writeAsStringSync(cfgWithout);
      final report = AdaptiveStudio(
              projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
          .run()!;

      for (final f in owned) {
        expect(File(res(f)).existsSync(), isFalse,
            reason: '$f should be pruned once no alias references it');
      }
      expect(report.removed.join('\n'), contains('themed icon disabled'));
    });

    test(
        'revert warns specifically that the manifest still references the '
        'deleted mipmaps', () {
      cfg().writeAsStringSync(cfgWith);
      generate();

      final log = _CapturingLogger();
      Reverter(projectRoot: project.path, logger: log).run();

      // The mipmaps are deleted...
      expect(File(res('mipmap-anydpi-v26/ic_launcher_light.xml')).existsSync(),
          isFalse);
      // ...and revert warned loudly and specifically about the dangling ref.
      final warn = log.warnings.join('\n');
      expect(warn, contains('@mipmap/ic_launcher_light'));
      expect(warn, contains('.FasIconLight'));
      expect(warn, contains('will FAIL'));
    });
  });
}

/// Captures `warn()` lines (which the logger sends to stderr) so tests can
/// assert on teardown/revert warnings without scraping process output.
class _CapturingLogger extends Logger {
  _CapturingLogger() : super(level: LogLevel.quiet);

  final List<String> warnings = [];

  @override
  void warn(String message) => warnings.add(message);
}

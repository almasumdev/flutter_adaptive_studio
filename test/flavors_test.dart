import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Flavors = one config file, base + per-flavor overrides, deep-merged and
/// written to that flavor's `src/<flavor>/res` overlay.
void main() {
  late Directory project;
  String res(String set, String rel) =>
      p.join(project.path, 'android', 'app', 'src', set, 'res', rel);

  setUp(() {
    project = Directory.systemTemp.createTempSync('fas_flavor_');
    Directory(p.join(project.path, 'android', 'app', 'src', 'main'))
        .createSync(recursive: true);
    File(p.join((Directory(p.join(project.path, 'assets'))..createSync()).path,
            'logo.svg'))
        .writeAsStringSync('<svg viewBox="0 0 100 100"><rect x="10" y="10" '
            'width="80" height="80" fill="#123456"/></svg>');
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    icon:
      adaptive:
        foreground: assets/logo.svg
        background: "#FFFFFF"
  flavors:
    dev:
      android:
        icon:
          adaptive:
            background: "#00C853"
''');
  });

  tearDown(() => project.deleteSync(recursive: true));

  test('flavor deep-merges overrides into the flavor source set', () {
    AdaptiveStudio(
      projectRoot: project.path,
      flavor: 'dev',
      logger: Logger(level: LogLevel.quiet),
    ).run();

    // Output lands in src/dev/res with the OVERRIDDEN background colour…
    final devColors = File(res('dev', 'values/colors.xml'));
    expect(devColors.existsSync(), isTrue);
    expect(devColors.readAsStringSync(), contains('#00C853'));
    // …and the base foreground is still inherited (adaptive xml written).
    expect(File(res('dev', 'mipmap-anydpi-v26/ic_launcher.xml')).existsSync(),
        isTrue);
    // The dev run does not touch main/res.
    expect(File(res('main', 'values/colors.xml')).existsSync(), isFalse);
  });

  test('no flavor → base config writes to main', () {
    AdaptiveStudio(
      projectRoot: project.path,
      logger: Logger(level: LogLevel.quiet),
    ).run();
    expect(File(res('main', 'values/colors.xml')).readAsStringSync(),
        contains('#FFFFFF'));
  });

  test(
      'a flavor accepts the full root schema — can add a section the base lacks',
      () {
    // Base has only an icon; the flavor introduces a whole splash block.
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    icon:
      adaptive:
        foreground: assets/logo.svg
        background: "#FFFFFF"
  flavors:
    full:
      android:
        splash:
          background: "#222222"
          image: assets/logo.svg
''');
    AdaptiveStudio(
      projectRoot: project.path,
      flavor: 'full',
      logger: Logger(level: LogLevel.quiet),
    ).run();

    // The flavor-added splash is generated…
    expect(File(res('full', 'values-v31/styles.xml')).existsSync(), isTrue);
    // …and the inherited base icon is still generated for that flavor.
    expect(File(res('full', 'mipmap-anydpi-v26/ic_launcher.xml')).existsSync(),
        isTrue);
  });

  test('unknown flavor throws a helpful ConfigException', () {
    expect(
      () => AdaptiveStudio(
        projectRoot: project.path,
        flavor: 'staging',
        logger: Logger(level: LogLevel.quiet),
      ).run(),
      throwsA(isA<ConfigException>()),
    );
  });
}

import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory project;
  File configFile() =>
      File(p.join(project.path, 'flutter_adaptive_studio.yaml'));

  setUp(() {
    project = Directory.systemTemp.createTempSync('fas_sync_');
    // An "old" config: real values, but missing the newer options.
    configFile().writeAsStringSync('''
flutter_adaptive_studio:

  android:
    icon:
      adaptive:
        foreground: assets/logo.svg
        background: "#E4ECE8"
      round: true
    splash:
      background: "#E4ECE8"
      image: assets/logo.svg
''');
  });

  tearDown(() => project.deleteSync(recursive: true));

  /// The line that mentions [key] (active or commented), or null.
  String? lineFor(String key) {
    for (final l in configFile().readAsLinesSync()) {
      if (RegExp('^\\s*#?\\s*$key\\s*:').hasMatch(l)) return l;
    }
    return null;
  }

  test('sync adds missing options as commented lines, untouched values', () {
    final before = configFile().readAsStringSync();
    final added = ConfigSync(
      projectRoot: project.path,
      logger: Logger(level: LogLevel.quiet),
    ).run();

    expect(added, greaterThan(0));
    final after = configFile().readAsStringSync();

    // New options are now present...
    for (final key in const [
      'status_bar_color',
      'navigation_bar_color',
      'branding_text',
      'image_format',
    ]) {
      expect(lineFor(key), isNotNull, reason: 'missing $key after sync');
      // ...and they are COMMENTED (so they don't change behaviour).
      expect(lineFor(key)!.trimLeft().startsWith('#'), isTrue,
          reason: '$key should be inserted commented');
    }

    // Existing ACTIVE lines are preserved verbatim, not commented.
    expect(after, contains('      foreground: assets/logo.svg'));
    expect(after, contains('      round: true'));
    expect(after, contains('      image: assets/logo.svg'));
    expect(lineFor('round')!.trimLeft().startsWith('#'), isFalse);

    // The active config is unchanged: the new options stay null/defaults.
    final cfg = ConfigLoader(project.path).load();
    expect(cfg!.android!.splash!.image, 'assets/logo.svg');
    expect(cfg.android!.splash!.statusBarColor, isNull);
    expect(cfg.android!.icon!.round, isTrue);

    // The whole original text still appears (nothing removed/rewritten).
    for (final origLine
        in before.split('\n').where((l) => l.trim().isNotEmpty)) {
      expect(after, contains(origLine));
    }
  });

  test('inserted splash options land inside the splash section', () {
    ConfigSync(projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();
    final lines = configFile().readAsLinesSync();
    final splashAt =
        lines.indexWhere((l) => RegExp(r'^\s*splash\s*:').hasMatch(l));
    final statusAt =
        lines.indexWhere((l) => RegExp(r'status_bar_color\s*:').hasMatch(l));
    expect(splashAt, greaterThanOrEqualTo(0));
    expect(statusAt, greaterThan(splashAt));
  });

  test('sync is idempotent — a second run adds nothing', () {
    final first = ConfigSync(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();
    expect(first, greaterThan(0));
    final second = ConfigSync(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();
    expect(second, 0);
  });

  test('sync returns -1 when there is no config file', () {
    configFile().deleteSync();
    final added = ConfigSync(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();
    expect(added, -1);
  });
}

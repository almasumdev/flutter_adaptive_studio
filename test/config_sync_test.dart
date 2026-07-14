import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
import 'package:flutter_adaptive_studio/src/config/config_loader.dart';
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

  /// Direct child keys of the `splash:` section, in file order (active or
  /// commented), using logical indent so `    #   key:` counts as a child.
  List<String> splashKeys(List<String> lines) {
    final keyRe = RegExp(r'^(\s*)(#\s*)?([A-Za-z_]\w*)\s*:');
    int logical(String l) {
      final m = RegExp(r'^(\s*)#\s?(.*)$').firstMatch(l);
      final t = m == null ? l : '${m.group(1)}${m.group(2)}';
      return t.length - t.trimLeft().length;
    }

    final out = <String>[];
    var splashIndent = -1;
    var inSplash = false;
    var done = false; // only the FIRST splash (android), not ios/flavors
    for (final l in lines) {
      if (done) break;
      final m = keyRe.firstMatch(l);
      if (m == null) continue;
      final key = m.group(3)!;
      final ind = logical(l);
      if (key == 'splash' && !inSplash) {
        splashIndent = ind;
        inSplash = true;
        continue;
      }
      if (!inSplash) continue;
      if (ind <= splashIndent) {
        done = true;
        continue;
      }
      if (ind == splashIndent + 2) out.add(key);
    }
    return out;
  }

  test('inserted keys are grouped with their siblings, not scattered', () {
    // A splash with only a couple of keys present (in template order).
    configFile().writeAsStringSync('''
flutter_adaptive_studio:
  android:
    icon:
      adaptive:
        foreground: assets/logo.svg
    splash:
      background: "#E4ECE8"
      image: assets/logo.svg
''');
    ConfigSync(projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();
    final keys = splashKeys(configFile().readAsLinesSync());

    // `image`'s companions land right after it, contiguous, in template order,
    // rather than being appended to the bottom of the section.
    final i = keys.indexOf('image');
    expect(keys.sublist(i, i + 4),
        ['image', 'image_dark', 'image_fit', 'image_format']);

    // `background_dark` sits right after `background` (before `image`).
    expect(keys.indexOf('background_dark'), keys.indexOf('background') + 1);

    // Every branding key forms one contiguous run.
    final brand = keys.where((k) => k.startsWith('branding')).toList();
    expect(brand, isNotEmpty);
    final start = keys.indexOf(brand.first);
    expect(keys.sublist(start, start + brand.length), brand,
        reason: 'branding keys must be contiguous, got $keys');
  });

  test('sync is idempotent: a second run adds nothing', () {
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

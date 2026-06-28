import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Guards the checked-in example app's generated splash
/// (`example/lib/fas_splash.g.dart`). Two things are easy to get wrong and
/// expensive to ship broken:
///
///   1. The example must depend on **nothing** from this package. The whole
///      point of generating a self-contained file is that a consuming app can't
///      inherit our build-time deps (image/xml) and clash with its own. If a
///      `package:` other than flutter ever leaks into the generated file, that
///      guarantee is gone.
///   2. The committed file is a *generated artifact*, so it silently rots: edit
///      the template (`splash_runtime_source.dart`) or the example's YAML and
///      forget to re-run the generator, and the published example no longer
///      reflects the tool. The end-to-end regen test below catches that.
void main() {
  // example/ sits at the package root; `dart test` runs from there.
  final exampleDir = Directory(p.join(Directory.current.path, 'example'));
  final committedFile =
      File(p.join(exampleDir.path, 'lib', 'fas_splash.g.dart'));

  setUpAll(() {
    expect(exampleDir.existsSync(), isTrue,
        reason: 'run tests from the package root; expected ${exampleDir.path}');
  });

  group('example/lib/fas_splash.g.dart — committed generated splash', () {
    late String src;
    setUp(() {
      expect(committedFile.existsSync(), isTrue,
          reason: 'the example must ship a generated splash — run '
              '`dart run flutter_adaptive_studio generate -p example`');
      src = committedFile.readAsStringSync();
    });

    test('imports only package:flutter (nothing leaks into a consuming app)',
        () {
      final packages = RegExp(r"import 'package:([^/']+)")
          .allMatches(src)
          .map((m) => m.group(1))
          .toSet();
      expect(packages, {'flutter'},
          reason:
              'a generated splash that imports anything but package:flutter '
              'would drag a transitive dependency into every consuming app');
      expect(src, isNot(contains('package:flutter_adaptive_studio')));
    });

    test('bakes in the whole runtime — config + widget + native-splash keeper',
        () {
      expect(src, contains('final FasSplashConfig fasSplash'));
      expect(src, contains('class FasSplashConfig'));
      expect(src, contains('class AdaptiveSplash'));
      expect(src, contains('class FasNativeSplash'));
    });

    test('mirrors the example config — colours, timing, themed branding', () {
      expect(src, contains('backgroundLight: 0xFFFBFAF5')); // #fbfaf5
      expect(src, contains('backgroundDark: 0xFF0E1A1C')); // #0E1A1C
      expect(src, contains('duration: const Duration(milliseconds: 1200)'));
      expect(src, contains('showOnAllVersions: true')); // flutter_splash_all_…
      expect(src, contains('brandingLight: _b64(')); // wordmark.svg
      expect(src, contains('brandingDark: _b64(')); // wordmark_dark.svg
      expect(src, contains('iosLogoDark: _b64(')); // ios.splash.image_dark
    });
  });

  group('the example app takes no dependency on flutter_adaptive_studio', () {
    test('pubspec.yaml lists no dependency on the package', () {
      final pubspec =
          File(p.join(exampleDir.path, 'pubspec.yaml')).readAsStringSync();
      expect(pubspec, isNot(contains('flutter_adaptive_studio:')),
          reason: 'the example must not depend on us — that is exactly the '
              'guarantee the self-contained generated splash exists to make');
    });

    test('main.dart wires the generated file, not our package', () {
      final main =
          File(p.join(exampleDir.path, 'lib', 'main.dart')).readAsStringSync();
      expect(main, contains("import 'fas_splash.g.dart'"));
      expect(main, contains('AdaptiveSplash('));
      expect(main, isNot(contains('package:flutter_adaptive_studio')));
    });
  });

  test('regenerating the example reproduces lib/fas_splash.g.dart (not stale)',
      () {
    // Faithful end-to-end: copy the example, regenerate into the copy, and
    // confirm the checked-in file still matches — config AND baked-in runtime.
    // Comparison is structural: the embedded artwork bytes are normalised out
    // (PNG/WebP encoders aren't byte-stable across image-package versions) and
    // formatting is normalised (the committed file is `dart format`ted, the
    // template is raw). What's left must match, or the checked-in file is stale.
    final tmp = Directory.systemTemp.createTempSync('fas_example_regen_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    _copyDir(exampleDir, tmp,
        skip: const {'.dart_tool', 'build', '.idea', '.git'});

    final regenFile = File(p.join(tmp.path, 'lib', 'fas_splash.g.dart'));
    if (regenFile.existsSync()) regenFile.deleteSync(); // force a fresh write

    final report = AdaptiveStudio(
      projectRoot: tmp.path,
      logger: Logger(level: LogLevel.quiet),
    ).run();
    expect(report, isNotNull, reason: 'no config found in the example copy');
    expect(regenFile.existsSync(), isTrue,
        reason: 'generation did not (re)write lib/fas_splash.g.dart');

    expect(
      _canon(regenFile.readAsStringSync()),
      _canon(committedFile.readAsStringSync()),
      reason: 'example/lib/fas_splash.g.dart is stale — re-run '
          '`dart run flutter_adaptive_studio generate -p example` and commit it',
    );
  });
}

/// Format-insensitive structural form of a generated splash, so the committed
/// (`dart format`ted) file and the raw generator output compare equal while any
/// real change still shows. In order: drop the base64 artwork payloads
/// (`_b64('…')`), collapse whitespace, tighten the space `dart format` puts
/// around delimiters, and drop the trailing commas it inserts before closers.
String _canon(String s) => s
    .replaceAll(RegExp(r'_b64\([^)]*\)'), '_b64(B)')
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAllMapped(RegExp(r'\s*([(){}\[\],;])\s*'), (m) => m.group(1)!)
    .replaceAllMapped(RegExp(r',([)\]}])'), (m) => m.group(1)!)
    .trim();

/// Recursively copies [from] into the existing [to], skipping any directory
/// named in [skip] (build artifacts that needn't be carried into the regen).
void _copyDir(Directory from, Directory to, {required Set<String> skip}) {
  for (final e in from.listSync(followLinks: false)) {
    final name = p.basename(e.path);
    if (skip.contains(name)) continue;
    final dest = p.join(to.path, name);
    if (e is Directory) {
      Directory(dest).createSync(recursive: true);
      _copyDir(e, Directory(dest), skip: skip);
    } else if (e is File) {
      e.copySync(dest);
    }
  }
}

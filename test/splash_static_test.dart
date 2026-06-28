import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory project;
  String res(String rel) =>
      p.join(project.path, 'android', 'app', 'src', 'main', 'res', rel);

  /// The generated in-app splash config (`lib/fas_splash.g.dart`, or the project
  /// root when there's no `lib/`).
  String splashCfg() {
    final lib = File(p.join(project.path, 'lib', 'fas_splash.g.dart'));
    final root = File(p.join(project.path, 'fas_splash.g.dart'));
    return (lib.existsSync() ? lib : root).readAsStringSync();
  }

  setUp(() {
    project = Directory.systemTemp.createTempSync('fas_splash_static_');
    Directory(p.join(project.path, 'android', 'app', 'src', 'main'))
        .createSync(recursive: true);
    final assets = Directory(p.join(project.path, 'assets'))..createSync();
    // Square logo.
    File(p.join(assets.path, 'logo.svg')).writeAsStringSync(
        '<svg viewBox="0 0 100 100"><rect x="20" y="20" width="60" '
        'height="60" rx="8" fill="#3e9aa6"/></svg>');
    // Wide branding wordmark (non-square → aspect-preserving VD).
    File(p.join(assets.path, 'wordmark.svg')).writeAsStringSync(
        '<svg viewBox="0 0 240 60"><rect x="0" y="10" width="240" '
        'height="40" fill="#1f5560"/></svg>');

    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    splash:
      background: "#FFFFFF"
      background_dark: "#0E1A1C"
      image: assets/logo.svg
      branding: assets/wordmark.svg
''');
  });

  tearDown(() => project.deleteSync(recursive: true));

  test('static splash: centre logo + bottom branding, no animation duration',
      () {
    final report = AdaptiveStudio(
      projectRoot: project.path,
      logger: Logger(level: LogLevel.quiet),
    ).run();
    expect(report, isNotNull);

    // Drawables: centre icon (square VD) + branding (rectangular VD).
    expect(File(res('drawable/splash_icon.xml')).existsSync(), isTrue);
    expect(File(res('drawable/splash_branding.xml')).existsSync(), isTrue);

    // Icon honours the Android 12 keyline: 288dp canvas (no icon background),
    // art inscribed in the ⌀192 safe circle so the mask can't clip it.
    final icon = File(res('drawable/splash_icon.xml')).readAsStringSync();
    expect(icon, contains('android:viewportWidth="288"'));
    final scale = RegExp(r'scaleX="([0-9.]+)"').firstMatch(icon);
    expect(scale, isNotNull);
    // 60×60 art (diagonal ≈ 84.85) → scale 192/84.85 ≈ 2.263.
    expect(double.parse(scale!.group(1)!), closeTo(2.263, 0.01));

    // Branding VD is letterboxed onto the 200×80dp Android branding slot so the
    // system can't vertically stretch a wide/short wordmark. The art (240×40,
    // 6:1) is scaled-to-fit: min(200/240, 80/40)*0.9 = 0.75, and centred.
    final branding =
        File(res('drawable/splash_branding.xml')).readAsStringSync();
    expect(branding, contains('android:width="200dp"'));
    expect(branding, contains('android:height="80dp"'));
    expect(branding, contains('android:viewportWidth="200"'));
    expect(branding, contains('android:viewportHeight="80"'));
    final bScale = RegExp(r'scaleX="([0-9.]+)"').firstMatch(branding);
    expect(bScale, isNotNull);
    expect(double.parse(bScale!.group(1)!), closeTo(0.75, 0.001));

    // API 31+ theme wires both the icon slot and the branding image, and —
    // because this is a *static* logo — omits the animation duration.
    final v31 = File(res('values-v31/styles.xml')).readAsStringSync();
    expect(v31, contains('windowSplashScreenAnimatedIcon'));
    expect(v31, contains('@drawable/splash_icon'));
    expect(v31, contains('windowSplashScreenBrandingImage'));
    expect(v31, contains('@drawable/splash_branding'));
    expect(v31, isNot(contains('windowSplashScreenAnimationDuration')));
    // postSplashScreenTheme is a compat-library-only attr — must never be
    // emitted into the framework v31 theme (it fails to link).
    expect(v31, isNot(contains('postSplashScreenTheme')));

    // Pre-31 layer-list centres the icon and pins branding to the bottom. BOTH
    // the centre logo AND the branding are RASTERS (`splash_icon_legacy`,
    // `splash_branding_legacy`), not the v31 vectors — a VectorDrawable in
    // windowBackground doesn't paint on API 21–23.
    final launch =
        File(res('drawable/launch_background.xml')).readAsStringSync();
    expect(launch, contains('@drawable/splash_icon_legacy'));
    expect(launch, contains('@drawable/splash_branding_legacy'));
    // The crisp vector branding name must NOT be referenced from the pre-31
    // layer (only the raster sibling is legacy-safe).
    expect(launch, isNot(contains('@drawable/splash_branding"')));
    expect(launch, contains('bottom|center_horizontal'));

    // The SVG branding is rasterised per density for the pre-31 launch, while
    // the crisp v31 vector (splash_branding.xml) is kept for the API 31+ slot.
    for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      expect(File(res('drawable-$d/splash_branding_legacy.png')).existsSync(),
          isTrue,
          reason: 'missing pre-31 branding raster for $d');
    }
    expect(File(res('drawable/splash_branding.xml')).existsSync(), isTrue);

    // CRUCIAL: the same launch background is also written to drawable-v21/.
    // On API 21+ Android resolves @drawable/launch_background to the -v21
    // bucket, so the stock white drawable-v21/launch_background.xml would
    // otherwise shadow ours and the splash would never appear.
    final launchV21 =
        File(res('drawable-v21/launch_background.xml')).readAsStringSync();
    expect(launchV21, contains('@color/splash_background'));
    expect(launchV21, contains('@drawable/splash_icon_legacy'));

    // The pre-31 logo is rasterised to PNG (default) at every density, and the
    // crisp v31 vector (splash_icon.xml) is left untouched for API 31+.
    for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      expect(
          File(res('drawable-$d/splash_icon_legacy.png')).existsSync(), isTrue,
          reason: 'missing pre-31 raster logo for $d');
    }
    expect(File(res('drawable/splash_icon.xml')).existsSync(), isTrue);

    // Dark background colour emitted via -night.
    final nightColors = File(res('values-night/colors.xml')).readAsStringSync();
    expect(nightColors, contains('#0E1A1C'));

    // In-app splash config generated with baked colours + embedded logo bytes.
    final cfg = splashCfg();
    expect(cfg, contains('FasSplashConfig'));
    expect(cfg, contains('0xFF0E1A1C')); // dark bg baked in
    expect(cfg, contains('logo: _b64(')); // logo rasterised + embedded
    expect(cfg, contains('brandingLight: _b64(')); // SVG wordmark embedded
    // Self-contained: the widget is baked into the file; it does NOT import our
    // package (that's what keeps the app conflict-free).
    expect(cfg, isNot(contains('package:flutter_adaptive_studio')));
    expect(cfg, contains('class AdaptiveSplash'));
    // Branding placement mirrors the native default (bottom-centre, 48dp). No
    // branding_dark here → no dark branding bytes.
    expect(cfg, contains('brandingAlignment: Alignment.bottomCenter'));
    expect(cfg, contains('brandingBottomPadding: 48'));
    expect(cfg, contains('brandingDark: null'));
    // Gated to API < 31 by default.
    expect(cfg, contains('showOnAllVersions: false'));
  });

  test('the in-app splash is a single generated config, not a folder/widget',
      () {
    AdaptiveStudio(
      projectRoot: project.path,
      logger: Logger(level: LogLevel.quiet),
    ).run();

    // No generated folder, widget, guide, or keeper drop-in anymore — the widget
    // (AdaptiveSplash) and keeper (FasNativeSplash) both ship in the package.
    expect(
        Directory(p.join(project.path, 'flutter_adaptive_studio')).existsSync(),
        isFalse);

    // Just one generated data file the user imports + wraps.
    final cfg = splashCfg();
    expect(cfg, contains('final FasSplashConfig fasSplash'));
    expect(cfg, contains('runApp('));
    expect(cfg, contains('AdaptiveSplash(config: fasSplash'));
  });

  test('the generated file bakes in a self-contained runtime', () {
    AdaptiveStudio(
      projectRoot: project.path,
      logger: Logger(level: LogLevel.quiet),
    ).run();
    final cfg = splashCfg();

    // The config, the widget, and the native-splash keeper all live in the one
    // generated file.
    expect(cfg, contains('class FasSplashConfig'));
    expect(cfg, contains('class AdaptiveSplash'));
    expect(cfg, contains('this.force')); // per-call force-on-all override
    expect(cfg, contains('class FasNativeSplash'));
    expect(cfg, contains('static void preserve('));
    expect(cfg, contains('static void remove()'));
    expect(cfg, contains('deferFirstFrame'));
    expect(cfg, contains('allowFirstFrame'));
    // Robustness extras over flutter_native_splash: a failsafe timeout and a
    // double-preserve guard.
    expect(cfg, contains('Duration? maxDuration'));
    expect(cfg, contains('static bool get isPreserved'));

    // The SDK gate is pure-Dart FFI using only core dart:ffi (no package:ffi),
    // so the app needs no extra dependency.
    expect(cfg, contains('__system_property_get'));
    expect(cfg, contains("import 'dart:ffi'"));

    // It depends on nothing but package:flutter (no package:ffi, no us).
    final packages = RegExp(r"import 'package:([^/']+)")
        .allMatches(cfg)
        .map((m) => m.group(1))
        .toSet();
    expect(packages, {'flutter'},
        reason: 'generated file must import only package:flutter');
  });

  test('themed branding: config embeds light + dark wordmark bytes', () {
    File(p.join(project.path, 'assets', 'wordmark_dark.svg')).writeAsStringSync(
        '<svg viewBox="0 0 240 60"><rect x="0" y="10" width="240" '
        'height="40" fill="#E6F2F4"/></svg>');
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    splash:
      background: "#FFFFFF"
      background_dark: "#0E1A1C"
      image: assets/logo.svg
      branding: assets/wordmark.svg
      branding_dark: assets/wordmark_dark.svg
''');

    AdaptiveStudio(
      projectRoot: project.path,
      logger: Logger(level: LogLevel.quiet),
    ).run();

    // Native: a -night branding drawable is emitted for the dark variant.
    expect(
        File(res('drawable-night/splash_branding.xml')).existsSync(), isTrue);

    // In-app config: BOTH light and dark wordmark bytes are embedded, so the
    // widget can swap by system brightness (no asset, no flutter_svg).
    final cfg = splashCfg();
    expect(cfg, contains('brandingLight: _b64('));
    expect(cfg, contains('brandingDark: _b64('));
    expect(cfg, isNot(contains('brandingDark: null')));
  });

  test(
      'splash knobs: image_dark, icon_background_dark, fullscreen, branding '
      'mode + padding, gravity', () {
    File(p.join(project.path, 'assets', 'logo_dark.svg')).writeAsStringSync(
        '<svg viewBox="0 0 100 100"><rect x="20" y="20" width="60" '
        'height="60" rx="8" fill="#E6F2F4"/></svg>');
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    splash:
      background: "#FFFFFF"
      background_dark: "#0E1A1C"
      image: assets/logo.svg
      image_dark: assets/logo_dark.svg
      icon_background: "#FFFFFF"
      icon_background_dark: "#111111"
      gravity: fill
      fullscreen: true
      branding: assets/wordmark.svg
      branding_mode: bottom_right
      branding_bottom_padding: 24
''');

    AdaptiveStudio(
      projectRoot: project.path,
      logger: Logger(level: LogLevel.quiet),
    ).run();

    // image_dark → a -night centre logo (auto-resolved on dark mode).
    expect(File(res('drawable-night/splash_icon.xml')).existsSync(), isTrue);

    // icon_background_dark → -night colour the v31 theme resolves at runtime.
    final nightColors = File(res('values-night/colors.xml')).readAsStringSync();
    expect(nightColors, contains('#111111'));

    // fullscreen → windowFullscreen on both the v31 and legacy launch themes.
    expect(File(res('values-v31/styles.xml')).readAsStringSync(),
        contains('android:windowFullscreen'));
    expect(File(res('values/styles.xml')).readAsStringSync(),
        contains('android:windowFullscreen'));

    // Pre-31 layer-list honours gravity + branding mode/padding.
    final launch =
        File(res('drawable/launch_background.xml')).readAsStringSync();
    expect(launch, contains('android:gravity="fill"'));
    expect(launch, contains('android:gravity="bottom|right"'));
    expect(launch, contains('android:bottom="24dp"'));

    // In-app config mirrors the branding placement.
    final cfg = splashCfg();
    expect(cfg, contains('brandingAlignment: Alignment.bottomRight'));
    expect(cfg, contains('brandingBottomPadding: 24'));
  });

  test(
      'SVG branding: pre-31 raster sibling (+night, webp), vector kept for v31, '
      'revert cleans it', () {
    File(p.join(project.path, 'assets', 'wordmark_dark.svg')).writeAsStringSync(
        '<svg viewBox="0 0 240 60"><rect x="0" y="10" width="240" '
        'height="40" fill="#E6F2F4"/></svg>');
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    splash:
      background: "#FFFFFF"
      background_dark: "#0E1A1C"
      image: assets/logo.svg
      image_format: webp
      branding: assets/wordmark.svg
      branding_dark: assets/wordmark_dark.svg
''');

    AdaptiveStudio(
      projectRoot: project.path,
      logger: Logger(level: LogLevel.quiet),
    ).run();

    // Pre-31: a per-density WebP branding raster, light AND -night, plus NO
    // stale .png sibling. The launch background references the raster name.
    for (final d in ['mdpi', 'xxhdpi', 'xxxhdpi']) {
      expect(File(res('drawable-$d/splash_branding_legacy.webp')).existsSync(),
          isTrue,
          reason: 'missing pre-31 branding webp for $d');
      expect(File(res('drawable-$d/splash_branding_legacy.png')).existsSync(),
          isFalse);
    }
    expect(
        File(res('drawable-night-xxhdpi/splash_branding_legacy.webp'))
            .existsSync(),
        isTrue);
    // The crisp vector is still emitted for the API 31+ slot.
    expect(File(res('drawable/splash_branding.xml')).existsSync(), isTrue);
    expect(File(res('values-v31/styles.xml')).readAsStringSync(),
        contains('@drawable/splash_branding'));

    // Revert removes the pre-31 branding rasters (both formats, + night).
    Reverter(projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();
    expect(
        File(res('drawable-xxhdpi/splash_branding_legacy.webp')).existsSync(),
        isFalse);
    expect(
        File(res('drawable-night-xxhdpi/splash_branding_legacy.webp'))
            .existsSync(),
        isFalse);
  });

  test('animated splash: a ready-made AVD .xml is used verbatim', () {
    const avd =
        '<animated-vector xmlns:android="http://schemas.android.com/apk/res/android" '
        'xmlns:aapt="http://schemas.android.com/aapt">MY_UNIQUE_AVD_MARKER</animated-vector>';
    File(p.join(project.path, 'assets', 'anim.xml')).writeAsStringSync(avd);
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    splash:
      background: "#FFFFFF"
      animated_icon: assets/anim.xml
''');

    AdaptiveStudio(
      projectRoot: project.path,
      logger: Logger(level: LogLevel.quiet),
    ).run();

    // Copied byte-for-byte (no Shapeshifter conversion).
    final out = File(res('drawable/splash_icon.xml')).readAsStringSync();
    expect(out, contains('MY_UNIQUE_AVD_MARKER'));

    // Wired as the animated icon, with the animation duration (it's animated).
    final v31 = File(res('values-v31/styles.xml')).readAsStringSync();
    expect(v31, contains('windowSplashScreenAnimatedIcon'));
    expect(v31, contains('windowSplashScreenAnimationDuration'));

    // Animated-only with NO fallback logo (no source / icon foreground) → no
    // pre-31 raster logo, so the launch background is colour-only.
    expect(File(res('drawable-xxhdpi/splash_icon_legacy.png')).existsSync(),
        isFalse);
    final launch =
        File(res('drawable/launch_background.xml')).readAsStringSync();
    expect(launch, isNot(contains('splash_icon_legacy')));
  });

  test(
      'generate overwrites a stale stock drawable-v21 launch background; '
      'revert restores the stock template', () {
    // Simulate the stock Flutter project: a white drawable-v21 launch background
    // that shadows ours on API 21+.
    final v21 = File(res('drawable-v21/launch_background.xml'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('<layer-list xmlns:android="http://schemas.android'
          '.com/apk/res/android"><item android:drawable="?android:color'
          'Background" /></layer-list>');

    AdaptiveStudio(
      projectRoot: project.path,
      logger: Logger(level: LogLevel.quiet),
    ).run();

    // The stale white -v21 file is replaced with our splash.
    final after = v21.readAsStringSync();
    expect(after, contains('@color/splash_background'));
    expect(after, contains('@drawable/splash_icon_legacy'));
    expect(after, isNot(contains('?android:colorBackground')));

    // Revert restores the stock template to drawable/ + drawable-v21/ (so the
    // LaunchTheme windowBackground reference doesn't dangle).
    Reverter(projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();
    for (final d in ['drawable', 'drawable-v21']) {
      final restored = File(res('$d/launch_background.xml')).readAsStringSync();
      expect(restored, contains('?android:colorBackground'),
          reason: '$d/launch_background.xml should be stock after revert');
      expect(restored, isNot(contains('splash_icon_legacy')));
    }
  });

  test('text branding renders a wordmark when no branding image is given', () {
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    splash:
      background: "#FFFFFF"
      background_dark: "#0E1A1C"
      image: assets/logo.svg
      branding_text: "ListKin"
      branding_text_color: "#1F5560"
''');

    AdaptiveStudio(
      projectRoot: project.path,
      logger: Logger(level: LogLevel.quiet),
    ).run();

    // Native: a rasterised wordmark per density (+ night, since background_dark).
    for (final d in ['mdpi', 'xxhdpi', 'xxxhdpi']) {
      expect(File(res('drawable-$d/splash_branding.png')).existsSync(), isTrue,
          reason: 'missing text branding for $d');
    }
    expect(File(res('drawable-night-xxhdpi/splash_branding.png')).existsSync(),
        isTrue);

    // Pre-31 launch background + v31 theme reference the branding.
    expect(File(res('drawable/launch_background.xml')).readAsStringSync(),
        contains('@drawable/splash_branding'));
    expect(File(res('values-v31/styles.xml')).readAsStringSync(),
        contains('windowSplashScreenBrandingImage'));

    // In-app config carries the text + colour (the widget renders a crisp Text);
    // no branding image bytes are embedded for a text wordmark.
    final cfg = splashCfg();
    expect(cfg, contains("brandingText: 'ListKin'"));
    expect(cfg, contains('brandingTextColorLight: 0xFF1F5560'));
    expect(cfg, contains('brandingLight: null'));
  });

  test('animated-only splash falls back to the app logo for the pre-31 launch',
      () {
    const avd =
        '<animated-vector xmlns:android="http://schemas.android.com/apk/res/android" '
        'xmlns:aapt="http://schemas.android.com/aapt">AVD</animated-vector>';
    File(p.join(project.path, 'assets', 'anim.xml')).writeAsStringSync(avd);
    // No splash `image:`, but a root `source:` is available as the fallback.
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  source: assets/logo.svg
  android:
    splash:
      background: "#E4ECE8"
      animated_icon: assets/anim.xml
''');

    AdaptiveStudio(
      projectRoot: project.path,
      logger: Logger(level: LogLevel.quiet),
    ).run();

    // The pre-31 launch logo is rasterised from the app logo so the launch
    // screen isn't a bare colour, and the launch background references it.
    for (final d in ['mdpi', 'xxhdpi', 'xxxhdpi']) {
      expect(
          File(res('drawable-$d/splash_icon_legacy.png')).existsSync(), isTrue,
          reason: 'expected fallback pre-31 logo for $d');
    }
    final launch =
        File(res('drawable/launch_background.xml')).readAsStringSync();
    expect(launch, contains('@drawable/splash_icon_legacy'));
    // The AVD still drives the API 31+ animated slot.
    expect(File(res('values-v31/styles.xml')).readAsStringSync(),
        contains('windowSplashScreenAnimatedIcon'));
  });

  test('pre-31 splash logo honours image_format: webp', () {
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    splash:
      background: "#FFFFFF"
      image: assets/logo.svg
      image_format: webp
''');

    AdaptiveStudio(
      projectRoot: project.path,
      logger: Logger(level: LogLevel.quiet),
    ).run();

    // WebP per density, and NO stale .png sibling of the same name.
    for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      expect(
          File(res('drawable-$d/splash_icon_legacy.webp')).existsSync(), isTrue,
          reason: 'missing webp pre-31 logo for $d');
      expect(File(res('drawable-$d/splash_icon_legacy.png')).existsSync(),
          isFalse);
    }
    // A real WebP file: starts with the RIFF/WEBP magic.
    final bytes =
        File(res('drawable-xxhdpi/splash_icon_legacy.webp')).readAsBytesSync();
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WEBP');
  });

  test('pre-31 splash logo: image_dark → -night raster per density', () {
    File(p.join(project.path, 'assets', 'logo_dark.svg')).writeAsStringSync(
        '<svg viewBox="0 0 100 100"><rect x="20" y="20" width="60" '
        'height="60" rx="8" fill="#E6F2F4"/></svg>');
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    splash:
      background: "#FFFFFF"
      background_dark: "#0E1A1C"
      image: assets/logo.svg
      image_dark: assets/logo_dark.svg
''');

    AdaptiveStudio(
      projectRoot: project.path,
      logger: Logger(level: LogLevel.quiet),
    ).run();

    // Both light and dark rasters exist; the single launch_background resolves
    // the -night density variant automatically on dark mode.
    expect(File(res('drawable-xxhdpi/splash_icon_legacy.png')).existsSync(),
        isTrue);
    expect(
        File(res('drawable-night-xxhdpi/splash_icon_legacy.png')).existsSync(),
        isTrue);
  });
}

import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory project;
  String res(String rel) =>
      p.join(project.path, 'android', 'app', 'src', 'main', 'res', rel);

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

    // Pre-31 layer-list centres the icon and pins branding to the bottom. The
    // centre logo is the RASTER (`splash_icon_legacy`), not the v31 vector — a
    // VectorDrawable in windowBackground doesn't paint on API 21–23.
    final launch =
        File(res('drawable/launch_background.xml')).readAsStringSync();
    expect(launch, contains('@drawable/splash_icon_legacy'));
    expect(launch, contains('@drawable/splash_branding'));
    expect(launch, contains('bottom|center_horizontal'));

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

    // Flutter fallback drop-in generated with baked colours.
    final glue = File(p.join(project.path, 'flutter_adaptive_studio', 'splash',
            'fas_splash.dart'))
        .readAsStringSync();
    expect(glue, contains('class FasSplash'));
    expect(glue, contains('0xFF0E1A1C')); // dark bg baked in
    expect(glue, contains('sdkInt < 31'));
    // kDebugMode is used to force the splash in debug — foundation MUST be
    // imported for it to compile (material doesn't re-export the k* constants).
    expect(glue, contains('kDebugMode'));
    expect(glue, contains("import 'package:flutter/foundation.dart'"));
    // The fallback mirrors native branding: bottom-centre, same 48dp inset,
    // pointing at the wordmark. No branding_dark here → single (un-themed) asset.
    expect(glue, contains('Alignment.bottomCenter'));
    expect(glue, contains('EdgeInsets.only(bottom: 48)'));
    expect(glue, contains('assets/wordmark.svg'));
    expect(glue, isNot(contains('wordmark_dark')));
  });

  test('FasNativeSplash ships in the package, not generated as a drop-in', () {
    AdaptiveStudio(
      projectRoot: project.path,
      logger: Logger(level: LogLevel.quiet),
    ).run();

    // The keeper now ships as `package:flutter_adaptive_studio/...` — generating
    // it too would collide with the imported class, so it must NOT be written.
    final keeper = File(p.join(project.path, 'flutter_adaptive_studio',
        'splash', 'fas_native_splash.dart'));
    expect(keeper.existsSync(), isFalse);

    // The guide points users at the package import instead.
    final guide = File(p.join(
            project.path, 'flutter_adaptive_studio', 'splash', 'SPLASH.md'))
        .readAsStringSync();
    expect(
        guide,
        contains(
            "import 'package:flutter_adaptive_studio/flutter_adaptive_studio.dart'"));
    expect(guide, contains('FasNativeSplash.preserve'));
  });

  test('the runtime library exposes the FasNativeSplash API', () {
    // Source-level guard on the shipped runtime class (it imports flutter, so it
    // can't be exercised under `dart test`; this asserts its public shape).
    final src = File('lib/src/runtime/native_splash.dart').readAsStringSync();
    expect(src, contains('class FasNativeSplash'));
    expect(src, contains('static void preserve({required WidgetsBinding'));
    expect(src, contains('static void remove()'));
    expect(src, contains('deferFirstFrame'));
    expect(src, contains('allowFirstFrame'));
    expect(src, contains("import 'package:flutter/widgets.dart'"));
  });

  test('themed branding: FasSplash swaps wordmark by app brightness', () {
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

    // Fallback: branding is chosen by the active theme brightness.
    final glue = File(p.join(project.path, 'flutter_adaptive_studio', 'splash',
            'fas_splash.dart'))
        .readAsStringSync();
    expect(glue, contains('dark ?'));
    expect(glue, contains('assets/wordmark_dark.svg'));
    expect(glue, contains('assets/wordmark.svg'));
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

    // Fallback mirrors the branding placement.
    final glue = File(p.join(project.path, 'flutter_adaptive_studio', 'splash',
            'fas_splash.dart'))
        .readAsStringSync();
    expect(glue, contains('Alignment.bottomRight'));
    expect(glue, contains('EdgeInsets.only(bottom: 24)'));
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

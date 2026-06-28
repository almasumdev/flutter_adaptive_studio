import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The in-app splash config (`fas_splash.g.dart`) is platform-agnostic: it bakes
/// iOS overrides for the iOS LaunchScreen, and is generated even for an iOS-only
/// project.
void main() {
  late Directory project;

  String cfg() {
    final lib = File(p.join(project.path, 'lib', 'fas_splash.g.dart'));
    final root = File(p.join(project.path, 'fas_splash.g.dart'));
    return (lib.existsSync() ? lib : root).readAsStringSync();
  }

  setUp(() {
    project = Directory.systemTemp.createTempSync('fas_splash_ios_');
    Directory(p.join(project.path, 'android', 'app', 'src', 'main'))
        .createSync(recursive: true);
    Directory(p.join(project.path, 'ios')).createSync(recursive: true);
    final assets = Directory(p.join(project.path, 'assets'))..createSync();
    File(p.join(assets.path, 'logo.svg')).writeAsStringSync(
        '<svg viewBox="0 0 100 100"><rect x="20" y="20" width="60" '
        'height="60" fill="#3e9aa6"/></svg>');
    File(p.join(assets.path, 'logo_ios.svg')).writeAsStringSync(
        '<svg viewBox="0 0 100 100"><circle cx="50" cy="50" r="40" '
        'fill="#1f5560"/></svg>');
  });

  tearDown(() => project.deleteSync(recursive: true));

  void run() => AdaptiveStudio(
        projectRoot: project.path,
        logger: Logger(level: LogLevel.quiet),
      ).run();

  test('iOS-specific splash → iOS overrides baked into the config', () {
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    splash:
      background: "#FFFFFF"
      image: assets/logo.svg
  ios:
    splash:
      background: "#101820"
      image: assets/logo_ios.svg
''');
    run();

    final c = cfg();
    // Base = Android values.
    expect(c, contains('backgroundLight: 0xFFFFFFFF'));
    expect(c, contains('logo: _b64('));
    // iOS overrides carry the distinct iOS background + logo.
    expect(c, contains('iosBackgroundLight: 0xFF101820'));
    expect(c, contains('iosLogo: _b64('));
  });

  test('matching iOS splash → no redundant iOS overrides', () {
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    splash:
      background: "#FFFFFF"
      image: assets/logo.svg
  ios:
    splash:
      background: "#FFFFFF"
      image: assets/logo.svg
''');
    run();

    final c = cfg();
    // Same look on both → overrides stay null (the widget reuses the base).
    expect(c, contains('iosBackgroundLight: null'));
    expect(c, contains('iosLogo: null'));
  });

  test('iOS-only project still generates fas_splash.g.dart', () {
    // No `android:` block at all.
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  ios:
    splash:
      background: "#FFFFFF"
      background_dark: "#0E1A1C"
      image: assets/logo_ios.svg
''');
    run();

    final c = cfg();
    expect(c, contains('final FasSplashConfig fasSplash'));
    // Base sourced from the iOS splash.
    expect(c, contains('backgroundLight: 0xFFFFFFFF'));
    expect(c, contains('backgroundDark: 0xFF0E1A1C'));
    expect(c, contains('logo: _b64('));
    // iOS has no branding concept.
    expect(c, contains('brandingLight: null'));
    expect(c, contains('brandingText: null'));
  });
}

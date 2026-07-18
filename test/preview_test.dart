import 'dart:convert';
import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
import 'package:flutter_adaptive_studio/src/config/config_loader.dart';
import 'package:flutter_adaptive_studio/src/preview/preview_generator.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The `preview` command writes a self-contained HTML sheet: the icon under each
/// platform's masks with the official safe-zone keylines overlaid (Google's 66dp
/// circle + 72dp square, Apple's squircle), plus a pure-CSS keyline toggle.
void main() {
  late Directory project;

  setUp(() {
    project = Directory.systemTemp.createTempSync('fas_preview_');
    File(p.join(project.path, 'assets', 'logo.svg'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('<svg viewBox="0 0 100 100"><rect x="15" y="15" '
          'width="70" height="70" rx="12" fill="#4285F4"/></svg>');
  });

  tearDown(() => project.deleteSync(recursive: true));

  String? runPreview() {
    final loader = ConfigLoader(project.path);
    final config = loader.load();
    if (config == null) return null;
    return PreviewGenerator(
            config: config,
            loader: loader,
            logger: Logger(level: LogLevel.quiet))
        .generate();
  }

  void writeCfg(String yaml) =>
      File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
          .writeAsStringSync(yaml);

  test('emits Google + Apple keyline overlays, both sections, and a toggle',
      () {
    writeCfg('''
flutter_adaptive_studio:
  android:
    icon:
      adaptive:
        foreground: assets/logo.svg
        background: "#0B1020"
        monochrome: assets/logo.svg
  ios:
    icon:
      image: assets/logo.svg
      background: "#101820"
''');
    final path = runPreview();
    expect(path, isNotNull);
    final html = File(path!).readAsStringSync();

    // Both platform sections.
    expect(html, contains('Android adaptive icon (Google)'));
    expect(html, contains('iOS app icon (Apple)'));

    // Google safe-zone keylines: the 66dp circle (r 33) + the 72dp safe square.
    expect(html, contains('r="33"'));
    expect(html, contains('width="72" height="72"'));

    // Apple squircle clip referenced by the mask + iOS tiles.
    expect(html, contains('clipPath id="squircle"'));
    expect(html, contains('tile m-squircle'));

    // The monochrome themed-icon section (configured above).
    expect(html, contains('Monochrome'));

    // A pure-CSS keyline toggle, no JavaScript.
    expect(html, contains('id="kl"'));
    expect(html, contains(r'body:has(#kl:checked) .kl'));
    expect(html, isNot(contains('<script')));
    // Self-contained: the icons are inline PNG data URIs, no external requests.
    expect(html, contains('src="data:image/png;base64,'));
    expect(html, isNot(contains('src="http')));
  });

  test('an SVG background is composed full-bleed, not a grey fallback', () {
    // A distinct GREEN full-bleed background SVG + a small RED foreground.
    File(p.join(project.path, 'assets', 'bg.svg')).writeAsStringSync(
        '<svg viewBox="0 0 100 100"><rect width="100" height="100" '
        'fill="#1B7F3B"/></svg>');
    File(p.join(project.path, 'assets', 'fg.svg')).writeAsStringSync(
        '<svg viewBox="0 0 100 100"><rect x="35" y="35" width="30" '
        'height="30" fill="#E53935"/></svg>');
    writeCfg('''
flutter_adaptive_studio:
  android:
    icon:
      adaptive:
        foreground: assets/fg.svg
        background: assets/bg.svg
''');
    final html = File(runPreview()!).readAsStringSync();

    // Decode the first composed tile. Its corner is the GREEN ground filling the
    // whole canvas (the old bug painted a grey #E0E0E0 fallback there instead).
    final m = RegExp(r'src="data:image/png;base64,([^"]+)"').firstMatch(html)!;
    final png = img.decodeImage(base64Decode(m.group(1)!))!;
    final corner = png.getPixel(1, 1);
    expect(corner.g > corner.r && corner.g > corner.b, isTrue,
        reason: 'the SVG background fills the tile (green), not grey');
    // The red foreground sits on top, fit to the safe zone (centre is red).
    final mid = png.getPixel(png.width ~/ 2, png.height ~/ 2);
    expect(mid.r > 150 && mid.g < 90, isTrue,
        reason: 'the foreground is composited over the full-bleed ground');
  });

  test('the iOS section is present even without an ios.icon (shared source)',
      () {
    writeCfg('''
flutter_adaptive_studio:
  source: assets/logo.svg
  android:
    icon:
      adaptive:
        background: "#0B1020"
''');
    final html = File(runPreview()!).readAsStringSync();
    expect(html, contains('iOS app icon (Apple)'),
        reason: 'iOS reuses the shared foreground when no ios.icon is set');
    // No monochrome configured → no monochrome section.
    expect(html, isNot(contains('Monochrome')));
  });

  test('skips when the foreground is not an SVG', () {
    writeCfg('''
flutter_adaptive_studio:
  android:
    icon:
      adaptive:
        foreground: assets/logo.png
        background: "#0B1020"
''');
    expect(runPreview(), isNull,
        reason: 'the vector preview needs an SVG foreground');
  });
}

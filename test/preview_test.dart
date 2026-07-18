import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
import 'package:flutter_adaptive_studio/src/config/config_loader.dart';
import 'package:flutter_adaptive_studio/src/preview/preview_generator.dart';
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

    // A pure-CSS keyline toggle, no external/JS dependencies.
    expect(html, contains('id="kl"'));
    expect(html, contains(r'body:has(#kl:checked) .kl'));
    expect(html, isNot(contains('<script')));
    expect(html, isNot(contains('src=')));
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

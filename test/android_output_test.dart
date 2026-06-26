import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Covers three Android output fixes: WebP icon encoding, the Play Store icon
/// location (`src/main`, not the `android/app` root), and de-duplication of a
/// stray `<color name="ic_launcher_background">` that would break the build.
void main() {
  late Directory project;
  String main_(String rel) =>
      p.join(project.path, 'android', 'app', 'src', 'main', rel);
  String res(String rel) => main_(p.join('res', rel));

  void writeManifest() {
    File(main_('AndroidManifest.xml'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
          '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
          '<application android:icon="@mipmap/ic_launcher"/></manifest>');
  }

  void writeSvgLogo() {
    File(p.join(project.path, 'assets', 'logo.svg'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('<svg viewBox="0 0 100 100"><rect x="15" y="15" '
          'width="70" height="70" rx="8" fill="#3e9aa6"/></svg>');
  }

  void run(String yaml) {
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync(yaml);
    AdaptiveStudio(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();
  }

  setUp(() {
    project = Directory.systemTemp.createTempSync('fas_androidout_');
    writeManifest();
    writeSvgLogo();
  });
  tearDown(() => project.deleteSync(recursive: true));

  test('image_format: webp encodes legacy mipmaps as WebP, not PNG', () {
    run('''
flutter_adaptive_studio:
  android:
    icon:
      legacy: true
      image_format: webp
      adaptive:
        foreground: assets/logo.svg
        background: "#FFFFFF"
''');

    final webp = File(res('mipmap-xxxhdpi/ic_launcher.webp'));
    expect(webp.existsSync(), isTrue, reason: 'should write a .webp mipmap');
    expect(File(res('mipmap-xxxhdpi/ic_launcher.png')).existsSync(), isFalse,
        reason: 'should not also write the .png');

    // Valid RIFF/WebP container, and decodable back to 192².
    final bytes = webp.readAsBytesSync();
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WEBP');
    final decoded = img.decodeImage(bytes)!;
    expect(decoded.width, 192);
  });

  test('image_format: webp encodes raster foreground density layers as WebP',
      () {
    final logo = img.Image(width: 96, height: 96, numChannels: 4)
      ..clear(img.ColorRgba8(62, 154, 166, 255));
    File(p.join(project.path, 'assets', 'logo.png'))
        .writeAsBytesSync(img.encodePng(logo));

    run('''
flutter_adaptive_studio:
  android:
    icon:
      image_format: webp
      adaptive:
        foreground: assets/logo.png
        background: "#E4ECE8"
''');

    expect(
        File(res('drawable-xxxhdpi/ic_launcher_foreground.webp')).existsSync(),
        isTrue);
    expect(
        File(res('drawable-xxxhdpi/ic_launcher_foreground.png')).existsSync(),
        isFalse);
    // The adaptive XML references the name only, so WebP resolves fine.
    expect(File(res('mipmap-anydpi-v26/ic_launcher.xml')).readAsStringSync(),
        contains('@drawable/ic_launcher_foreground'));
  });

  test('Play Store icon is written under src/main, not the android/app root',
      () {
    // A stale copy left by an older version in the wrong place.
    final staleRoot = File(
        p.join(project.path, 'android', 'app', 'ic_launcher-playstore.png'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(const [1, 2, 3]);

    run('''
flutter_adaptive_studio:
  android:
    icon:
      play_store: true
      adaptive:
        foreground: assets/logo.svg
        background: "#FFFFFF"
''');

    expect(File(main_('ic_launcher-playstore.png')).existsSync(), isTrue,
        reason: 'store icon belongs in src/main');
    expect(staleRoot.existsSync(), isFalse,
        reason: 'the stale android/app root copy should be cleaned up');
  });

  test('a stray ic_launcher_background.xml duplicate is removed', () {
    // Simulate Android Studio's Image Asset wizard output.
    File(res('values/ic_launcher_background.xml'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('<?xml version="1.0" encoding="utf-8"?>\n'
          '<resources>\n'
          '  <color name="ic_launcher_background">#FF0000</color>\n'
          '</resources>\n');

    run('''
flutter_adaptive_studio:
  android:
    icon:
      adaptive:
        foreground: assets/logo.svg
        background: "#00FF00"
''');

    // The stray single-color file is gone; colors.xml is the single source.
    expect(
        File(res('values/ic_launcher_background.xml')).existsSync(), isFalse);
    final colors = File(res('values/colors.xml')).readAsStringSync();
    expect(colors, contains('name="ic_launcher_background">#00FF00'));
  });

  test(
      'a duplicate color in a shared file is stripped without dropping the file',
      () {
    // A user file that also holds other colours must survive, minus the dupe.
    File(res('values/extra.xml'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('<?xml version="1.0" encoding="utf-8"?>\n'
          '<resources>\n'
          '  <color name="ic_launcher_background">#FF0000</color>\n'
          '  <color name="brandPrimary">#123456</color>\n'
          '</resources>\n');

    run('''
flutter_adaptive_studio:
  android:
    icon:
      adaptive:
        foreground: assets/logo.svg
        background: "#00FF00"
''');

    final extra = File(res('values/extra.xml'));
    expect(extra.existsSync(), isTrue, reason: 'file with other colours stays');
    final body = extra.readAsStringSync();
    expect(body, isNot(contains('ic_launcher_background')));
    expect(body, contains('name="brandPrimary"'));
  });
}

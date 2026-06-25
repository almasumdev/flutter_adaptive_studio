import 'dart:io';

import 'package:flutter_adaptive_studio/flutter_adaptive_studio.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory project;
  String iconSet(String rel) => p.join(project.path, 'ios', 'Runner',
      'Assets.xcassets', 'AppIcon.appiconset', rel);

  setUp(() {
    project = Directory.systemTemp.createTempSync('fas_ios_');
    Directory(p.join(project.path, 'ios', 'Runner', 'Assets.xcassets',
            'AppIcon.appiconset'))
        .createSync(recursive: true);
    // A stale legacy matrix PNG that should be cleaned out.
    File(iconSet('Icon-App-20x20@1x.png')).writeAsStringSync('stale');
    final assets = Directory(p.join(project.path, 'assets'))..createSync();
    for (final name in ['logo', 'logo_dark', 'logo_mono']) {
      File(p.join(assets.path, '$name.svg')).writeAsStringSync(
          '<svg viewBox="0 0 100 100"><circle cx="50" cy="50" r="40" '
          'fill="#3e9aa6"/></svg>');
    }
  });

  tearDown(() => project.deleteSync(recursive: true));

  test('iOS icon: opaque 1024 single-size set + dark/tinted + legacy cleanup',
      () {
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  ios:
    icon:
      image: assets/logo.svg
      background: "#FFFFFF"
      dark: assets/logo_dark.svg
      tinted: assets/logo_mono.svg
''');
    AdaptiveStudio(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();

    // The three appearance PNGs exist.
    final std = File(iconSet('Icon-1024.png'));
    expect(std.existsSync(), isTrue);
    expect(File(iconSet('Icon-1024-dark.png')).existsSync(), isTrue);
    expect(File(iconSet('Icon-1024-tinted.png')).existsSync(), isTrue);

    // 1024² and fully OPAQUE (App Store rejects alpha) — check a transparent
    // corner of the source circle got filled by the background.
    final decoded = img.decodeImage(std.readAsBytesSync())!;
    expect(decoded.width, 1024);
    expect(decoded.height, 1024);
    expect(decoded.getPixel(0, 0).a, 255);

    // Contents.json is the modern single-size universal set with appearances.
    final contents = File(iconSet('Contents.json')).readAsStringSync();
    expect(contents, contains('"size": "1024x1024"'));
    expect(contents, contains('"luminosity"'));
    expect(contents, contains('"value": "dark"'));
    expect(contents, contains('"value": "tinted"'));

    // The stale legacy matrix PNG is gone.
    expect(File(iconSet('Icon-App-20x20@1x.png')).existsSync(), isFalse);
  });

  test('iOS icon falls back to the Android foreground (one source, both OSes)',
      () {
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    icon:
      adaptive:
        foreground: assets/logo.svg
        background: "#FFFFFF"
  ios:
    icon:
      background: "#101820"
''');
    AdaptiveStudio(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();

    // No ios.icon.image given → it used the Android foreground.
    final std = File(iconSet('Icon-1024.png'));
    expect(std.existsSync(), isTrue);
    // Only the standard appearance (no dark/tinted configured).
    expect(File(iconSet('Icon-1024-dark.png')).existsSync(), isFalse);
    final contents = File(iconSet('Contents.json')).readAsStringSync();
    expect(contents, isNot(contains('luminosity')));
  });
}

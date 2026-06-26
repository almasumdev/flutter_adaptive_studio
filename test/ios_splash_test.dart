import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The default Flutter launch storyboard (centres a "LaunchImage" image view).
const _defaultStoryboard =
    '<?xml version="1.0" encoding="UTF-8" standalone="no"?>\n'
    '<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" '
    'launchScreen="YES" initialViewController="01J-lp-oVM">\n'
    '  <scenes><scene sceneID="EHf-IW-A2E"><objects>\n'
    '    <viewController id="01J-lp-oVM" sceneMemberID="viewController">\n'
    '      <view key="view" contentMode="scaleToFill" id="Ze5-6b-2t3">\n'
    '        <subviews>\n'
    '          <imageView contentMode="center" image="LaunchImage" id="YRO-k0-Ey4"/>\n'
    '        </subviews>\n'
    '        <color key="backgroundColor" red="1" green="1" blue="1" alpha="1" '
    'colorSpace="custom" customColorSpace="sRGB"/>\n'
    '      </view>\n'
    '    </viewController>\n'
    '  </objects></scene></scenes>\n'
    '  <resources><image name="LaunchImage" width="168" height="185"/></resources>\n'
    '</document>\n';

void main() {
  late Directory project;
  String asset(String rel) =>
      p.join(project.path, 'ios', 'Runner', 'Assets.xcassets', rel);
  String storyboardPath() => p.join(
      project.path, 'ios', 'Runner', 'Base.lproj', 'LaunchScreen.storyboard');

  setUp(() {
    project = Directory.systemTemp.createTempSync('fas_iossplash_');
    Directory(p.join(project.path, 'ios', 'Runner', 'Assets.xcassets'))
        .createSync(recursive: true);
    Directory(p.join(project.path, 'ios', 'Runner', 'Base.lproj'))
        .createSync(recursive: true);
    File(storyboardPath()).writeAsStringSync(_defaultStoryboard);
    final assets = Directory(p.join(project.path, 'assets'))..createSync();
    for (final n in ['logo', 'logo_dark']) {
      File(p.join(assets.path, '$n.svg')).writeAsStringSync(
          '<svg viewBox="0 0 100 100"><circle cx="50" cy="50" r="40" '
          'fill="#3e9aa6"/></svg>');
    }
  });

  tearDown(() => project.deleteSync(recursive: true));

  test('iOS splash: colour set (light+dark), logo imageset, storyboard bg', () {
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  ios:
    splash:
      background: "#FFFFFF"
      background_dark: "#0E1A1C"
      image: assets/logo.svg
      image_dark: assets/logo_dark.svg
''');
    AdaptiveStudio(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();

    // Background colour set with a light + dark entry.
    final colors = File(asset('LaunchBackground.colorset/Contents.json'))
        .readAsStringSync();
    expect(colors, contains('"luminosity"'));
    expect(
        colors, contains('"blue": "0.110"')); // 0x0E1A1C blue = 28/255 ≈ 0.110

    // Logo imageset: light @1x/2x/3x + dark variants.
    expect(File(asset('LaunchImage.imageset/LaunchImage.png')).existsSync(),
        isTrue);
    expect(File(asset('LaunchImage.imageset/LaunchImage@3x.png')).existsSync(),
        isTrue);
    expect(
        File(asset('LaunchImage.imageset/LaunchImage@2x~dark.png'))
            .existsSync(),
        isTrue);

    // Storyboard background now points at the colour set.
    final story = File(storyboardPath()).readAsStringSync();
    expect(story, contains('key="backgroundColor" name="LaunchBackground"'));
    expect(story, contains('<namedColor name="LaunchBackground"'));
    expect(story, isNot(contains('red="1" green="1" blue="1"')));
  });

  test('iOS splash inherits from the Android splash (one source)', () {
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    splash:
      background: "#123456"
      image: assets/logo.svg
  ios:
    splash: {}
''');
    AdaptiveStudio(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();

    // No iOS-specific values, but it used the Android splash background + logo.
    expect(
        File(asset('LaunchBackground.colorset/Contents.json'))
            .readAsStringSync(),
        contains('"red": "0.071"')); // 0x12 = 18/255 ≈ 0.071
    expect(File(asset('LaunchImage.imageset/LaunchImage.png')).existsSync(),
        isTrue);
  });
}

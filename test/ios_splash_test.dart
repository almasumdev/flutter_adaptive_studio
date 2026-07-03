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

  test('iOS splash strips a stale flutter_native_splash launch background', () {
    // A project migrated from flutter_native_splash: a full-bleed
    // <imageView image="LaunchBackground"> (pinned by a constraint) painting
    // OVER the logo, plus a colliding LaunchBackground *imageset*. Both must be
    // removed or the stale image shadows our colour set on iOS.
    File(storyboardPath()).writeAsStringSync(
        '<?xml version="1.0" encoding="UTF-8" standalone="no"?>\n'
        '<document launchScreen="YES" initialViewController="01J-lp-oVM">\n'
        '  <scenes><scene sceneID="EHf-IW-A2E"><objects>\n'
        '    <viewController id="01J-lp-oVM" sceneMemberID="viewController">\n'
        '      <view key="view" contentMode="scaleToFill" id="Ze5-6b-2t3">\n'
        '        <subviews>\n'
        '          <imageView contentMode="scaleAspectFill" image="LaunchBackground" id="bg1"/>\n'
        '          <imageView contentMode="center" image="LaunchImage" id="YRO-k0-Ey4"/>\n'
        '        </subviews>\n'
        '        <constraints>\n'
        '          <constraint firstItem="bg1" firstAttribute="top" secondItem="Ze5-6b-2t3" secondAttribute="top" id="c-bg"/>\n'
        '          <constraint firstItem="YRO-k0-Ey4" firstAttribute="centerX" secondItem="Ze5-6b-2t3" secondAttribute="centerX" id="c-logo"/>\n'
        '        </constraints>\n'
        '        <color key="backgroundColor" systemColor="systemBackgroundColor"/>\n'
        '      </view>\n'
        '    </viewController>\n'
        '  </objects></scene></scenes>\n'
        '  <resources>\n'
        '    <image name="LaunchBackground" width="1" height="1"/>\n'
        '    <image name="LaunchImage" width="168" height="185"/>\n'
        '  </resources>\n'
        '</document>\n');
    Directory(asset('LaunchBackground.imageset')).createSync(recursive: true);
    File(asset('LaunchBackground.imageset/Contents.json'))
        .writeAsStringSync('{}');

    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  ios:
    splash:
      background: "#FFFFFF"
      image: assets/logo.svg
''');
    AdaptiveStudio(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();

    final story = File(storyboardPath()).readAsStringSync();
    // The full-bleed background image view + its <image> resource are gone.
    expect(story, isNot(contains('image="LaunchBackground"')));
    expect(story, isNot(contains('<image name="LaunchBackground"')));
    // Its orphaned constraint is gone; the logo's constraint survives.
    expect(story, isNot(contains('id="c-bg"')));
    expect(story, contains('id="c-logo"'));
    // The centred logo view is preserved, now over the colour set.
    expect(story, contains('image="LaunchImage"'));
    expect(story, contains('key="backgroundColor" name="LaunchBackground"'));
    // The colliding imageset is deleted; only the colour set remains.
    expect(Directory(asset('LaunchBackground.imageset')).existsSync(), isFalse);
    expect(File(asset('LaunchBackground.colorset/Contents.json')).existsSync(),
        isTrue);
  });

  test('iOS splash: full-bleed background image sits behind the logo', () {
    File(p.join(project.path, 'assets', 'bg.svg')).writeAsStringSync(
        '<svg viewBox="0 0 200 400"><rect width="200" height="400" '
        'fill="#3949AB"/><circle cx="100" cy="150" r="70" fill="#FFD54F"/></svg>');
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  ios:
    splash:
      background: "#3949AB"
      background_image: assets/bg.svg
      image: assets/logo.svg
''');
    AdaptiveStudio(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();

    // The image set is written (light entry; no dark configured).
    expect(
        File(asset('LaunchBackgroundImage.imageset/LaunchBackgroundImage.png'))
            .existsSync(),
        isTrue);

    final story = File(storyboardPath()).readAsStringSync();
    // A full-bleed scaleAspectFill image view pinned to all four edges.
    expect(story, contains('image="LaunchBackgroundImage"'));
    expect(story, contains('contentMode="scaleAspectFill"'));
    for (final id in [
      'fasBgTop',
      'fasBgLeading',
      'fasBgTrailing',
      'fasBgBottom'
    ]) {
      expect(story, contains('id="$id"'), reason: 'missing pin $id');
    }
    expect(story, contains('<image name="LaunchBackgroundImage"'));
    // Behind the centred logo (its view appears before the logo view), over the
    // colour set.
    expect(story, contains('image="LaunchImage"'));
    expect(story.indexOf('image="LaunchBackgroundImage"'),
        lessThan(story.indexOf('image="LaunchImage"')));
    expect(story, contains('key="backgroundColor" name="LaunchBackground"'));

    // Idempotent: a second run does not duplicate the view, pins, or resource.
    AdaptiveStudio(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();
    final again = File(storyboardPath()).readAsStringSync();
    expect(RegExp('image="LaunchBackgroundImage"').allMatches(again).length, 1);
    expect(RegExp('id="fasBgTop"').allMatches(again).length, 1);
    expect(
        RegExp('<image name="LaunchBackgroundImage"').allMatches(again).length,
        1);
  });

  test('iOS splash: removing background_image cleans up the launch screen', () {
    final cfg = File(p.join(project.path, 'flutter_adaptive_studio.yaml'));
    File(p.join(project.path, 'assets', 'bg.svg')).writeAsStringSync(
        '<svg viewBox="0 0 200 400"><rect width="200" height="400" '
        'fill="#3949AB"/></svg>');
    cfg.writeAsStringSync('''
flutter_adaptive_studio:
  ios:
    splash:
      background: "#3949AB"
      background_image: assets/bg.svg
      image: assets/logo.svg
''');
    AdaptiveStudio(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();
    expect(Directory(asset('LaunchBackgroundImage.imageset')).existsSync(),
        isTrue);

    // Drop background_image and regenerate: the image set, the image view, its
    // constraints, and its <image> resource are all removed; the logo stays.
    cfg.writeAsStringSync('''
flutter_adaptive_studio:
  ios:
    splash:
      background: "#3949AB"
      image: assets/logo.svg
''');
    AdaptiveStudio(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();

    expect(Directory(asset('LaunchBackgroundImage.imageset')).existsSync(),
        isFalse);
    final story = File(storyboardPath()).readAsStringSync();
    expect(story, isNot(contains('image="LaunchBackgroundImage"')));
    expect(story, isNot(contains('id="fasBgTop"')));
    expect(story, isNot(contains('<image name="LaunchBackgroundImage"')));
    expect(story, contains('image="LaunchImage"'));
  });
}

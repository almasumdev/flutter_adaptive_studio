import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xml/xml.dart';

/// Behavioural coverage for config keys the audit flagged as wired-but-untested:
/// the iOS-only `ios.splash.logo_size`, `ios.splash.background_image_dark`, and
/// `ios.icon.padding`; the `android.icon.image` full-bleed positive path (an
/// image with no adaptive foreground); and the `-dark` splash overrides
/// `branding_text_color_dark`, `status_bar_icon_brightness_dark`, and
/// `navigation_bar_icon_brightness_dark`.
///
/// The `-light` counterparts already have coverage (splash_extras_test,
/// splash_logo_size_test, icon_image_inset_test); these close the dark/iOS gaps.
void main() {
  /// The default Flutter launch storyboard (centres a "LaunchImage" view).
  const storyboard = '<?xml version="1.0" encoding="UTF-8" standalone="no"?>\n'
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

  /// A Flutter iOS project skeleton: an empty AppIcon set + a default launch
  /// storyboard + an `assets/` dir, enough to drive `ios.icon` and `ios.splash`.
  Directory newIosProject() {
    final project = Directory.systemTemp.createTempSync('fas_cov_ios_');
    Directory(p.join(project.path, 'ios', 'Runner', 'Assets.xcassets',
            'AppIcon.appiconset'))
        .createSync(recursive: true);
    final base = Directory(p.join(project.path, 'ios', 'Runner', 'Base.lproj'))
      ..createSync(recursive: true);
    File(p.join(base.path, 'LaunchScreen.storyboard'))
        .writeAsStringSync(storyboard);
    Directory(p.join(project.path, 'assets')).createSync();
    return project;
  }

  /// A Flutter Android project skeleton with a manifest + an `assets/` dir.
  Directory newAndroidProject() {
    final project = Directory.systemTemp.createTempSync('fas_cov_android_');
    File(p.join(
        project.path, 'android', 'app', 'src', 'main', 'AndroidManifest.xml'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
          '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
          '<application android:icon="@mipmap/ic_launcher"/></manifest>');
    Directory(p.join(project.path, 'assets')).createSync();
    return project;
  }

  void run(Directory project) => AdaptiveStudio(
          projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
      .run();

  void writeCfg(Directory project, String yaml) =>
      File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
          .writeAsStringSync(yaml);

  /// A full-bleed single-colour SVG (fills its viewBox), so a rendered corner or
  /// centre pixel is a deterministic sample of that colour.
  String solidSvg(String hex) =>
      '<svg viewBox="0 0 100 100"><rect width="100" height="100" '
      'fill="$hex"/></svg>';

  /// Counts pixels satisfying [test] over (r, g, b, a).
  int countPixels(
      img.Image im, bool Function(num r, num g, num b, num a) test) {
    var n = 0;
    for (var y = 0; y < im.height; y++) {
      for (var x = 0; x < im.width; x++) {
        final px = im.getPixel(x, y);
        if (test(px.r, px.g, px.b, px.a)) n++;
      }
    }
    return n;
  }

  // ------------------------------------------------------- ios.splash.logo_size

  group('ios.splash.logo_size', () {
    test('sizes the LaunchImage imageset (1x = pt, 2x = 2×, 3x = 3×)', () {
      final project = newIosProject();
      addTearDown(() => project.deleteSync(recursive: true));
      File(p.join(project.path, 'assets', 'logo.svg'))
          .writeAsStringSync(solidSvg('#3e9aa6'));
      writeCfg(project, '''
flutter_adaptive_studio:
  ios:
    splash:
      background: "#FFFFFF"
      image: assets/logo.svg
      logo_size: 120
''');
      run(project);

      int side(String file) {
        final f = File(p.join(project.path, 'ios', 'Runner', 'Assets.xcassets',
            'LaunchImage.imageset', file));
        expect(f.existsSync(), isTrue, reason: 'missing $file');
        return img.decodeImage(f.readAsBytesSync())!.width;
      }

      // Custom 120 pt drives 120 / 240 / 360 px, distinct from the 192 default.
      expect(side('LaunchImage.png'), 120);
      expect(side('LaunchImage@2x.png'), 240);
      expect(side('LaunchImage@3x.png'), 360);
    });
  });

  // -------------------------------------------- ios.splash.background_image_dark

  group('ios.splash.background_image_dark', () {
    test('writes a ~dark image + a dark appearance entry from the dark source',
        () {
      final project = newIosProject();
      addTearDown(() => project.deleteSync(recursive: true));
      File(p.join(project.path, 'assets', 'logo.svg'))
          .writeAsStringSync(solidSvg('#3e9aa6'));
      File(p.join(project.path, 'assets', 'bg.svg'))
          .writeAsStringSync(solidSvg('#3949AB')); // blue-dominant
      File(p.join(project.path, 'assets', 'bg_dark.svg'))
          .writeAsStringSync(solidSvg('#1B5E20')); // green-dominant
      writeCfg(project, '''
flutter_adaptive_studio:
  ios:
    splash:
      background: "#FFFFFF"
      background_image: assets/bg.svg
      background_image_dark: assets/bg_dark.svg
      image: assets/logo.svg
''');
      run(project);

      final set = p.join(project.path, 'ios', 'Runner', 'Assets.xcassets',
          'LaunchBackgroundImage.imageset');
      final light = File(p.join(set, 'LaunchBackgroundImage.png'));
      final dark = File(p.join(set, 'LaunchBackgroundImage~dark.png'));
      expect(light.existsSync(), isTrue);
      expect(dark.existsSync(), isTrue,
          reason: 'background_image_dark must emit a ~dark variant');

      // The dark PNG is rendered from the DARK source, not a copy of the light
      // one: its centre is green-dominant (#1B5E20), whereas light is blue.
      final di = img.decodeImage(dark.readAsBytesSync())!;
      final c = di.getPixel(di.width ~/ 2, di.height ~/ 2);
      expect(c.g > c.b && c.g > c.r && c.b < 120, isTrue,
          reason: 'the dark background uses assets/bg_dark.svg');

      // Contents.json carries the dark appearance, keyed to the ~dark file.
      final contents = File(p.join(set, 'Contents.json')).readAsStringSync();
      expect(contents, contains('"value": "dark"'));
      expect(contents, contains('LaunchBackgroundImage~dark.png'));
    });
  });

  // ----------------------------------------------------------- ios.icon.padding

  group('ios.icon.padding', () {
    // A full-bleed mark on a white background: padding fits the mark smaller, so
    // the coloured area shrinks and white shows around it.
    int markPixels(int? padding) {
      final project = newIosProject();
      addTearDown(() => project.deleteSync(recursive: true));
      File(p.join(project.path, 'assets', 'mark.svg'))
          .writeAsStringSync(solidSvg('#3355FF')); // blue mark
      writeCfg(project, '''
flutter_adaptive_studio:
  ios:
    icon:
      image: assets/mark.svg
      background: "#FFFFFF"
${padding == null ? '' : '      padding: $padding'}
''');
      run(project);
      final icon = File(p.join(project.path, 'ios', 'Runner', 'Assets.xcassets',
          'AppIcon.appiconset', 'Icon-1024.png'));
      expect(icon.existsSync(), isTrue);
      final im = img.decodeImage(icon.readAsBytesSync())!;
      // Blue (mark) vs white (background): b high, r low.
      return countPixels(im, (r, g, b, a) => b > 180 && r < 120);
    }

    test('padding insets the mark; 0/absent fills the square', () {
      const total = 1024 * 1024;
      final unpadded = markPixels(null);
      final padded = markPixels(40);
      expect(unpadded, greaterThan((total * 0.9).round()),
          reason: 'padding 0/absent fills the icon square with the mark');
      expect(padded, lessThan((total * 0.5).round()),
          reason: 'padding 40 fits the mark to ~60% per side (~36% area)');
      expect(padded, lessThan(unpadded));
    });
  });

  // ------------------------------------------------------- android.icon.image

  group('android.icon.image', () {
    test(
        'supplies the full-bleed legacy + Play Store icons when the adaptive '
        'block carries no foreground of its own', () {
      final project = newAndroidProject();
      addTearDown(() => project.deleteSync(recursive: true));
      // The adaptive foreground (from the top-level `source`) is a RED mark; the
      // finished full-bleed `icon.image` is BLUE. The legacy raster + Play Store
      // must be the image, not the foreground.
      File(p.join(project.path, 'assets', 'mark.svg')).writeAsStringSync(
          '<svg viewBox="0 0 100 100"><rect x="30" y="30" width="40" '
          'height="40" fill="#FF0000"/></svg>');
      File(p.join(project.path, 'assets', 'finished.svg'))
          .writeAsStringSync(solidSvg('#3355FF'));
      writeCfg(project, '''
flutter_adaptive_studio:
  source: assets/mark.svg
  android:
    icon:
      legacy: true
      play_store: true
      image: assets/finished.svg
      adaptive:
        background: "#FFFFFF"
''');
      run(project);

      String main(String rel) =>
          p.join(project.path, 'android', 'app', 'src', 'main', rel);
      bool blue(num r, num g, num b, num a) => a > 200 && b > 180 && r < 120;
      bool red(num r, num g, num b, num a) =>
          a > 200 && r > 180 && g < 80 && b < 80;

      // The adaptive icon still builds, its foreground from the top-level source.
      expect(File(main('res/mipmap-anydpi-v26/ic_launcher.xml')).existsSync(),
          isTrue);

      // The legacy mipmap is the BLUE image full-bleed: no RED foreground shows
      // through, and the blue reaches the straight edge (the extreme corner is
      // rounded off by the 8% shape mask, so sample just inside it).
      final legacy = img.decodeImage(
          File(main('res/mipmap-xxxhdpi/ic_launcher.png')).readAsBytesSync())!;
      expect(countPixels(legacy, red), 0,
          reason: 'icon.image supersedes the foreground for the legacy raster');
      final edge = legacy.getPixel(2, legacy.height ~/ 2);
      expect(blue(edge.r, edge.g, edge.b, edge.a), isTrue,
          reason: 'the image is full-bleed to the edge, not inset');

      // The 512² Play Store icon is likewise full-bleed BLUE, opaque to the
      // corner (it carries no rounding).
      final store = img.decodeImage(
          File(main('ic_launcher-playstore.png')).readAsBytesSync())!;
      expect(store.width, 512);
      final corner = store.getPixel(0, 0);
      expect(corner.a, 255);
      expect(blue(corner.r, corner.g, corner.b, corner.a), isTrue,
          reason: 'Play Store icon is full-bleed from icon.image');
      expect(countPixels(store, red), 0);
    });
  });

  // ------------------------------ android.splash.branding_text_color_dark

  group('android.splash.branding_text_color_dark', () {
    test('colours the -night wordmark independently of the day wordmark', () {
      final project = newAndroidProject();
      addTearDown(() => project.deleteSync(recursive: true));
      File(p.join(project.path, 'assets', 'logo.svg'))
          .writeAsStringSync(solidSvg('#3e9aa6'));
      writeCfg(project, '''
flutter_adaptive_studio:
  android:
    splash:
      background: "#FFFFFF"
      background_dark: "#000000"
      image: assets/logo.svg
      branding_text: "ACME"
      branding_text_color: "#FF0000"
      branding_text_color_dark: "#00FF00"
''');
      run(project);

      // The clearest (highest-density) day vs -night branding raster.
      img.Image? branding({required bool night}) {
        final res = Directory(
            p.join(project.path, 'android', 'app', 'src', 'main', 'res'));
        img.Image? best;
        for (final f in res.listSync(recursive: true)) {
          if (f is! File || !f.path.endsWith('splash_branding.png')) continue;
          final isNight =
              f.path.replaceAll('\\', '/').contains('drawable-night');
          if (isNight != night) continue;
          final im = img.decodeImage(f.readAsBytesSync());
          if (im == null) continue;
          if (best == null || im.width * im.height > best.width * best.height) {
            best = im;
          }
        }
        return best;
      }

      bool redGlyph(num r, num g, num b, num a) =>
          a > 200 && r > 180 && g < 80 && b < 80;
      bool greenGlyph(num r, num g, num b, num a) =>
          a > 200 && g > 180 && r < 80 && b < 80;

      final day = branding(night: false);
      final dark = branding(night: true);
      expect(day, isNotNull, reason: 'day branding raster expected');
      expect(dark, isNotNull,
          reason: 'branding_text_color_dark must emit a -night raster');

      // Day wordmark is red (branding_text_color); no green.
      expect(countPixels(day!, redGlyph), greaterThan(0));
      expect(countPixels(day, greenGlyph), 0);
      // Night wordmark is green (branding_text_color_dark); no red.
      expect(countPixels(dark!, greenGlyph), greaterThan(0));
      expect(countPixels(dark, redGlyph), 0);
    });
  });

  // ------------------ android.splash.{status,navigation}_bar_icon_brightness_dark

  group('android.splash system-bar icon brightness (dark override)', () {
    test('the _dark override wins in -night, independently of the day value',
        () {
      final project = newAndroidProject();
      addTearDown(() => project.deleteSync(recursive: true));
      File(p.join(project.path, 'assets', 'logo.svg'))
          .writeAsStringSync(solidSvg('#3e9aa6'));
      // Each brightness is the OPPOSITE of what the bar colour would auto-derive
      // (a white bar auto-derives dark icons ⇒ windowLight*Bar=true), so a passing
      // assertion can only come from the explicit key being read.
      writeCfg(project, '''
flutter_adaptive_studio:
  android:
    splash:
      background: "#FFFFFF"
      background_dark: "#000000"
      image: assets/logo.svg
      status_bar_color: "#FFFFFF"
      status_bar_color_dark: "#000000"
      status_bar_icon_brightness: light
      status_bar_icon_brightness_dark: dark
      navigation_bar_color: "#FFFFFF"
      navigation_bar_color_dark: "#000000"
      navigation_bar_icon_brightness: light
      navigation_bar_icon_brightness_dark: dark
''');
      run(project);

      String? item(String stylesRel, String name) {
        final f = File(p.join(
            project.path, 'android', 'app', 'src', 'main', 'res', stylesRel));
        expect(f.existsSync(), isTrue, reason: 'missing $stylesRel');
        for (final it in XmlDocument.parse(f.readAsStringSync())
            .findAllElements('item')) {
          if (it.getAttribute('name') == 'android:$name') {
            return it.innerText.trim();
          }
        }
        return null;
      }

      // Day: brightness=light forces LIGHT icons ⇒ windowLight*Bar=false
      // (opposite of the white bar's auto-derived true).
      expect(item('values/styles.xml', 'windowLightStatusBar'), 'false');
      expect(item('values/styles.xml', 'windowLightNavigationBar'), 'false');
      // Night: brightness_dark=dark forces DARK icons ⇒ windowLight*Bar=true
      // (opposite of the black bar's auto-derived false).
      expect(item('values-night/styles.xml', 'windowLightStatusBar'), 'true');
      expect(
          item('values-night/styles.xml', 'windowLightNavigationBar'), 'true');
    });
  });
}

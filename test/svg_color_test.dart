import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
import 'package:flutter_adaptive_studio/src/graphic/config_color.dart';
import 'package:flutter_adaptive_studio/src/graphic/svg_color.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A logger that keeps its warnings instead of printing them.
class _RecordingLogger extends Logger {
  final warnings = <String>[];

  @override
  void warn(String message) => warnings.add(message);
}

void main() {
  group('Malformed colours', () {
    test('a malformed value resolves to flagged black, never throws', () {
      // These used to throw out of int.parse, double.parse or substring, so
      // one odd value in an SVG or the config ended the whole generate run.
      for (final value in [
        '#gggggg',
        '#12345z',
        'rgb(1,2)',
        'rgb(10,20',
        'rgb(a,b,c)',
        'rgba(1,2,3,x)',
        'rgb)1,2,3(',
      ]) {
        final color = SvgColor.parse(value);
        expect(color.recognised, isFalse, reason: value);
        expect(color.argb, 0xFF000000, reason: value);
      }
    });

    test('valid colours read as before', () {
      expect(SvgColor.parse('#FFF').argb, 0xFFFFFFFF);
      expect(SvgColor.parse('#336699').argb, 0xFF336699);
      expect(SvgColor.parse('#33669980').argb, 0x80336699);
      expect(SvgColor.parse('rgb(255, 0, 0)').argb, 0xFFFF0000);
      expect(SvgColor.parse('rgb(100%, 0%, 0%)').argb, 0xFFFF0000);
      expect(SvgColor.parse('rgba(0, 0, 255, 0.5)').argb, 0x800000FF);
      expect(SvgColor.parse('red').recognised, isTrue);
    });
  });

  group('Config colours', () {
    test('a colour the user typed wrongly is reported, naming the key', () {
      // Without this the icon simply came out black with nothing saying why.
      final logger = _RecordingLogger();
      final argb = configColorArgb('#FFFFGG', 'background', logger);
      expect(argb, 0xFF000000);
      expect(logger.warnings, hasLength(1));
      expect(logger.warnings.single, contains('background'));
      expect(logger.warnings.single, contains('#FFFFGG'));
    });

    test('a valid colour is read quietly', () {
      final logger = _RecordingLogger();
      expect(configColorArgb('#336699', 'background', logger), 0xFF336699);
      expect(logger.warnings, isEmpty);
    });
  });

  group('Config colours on iOS', () {
    late Directory project;

    setUp(() {
      project = Directory.systemTemp.createTempSync('fas_color_ios_');
      Directory(
        p.join(project.path, 'ios', 'Runner', 'Assets.xcassets',
            'AppIcon.appiconset'),
      ).createSync(recursive: true);
      Directory(p.join(project.path, 'ios', 'Runner', 'Base.lproj'))
          .createSync(recursive: true);
      File(p.join(project.path, 'ios', 'Runner', 'Base.lproj',
              'LaunchScreen.storyboard'))
          .writeAsStringSync(
        '<?xml version="1.0" encoding="UTF-8" standalone="no"?>\n'
        '<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" '
        'launchScreen="YES" initialViewController="01J-lp-oVM">\n'
        '  <scenes><scene sceneID="EHf-IW-A2E"><objects>\n'
        '    <viewController id="01J-lp-oVM" sceneMemberID="viewController">\n'
        '      <view key="view" contentMode="scaleToFill" id="Ze5-6b-2t3">\n'
        '        <subviews>\n'
        '          <imageView contentMode="center" image="LaunchImage" id="YRO-k0-Ey4"/>\n'
        '        </subviews>\n'
        '      </view>\n'
        '    </viewController>\n'
        '  </objects></scene></scenes>\n'
        '</document>\n',
      );
      Directory(p.join(project.path, 'assets')).createSync();
      File(p.join(project.path, 'assets', 'logo.svg')).writeAsStringSync(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<rect width="10" height="10" fill="#336699"/></svg>',
      );
    });

    tearDown(() => project.deleteSync(recursive: true));

    List<String> run(String yaml) {
      File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
          .writeAsStringSync(yaml);
      final logger = _RecordingLogger();
      AdaptiveStudio(projectRoot: project.path, logger: logger).run();
      return logger.warnings;
    }

    test('a mistyped icon background is reported, not silently black', () {
      final warnings = run('''
ios:
  icon:
    image: assets/logo.svg
    background: "#FFFFGG"
''');
      expect(
        warnings.where((w) => w.contains('ios.icon.background')),
        hasLength(1),
      );
      expect(warnings.join(), contains('#FFFFGG'));
    });

    test('a mistyped splash background is reported, dark included', () {
      final warnings = run('''
ios:
  splash:
    image: assets/logo.svg
    background: "rgb(1,2"
    background_dark: "#zzzzzz"
''');
      expect(warnings.join(), contains('ios.splash.background '));
      expect(warnings.join(), contains('ios.splash.background_dark'));
    });

    test('valid colours say nothing', () {
      final warnings = run('''
ios:
  icon:
    image: assets/logo.svg
    background: "#336699"
  splash:
    image: assets/logo.svg
    background: "#FFFFFF"
    background_dark: "#000000"
''');
      expect(warnings.where((w) => w.contains('is not a colour')), isEmpty);
    });
  });
}

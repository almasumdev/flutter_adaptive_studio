import 'package:flutter_adaptive_studio/src/graphic/config_color.dart';
import 'package:flutter_adaptive_studio/src/graphic/svg_color.dart';
import 'package:flutter_adaptive_studio/src/logger.dart';
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
}

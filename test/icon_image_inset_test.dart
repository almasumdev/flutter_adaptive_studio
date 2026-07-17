import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Padding is a foreground concern. A finished `icon.image` already carries its
/// own background full-bleed with the mark framed as authored, so the legacy
/// mipmaps and the Play Store PNG use it edge-to-edge, even when an adaptive
/// `safe_zone` is set (that governs the bare adaptive foreground, not a finished
/// image). An explicit `legacy_padding` / `play_store_padding` insets it on
/// purpose.
void main() {
  late Directory project;
  String main_(String rel) =>
      p.join(project.path, 'android', 'app', 'src', 'main', rel);

  /// Generates from a full-bleed red `icon.image` over a white background and
  /// returns the opaque 512² Play Store PNG.
  img.Image storeIcon({int? legacyPadding}) {
    final dir = Directory.systemTemp.createTempSync('fas_iconimg_');
    project = dir;
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    File(main_('AndroidManifest.xml'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
          '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
          '<application android:icon="@mipmap/ic_launcher"/></manifest>');

    // A finished, edge-to-edge red icon (no built-in padding).
    final red = img.Image(width: 256, height: 256, numChannels: 4)
      ..clear(img.ColorRgba8(255, 0, 0, 255));
    File(p.join(project.path, 'assets', 'icon.png'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(img.encodePng(red));
    // A foreground the adaptive layer composes from (so an adaptive safe zone is
    // in play; the finished icon.image must NOT inherit that inset).
    File(p.join(project.path, 'assets', 'logo.svg')).writeAsStringSync(
        '<svg viewBox="0 0 100 100"><rect width="100" height="100" '
        'fill="#FF0000"/></svg>');

    final padLine =
        legacyPadding == null ? '' : '      legacy_padding: $legacyPadding\n';
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    icon:
      legacy: true
      play_store: true
$padLine      image: assets/icon.png
      adaptive:
        foreground: assets/logo.svg
        background: "#FFFFFF"
        safe_zone: fit
''');

    AdaptiveStudio(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();

    final store = File(main_('ic_launcher-playstore.png'));
    expect(store.existsSync(), isTrue, reason: 'Play Store icon should emit');
    return img.decodeImage(store.readAsBytesSync())!;
  }

  bool isRed(img.Pixel px) => px.r > 200 && px.g < 80 && px.b < 80;
  bool isWhite(img.Pixel px) => px.r > 200 && px.g > 200 && px.b > 200;

  test('a finished icon.image is full-bleed by default on the Play Store PNG',
      () {
    final store = storeIcon();
    expect(store.width, 512);
    // Full-bleed: the finished icon's own ground reaches the corner. The
    // adaptive safe_zone does NOT matte a border around it.
    expect(isRed(store.getPixel(4, 4)), isTrue,
        reason: 'a finished icon.image must not be inset by the safe zone');
    expect(isRed(store.getPixel(256, 256)), isTrue,
        reason: 'the art still fills the centre');
  });

  test('legacy_padding insets a finished icon.image on purpose', () {
    final store = storeIcon(legacyPadding: 25);
    // Inset → a background-coloured (white) border; the art is centred and does
    // not reach the corner.
    expect(isWhite(store.getPixel(4, 4)), isTrue,
        reason: 'legacy_padding must inset the finished icon');
    expect(isRed(store.getPixel(256, 256)), isTrue,
        reason: 'the art is still centred');
  });

  test('a larger inset leaves less art than the full-bleed default', () {
    int redPixels(img.Image im) {
      var n = 0;
      for (var y = 0; y < im.height; y++) {
        for (var x = 0; x < im.width; x++) {
          if (isRed(im.getPixel(x, y))) n++;
        }
      }
      return n;
    }

    final fullBleed = redPixels(storeIcon()); // default, edge-to-edge
    final inset = redPixels(storeIcon(legacyPadding: 25));
    expect(inset, greaterThan(0));
    expect(inset, lessThan(fullBleed),
        reason:
            'legacy_padding must leave less art than the full-bleed default');
  });
}

import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A finished `icon.image` must be inset to match the adaptive foreground (and
/// the iOS icon) on the raster outputs — the legacy mipmaps and the Play Store
/// PNG — so every generated icon shares one framing. `legacy_padding: 0` opts
/// back into edge-to-edge for a genuinely pre-framed icon.
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
    // A foreground the adaptive layer composes from (so an adaptive safe zone
    // is in play — the inset intent the finished icon should also follow).
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

  test('icon.image is inset to the safe zone on the Play Store PNG', () {
    final store = storeIcon();
    expect(store.width, 512);
    // Inset → a background-coloured (white) border; the red art is centred and
    // does not reach the corner.
    expect(isWhite(store.getPixel(4, 4)), isTrue,
        reason: 'corner should be the background, not the art');
    expect(isRed(store.getPixel(256, 256)), isTrue,
        reason: 'the art is still centred');
  });

  test('legacy_padding: 0 keeps a finished icon.image edge-to-edge', () {
    final store = storeIcon(legacyPadding: 0);
    // Full-bleed → the red art reaches the corner.
    expect(isRed(store.getPixel(4, 4)), isTrue,
        reason: 'legacy_padding: 0 must opt back into edge-to-edge');
  });

  test('the inset shrinks the red area vs. edge-to-edge', () {
    int redPixels(img.Image im) {
      var n = 0;
      for (var y = 0; y < im.height; y++) {
        for (var x = 0; x < im.width; x++) {
          if (isRed(im.getPixel(x, y))) n++;
        }
      }
      return n;
    }

    final inset = redPixels(storeIcon()); // safe-zone fit (~15%)
    final fullBleed = redPixels(storeIcon(legacyPadding: 0));
    expect(inset, greaterThan(0));
    expect(inset, lessThan(fullBleed),
        reason: 'the safe-zone inset must leave less art than edge-to-edge');
  });
}

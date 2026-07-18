import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The legacy mipmaps and the Play Store PNG compose the same way as the
/// adaptive icon: the adaptive foreground (padded) over the adaptive background
/// (full-bleed). So when both the layers and a finished `icon.image` are set,
/// the layers win (padding applies, the icons match the adaptive icon) and the
/// `icon.image` is superseded.
void main() {
  late Directory project;
  String main_(String rel) =>
      p.join(project.path, 'android', 'app', 'src', 'main', rel);

  /// Generates with a GREEN finished icon.image AND a RED adaptive foreground
  /// over a white ground, so the colour reveals which source was used. Returns
  /// the opaque 512² Play Store PNG.
  img.Image storeIcon({int? playStorePadding}) {
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

    // A finished, edge-to-edge GREEN icon.image (the source that must be ignored).
    final green = img.Image(width: 256, height: 256, numChannels: 4)
      ..clear(img.ColorRgba8(0, 200, 0, 255));
    File(p.join(project.path, 'assets', 'icon.png'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(img.encodePng(green));
    // The adaptive foreground is a RED mark (the source that must be used).
    File(p.join(project.path, 'assets', 'logo.svg')).writeAsStringSync(
        '<svg viewBox="0 0 100 100"><rect width="100" height="100" '
        'fill="#FF0000"/></svg>');

    final pad = playStorePadding == null
        ? ''
        : '      play_store_padding: $playStorePadding\n';
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    icon:
      legacy: true
      play_store: true
$pad      image: assets/icon.png
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
  bool isGreen(img.Pixel px) => px.g > 150 && px.r < 80 && px.b < 80;
  bool isWhite(img.Pixel px) => px.r > 200 && px.g > 200 && px.b > 200;

  /// Width fraction of the red (foreground) art in the Play Store PNG.
  double redWidthFraction(img.Image im) {
    var minX = im.width, maxX = -1;
    for (var y = 0; y < im.height; y++) {
      for (var x = 0; x < im.width; x++) {
        if (isRed(im.getPixel(x, y))) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
        }
      }
    }
    return maxX < 0 ? 0 : (maxX - minX + 1) / im.width;
  }

  test('the adaptive foreground supersedes icon.image on the store PNG', () {
    final store = storeIcon();
    expect(store.width, 512);
    // Composed from the RED foreground (padded over the white ground), NOT the
    // GREEN icon.image: red in the centre, white in the corner, no green.
    expect(isRed(store.getPixel(256, 256)), isTrue,
        reason: 'the adaptive foreground (red) is used, not icon.image');
    expect(isWhite(store.getPixel(4, 4)), isTrue,
        reason: 'the foreground is padded, so the ground shows at the corner');
    var greenPixels = 0;
    for (final px in store) {
      if (isGreen(px)) greenPixels++;
    }
    expect(greenPixels, 0, reason: 'icon.image (green) must not appear');
  });

  test('play_store_padding pads the foreground even when icon.image is set',
      () {
    final small = redWidthFraction(storeIcon(playStorePadding: 10));
    final large = redWidthFraction(storeIcon(playStorePadding: 45));
    expect(small, greaterThan(0));
    expect(large, lessThan(small),
        reason: 'more play_store_padding must leave a smaller mark');
  });
}

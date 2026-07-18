import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A finished `icon.image` is a complete icon: it carries its own ground with
/// the mark framed as authored, so you cannot pad just its foreground. It is
/// used FULL-BLEED on the legacy mipmaps and the Play Store PNG, and
/// `legacy_padding` / `play_store_padding` do NOT inset it (those pad the
/// foreground; to inset the mark, use the adaptive foreground + background
/// layers instead of a pre-composed image).
void main() {
  late Directory project;
  String main_(String rel) =>
      p.join(project.path, 'android', 'app', 'src', 'main', rel);

  /// Generates from a full-bleed red `icon.image` over a white background and
  /// returns the opaque 512² Play Store PNG.
  img.Image storeIcon({int? legacyPadding, int? playStorePadding}) {
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

    final lines = [
      if (legacyPadding != null) '      legacy_padding: $legacyPadding',
      if (playStorePadding != null)
        '      play_store_padding: $playStorePadding',
    ].join('\n');
    File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .writeAsStringSync('''
flutter_adaptive_studio:
  android:
    icon:
      legacy: true
      play_store: true
$lines
      image: assets/icon.png
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

  test('a finished icon.image is full-bleed on the Play Store PNG', () {
    final store = storeIcon();
    expect(store.width, 512);
    // Full-bleed: the finished icon's own ground reaches the corner. The
    // adaptive safe_zone does NOT matte a border around it.
    expect(isRed(store.getPixel(4, 4)), isTrue,
        reason: 'a finished icon.image must not be inset by the safe zone');
    expect(isRed(store.getPixel(256, 256)), isTrue,
        reason: 'the art still fills the centre');
  });

  test('legacy_padding does not inset a finished icon.image', () {
    final store = storeIcon(legacyPadding: 25);
    // legacy_padding is a foreground inset; a finished icon.image has no
    // separable foreground, so it stays full-bleed (no white matte at the edge).
    expect(isRed(store.getPixel(4, 4)), isTrue,
        reason: 'legacy_padding must not inset a finished icon.image');
  });

  test('play_store_padding does not inset a finished icon.image', () {
    final store = storeIcon(playStorePadding: 15);
    // Same for the Play Store's own padding: a finished icon.image is full-bleed,
    // so no background-coloured border appears around it.
    expect(isRed(store.getPixel(4, 4)), isTrue,
        reason: 'play_store_padding must not inset a finished icon.image');
    expect(isRed(store.getPixel(508, 508)), isTrue,
        reason: 'the opposite corner is full-bleed too');
  });
}

import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// `raster_view` chooses what the legacy mipmaps and the Play Store PNG show
/// of the adaptive layers: the whole 108dp tile (the default, unchanged), or
/// the 72dp square a launcher shows, so the background is framed as on a phone.
void main() {
  late Directory project;
  String mainFile(String rel) =>
      p.join(project.path, 'android', 'app', 'src', 'main', rel);
  File cfg() => File(p.join(project.path, 'flutter_adaptive_studio.yaml'));

  setUp(() {
    project = Directory.systemTemp.createTempSync('fas_rview_');
    Directory(p.join(project.path, 'android', 'app', 'src', 'main'))
        .createSync(recursive: true);
    File(mainFile('AndroidManifest.xml')).writeAsStringSync(
        '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '  <application android:icon="@mipmap/ic_launcher"/>\n'
        '</manifest>\n');
    Directory(p.join(project.path, 'assets')).createSync();
    // A small black square for the mark.
    File(p.join(project.path, 'assets', 'mark.svg')).writeAsStringSync(
        '<svg viewBox="0 0 100 100">'
        '<rect x="0" y="0" width="100" height="100" fill="#000000"/></svg>');
    // A blue ground with a red band round the outer 18 of 108: exactly the
    // part of the tile a launcher's mask never shows.
    File(p.join(project.path, 'assets', 'ground.svg')).writeAsStringSync(
        '<svg viewBox="0 0 108 108">'
        '<rect width="108" height="108" fill="#FF0000"/>'
        '<rect x="18" y="18" width="72" height="72" fill="#0000FF"/></svg>');
  });

  tearDown(() => project.deleteSync(recursive: true));

  img.Image gen(String extraIconLines) {
    cfg().writeAsStringSync('''
flutter_adaptive_studio:
  android:
    icon:
      play_store: true
      legacy: true
      adaptive:
        foreground: assets/mark.svg
        background: assets/ground.svg
$extraIconLines
''');
    AdaptiveStudio(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();
    return img.decodeImage(
        File(mainFile('ic_launcher-playstore.png')).readAsBytesSync())!;
  }

  /// Width fraction (0..1) of the black mark across the middle row.
  double markWidth(img.Image im) {
    final y = im.height ~/ 2;
    var n = 0;
    for (var x = 0; x < im.width; x++) {
      final px = im.getPixel(x, y);
      if (px.r < 60 && px.g < 60 && px.b < 60) n++;
    }
    return n / im.width;
  }

  bool isRed(img.Pixel px) => px.r > 200 && px.b < 60;
  bool isBlue(img.Pixel px) => px.b > 200 && px.r < 60;

  test('unset and tile draw the whole tile, byte for byte the same', () {
    final unset = gen('');
    final unsetBytes =
        File(mainFile('ic_launcher-playstore.png')).readAsBytesSync();
    final tile = gen('      raster_view: tile');
    expect(File(mainFile('ic_launcher-playstore.png')).readAsBytesSync(),
        unsetBytes);
    // The band round the edge is in the picture.
    expect(isRed(unset.getPixel(4, 4)), isTrue);
    expect(isRed(tile.getPixel(4, 256)), isTrue);
  });

  test('launcher shows only the visible square: the ground zoomed 1.5x', () {
    final tile = gen('');
    final launcher = gen('      raster_view: launcher');
    // The band a mask hides is gone; the visible blue fills the square.
    expect(isBlue(launcher.getPixel(4, 4)), isTrue);
    expect(isBlue(launcher.getPixel(507, 507)), isTrue);
    // With no padding set, the mark is the size a launcher shows: 1.5x.
    expect(markWidth(launcher) / markWidth(tile), closeTo(1.5, 0.02));
  });

  test('launcher keeps an explicit padding as the inset of that square', () {
    final tile = gen('      play_store_padding: 30');
    final launcher = gen('      play_store_padding: 30\n'
        '      raster_view: launcher');
    expect(markWidth(launcher), closeTo(markWidth(tile), 0.01));
    expect(markWidth(launcher), closeTo(0.70, 0.01));
    expect(isBlue(launcher.getPixel(4, 4)), isTrue);
  });

  test('launcher applies to the legacy mipmaps too', () {
    gen('      raster_view: launcher');
    final mip = img.decodeImage(
        File(mainFile('res/mipmap-xxxhdpi/ic_launcher.png'))
            .readAsBytesSync())!;
    // Just inside the rounded corner: the visible blue, not the hidden band.
    expect(isBlue(mip.getPixel(mip.width ~/ 2, 3)), isTrue);
  });
}

import 'dart:io';

import 'package:flutter_adaptive_studio/src/raster/image_rasterizer.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late String srcPath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('fas_raster_test_');
    // A 64×64 fully-opaque green source.
    final src = img.Image(width: 64, height: 64, numChannels: 4)
      ..clear(img.ColorRgba8(0, 200, 100, 255));
    srcPath = p.join(tmp.path, 'src.png');
    File(srcPath).writeAsBytesSync(img.encodePng(src));
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('resizes a PNG to the requested square size', () {
    const r = ImageRasterizer();
    final out = p.join(tmp.path, 'out.png');
    expect(
        r.renderToPng(sourcePath: srcPath, sizePx: 32, outPath: out), isTrue);
    final decoded = img.decodeImage(File(out).readAsBytesSync())!;
    expect(decoded.width, 32);
    expect(decoded.height, 32);
  });

  test('supports() recognises raster but not svg', () {
    const r = ImageRasterizer();
    expect(r.supports('.png'), isTrue);
    expect(r.supports('.webp'), isTrue);
    expect(r.supports('.svg'), isFalse);
  });

  test('circular mask clears corners, keeps centre', () {
    const r = ImageRasterizer();
    final out = p.join(tmp.path, 'round.png');
    r.renderToPng(sourcePath: srcPath, sizePx: 64, outPath: out);
    ImageRasterizer.maskCircleInPlace(out);
    final masked = img.decodeImage(File(out).readAsBytesSync())!;
    expect(masked.getPixel(0, 0).a, 0); // corner transparent
    expect(masked.getPixel(32, 32).a, 255); // centre opaque
  });
}

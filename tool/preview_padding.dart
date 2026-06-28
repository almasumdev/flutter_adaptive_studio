// Renders the square legacy icon at several padding values into uniquely-named
// files, so a stale thumbnail cache can't mask the difference.
//   dart run tool/preview_padding.dart
import 'dart:io';
import 'package:image/image.dart' as img;

import '../lib/src/graphic/svg_document.dart';
import '../lib/src/raster/svg_rasterizer.dart';
import '../lib/src/raster/image_rasterizer.dart';

void main() {
  const size = 256;
  const inset = 27; // ~10.4% of 256, the square tile inset
  final inner = size - 2 * inset;
  final svg = File('example_2/assets/listkin_logo.svg').readAsStringSync();
  final doc = SvgDocument.parse(svg);
  final outDir = Directory('example_2/preview')..createSync(recursive: true);

  for (final pad in [15, 30, 50]) {
    final fit = 1 - pad / 100;
    final innerImg = const SvgRasterizer()
        .rasterize(doc, inner, backgroundArgb: 0xFFFFFFFF, fitFraction: fit);
    final out =
        '${outDir.path}/square_pad_${pad.toString().padLeft(2, '0')}.png';
    ImageRasterizer.shapeIconImage(
      inner: innerImg,
      sizePx: size,
      inset: inset,
      cornerRadiusFraction: 0.08,
      circle: false,
      outPath: out,
      elevate: true,
    );
    print('wrote $out  (padding $pad%)');
  }
  // Touch a marker so the bytes are unmistakably new.
  print('done — open the three files in example_2/preview/');
  // ignore: unused_local_variable
  final _ = img.Image(width: 1, height: 1);
}

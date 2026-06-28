import 'dart:io';
import 'package:image/image.dart' as img;

void bbox(String path) {
  final im = img.decodeImage(File(path).readAsBytesSync())!;
  int minX = im.width, minY = im.height, maxX = -1, maxY = -1;
  for (int y = 0; y < im.height; y++) {
    for (int x = 0; x < im.width; x++) {
      final p = im.getPixel(x, y);
      if (p.a.toInt() < 16) continue;
      final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
      final chroma = [r, g, b].reduce((a, c) => a > c ? a : c) -
          [r, g, b].reduce((a, c) => a < c ? a : c);
      if (chroma < 30)
        continue; // skip white tile + gray shadow; keep teal logo
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  final w = im.width;
  final logoW = maxX - minX + 1, logoH = maxY - minY + 1;
  print('${path.split(RegExp(r"[\\/]")).last}: ${im.width}x${im.height}  '
      'logo ${logoW}x$logoH = ${(logoW * 100 / w).toStringAsFixed(1)}% wide  '
      'top-margin ${(minY * 100 / w).toStringAsFixed(1)}%');
}

void main() {
  final base = Platform.environment['BASE']!;
  for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
    bbox('$base/mipmap-$d/ic_launcher.png');
  }
}

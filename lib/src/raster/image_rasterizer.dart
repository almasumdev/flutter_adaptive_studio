/// Pure-Dart raster backend (the `image` package). Handles raster sources
/// (PNG/JPG/WebP/...) only. It cannot read SVG. Always available, no system
/// dependency.
///
/// Resampling beats the incumbents: box-average on downscale (sharp, no moiré),
/// cubic on upscale (vs flutter_launcher_icons, which avoids cubic entirely).
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'icon_effects.dart';
import 'image_format.dart';
import 'rasterizer.dart';

class ImageRasterizer implements Rasterizer {
  const ImageRasterizer();

  static const _rasterExts = {'.png', '.jpg', '.jpeg', '.webp', '.bmp', '.gif'};

  /// Encodes [image] in the requested [format] (PNG by default). WebP uses the
  /// `image` package's lossless VP8L encoder.
  static List<int> encode(img.Image image,
          [ImageFormat format = ImageFormat.png]) =>
      format == ImageFormat.webp ? img.encodeWebP(image) : img.encodePng(image);

  @override
  String get name => 'image (pure Dart)';

  @override
  bool get available => true;

  @override
  bool supports(String extension) =>
      _rasterExts.contains(extension.toLowerCase());

  @override
  bool renderToPng({
    required String sourcePath,
    required int sizePx,
    required String outPath,
  }) {
    final bytes = File(sourcePath).readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return false;

    final resized = resizeSmart(decoded, sizePx, sizePx);

    final outFile = File(outPath)..parent.createSync(recursive: true);
    outFile.writeAsBytesSync(img.encodePng(resized));
    return true;
  }

  /// Flattens any alpha over [backgroundHex] (used for the opaque store icon
  /// when the source is transparent). Returns the path written.
  bool renderFlattenedPng({
    required String sourcePath,
    required int sizePx,
    required String outPath,
    required int backgroundArgb,
  }) {
    final decoded = img.decodeImage(File(sourcePath).readAsBytesSync());
    if (decoded == null) return false;
    final canvas = img.Image(width: sizePx, height: sizePx, numChannels: 4)
      ..clear(img.ColorRgba8(
        (backgroundArgb >> 16) & 0xFF,
        (backgroundArgb >> 8) & 0xFF,
        backgroundArgb & 0xFF,
        0xFF,
      ));
    final scaled = resizeSmart(decoded, sizePx, sizePx);
    img.compositeImage(canvas, scaled);
    File(outPath)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(img.encodePng(canvas));
    return true;
  }

  /// Renders [sourcePath] into a transparent [canvasPx]² PNG, scaled (aspect
  /// preserved) so its longest side fills [fillFraction] of the canvas and
  /// centred, i.e. an adaptive-icon layer with the source fit into the safe
  /// zone. Works for any raster source; no system tool needed.
  ///
  /// [trim] (the `auto` fit) drops fully-transparent margins first, so only the
  /// real art is measured and fills the slot; leave it false (`as_is`) to keep
  /// the source's own padding.
  bool renderFittedPng({
    required String sourcePath,
    required int canvasPx,
    required double fillFraction,
    required String outPath,
    ImageFormat format = ImageFormat.png,
    bool trim = false,
  }) {
    var src = img.decodeImage(File(sourcePath).readAsBytesSync());
    if (src == null) return false;
    if (trim) src = trimTransparent(src);
    final target = (canvasPx * fillFraction).round();
    final longest = src.width > src.height ? src.width : src.height;
    final scale = longest == 0 ? 1.0 : target / longest;
    final w = (src.width * scale).round().clamp(1, canvasPx);
    final h = (src.height * scale).round().clamp(1, canvasPx);
    final resized = resizeSmart(src, w, h);
    final canvas = img.Image(width: canvasPx, height: canvasPx, numChannels: 4);
    img.compositeImage(
      canvas,
      resized,
      dstX: ((canvasPx - w) / 2).round(),
      dstY: ((canvasPx - h) / 2).round(),
    );
    File(outPath)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(encode(canvas, format));
    return true;
  }

  /// Composes a square, **opaque** icon: [foregroundPath] fit to [fillFraction]
  /// of [sizePx], centred over a solid [backgroundArgb]. Used to build the
  /// legacy/store icon from a raster foreground + background colour.
  bool composeIconPng({
    required String foregroundPath,
    required int backgroundArgb,
    required int sizePx,
    required double fillFraction,
    required String outPath,
    bool trim = false,
  }) {
    var src = img.decodeImage(File(foregroundPath).readAsBytesSync());
    if (src == null) return false;
    if (trim) src = trimTransparent(src);
    final canvas = img.Image(width: sizePx, height: sizePx, numChannels: 4)
      ..clear(img.ColorRgba8(
        (backgroundArgb >> 16) & 0xFF,
        (backgroundArgb >> 8) & 0xFF,
        backgroundArgb & 0xFF,
        0xFF,
      ));
    final target = (sizePx * fillFraction).round();
    final longest = src.width > src.height ? src.width : src.height;
    final scale = longest == 0 ? 1.0 : target / longest;
    final w = (src.width * scale).round().clamp(1, sizePx);
    final h = (src.height * scale).round().clamp(1, sizePx);
    final fg = resizeSmart(src, w, h);
    img.compositeImage(canvas, fg,
        dstX: ((sizePx - w) / 2).round(), dstY: ((sizePx - h) / 2).round());
    File(outPath)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(img.encodePng(canvas));
    return true;
  }

  /// Applies a rounded-square alpha mask to a PNG in place. Gives the legacy
  /// `ic_launcher` the standard launcher icon shape instead of a hard square.
  static void maskRoundedRectInPlace(String path,
      {double radiusFraction = 0.2}) {
    final src = img.decodeImage(File(path).readAsBytesSync());
    if (src == null) return;
    File(path)
        .writeAsBytesSync(img.encodePng(_maskRounded(src, radiusFraction)));
  }

  /// Applies a circular alpha mask to a PNG in place, used for the legacy
  /// `ic_launcher_round` so pre-API-26 launchers get a real round icon.
  static void maskCircleInPlace(String path) {
    final src = img.decodeImage(File(path).readAsBytesSync());
    if (src == null) return;
    File(path).writeAsBytesSync(img.encodePng(_maskCircle(src)));
  }

  /// Shapes a pre-rendered [inner]-sized solid square into a density icon:
  /// applies the rounded-square (or circle) mask, centres it on a transparent
  /// [sizePx]² canvas at [inset], and optionally adds the elevate effect.
  ///
  /// The caller renders [inner] at *exactly* the inner size. For SVG that's a
  /// direct rasterisation (no resampling), which avoids the box-average grid
  /// `copyResize` leaves on flat fills at non-integer downscale ratios.
  static bool shapeIconImage({
    required img.Image inner,
    required int sizePx,
    required int inset,
    required double cornerRadiusFraction,
    required bool circle,
    required String outPath,
    bool elevate = false,
    ImageFormat format = ImageFormat.png,
  }) {
    final shaped =
        circle ? _maskCircle(inner) : _maskRounded(inner, cornerRadiusFraction);
    var canvas = img.Image(width: sizePx, height: sizePx, numChannels: 4);
    img.compositeImage(canvas, shaped, dstX: inset, dstY: inset);
    // Optional Material drop shadow + sheen (Asset Studio / IconKitchen look).
    if (elevate) canvas = IconEffects.elevate(canvas);
    File(outPath)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(encode(canvas, format));
    return true;
  }

  static img.Image _maskRounded(img.Image src, double radiusFraction) {
    final out = src.convert(numChannels: 4);
    final w = out.width, h = out.height;
    final r = (w < h ? w : h) * radiusFraction;
    final r2 = r * r;
    bool inside(double sx, double sy) {
      final cx = sx < r ? r : (sx > w - r ? w - r : sx);
      final cy = sy < r ? r : (sy > h - r ? h - r : sy);
      final dx = sx - cx, dy = sy - cy;
      return dx * dx + dy * dy <= r2;
    }

    _applyCoverage(out, inside);
    return out;
  }

  static img.Image _maskCircle(img.Image src) {
    final out = src.convert(numChannels: 4);
    final cx = out.width / 2.0, cy = out.height / 2.0;
    final r = (out.width < out.height ? out.width : out.height) / 2.0;
    final r2 = r * r;
    bool inside(double sx, double sy) {
      final dx = sx - cx, dy = sy - cy;
      return dx * dx + dy * dy <= r2;
    }

    _applyCoverage(out, inside);
    return out;
  }

  /// Multiplies each pixel's alpha by its coverage of [inside], estimated with
  /// 8×8 supersampling (64 levels). This is what gives the mask smooth,
  /// anti-aliased edges instead of stair-stepped ones. Only edge pixels pay the
  /// cost; fully-inside pixels are skipped.
  static void _applyCoverage(
      img.Image out, bool Function(double sx, double sy) inside) {
    const n = 8;
    for (final pixel in out) {
      if (pixel.a == 0) continue;
      var hits = 0;
      for (var i = 0; i < n; i++) {
        for (var j = 0; j < n; j++) {
          if (inside(pixel.x + (i + 0.5) / n, pixel.y + (j + 0.5) / n)) hits++;
        }
      }
      if (hits == n * n) continue; // fully inside, leave as-is
      pixel.a = (pixel.a * hits / (n * n)).round();
    }
  }

  /// Quality resize. Enlarging uses cubic; shrinking **halves repeatedly**
  /// (never more than 2× per step) before the final step. This is Android Asset
  /// Studio's `drawImageScaled` technique: a single large box-average leaves an
  /// aliasing grid on flat fills, while stepped halving stays clean.
  static img.Image resizeSmart(img.Image src, int w, int h) {
    if (w >= src.width && h >= src.height) {
      return img.copyResize(src,
          width: w, height: h, interpolation: img.Interpolation.cubic);
    }
    var cur = src;
    while (cur.width > w * 2 || cur.height > h * 2) {
      final nw = math.max(w, (cur.width / 2).ceil());
      final nh = math.max(h, (cur.height / 2).ceil());
      cur = img.copyResize(cur,
          width: nw, height: nh, interpolation: img.Interpolation.average);
    }
    if (cur.width == w && cur.height == h) return cur;
    return img.copyResize(cur,
        width: w, height: h, interpolation: img.Interpolation.average);
  }

  /// Crops fully-transparent margins so only the real art remains. Returns the
  /// source unchanged when it has no alpha border (or is entirely transparent).
  /// Backs the `auto` fit for raster sources.
  static img.Image trimTransparent(img.Image src) {
    final t = img.findTrim(src, mode: img.TrimMode.transparent);
    if (t[2] <= 0 || t[3] <= 0) return src;
    if (t[0] == 0 && t[1] == 0 && t[2] == src.width && t[3] == src.height) {
      return src;
    }
    return img.copyCrop(src, x: t[0], y: t[1], width: t[2], height: t[3]);
  }

  static String basename(String path) => p.basename(path);
}

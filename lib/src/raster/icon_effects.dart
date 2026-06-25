/// Raster-icon post-processing that reproduces the Android Asset Studio /
/// IconKitchen "elevate" look on a shaped icon: a soft drop shadow beneath the
/// icon plus a faint top-left radial sheen on top.
///
/// The constants are Asset Studio's, expressed in mdpi-48 units and scaled to
/// the icon size (`mult = size / 48`): outer shadow `black α0.3, blur 0.7dp,
/// +0.7dp`; sheen `white 0.1 → 0` from the top-left corner. Android Studio's
/// desktop tool bakes the equivalent into per-shape stencil PNGs; we compute it
/// so a single source still drives everything with no shipped assets.
library;

import 'dart:math' as math;

import 'package:image/image.dart' as img;

class IconEffects {
  const IconEffects._();

  /// Returns a new image: [content] (RGBA, transparent outside the icon shape)
  /// with a drop shadow composited beneath it and a radial sheen on top. The
  /// shaped icon must leave a little transparent margin for the shadow to land
  /// in (the legacy padding does).
  static img.Image elevate(img.Image content) {
    final size = content.width;
    final mult = size / 48.0;
    final canvas = img.Image(width: size, height: size, numChannels: 4);

    final shadow = _dropShadow(
      content,
      blurRadius: math.max(1, (0.7 * mult).round()),
      offsetY: math.max(1, (0.7 * mult).round()),
      alpha: 0.3,
    );
    img.compositeImage(canvas, shadow);
    img.compositeImage(canvas, content);
    _radialSheen(canvas, content, radius: size.toDouble(), strength: 0.1);
    return canvas;
  }

  /// A black silhouette of [content] at [alpha] opacity, Gaussian-blurred and
  /// offset down — the classic Material drop shadow.
  static img.Image _dropShadow(
    img.Image content, {
    required int blurRadius,
    required int offsetY,
    required double alpha,
  }) {
    final size = content.width;
    final sil = img.Image(width: size, height: size, numChannels: 4);
    for (final p in content) {
      if (p.a == 0) continue;
      sil.setPixelRgba(p.x, p.y, 0, 0, 0, (p.a.toDouble() * alpha).round());
    }
    final blurred = img.gaussianBlur(sil, radius: blurRadius);
    final out = img.Image(width: size, height: size, numChannels: 4);
    img.compositeImage(out, blurred, dstY: offsetY);
    return out;
  }

  /// Blends a white radial gradient (strength at the top-left corner, fading to
  /// 0 at [radius]) onto [canvas], clipped to [mask]'s alpha — a subtle sheen.
  static void _radialSheen(
    img.Image canvas,
    img.Image mask, {
    required double radius,
    required double strength,
  }) {
    for (final p in mask) {
      if (p.a == 0) continue;
      final d = math.sqrt(p.x * p.x + p.y * p.y);
      final t = 1 - d / radius;
      if (t <= 0) continue;
      final a = strength * t * (p.a / 255.0);
      final px = canvas.getPixel(p.x, p.y);
      px
        ..r = (255 * a + px.r * (1 - a)).round().clamp(0, 255)
        ..g = (255 * a + px.g * (1 - a)).round().clamp(0, 255)
        ..b = (255 * a + px.b * (1 - a)).round().clamp(0, 255);
    }
  }
}

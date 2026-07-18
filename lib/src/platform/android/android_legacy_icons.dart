/// Generates the raster-only icon outputs: pre-API-26 legacy mipmaps (+ round)
/// and the 512² Play Store PNG.
///
/// These compose the same way as the adaptive icon: the adaptive foreground
/// (padded to the safe zone) over the adaptive background (full-bleed colour,
/// SVG or PNG), so every padding key applies and the icons match. A finished
/// `icon.image` is a fallback used full-bleed only when there is no adaptive
/// foreground. Rasterisation is pure-Dart (the SVG rasteriser, or the image
/// package for raster sources); if a source can't be handled the outputs are
/// skipped with a clear message, never a hard failure.
library;

import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../config/config.dart';
import '../../config/config_loader.dart';
import '../../geometry/adaptive_geometry.dart';
import '../../graphic/svg_color.dart';
import '../../graphic/svg_document.dart';
import '../../logger.dart';
import '../../raster/image_rasterizer.dart';
import '../../raster/svg_rasterizer.dart';
import '../platform_generator.dart';
import 'android_paths.dart';

class AndroidLegacyIcons {
  AndroidLegacyIcons({
    required this.iconConfig,
    required this.adaptive,
    required this.loader,
    required this.paths,
    required this.logger,
    required this.emitLegacy,
    required this.emitPlayStore,
  });

  final AndroidIconConfig iconConfig;
  final AdaptiveConfig? adaptive;
  final ConfigLoader loader;
  final AndroidPaths paths;
  final Logger logger;
  final bool emitLegacy;
  final bool emitPlayStore;

  /// Legacy ic_launcher mipmap pixel sizes per density.
  static const Map<String, int> _mipmap = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };

  GenerationReport generate() {
    final report = GenerationReport();
    if (!emitLegacy && !emitPlayStore) return report;

    final name = iconConfig.iconName;
    final elevate = iconConfig.effect == LegacyEffect.elevate;
    final fmt = iconConfig.imageFormat;
    final ext = fmt.extension;

    // The legacy + Play Store icons compose from the adaptive foreground
    // (padded) over the background (full-bleed) to match the adaptive icon, so a
    // pre-composed icon.image is superseded when the layers exist. Say so rather
    // than silently dropping it.
    if (iconConfig.image != null && adaptive?.foreground != null) {
      logger.warn(
          'icon.image is ignored: the legacy and Play Store icons are composed '
          'from the adaptive foreground + background, so padding applies and '
          'they match the adaptive icon. Remove icon.image to silence this.');
    }

    // The Play Store icon gets its own inset when `play_store_padding` is set;
    // otherwise it shares the legacy source's framing.
    final storeFill = emitPlayStore ? _playStoreFill() : null;
    final storeSharesLegacy = storeFill == null;

    // Prepare the legacy source only when it's actually used: for the legacy
    // mipmaps, or for the Play Store when it shares that framing.
    _Source? legacy;
    if (emitLegacy || (emitPlayStore && storeSharesLegacy)) {
      legacy = _prepareSource(report);
      if (legacy == null) return report;
    }

    if (emitLegacy) {
      final src = legacy!; // prepared above whenever emitLegacy is true
      _mipmap.forEach((density, px) {
        // The composed square is already background-full-bleed with the
        // foreground fit to the safe zone (padding is a foreground concern), so
        // the mipmap fills the tile and is only shaped: rounded ~8%, or a circle
        // for the round variant. The `elevate` card effect is the one case that
        // insets the whole icon, to leave room for its drop shadow.
        _shapeDensity(src, px, density, '$name$ext', report,
            paddingFraction: elevate ? 0.104 : 0.0,
            cornerRadiusFraction: 0.08,
            circle: false,
            elevate: elevate,
            format: fmt);
        if (iconConfig.round) {
          _shapeDensity(src, px, density, '${name}_round$ext', report,
              paddingFraction: elevate ? 0.042 : 0.0,
              cornerRadiusFraction: 0,
              circle: true,
              elevate: elevate,
              format: fmt);
        }
        // A same-name PNG from a previous (png) run would shadow a new webp
        // resource of the same name. Drop any stale sibling.
        _removeStaleMipmap(density, name, ext, report);
      });
      logger.step(
          'legacy mipmaps (48-192px${iconConfig.round ? ' + round' : ''}, '
          '${fmt.name}), pure Dart');
    }

    if (emitPlayStore) {
      // The Play Store marketing icon must be a 32-bit PNG (Google's rule), so
      // it ignores `image_format`. It lives in src/main, not the android/app
      // root. When `play_store_padding` is set it uses a source of its own.
      final storeSource = storeSharesLegacy
          ? legacy!
          : _prepareSource(report, fillOverride: storeFill);
      final store = storeSource?.square(512); // opaque
      if (store != null) {
        final out = p.join(paths.mainSrcDir, '$name-playstore.png');
        File(out)
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(img.encodePng(store));
        report.written.add('$name-playstore.png (512²)');
        logger.step('Play Store icon → '
            'android/app/src/main/$name-playstore.png');
        // Clean up a copy left in the old android/app root by older versions.
        final stale = File(p.join(paths.appDir, '$name-playstore.png'));
        if (stale.existsSync()) {
          stale.deleteSync();
          report.removed.add('android/app/$name-playstore.png (moved to main)');
        }
      }
      if (!storeSharesLegacy) storeSource?.cleanup();
    }

    legacy?.cleanup();
    return report;
  }

  /// Fill fraction (0..1) for the Play Store PNG when `play_store_padding` is
  /// set, or null to share the legacy source's framing.
  double? _playStoreFill() {
    final pp = iconConfig.playStorePadding;
    return pp == null ? null : 1 - (pp.clamp(0, 95) / 100);
  }

  /// Shapes one density mipmap from [src]: renders the composed square (its
  /// background already full-bleed, its foreground already fit to the safe
  /// zone), masks it to the launcher shape, and insets it by [paddingFraction]
  /// (0 = full-bleed; a positive value is the `elevate` card margin). Written
  /// into `mipmap-<density>/`.
  void _shapeDensity(
    _Source src,
    int px,
    String density,
    String fileName,
    GenerationReport report, {
    required double paddingFraction,
    required double cornerRadiusFraction,
    required bool circle,
    required bool elevate,
    required ImageFormat format,
  }) {
    final inset = (px * paddingFraction).round();
    final inner = px - 2 * inset;
    if (inner < 1) return;
    final innerImg = src.square(inner);
    if (innerImg == null) return;
    if (ImageRasterizer.shapeIconImage(
        inner: innerImg,
        sizePx: px,
        inset: inset,
        cornerRadiusFraction: cornerRadiusFraction,
        circle: circle,
        outPath: p.join(paths.mipmapDir(density), fileName),
        elevate: elevate,
        format: format)) {
      report.written.add('mipmap-$density/$fileName');
    }
  }

  /// Removes a `mipmap-<density>/<name>.<other>` left by a previous run in the
  /// other format, so a stale PNG can't shadow a fresh WebP (or vice-versa).
  void _removeStaleMipmap(
      String density, String name, String keepExt, GenerationReport report) {
    const exts = ['.png', '.webp'];
    for (final base in [name, '${name}_round']) {
      for (final e in exts) {
        if (e == keepExt) continue;
        final f = File(p.join(paths.mipmapDir(density), '$base$e'));
        if (f.existsSync()) {
          f.deleteSync();
          report.removed.add('mipmap-$density/$base$e (stale)');
        }
      }
    }
  }

  /// Resolves the icon into a [_Source] that composites a **full-bleed
  /// background** under a **fit foreground**, so the raster icons match the
  /// adaptive icon (whose background fills the tile and whose foreground sits in
  /// the safe zone).
  ///
  /// The foreground is the adaptive foreground (a bare mark, fit to the same
  /// fraction the adaptive foreground uses, so the icons match), or, only when
  /// there is no adaptive foreground, a finished `icon.image` (used full-bleed).
  /// The background is the adaptive background rendered full-bleed (colour, SVG
  /// or PNG); it is never padded. `legacy_padding` / `play_store_padding`
  /// override the foreground inset; `safe_zone: as_is` keeps the mark's own
  /// framing. Returns null (with a clear skip) when no source can be used.
  _Source? _prepareSource(GenerationReport report, {double? fillOverride}) {
    // ---- Foreground source ----
    // Prefer the adaptive foreground so the legacy/store icons compose the same
    // way as the adaptive icon (mark padded over a full-bleed ground) and every
    // padding key applies. A finished icon.image is only a fallback for when no
    // foreground exists; when both are set it is superseded (see generate).
    final String rel;
    final bool fullIcon;
    if (adaptive?.foreground != null) {
      rel = adaptive!.foreground!;
      fullIcon = false;
    } else if (iconConfig.image != null) {
      rel = iconConfig.image!;
      fullIcon = true;
    } else {
      logger.skip('legacy/store: no foreground or icon.image to compose');
      report.skipped.add('legacy/store (no composable source)');
      return null;
    }
    final abs = loader.resolveAsset(rel);
    if (!File(abs).existsSync()) {
      logger.warn('legacy/store source not found: $abs');
      report.skipped.add('legacy/store (source missing)');
      return null;
    }
    final fgLayer = _layerFor(abs, 'legacy/store foreground', report);
    if (fgLayer == null) return null;

    // ---- Foreground framing ----
    // A finished `icon.image` is ALWAYS full-bleed: it carries its own ground,
    // so you cannot pad just its foreground, and `legacy_padding` /
    // `play_store_padding` do not apply to it (see the warning in `generate`).
    // A bare foreground is fit to the SAME fraction the adaptive foreground uses
    // (so the raster icons match the adaptive icon), with those keys overriding
    // and `safe_zone: as_is` keeping the source's own framing.
    final zone = adaptive?.safeZone ?? const SafeZone.fit();
    final asIs = fillOverride == null && zone.mode == SafeZoneMode.asIs;
    final double? fgFill;
    if (fullIcon) {
      fgFill = null; // a finished icon.image is used full-bleed
    } else if (fillOverride != null) {
      fgFill = fillOverride; // play_store_padding
    } else if (iconConfig.legacyPadding != null) {
      fgFill = 1 - (iconConfig.legacyPadding!.clamp(0, 95) / 100);
    } else {
      // fit / inset / none / as_is all map through canvasFillFraction, so the
      // mark is the SAME size as the adaptive foreground (as_is fills the safe
      // square, not the whole tile).
      fgFill = AdaptiveGeometry.canvasFillFraction(zone);
    }
    // `as_is` keeps the source's own framing (whole viewBox / full bitmap); every
    // other mode trims to the measured art before fitting.
    final fgTrim = fgFill != null && !asIs;

    // ---- Background: full-bleed colour / SVG / PNG (never padded). It backs
    //      the foreground, so any transparent area (a fit bare mark, or a
    //      transparent `icon.image`) shows the ground rather than a white
    //      matte. ----
    var bgArgb = 0xFFFFFF; // opaque backing behind any transparency
    _Layer? bgLayer;
    final adpt = adaptive;
    if (adpt != null && adpt.background != null) {
      if (adpt.backgroundIsColor) {
        bgArgb = SvgColor.parse(adpt.background!).argb;
      } else {
        final bgAbs = loader.resolveAsset(adpt.background!);
        if (File(bgAbs).existsSync()) {
          bgLayer = _layerFor(bgAbs, 'legacy/store background', report);
        } else {
          logger.warn('legacy/store background not found: $bgAbs');
        }
      }
    }

    return _Source(
      foreground: fgLayer,
      background: bgLayer,
      backgroundArgb: bgArgb,
      foregroundFill: fgFill,
      foregroundTrim: fgTrim,
    );
  }

  /// Wraps a source file as an SVG or raster [_Layer], or null (with a skip) if
  /// it can't be rasterised.
  _Layer? _layerFor(String abs, String label, GenerationReport report) {
    final ext = p.extension(abs).toLowerCase();
    if (ext == '.svg') {
      try {
        return _Layer.svg(SvgDocument.parse(File(abs).readAsStringSync()));
      } on Exception {
        logger.skip('$label: could not parse SVG "$abs"');
        report.skipped.add('$label (SVG parse failed)');
        return null;
      }
    }
    if (ImageRasterizer().supports(ext)) return _Layer.raster(abs);
    logger.skip('$label: "$abs" not rasterisable ($ext)');
    report.skipped.add('$label (unsupported $ext)');
    return null;
  }
}

/// Composites a full-bleed [background] under a [foreground] fit to
/// [foregroundFill] of the tile (null = full-bleed), producing a solid,
/// background-filled square at any size. Rendered per size (SVG renders
/// directly, avoiding the box-average grid `copyResize` leaves on flat fills).
class _Source {
  _Source({
    required this.foreground,
    required this.backgroundArgb,
    this.background,
    this.foregroundFill,
    this.foregroundTrim = false,
  });

  final _Layer foreground;
  final _Layer? background;
  final int backgroundArgb;
  final double? foregroundFill;
  final bool foregroundTrim;

  img.Image? square(int size) {
    final canvas = background != null
        ? background!.renderFull(size, backgroundArgb)
        : solid(size, backgroundArgb);
    img.compositeImage(
        canvas, foreground.renderFit(size, foregroundFill, foregroundTrim));
    return canvas;
  }

  /// An opaque [size]² square filled with [argb].
  static img.Image solid(int size, int argb) =>
      img.Image(width: size, height: size, numChannels: 4)
        ..clear(img.ColorRgba8(
            (argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF, 0xFF));

  void cleanup() {}
}

/// One icon layer, rendered from an SVG document or a raster file.
class _Layer {
  _Layer.svg(this._doc) : _path = null;
  _Layer.raster(this._path) : _doc = null;

  final SvgDocument? _doc;
  final String? _path;

  /// Fills the whole [size] square (no inset), opaque over [bgArgb]: the
  /// background layer.
  img.Image renderFull(int size, int bgArgb) {
    final doc = _doc;
    if (doc != null) {
      return const SvgRasterizer()
          .rasterize(doc, size, backgroundArgb: bgArgb, fitFraction: null);
    }
    final canvas = _Source.solid(size, bgArgb);
    final src = img.decodeImage(File(_path!).readAsBytesSync());
    if (src != null) {
      img.compositeImage(canvas, ImageRasterizer.resizeSmart(src, size, size));
    }
    return canvas;
  }

  /// The art scaled to [fill] of [size] (null = full-bleed), centred on a
  /// transparent canvas; [trim] drops the source's transparent margins first
  /// (the `auto` fit). The foreground layer.
  img.Image renderFit(int size, double? fill, bool trim) {
    final doc = _doc;
    if (doc != null) {
      return const SvgRasterizer()
          .rasterize(doc, size, fitFraction: fill, fitArtBounds: trim);
    }
    final canvas = img.Image(width: size, height: size, numChannels: 4);
    var src = img.decodeImage(File(_path!).readAsBytesSync());
    if (src == null) return canvas;
    if (trim) src = ImageRasterizer.trimTransparent(src);
    final target = fill == null ? size : (size * fill).round();
    final longest = src.width > src.height ? src.width : src.height;
    final scale = longest == 0 ? 1.0 : target / longest;
    final w = (src.width * scale).round().clamp(1, size);
    final h = (src.height * scale).round().clamp(1, size);
    final resized = ImageRasterizer.resizeSmart(src, w, h);
    img.compositeImage(canvas, resized,
        dstX: ((size - w) / 2).round(), dstY: ((size - h) / 2).round());
    return canvas;
  }
}

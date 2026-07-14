/// Generates the raster-only icon outputs: pre-API-26 legacy mipmaps (+ round)
/// and the 512² Play Store PNG.
///
/// Source priority: an explicit `icon.image`, otherwise a composed
/// foreground-over-background SVG. Rasterisation goes through the pluggable
/// [RasterizerFactory] (pure-Dart for raster sources, a detected system tool for
/// SVG). If no backend can handle the source, the outputs are skipped with a
/// clear message, never a hard failure.
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
        // Each density is rendered straight at its target size (SVG: a direct
        // rasterisation, no resample, no grid). Geometry matches Android
        // Studio / Asset Studio's square target (5,5,38,38 in 48dp): ~10.4%
        // inset, ~8% corner radius.
        _shapeDensity(src, px, density, '$name$ext', report,
            paddingFraction: 0.104,
            cornerRadiusFraction: 0.08,
            circle: false,
            elevate: elevate,
            format: fmt);
        if (iconConfig.round) {
          _shapeDensity(src, px, density, '${name}_round$ext', report,
              paddingFraction: 0.042,
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

  /// Renders one density icon: a direct inner-sized square from [src], shaped
  /// and written into `mipmap-<density>/`.
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

  /// Resolves the icon source into a [_Source] that can produce a solid square
  /// at any size. The source is an explicit `icon.image`, or failing that the
  /// adaptive foreground; either way the art is inset to match the adaptive
  /// foreground (see [_composePadding]) so every generated icon shares one
  /// framing. SVG defers to a direct per-size render (sharpest, grid-free);
  /// raster composes a high-res master once. Returns null (with a clear skip)
  /// when no source can be used.
  _Source? _prepareSource(GenerationReport report, {double? fillOverride}) {
    final String rel;
    final bool fullIcon;
    if (iconConfig.image != null) {
      rel = iconConfig.image!;
      fullIcon = true;
    } else if (adaptive?.foreground != null) {
      rel = adaptive!.foreground!;
      fullIcon = false;
    } else {
      logger.skip('legacy/store: no icon.image and no foreground to compose');
      report.skipped.add('legacy/store (no composable source)');
      return null;
    }

    final abs = loader.resolveAsset(rel);
    if (!File(abs).existsSync()) {
      logger.warn('legacy/store source not found: $abs');
      report.skipped.add('legacy/store (source missing)');
      return null;
    }

    final bg = (adaptive != null && adaptive!.backgroundIsColor)
        ? adaptive!.background!
        : '#FFFFFF';
    final bgArgb = SvgColor.parse(bg).argb;
    final ext = p.extension(abs).toLowerCase();

    // Inset the legacy/store art by the same amount as every other generated
    // icon, so the launcher mipmaps + Play Store PNG line up with the adaptive
    // foreground and the iOS icon. An explicit `legacy_padding` wins, else the
    // adaptive `safe_zone`, else the package default. A genuinely finished
    // `icon.image` with no inset intent (no adaptive safe zone and no
    // `legacy_padding`) is still used full-bleed. Set `legacy_padding: 0` to
    // force that explicitly.
    // A [fillOverride] (the Play Store's own `play_store_padding`) forces an
    // explicit inset even for an otherwise full-bleed finished `icon.image`.
    final insetArt = fillOverride != null ||
        !fullIcon ||
        adaptive != null ||
        iconConfig.legacyPadding != null;
    final composeFill =
        insetArt ? (fillOverride ?? (1 - _composePadding())) : 1.0;
    // `safe_zone: as_is` keeps the source's own framing (whole viewBox / full
    // bitmap, padding preserved) so the mipmaps + Play Store PNG match the
    // adaptive foreground. A Play Store `fillOverride` still forces its inset.
    final asIs =
        fillOverride == null && adaptive?.safeZone.mode == SafeZoneMode.asIs;

    // SVG → render directly at each target size (no resample → no grid, sharpest
    // result). A null fit fraction fills the canvas (a finished icon kept
    // full-bleed); otherwise the art is fit into the inset.
    if (ext == '.svg') {
      try {
        final doc = SvgDocument.parse(File(abs).readAsStringSync());
        return _Source.svg(
            doc, bgArgb, asIs ? null : (insetArt ? composeFill : null));
      } on Exception {
        logger.skip('legacy/store: could not parse SVG "$rel"');
        report.skipped.add('legacy/store (SVG parse failed)');
        return null;
      }
    }

    // Raster → compose a high-res master once; each density resizes from it.
    if (ImageRasterizer().supports(ext)) {
      final tmpDir = Directory.systemTemp.createTempSync('fas_legacy_');
      final master = p.join(tmpDir.path, 'master.png');
      final ok = insetArt
          ? const ImageRasterizer().composeIconPng(
              foregroundPath: abs,
              backgroundArgb: bgArgb,
              sizePx: 1024,
              fillFraction: asIs ? 1.0 : composeFill,
              outPath: master,
              trim: !asIs)
          : const ImageRasterizer().renderFlattenedPng(
              sourcePath: abs,
              sizePx: 1024,
              outPath: master,
              backgroundArgb: bgArgb);
      if (!ok) {
        tmpDir.deleteSync(recursive: true);
        report.skipped.add('legacy/store (compose failed)');
        return null;
      }
      return _Source.raster(master, tmpDir);
    }

    logger.skip('legacy/store: source "$rel" not rasterisable ($ext)');
    report.skipped.add('legacy/store (unsupported $ext)');
    return null;
  }

  /// Fraction (0..1) the composed legacy/store art is inset from the tile edge.
  /// An explicit `legacy_padding` (percent, clamped 0-95) wins; otherwise it
  /// follows the adaptive safe zone, then the package default.
  double _composePadding() {
    final lp = iconConfig.legacyPadding;
    if (lp != null) return lp.clamp(0, 95) / 100;
    return adaptive != null
        ? AdaptiveGeometry.paddingFraction(adaptive!.safeZone)
        : SafeZone.defaultPadding / 100;
  }
}

/// Produces a background-filled square icon image at any size. SVG renders
/// directly at the requested size (no resampling, avoids the box-average grid
/// on flat fills); a raster source resizes from a once-composed master.
class _Source {
  _Source.svg(this._doc, this._bgArgb, this._fit)
      : _masterPath = null,
        _tmpDir = null;
  _Source.raster(this._masterPath, this._tmpDir)
      : _doc = null,
        _bgArgb = 0,
        _fit = null;

  final SvgDocument? _doc;
  final String? _masterPath;
  final int _bgArgb;
  final double? _fit;
  final Directory? _tmpDir;

  img.Image? square(int size) {
    final doc = _doc;
    if (doc != null) {
      return const SvgRasterizer()
          .rasterize(doc, size, backgroundArgb: _bgArgb, fitFraction: _fit);
    }
    final src = img.decodeImage(File(_masterPath!).readAsBytesSync());
    if (src == null) return null;
    return ImageRasterizer.resizeSmart(src, size, size);
  }

  void cleanup() {
    final d = _tmpDir;
    if (d != null && d.existsSync()) d.deleteSync(recursive: true);
  }
}

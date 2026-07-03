/// Generates Android launcher icons: adaptive layers (API 26+) — SVG →
/// VectorDrawable, or a raster source → per-density PNGs — with safe-zone fit
/// and the `mipmap-anydpi-v26` adaptive XML (plus the optional round variant).
/// Legacy pre-26 mipmaps and the 512² Play Store PNG are delegated to
/// [AndroidLegacyIcons], and the themed light/dark icon to [AndroidThemedIcons].
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../config/config.dart';
import '../../config/config_loader.dart';
import '../../geometry/adaptive_geometry.dart';
import '../../graphic/svg_document.dart';
import '../../io/res_writer.dart';
import '../../logger.dart';
import '../../raster/image_rasterizer.dart';
import '../../vector/vector_drawable_writer.dart';
import '../platform_generator.dart';
import 'android_legacy_icons.dart';
import 'android_manifest_editor.dart';
import 'android_paths.dart';
import 'android_themed_icons.dart';

class AndroidIcons {
  AndroidIcons({
    required this.config,
    required this.iconConfig,
    required this.loader,
    required this.paths,
    required this.writer,
    required this.logger,
  });

  final AdaptiveStudioConfig config;
  final AndroidIconConfig iconConfig;
  final ConfigLoader loader;
  final AndroidPaths paths;
  final ResWriter writer;
  final Logger logger;

  static const _ns = 'http://schemas.android.com/apk/res/android';

  GenerationReport generate() {
    final report = GenerationReport();
    final adaptive = iconConfig.adaptive;
    if (adaptive == null) {
      report.skipped.add('icon.adaptive (no adaptive config)');
      return report;
    }

    final name = iconConfig.iconName;

    // ---- Foreground (required to build an adaptive icon) ----
    // Accepts SVG (→ VectorDrawable) or raster (→ density PNGs), fit to the
    // safe zone either way.
    final fgSource = adaptive.foreground ?? config.source;
    if (fgSource == null) {
      logger.skip('adaptive foreground: no source given');
      report.skipped.add('adaptive foreground (no source)');
      return report;
    }
    final foregroundRef = _buildLayer(fgSource, '${name}_foreground',
        'foreground', adaptive.safeZone, report);
    if (foregroundRef == null) return report;

    // ---- Background (color, vector, or raster; default white if absent) ----
    String backgroundRef;
    if (adaptive.background == null) {
      writer.upsertColor(paths.valuesDir, '${name}_background', '#FFFFFF');
      backgroundRef = '@color/${name}_background';
      logger.skip('adaptive background: none given, defaulting to #FFFFFF');
      report.skipped.add('adaptive background (defaulted #FFFFFF)');
    } else if (adaptive.backgroundIsColor) {
      writer.upsertColor(paths.valuesDir, '${name}_background',
          adaptive.background!.toUpperCase());
      backgroundRef = '@color/${name}_background';
      logger.step('background colour → @color/${name}_background');
    } else {
      // Background fills the whole canvas (no safe-zone inset).
      final ref = _buildLayer(adaptive.background!, '${name}_background',
          'background', const SafeZone.none(), report);
      if (ref != null) {
        backgroundRef = ref;
      } else {
        writer.upsertColor(paths.valuesDir, '${name}_background', '#FFFFFF');
        backgroundRef = '@color/${name}_background';
      }
    }

    // ---- Monochrome (Android 13 themed icon) ----
    String? monochromeRef;
    if (adaptive.monochrome != null) {
      monochromeRef = _buildLayer(adaptive.monochrome!, '${name}_monochrome',
          'monochrome', adaptive.safeZone, report);
    } else {
      logger.skip('monochrome: not provided (Android 13 themed icon disabled)');
      report.skipped.add('monochrome (not provided)');
    }

    // ---- Adaptive icon XML (+ round) ----
    final adaptiveXml = _adaptiveIconXml(
      foreground: foregroundRef,
      background: backgroundRef,
      monochrome: monochromeRef,
    );
    writer.writeText(p.join(paths.mipmapAnydpiV26, '$name.xml'), adaptiveXml);
    report.written.add('mipmap-anydpi-v26/$name.xml');
    logger.step('adaptive icon → mipmap-anydpi-v26/$name.xml');

    if (iconConfig.round) {
      writer.writeText(
          p.join(paths.mipmapAnydpiV26, '${name}_round.xml'), adaptiveXml);
      report.written.add('mipmap-anydpi-v26/${name}_round.xml');
      logger.step('round icon → mipmap-anydpi-v26/${name}_round.xml');
    }

    // ---- Manifest ----
    final edited = AndroidManifestEditor(paths.manifest)
        .ensureIconAttributes(name, round: iconConfig.round);
    if (edited) {
      report.written.add('AndroidManifest.xml');
      logger.step('AndroidManifest.xml updated');
    }

    // ---- Legacy mipmaps + Play Store icon (raster) ----
    final minSdk = config.android?.minSdk ?? 21;
    final emitLegacy = iconConfig.legacy ?? (minSdk < 26);
    if (emitLegacy || iconConfig.playStore) {
      report.merge(AndroidLegacyIcons(
        iconConfig: iconConfig,
        adaptive: adaptive,
        loader: loader,
        paths: paths,
        logger: logger,
        emitLegacy: emitLegacy,
        emitPlayStore: iconConfig.playStore,
      ).generate());
    }

    // ---- Themed full-colour light/dark icon (activity-alias) ----
    if (iconConfig.themed != null) {
      report.merge(AndroidThemedIcons(
        iconConfig: iconConfig,
        themed: iconConfig.themed!,
        adaptive: adaptive,
        loader: loader,
        paths: paths,
        writer: writer,
        logger: logger,
      ).generate());
    }

    return report;
  }

  /// Builds one adaptive layer (foreground/background/monochrome) from [source],
  /// accepting SVG (→ VectorDrawable) or raster (→ density PNGs). Returns the
  /// `@drawable/...` reference, or null if the source couldn't be used.
  String? _buildLayer(String source, String base, String label, SafeZone zone,
      GenerationReport report) {
    final abs = loader.resolveAsset(source);
    final ext = p.extension(abs).toLowerCase();

    if (ext == '.svg') {
      final doc = _loadSvg(source, label, report);
      if (doc == null) return null;
      final warns = <String>[];
      final xml = VectorDrawableWriter(warnings: warns).build(
        doc,
        viewport: AdaptiveGeometry.canvas,
        fit: AdaptiveGeometry.fit(
            doc.artBounds(),
            zone,
            doc.viewportWidth > doc.viewportHeight
                ? doc.viewportWidth
                : doc.viewportHeight),
      );
      writer.writeText(p.join(paths.drawableDir, '$base.xml'), xml);
      report.written.add('$base.xml');
      // A density PNG of the same name (from a previous raster run) would
      // shadow this vector on-device — drop any so the new icon actually shows.
      _removeStaleRaster(base, report);
      report.warnings
        ..addAll(doc.warnings)
        ..addAll(warns);
      logger.step('$label → drawable/$base.xml');
      return '@drawable/$base';
    }

    if (_rasterExts.contains(ext)) {
      if (!File(abs).existsSync()) {
        logger.warn('$label source not found: $abs');
        report.skipped.add('$label (file not found)');
        return null;
      }
      final ok =
          _rasterDensities(abs, base, _fillFraction(zone), report, label);
      if (ok) _removeStaleVector(base, report);
      return ok ? '@drawable/$base' : null;
    }

    final why = 'unsupported source ($ext)';
    logger.skip('$label "$source": $why');
    report.skipped.add('$label ($why)');
    return null;
  }

  /// Writes [base].png at each density into `drawable-<density>/`, the source fit
  /// to [fillFraction] of the 108dp layer canvas, centred and transparent.
  bool _rasterDensities(String abs, String base, double fillFraction,
      GenerationReport report, String label) {
    const layerDp = 108;
    const densities = {
      'mdpi': 1.0,
      'hdpi': 1.5,
      'xhdpi': 2.0,
      'xxhdpi': 3.0,
      'xxxhdpi': 4.0,
    };
    const rasterizer = ImageRasterizer();
    final fmt = iconConfig.imageFormat;
    final ext = fmt.extension;
    var any = false;
    densities.forEach((density, mult) {
      final out = p.join(paths.drawableDensityDir(density), '$base$ext');
      if (rasterizer.renderFittedPng(
        sourcePath: abs,
        canvasPx: (layerDp * mult).round(),
        fillFraction: fillFraction,
        outPath: out,
        format: fmt,
      )) {
        any = true;
        report.written.add('drawable-$density/$base$ext');
        // Drop a same-name sibling in the other format from a previous run.
        _removeStaleRasterSibling(density, base, ext, report);
      }
    });
    if (any) logger.step('$label (raster, ${fmt.name}) → drawable-*/$base$ext');
    return any;
  }

  /// Deletes a `drawable-<density>/<base>.<other>` left by a previous run in the
  /// other raster format, so a stale PNG can't shadow a fresh WebP layer.
  void _removeStaleRasterSibling(
      String density, String base, String keepExt, GenerationReport report) {
    for (final e in const ['.png', '.webp']) {
      if (e == keepExt) continue;
      final f = File(p.join(paths.drawableDensityDir(density), '$base$e'));
      if (f.existsSync()) {
        f.deleteSync();
        report.removed.add('drawable-$density/$base$e (stale)');
      }
    }
  }

  static const _layerDensities = ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'];

  /// Deletes any `drawable-<dpi>/<base>.png` left by a previous raster run. On a
  /// real device a density-specific PNG wins over the default-density `<base>.xml`
  /// vector, so a stale PNG would silently keep showing the old layer.
  void _removeStaleRaster(String base, GenerationReport report) {
    for (final d in _layerDensities) {
      for (final e in const ['.png', '.webp']) {
        final f = File(p.join(paths.drawableDensityDir(d), '$base$e'));
        if (f.existsSync()) {
          f.deleteSync();
          report.removed.add('drawable-$d/$base$e (stale)');
        }
      }
    }
  }

  /// Deletes a stale `drawable/<base>.xml` vector left by a previous SVG run, so
  /// it can't mix with freshly written density PNGs of the same name.
  void _removeStaleVector(String base, GenerationReport report) {
    final f = File(p.join(paths.drawableDir, '$base.xml'));
    if (f.existsSync()) {
      f.deleteSync();
      report.removed.add('drawable/$base.xml (stale)');
    }
  }

  static const Set<String> _rasterExts = {
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
    '.bmp',
    '.gif'
  };

  double _fillFraction(SafeZone zone) =>
      AdaptiveGeometry.canvasFillFraction(zone);

  /// Loads + parses [source] into an [SvgDocument]. Returns null — with a skip
  /// or warn message — when the source isn't an SVG, is missing, or fails to
  /// parse.
  SvgDocument? _loadSvg(String source, String role, GenerationReport report) {
    final abs = loader.resolveAsset(source);
    final ext = p.extension(abs).toLowerCase();
    if (ext != '.svg') {
      final why = 'raster ($ext) needs the rasteriser (Phase 3)';
      logger.skip('$role "$source": $why');
      report.skipped.add('$role ($why)');
      return null;
    }
    final file = File(abs);
    if (!file.existsSync()) {
      logger.warn('$role source not found: $abs');
      report.skipped.add('$role (file not found)');
      return null;
    }
    try {
      return SvgDocument.parse(file.readAsStringSync());
    } on Exception catch (e) {
      logger.error('failed to parse $role SVG "$source": $e');
      report.warnings.add('$role parse error: $e');
      return null;
    }
  }

  String _adaptiveIconXml({
    required String foreground,
    required String background,
    String? monochrome,
  }) {
    final b = XmlBuilder();
    b.processing('xml', 'version="1.0" encoding="utf-8"');
    b.comment(' Generated by flutter_adaptive_studio — do not edit. ');
    b.element('adaptive-icon', namespaceUris: {'android': _ns}, nest: () {
      b.element('background', nest: () {
        b.attribute('drawable', background, namespaceUri: _ns);
      });
      b.element('foreground', nest: () {
        b.attribute('drawable', foreground, namespaceUri: _ns);
      });
      if (monochrome != null) {
        b.element('monochrome', nest: () {
          b.attribute('drawable', monochrome, namespaceUri: _ns);
        });
      }
    });
    return b.buildDocument().toXmlString(pretty: true, indent: '    ');
  }
}

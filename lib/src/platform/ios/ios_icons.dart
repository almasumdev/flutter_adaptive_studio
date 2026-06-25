/// Generates the iOS app icon into `AppIcon.appiconset`.
///
/// iOS draws the icon square as-is (the system rounds the corners), and the App
/// Store rejects transparency — so every variant is composited onto an opaque
/// [IosIconConfig.background]. One source (SVG or raster) drives a modern
/// **single-size 1024²** set; optional `dark`/`tinted` add the iOS 18 appearance
/// variants. The same SVG that drives the Android icon can drive this one.
library;

import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../config/config.dart';
import '../../config/config_loader.dart';
import '../../graphic/svg_color.dart';
import '../../graphic/svg_document.dart';
import '../../logger.dart';
import '../../raster/image_rasterizer.dart';
import '../../raster/svg_rasterizer.dart';
import '../platform_generator.dart';
import 'ios_paths.dart';
import 'pbxproj_editor.dart';
import 'xcode_scheme.dart';

class IosIcons {
  IosIcons({
    required this.config,
    required this.iconConfig,
    required this.loader,
    required this.paths,
    required this.logger,
    this.flavor,
  });

  final AdaptiveStudioConfig config;
  final IosIconConfig iconConfig;
  final ConfigLoader loader;
  final IosPaths paths;
  final Logger logger;

  /// Build flavor → writes to `AppIcon-<flavor>.appiconset` instead of the
  /// default set.
  final String? flavor;

  static const _size = 1024;

  GenerationReport generate() {
    final report = GenerationReport();

    final source = _source();
    if (source == null) {
      logger.skip('ios icon: no source (set ios.icon.image, root source, or an '
          'Android foreground)');
      report.skipped.add('ios icon (no source)');
      return report;
    }
    final abs = loader.resolveAsset(source);
    if (!File(abs).existsSync()) {
      logger.warn('ios icon source not found: $abs');
      report.skipped.add('ios icon (source missing)');
      return report;
    }

    final dir = paths.appIconSet(flavor);
    final setName = p.basename(dir);
    Directory(dir).createSync(recursive: true);
    // padding 0 → use the source's own framing; >0 → fit the art with that inset.
    final fit = iconConfig.padding > 0
        ? (1 - iconConfig.padding / 100).clamp(0.1, 1.0).toDouble()
        : null;

    // Standard (light) appearance — required.
    if (!_render(abs, SvgColor.parse(iconConfig.background).argb, fit,
        p.join(dir, 'Icon-1024.png'))) {
      report.skipped.add('ios icon (render failed)');
      return report;
    }
    report.written.add('$setName/Icon-1024.png');

    final hasDark = _variant(iconConfig.dark, iconConfig.backgroundDark, fit,
        'Icon-1024-dark.png', 'dark', report);
    // Tinted is a grayscale mark the system tints — flattened on black.
    final hasTinted = _variant(iconConfig.tinted, '#000000', fit,
        'Icon-1024-tinted.png', 'tinted', report);

    _removeLegacyMatrix(dir, report);
    File(p.join(dir, 'Contents.json'))
        .writeAsStringSync(_contentsJson(dark: hasDark, tinted: hasTinted));
    report.written.add('$setName/Contents.json');
    logger.step('iOS app icon → $setName (1024'
        '${hasDark ? ' +dark' : ''}${hasTinted ? ' +tinted' : ''})');
    if (flavor != null) {
      _wireBuildConfig(setName.replaceAll('.appiconset', ''), report);
    }
    return report;
  }

  /// Points the flavor's Xcode build configurations at [iconName] by setting
  /// `ASSETCATALOG_COMPILER_APPICON_NAME` in `project.pbxproj` (backed up first).
  /// Falls back to a printed instruction when the project has no `*-<flavor>`
  /// build configs (so we never guess at an unrecognised project layout).
  void _wireBuildConfig(String iconName, GenerationReport report) {
    // Authoritative: the configs the flavor's scheme builds. Falls back to the
    // `Debug-<flavor>` convention when there's no shared scheme.
    final schemeConfigs = XcodeScheme.buildConfigs(paths.scheme(flavor!));
    final result = PbxprojEditor(paths.pbxproj)
        .setAppIcon(flavor!, iconName, onlyConfigs: schemeConfigs);
    final via =
        schemeConfigs.isEmpty ? 'naming convention' : '$flavor.xcscheme';
    if (result.changed) {
      logger.step('wired $iconName → ${result.configs.join(', ')} in '
          'project.pbxproj via $via (backup: ${p.basename(result.backupPath!)})');
      report.written.add('project.pbxproj ($iconName)');
    } else if (result.matched) {
      logger
          .detail('$iconName already wired into ${result.configs.join(', ')}');
    } else {
      logger.warn('Flavor "$flavor": no matching iOS build configs found '
          '(checked $flavor.xcscheme and the `*-$flavor` convention). The iOS '
          'flavor isn\'t set up in Xcode yet — create its scheme/configs (e.g. '
          'with flutter_flavorizr), then re-run and this wires automatically. '
          'Until then set ASSETCATALOG_COMPILER_APPICON_NAME = $iconName by hand.');
    }
  }

  /// One source for every platform: explicit iOS image, else the root `source`,
  /// else the Android foreground/finished icon.
  String? _source() =>
      iconConfig.image ??
      config.source ??
      config.android?.icon?.adaptive?.foreground ??
      config.android?.icon?.image;

  bool _variant(String? src, String bg, double? fit, String file, String label,
      GenerationReport report) {
    if (src == null) return false;
    final abs = loader.resolveAsset(src);
    final dir = paths.appIconSet(flavor);
    if (File(abs).existsSync() &&
        _render(abs, SvgColor.parse(bg).argb, fit, p.join(dir, file))) {
      report.written.add('${p.basename(dir)}/$file');
      return true;
    }
    logger
        .warn('ios icon $label variant skipped (missing or unreadable): $src');
    return false;
  }

  /// Renders [abs] to a [_size]² opaque PNG at [outPath]. SVG rasterises
  /// directly (sharpest); raster sources are flattened onto [bgArgb].
  bool _render(String abs, int bgArgb, double? fit, String outPath) {
    final ext = p.extension(abs).toLowerCase();
    if (ext == '.svg') {
      final SvgDocument doc;
      try {
        doc = SvgDocument.parse(File(abs).readAsStringSync());
      } on Exception catch (e) {
        logger.error('ios icon SVG parse error: $e');
        return false;
      }
      final image = const SvgRasterizer()
          .rasterize(doc, _size, backgroundArgb: bgArgb, fitFraction: fit);
      File(outPath)
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(img.encodePng(image));
      return true;
    }
    if (const ImageRasterizer().supports(ext)) {
      return fit == null
          ? const ImageRasterizer().renderFlattenedPng(
              sourcePath: abs,
              sizePx: _size,
              outPath: outPath,
              backgroundArgb: bgArgb)
          : const ImageRasterizer().composeIconPng(
              foregroundPath: abs,
              backgroundArgb: bgArgb,
              sizePx: _size,
              fillFraction: fit,
              outPath: outPath);
    }
    logger.skip(
        'ios icon: unsupported source ($ext) — use SVG or a raster image');
    return false;
  }

  /// Modern single-size universal `Contents.json`, with iOS 18 appearance
  /// entries for whichever variants were emitted.
  String _contentsJson({required bool dark, required bool tinted}) {
    Map<String, Object> entry(String file, [String? appearance]) => {
          if (appearance != null)
            'appearances': [
              {'appearance': 'luminosity', 'value': appearance}
            ],
          'filename': file,
          'idiom': 'universal',
          'platform': 'ios',
          'size': '1024x1024',
        };
    final images = <Map<String, Object>>[
      entry('Icon-1024.png'),
      if (dark) entry('Icon-1024-dark.png', 'dark'),
      if (tinted) entry('Icon-1024-tinted.png', 'tinted'),
    ];
    const encoder = JsonEncoder.withIndent('  ');
    return '${encoder.convert({
          'images': images,
          'info': {'author': 'flutter_adaptive_studio', 'version': 1},
        })}\n';
  }

  /// Drops the legacy `Icon-App-*.png` matrix Flutter ships, so the single-size
  /// set isn't shadowed by stale files.
  void _removeLegacyMatrix(String dir, GenerationReport report) {
    for (final f in Directory(dir).listSync().whereType<File>()) {
      final name = p.basename(f.path);
      if (name.startsWith('Icon-App-')) {
        f.deleteSync();
        report.removed.add('${p.basename(dir)}/$name (legacy matrix)');
      }
    }
  }
}

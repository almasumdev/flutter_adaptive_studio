/// Phase 4: full-colour light/dark launcher icons via `activity-alias`.
///
/// Android has no declarative "swap the launcher icon by system theme": the
/// only way to ship two *different full-colour* icons is alias toggling done at
/// runtime (the Swiggy/Zomato approach). We generate the hard parts: a per-theme
/// adaptive icon set, the alias manifest wiring, and ready-to-paste runtime glue
/// (Kotlin + Dart) with the documented caveats.
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
import '../../vector/vector_drawable_writer.dart';
import '../platform_generator.dart';
import 'android_manifest_editor.dart';
import 'android_paths.dart';
import 'themed_icon_templates.dart';

/// Single source of truth for the files and shared-resource names the themed
/// light/dark icon feature owns, so `generate` (teardown) and `revert` can't
/// drift apart. Pure naming: no I/O.
class ThemedIconAssets {
  const ThemedIconAssets._();

  static const variants = ['light', 'dark'];

  /// The manifest `<activity-alias>` name for [variant], e.g. `.FasIconLight`.
  static String aliasName(String variant) =>
      '.FasIcon${variant[0].toUpperCase()}${variant.substring(1)}';

  /// The `values/colors.xml` entry name for [variant]'s background.
  static String backgroundColorName(String iconName, String variant) =>
      '${iconName}_${variant}_background';

  /// Absolute paths of the files fully owned by [variant]: the adaptive mipmap
  /// XML, its round sibling (only written when `round: true`), and the
  /// foreground vector. Safe to delete *only once no activity-alias references
  /// them* (an alias points at `@mipmap/<iconName>_<variant>`).
  static List<String> ownedFiles(
          AndroidPaths paths, String iconName, String variant) =>
      [
        p.join(paths.mipmapAnydpiV26, '${iconName}_$variant.xml'),
        p.join(paths.mipmapAnydpiV26, '${iconName}_${variant}_round.xml'),
        p.join(paths.drawableDir, '${iconName}_${variant}_foreground.xml'),
      ];
}

class AndroidThemedIcons {
  AndroidThemedIcons({
    required this.iconConfig,
    required this.themed,
    required this.adaptive,
    required this.loader,
    required this.paths,
    required this.writer,
    required this.logger,
  });

  final AndroidIconConfig iconConfig;
  final ThemedIconConfig themed;
  final AdaptiveConfig? adaptive;
  final ConfigLoader loader;
  final AndroidPaths paths;
  final ResWriter writer;
  final Logger logger;

  static const _ns = 'http://schemas.android.com/apk/res/android';

  /// A hex colour upper-cased, or null if [v] isn't one: lets the themed
  /// background fall back through the override chain to the adaptive background.
  static String? _color(String? v) =>
      (v != null && v.trim().startsWith('#')) ? v.trim().toUpperCase() : null;

  GenerationReport generate() {
    final report = GenerationReport();
    final name = iconConfig.iconName;

    // The adaptive background is the fallback; `themed.background` /
    // `background_dark` override it (the dark variant prefers `background_dark`,
    // then `background`). Themed backgrounds are colours, not images.
    final adaptiveBg = _color(adaptive?.background) ?? '#FFFFFF';
    final lightBg = _color(themed.background) ?? adaptiveBg;
    final darkBg = _color(themed.backgroundDark) ??
        _color(themed.background) ??
        adaptiveBg;

    final variants = <String>[];
    for (final entry in {'light': themed.light, 'dark': themed.dark}.entries) {
      if (entry.value == null) continue;
      final variant = entry.key;
      writer.upsertColor(paths.valuesDir, '${name}_${variant}_background',
          variant == 'dark' ? darkBg : lightBg);
      if (_writeVariant(name, variant, entry.value!, report)) {
        variants.add(variant);
      }
    }
    if (variants.isEmpty) {
      logger.skip('themed icons: no usable light/dark source');
      report.skipped.add('themed icons (no source)');
      return report;
    }

    // Manifest aliases.
    final wired = AndroidManifestEditor(paths.manifest).configureThemedAliases(
      iconName: name,
      variants: variants,
      round: iconConfig.round,
    );
    if (wired) {
      report.written
          .add('AndroidManifest.xml (activity-alias × ${variants.length})');
      logger.step('activity-aliases wired (${variants.join(', ')})');
    } else {
      logger.detail('themed aliases already present or no launcher activity');
    }

    // Drop-in runtime glue + guide.
    _writeGlue(report);
    logger
        .step('runtime glue + guide → flutter_adaptive_studio/THEMED_ICONS.md');

    logger.warn('Themed icons carry caveats (possible relaunch, permanent '
        'aliases, OEM variance). See flutter_adaptive_studio/THEMED_ICONS.md.');
    return report;
  }

  /// Tears the themed feature down when it is no longer configured, called from
  /// [AndroidIcons] on a `generate` where `icon.themed` is absent.
  ///
  /// The owned mipmaps are referenced by the `.FasIcon*` activity-aliases in the
  /// **shared** manifest, which we never auto-edit. So we only prune a variant's
  /// owned files when **no alias references them** (deleting a still-referenced
  /// mipmap would dangle `@mipmap/<name>_<variant>` and break the build). When an
  /// alias (or a leftover background colour) remains, we leave the files in place
  /// and WARN, naming the remnants and how to remove them. Does nothing (and
  /// stays quiet) when there is no themed residue at all.
  static void tearDownDisabled({
    required AndroidPaths paths,
    required String iconName,
    required Logger logger,
    required GenerationReport report,
  }) {
    final aliasVariants =
        AndroidManifestEditor(paths.manifest).themedAliasVariants().toSet();

    final colorsFile = File(p.join(paths.valuesDir, 'colors.xml'));
    final colorsXml =
        colorsFile.existsSync() ? colorsFile.readAsStringSync() : '';
    bool colorPresent(String v) => colorsXml.contains(
        'name="${ThemedIconAssets.backgroundColorName(iconName, v)}"');

    final leftoverColors = <String>[];
    var prunedAny = false;

    for (final v in ThemedIconAssets.variants) {
      final files = ThemedIconAssets.ownedFiles(paths, iconName, v)
          .map(File.new)
          .where((f) => f.existsSync())
          .toList();
      if (aliasVariants.contains(v)) {
        // An alias still references @mipmap/${iconName}_$v; leave the files in
        // place so the reference resolves and the build keeps working.
      } else {
        for (final f in files) {
          f.deleteSync();
          prunedAny = true;
          final rel = p.relative(f.path, from: paths.resDir);
          report.removed.add('$rel (themed icon disabled)');
          logger.detail('pruned $rel (themed icon disabled)');
        }
      }
      if (colorPresent(v)) {
        leftoverColors
            .add('@color/${ThemedIconAssets.backgroundColorName(iconName, v)}');
      }
    }

    if (prunedAny) {
      logger.step('themed icons disabled: pruned orphaned generated files');
    }

    // Surface shared-file remnants we will not auto-edit (manifest, colors).
    if (aliasVariants.isNotEmpty) {
      final aliasNames =
          aliasVariants.map(ThemedIconAssets.aliasName).join(' / ');
      final colorNote = leftoverColors.isNotEmpty
          ? ', and values/colors.xml still has ${leftoverColors.join(', ')}'
          : '';
      final w =
          'Themed icons look disabled in your config, but AndroidManifest.xml '
          'still has the $aliasNames <activity-alias> node(s)$colorNote. They '
          'reference the generated themed mipmaps, so those files were left in '
          'place to keep the build working. Remove the alias node(s)'
          '${leftoverColors.isNotEmpty ? ' and colour(s)' : ''} via version '
          'control or a manifest edit, then re-run generate to prune the files, '
          'or run `fas revert`.';
      logger.warn(w);
      report.warnings.add(w);
    } else if (leftoverColors.isNotEmpty && prunedAny) {
      final w = 'Themed icons are disabled and the generated mipmaps/drawables '
          'were pruned, but values/colors.xml still has the now-unused '
          '${leftoverColors.join(', ')} entr'
          '${leftoverColors.length == 1 ? 'y' : 'ies'}. Harmless, but remove '
          'via version control to keep colors.xml clean.';
      logger.warn(w);
      report.warnings.add(w);
    }
  }

  bool _writeVariant(
      String name, String variant, String source, GenerationReport report) {
    final abs = loader.resolveAsset(source);
    if (p.extension(abs).toLowerCase() != '.svg') {
      logger.skip('themed $variant "$source": full-colour themed icons '
          'currently require an SVG source');
      report.skipped.add('themed $variant (non-SVG)');
      return false;
    }
    final SvgDocument doc;
    try {
      doc = SvgDocument.parse(File(abs).readAsStringSync());
    } on Exception catch (e) {
      logger.error('themed $variant parse error: $e');
      return false;
    }

    final fit = AdaptiveGeometry.fitDoc(
      doc.artBounds(),
      doc.viewBox,
      adaptive?.safeZone ?? const SafeZone.fit(),
    );
    final fgXml = VectorDrawableWriter()
        .build(doc, viewport: AdaptiveGeometry.canvas, fit: fit);
    writer.writeText(
        p.join(paths.drawableDir, '${name}_${variant}_foreground.xml'), fgXml);

    final monoRef =
        adaptive?.monochrome != null ? '@drawable/${name}_monochrome' : null;
    final adaptiveXml = _adaptiveXml(
      foreground: '@drawable/${name}_${variant}_foreground',
      background: '@color/${name}_${variant}_background',
      monochrome: monoRef,
    );
    writer.writeText(
        p.join(paths.mipmapAnydpiV26, '${name}_$variant.xml'), adaptiveXml);
    report.written
      ..add('drawable/${name}_${variant}_foreground.xml')
      ..add('mipmap-anydpi-v26/${name}_$variant.xml');
    // Round variant mirrors the alias's android:roundIcon reference.
    if (iconConfig.round) {
      writer.writeText(
          p.join(paths.mipmapAnydpiV26, '${name}_${variant}_round.xml'),
          adaptiveXml);
      report.written.add('mipmap-anydpi-v26/${name}_${variant}_round.xml');
    }
    logger
        .step('themed $variant icon → mipmap-anydpi-v26/${name}_$variant.xml');
    return true;
  }

  void _writeGlue(GenerationReport report) {
    final dir = p.join(loader.projectRoot, 'flutter_adaptive_studio');
    writer.writeText(p.join(dir, 'FasIconSwitcher.kt'), themedIconKotlin);
    writer.writeText(p.join(dir, 'icon_switcher.dart'), themedIconDart);
    writer.writeText(p.join(dir, 'THEMED_ICONS.md'), themedIconGuide);
    report.written.add('flutter_adaptive_studio/ (Kotlin + Dart + guide)');
  }

  String _adaptiveXml({
    required String foreground,
    required String background,
    String? monochrome,
  }) {
    final b = XmlBuilder();
    b.processing('xml', 'version="1.0" encoding="utf-8"');
    b.comment(' Generated by flutter_adaptive_studio. Do not edit. ');
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

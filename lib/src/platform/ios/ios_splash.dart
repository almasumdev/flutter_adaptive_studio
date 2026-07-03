/// Generates the iOS launch screen (iOS has no SplashScreen API).
///
/// Drives `LaunchScreen.storyboard` through the asset catalog: a centred,
/// transparent **logo imageset** (light/dark) over a **background colour set**
/// (light/dark), with the storyboard's background pointed at that colour. Robust
/// by design — it edits only the background colour + populates asset sets rather
/// than rewriting Interface Builder XML. Sources fall back to the Android splash
/// / root source, so one config covers both platforms.
library;

import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../config/config.dart';
import '../../config/config_loader.dart';
import '../../graphic/svg_color.dart';
import '../../graphic/svg_document.dart';
import '../../logger.dart';
import '../../raster/image_rasterizer.dart';
import '../../raster/svg_rasterizer.dart';
import '../platform_generator.dart';
import 'ios_paths.dart';

class IosSplash {
  IosSplash({
    required this.config,
    required this.splash,
    required this.loader,
    required this.paths,
    required this.logger,
  });

  final AdaptiveStudioConfig config;
  final IosSplashConfig splash;
  final ConfigLoader loader;
  final IosPaths paths;
  final Logger logger;

  static const _bgColorName = 'LaunchBackground';
  static const _imageName = 'LaunchImage';
  static const _fit = 0.92; // logo fills 92% of its box, leaving a little air

  GenerationReport generate() {
    final report = GenerationReport();
    final android = config.android?.splash;

    final logo = splash.image ??
        android?.image ??
        config.source ??
        config.android?.icon?.adaptive?.foreground;
    final logoDark = splash.imageDark ?? android?.imageDark;
    final bg = splash.background ?? android?.background ?? '#FFFFFF';
    final bgDark = splash.backgroundDark ?? android?.backgroundDark;

    _writeColorset(bg, bgDark, report);
    _removeStaleBackgroundImageset(report);
    final hasLogo = logo != null && _writeLaunchImage(logo, logoDark, report);
    _patchStoryboard(report, hasLogo: hasLogo);
    logger.step('iOS launch screen → LaunchScreen.storyboard + asset catalog');
    return report;
  }

  // ----------------------------------------------------------------- colour set

  void _writeColorset(String bg, String? bgDark, GenerationReport report) {
    Map<String, Object> entry(int argb, [String? appearance]) => {
          'idiom': 'universal',
          if (appearance != null)
            'appearances': [
              {'appearance': 'luminosity', 'value': appearance}
            ],
          'color': {
            'color-space': 'srgb',
            'components': {
              'alpha': '1.000',
              'red': _f((argb >> 16) & 0xFF),
              'green': _f((argb >> 8) & 0xFF),
              'blue': _f(argb & 0xFF),
            },
          },
        };
    final colors = <Map<String, Object>>[
      entry(SvgColor.parse(bg).argb),
      if (bgDark != null) entry(SvgColor.parse(bgDark).argb, 'dark'),
    ];
    _writeJson(
        p.join(paths.xcassetsDir, '$_bgColorName.colorset', 'Contents.json'),
        {'colors': colors, 'info': _info});
    report.written.add('$_bgColorName.colorset');
  }

  /// Deletes a stale `LaunchBackground` *image set* a previous tool (e.g.
  /// flutter_native_splash) wrote for a full-bleed background image. We own that
  /// name as a colour set, so leaving the imageset gives the asset catalog two
  /// `LaunchBackground` entries ("ambiguous content") and the stale image can
  /// shadow the colour.
  void _removeStaleBackgroundImageset(GenerationReport report) {
    final dir = Directory(p.join(paths.xcassetsDir, '$_bgColorName.imageset'));
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
      report.removed.add('$_bgColorName.imageset (stale background image)');
    }
  }

  static String _f(int v) => (v / 255).toStringAsFixed(3);

  // ------------------------------------------------------------------ image set

  bool _writeLaunchImage(
      String logo, String? logoDark, GenerationReport report) {
    final abs = loader.resolveAsset(logo);
    if (!File(abs).existsSync()) {
      logger.warn('ios splash logo not found: $abs');
      report.skipped.add('ios splash logo (missing)');
      return false;
    }
    final dir = p.join(paths.xcassetsDir, '$_imageName.imageset');
    Directory(dir).createSync(recursive: true);

    const scales = {'1x': 1, '2x': 2, '3x': 3};
    var ok = true;
    scales.forEach((scale, mult) {
      final px = splash.logoSizePt * mult;
      ok &= _renderLogo(abs, px, p.join(dir, _file(scale, dark: false)));
    });
    if (!ok) {
      report.skipped.add('ios splash logo (render failed)');
      return false;
    }

    final darkAbs = logoDark == null ? null : loader.resolveAsset(logoDark);
    final hasDark = darkAbs != null && File(darkAbs).existsSync();
    if (hasDark) {
      scales.forEach((scale, mult) {
        _renderLogo(darkAbs, splash.logoSizePt * mult,
            p.join(dir, _file(scale, dark: true)));
      });
    }

    Map<String, Object> img(String scale, {required bool dark}) => {
          'idiom': 'universal',
          if (dark)
            'appearances': [
              {'appearance': 'luminosity', 'value': 'dark'}
            ],
          'filename': _file(scale, dark: dark),
          'scale': scale,
        };
    final images = <Map<String, Object>>[
      for (final s in scales.keys) img(s, dark: false),
      if (hasDark)
        for (final s in scales.keys) img(s, dark: true),
    ];
    _writeJson(p.join(dir, 'Contents.json'), {'images': images, 'info': _info});
    report.written.add('$_imageName.imageset');
    return true;
  }

  static String _file(String scale, {required bool dark}) {
    final suffix = scale == '1x' ? '' : '@$scale';
    return '$_imageName$suffix${dark ? '~dark' : ''}.png';
  }

  /// Renders [abs] to a transparent [px]² PNG (logo fitted, no background).
  bool _renderLogo(String abs, int px, String outPath) {
    final ext = p.extension(abs).toLowerCase();
    if (ext == '.svg') {
      try {
        final doc = SvgDocument.parse(File(abs).readAsStringSync());
        final image =
            const SvgRasterizer().rasterize(doc, px, fitFraction: _fit);
        File(outPath)
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(img.encodePng(image));
        return true;
      } on Exception catch (e) {
        logger.error('ios splash logo SVG parse error: $e');
        return false;
      }
    }
    if (const ImageRasterizer().supports(ext)) {
      return const ImageRasterizer().renderFittedPng(
          sourcePath: abs, canvasPx: px, fillFraction: _fit, outPath: outPath);
    }
    logger.skip('ios splash logo: unsupported source ($ext)');
    return false;
  }

  // ----------------------------------------------------------------- storyboard

  /// Points the launch view's background at the [_bgColorName] colour set. Only
  /// touches the background colour + a `<namedColor>` resource — never rewrites
  /// the IB layout.
  void _patchStoryboard(GenerationReport report, {required bool hasLogo}) {
    final file =
        File(p.join(paths.runnerDir, 'Base.lproj', 'LaunchScreen.storyboard'));
    if (!file.existsSync()) {
      logger
          .warn('LaunchScreen.storyboard not found — wrote the asset sets but '
              'could not wire the background colour.');
      report.skipped.add('ios LaunchScreen (storyboard missing)');
      return;
    }
    final doc = XmlDocument.parse(file.readAsStringSync());

    final view = doc.descendantElements.cast<XmlElement?>().firstWhere(
        (e) => e!.name.local == 'view' && e.getAttribute('key') == 'view',
        orElse: () => null);
    if (view == null) {
      logger.warn('LaunchScreen.storyboard has no root <view> — skipped.');
      report.skipped.add('ios LaunchScreen (no root view)');
      return;
    }

    _stripStaleBackgroundImageViews(doc, report);

    view.children.removeWhere((n) =>
        n is XmlElement &&
        n.name.local == 'color' &&
        n.getAttribute('key') == 'backgroundColor');
    view.children.add(XmlElement(XmlName.parts('color'), [
      XmlAttribute(XmlName.parts('key'), 'backgroundColor'),
      XmlAttribute(XmlName.parts('name'), _bgColorName),
    ]));

    // Register the named colour in <resources> (create the section if needed).
    var resources = doc.rootElement.childElements
        .cast<XmlElement?>()
        .firstWhere((e) => e!.name.local == 'resources', orElse: () => null);
    if (resources == null) {
      resources = XmlElement(XmlName.parts('resources'));
      doc.rootElement.children.add(resources);
    }
    final hasNamed = resources.childElements.any((e) =>
        e.name.local == 'namedColor' && e.getAttribute('name') == _bgColorName);
    if (!hasNamed) {
      resources.children.add(XmlElement(XmlName.parts('namedColor'),
          [XmlAttribute(XmlName.parts('name'), _bgColorName)]));
    }
    // Drop a stale <image name="LaunchBackground"> resource a prior tool left
    // for its full-bleed background — we own that name as a <namedColor> now.
    resources.children.removeWhere((n) =>
        n is XmlElement &&
        n.name.local == 'image' &&
        n.getAttribute('name') == _bgColorName);

    if (hasLogo) {
      final hasImageView = doc.descendantElements.any((e) =>
          e.name.local == 'imageView' && e.getAttribute('image') == _imageName);
      if (!hasImageView) {
        logger.warn('LaunchScreen.storyboard has no "$_imageName" image view — '
            'the logo imageset was written but the storyboard will not show it. '
            'Restore the default Flutter LaunchScreen (a centred LaunchImage).');
      }
    }

    file.writeAsStringSync(doc.toXmlString(pretty: true, indent: '    '));
    report.written.add('Base.lproj/LaunchScreen.storyboard (background)');
  }

  /// Removes a full-bleed background image view (and any layout constraints that
  /// reference it) a prior tool painted over the launch background —
  /// flutter_native_splash adds `<imageView image="LaunchBackground">`, which
  /// sits ON TOP of our `backgroundColor` and shadows it. Orphaned constraints
  /// must go too, or the storyboard won't load.
  void _stripStaleBackgroundImageViews(
      XmlDocument doc, GenerationReport report) {
    final stale = doc.descendantElements
        .where((e) =>
            e.name.local == 'imageView' &&
            e.getAttribute('image') == _bgColorName)
        .toList();
    if (stale.isEmpty) return;
    final ids =
        stale.map((e) => e.getAttribute('id')).whereType<String>().toSet();
    for (final e in stale) {
      e.parent?.children.remove(e);
    }
    for (final c in doc.descendantElements
        .where((e) => e.name.local == 'constraint')
        .toList()) {
      if (ids.contains(c.getAttribute('firstItem')) ||
          ids.contains(c.getAttribute('secondItem'))) {
        c.parent?.children.remove(c);
      }
    }
    report.removed.add('LaunchScreen stale background image view');
  }

  // ---------------------------------------------------------------------- utils

  static const Map<String, Object> _info = {
    'author': 'flutter_adaptive_studio',
    'version': 1,
  };

  void _writeJson(String path, Object json) {
    const encoder = JsonEncoder.withIndent('  ');
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('${encoder.convert(json)}\n');
  }
}

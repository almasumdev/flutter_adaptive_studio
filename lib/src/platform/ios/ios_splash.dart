/// Generates the iOS launch screen (iOS has no SplashScreen API).
///
/// Drives `LaunchScreen.storyboard` through the asset catalog: a centred,
/// transparent **logo imageset** (light/dark) over a **background colour set**
/// (light/dark), with the storyboard's background pointed at that colour. Robust
/// by design: it edits only the background colour + populates asset sets rather
/// than rewriting Interface Builder XML. Sources fall back to the Android splash
/// / root source, so one config covers both platforms.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
  static const _bgImageName = 'LaunchBackgroundImage';
  static const _bgViewId = 'fasSplashBg';
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
    final bgImageSrc = splash.backgroundImage ?? android?.backgroundImage;
    final bgImageDark =
        splash.backgroundImageDark ?? android?.backgroundImageDark;

    _writeColorset(bg, bgDark, report);
    _removeStaleBackgroundImageset(report);
    final bgImage = bgImageSrc != null
        ? _writeBackgroundImage(bgImageSrc, bgImageDark, report)
        : null;
    if (bgImage == null) _removeBackgroundImage(report);
    final hasLogo = logo != null && _writeLaunchImage(logo, logoDark, report);
    _patchStoryboard(report, hasLogo: hasLogo, bgImage: bgImage);
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

  // ------------------------------------------------------- full-bleed background

  /// Renders the optional full-bleed background image into
  /// `LaunchBackgroundImage.imageset` (light + dark), sized to fill the launch
  /// screen. Returns the light image's pixel size (for the storyboard's design
  /// hint), or null when the source is missing or cannot be rendered.
  ({int w, int h})? _writeBackgroundImage(
      String src, String? darkSrc, GenerationReport report) {
    final abs = loader.resolveAsset(src);
    if (!File(abs).existsSync()) {
      logger.warn('ios splash background image not found: $abs');
      report.skipped.add('ios splash background image (missing)');
      return null;
    }
    final dir = p.join(paths.xcassetsDir, '$_bgImageName.imageset');
    Directory(dir).createSync(recursive: true);
    final light = _renderFillImage(abs, p.join(dir, '$_bgImageName.png'));
    if (light == null) {
      report.skipped.add('ios splash background image (render failed)');
      return null;
    }
    var hasDark = false;
    if (darkSrc != null) {
      final dAbs = loader.resolveAsset(darkSrc);
      if (File(dAbs).existsSync()) {
        hasDark =
            _renderFillImage(dAbs, p.join(dir, '$_bgImageName~dark.png')) !=
                null;
      }
    }
    final images = <Map<String, Object>>[
      {'idiom': 'universal', 'filename': '$_bgImageName.png'},
      if (hasDark)
        {
          'idiom': 'universal',
          'appearances': [
            {'appearance': 'luminosity', 'value': 'dark'}
          ],
          'filename': '$_bgImageName~dark.png',
        },
    ];
    _writeJson(p.join(dir, 'Contents.json'), {'images': images, 'info': _info});
    report.written.add('$_bgImageName.imageset');
    logger.step('ios splash background image → $_bgImageName.imageset');
    return light;
  }

  /// Rasterises [abs] (SVG or raster) to [outPath] at its source aspect, sized
  /// for a full-screen `scaleAspectFill`. Returns the written pixel size or null.
  ({int w, int h})? _renderFillImage(String abs, String outPath) {
    final ext = p.extension(abs).toLowerCase();
    final img.Image out;
    if (ext == '.svg') {
      try {
        final doc = SvgDocument.parse(File(abs).readAsStringSync());
        const sq = 1024;
        final vw = doc.viewportWidth <= 0 ? 1.0 : doc.viewportWidth;
        final vh = doc.viewportHeight <= 0 ? 1.0 : doc.viewportHeight;
        final s = sq / math.max(vw, vh);
        final w = (vw * s).round().clamp(1, sq);
        final h = (vh * s).round().clamp(1, sq);
        final square = const SvgRasterizer().rasterize(doc, sq);
        out = (w == sq && h == sq)
            ? square
            : img.copyCrop(square,
                x: ((sq - w) / 2).round(),
                y: ((sq - h) / 2).round(),
                width: w,
                height: h);
      } on Exception catch (e) {
        logger.error('ios splash background image SVG parse error: $e');
        return null;
      }
    } else if (const ImageRasterizer().supports(ext)) {
      final src = img.decodeImage(File(abs).readAsBytesSync());
      if (src == null) {
        logger.warn('ios splash background image: could not decode $abs');
        return null;
      }
      const maxDim = 1536;
      final longest = math.max(src.width, src.height);
      out = longest > maxDim
          ? img.copyResize(src,
              width: (src.width * maxDim / longest).round(),
              height: (src.height * maxDim / longest).round(),
              interpolation: img.Interpolation.average)
          : src;
    } else {
      logger.skip('ios splash background image: unsupported source ($ext)');
      return null;
    }
    File(outPath)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(img.encodePng(out));
    return (w: out.width, h: out.height);
  }

  /// Deletes our `LaunchBackgroundImage.imageset` when no background image is
  /// configured, so removing it from the config removes it from the project.
  void _removeBackgroundImage(GenerationReport report) {
    final dir = Directory(p.join(paths.xcassetsDir, '$_bgImageName.imageset'));
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
      report.removed.add('$_bgImageName.imageset (background image removed)');
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
  /// touches the background colour + a `<namedColor>` resource, never rewrites
  /// the IB layout.
  void _patchStoryboard(GenerationReport report,
      {required bool hasLogo, ({int w, int h})? bgImage}) {
    final file =
        File(p.join(paths.runnerDir, 'Base.lproj', 'LaunchScreen.storyboard'));
    if (!file.existsSync()) {
      logger.warn('LaunchScreen.storyboard not found. Wrote the asset sets but '
          'could not wire the background colour.');
      report.skipped.add('ios LaunchScreen (storyboard missing)');
      return;
    }
    final doc = XmlDocument.parse(file.readAsStringSync());

    final view = doc.descendantElements.cast<XmlElement?>().firstWhere(
        (e) => e!.name.local == 'view' && e.getAttribute('key') == 'view',
        orElse: () => null);
    if (view == null) {
      logger.warn('LaunchScreen.storyboard has no root <view>. Skipped.');
      report.skipped.add('ios LaunchScreen (no root view)');
      return;
    }

    if (_stripImageViews(doc, _bgColorName) > 0) {
      report.removed.add('LaunchScreen stale background image view');
    }
    _stripImageViews(doc, _bgImageName); // our own bg image, re-added below

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
    // for its full-bleed background. We own that name as a <namedColor> now.
    resources.children.removeWhere((n) =>
        n is XmlElement &&
        n.name.local == 'image' &&
        n.getAttribute('name') == _bgColorName);

    // Optional full-bleed background image, behind the centred logo. Idempotent:
    // any prior image view was stripped above; drop its <image> hint and re-add.
    resources.children.removeWhere((n) =>
        n is XmlElement &&
        n.name.local == 'image' &&
        n.getAttribute('name') == _bgImageName);
    if (bgImage != null) {
      _addBackgroundImageView(view, resources, bgImage);
      report.written.add('LaunchScreen background image');
    }

    if (hasLogo) {
      final hasImageView = doc.descendantElements.any((e) =>
          e.name.local == 'imageView' && e.getAttribute('image') == _imageName);
      if (!hasImageView) {
        logger.warn('LaunchScreen.storyboard has no "$_imageName" image view. '
            'The logo imageset was written but the storyboard will not show it. '
            'Restore the default Flutter LaunchScreen (a centred LaunchImage).');
      }
    }

    file.writeAsStringSync(doc.toXmlString(pretty: true, indent: '    '));
    report.written.add('Base.lproj/LaunchScreen.storyboard (background)');
  }

  /// Inserts the full-bleed background image view (pinned to the launch view's
  /// edges) as the first subview, behind the logo, plus its `<image>` design
  /// hint. Uses `scaleAspectFill` so the image covers the screen at any size.
  void _addBackgroundImageView(
      XmlElement view, XmlElement resources, ({int w, int h}) size) {
    final rootId = view.getAttribute('id') ?? 'view';
    var subviews = view.childElements
        .cast<XmlElement?>()
        .firstWhere((e) => e!.name.local == 'subviews', orElse: () => null);
    if (subviews == null) {
      subviews = XmlElement(XmlName.parts('subviews'));
      view.children.insert(0, subviews);
    }
    subviews.children.insert(
        0,
        XmlElement(XmlName.parts('imageView'), [
          XmlAttribute(XmlName.parts('clipsSubviews'), 'YES'),
          XmlAttribute(XmlName.parts('userInteractionEnabled'), 'NO'),
          XmlAttribute(XmlName.parts('contentMode'), 'scaleAspectFill'),
          XmlAttribute(XmlName.parts('image'), _bgImageName),
          XmlAttribute(
              XmlName.parts('translatesAutoresizingMaskIntoConstraints'), 'NO'),
          XmlAttribute(XmlName.parts('id'), _bgViewId),
        ]));
    var constraints = view.childElements
        .cast<XmlElement?>()
        .firstWhere((e) => e!.name.local == 'constraints', orElse: () => null);
    if (constraints == null) {
      constraints = XmlElement(XmlName.parts('constraints'));
      view.children.add(constraints);
    }
    XmlElement pin(String attr, String id) =>
        XmlElement(XmlName.parts('constraint'), [
          XmlAttribute(XmlName.parts('firstItem'), _bgViewId),
          XmlAttribute(XmlName.parts('firstAttribute'), attr),
          XmlAttribute(XmlName.parts('secondItem'), rootId),
          XmlAttribute(XmlName.parts('secondAttribute'), attr),
          XmlAttribute(XmlName.parts('id'), id),
        ]);
    constraints.children.addAll([
      pin('top', 'fasBgTop'),
      pin('leading', 'fasBgLeading'),
      pin('trailing', 'fasBgTrailing'),
      pin('bottom', 'fasBgBottom'),
    ]);
    resources.children.add(XmlElement(XmlName.parts('image'), [
      XmlAttribute(XmlName.parts('name'), _bgImageName),
      XmlAttribute(XmlName.parts('width'), '${size.w}'),
      XmlAttribute(XmlName.parts('height'), '${size.h}'),
    ]));
  }

  /// Removes every `<imageView image="[imageName]">` and any layout constraints
  /// referencing it, returning how many image views were removed. Used to scrub
  /// a prior tool's full-bleed background (flutter_native_splash paints an
  /// `image="LaunchBackground"` view over our colour) and to re-write our own
  /// background image view idempotently.
  int _stripImageViews(XmlDocument doc, String imageName) {
    final stale = doc.descendantElements
        .where((e) =>
            e.name.local == 'imageView' && e.getAttribute('image') == imageName)
        .toList();
    if (stale.isEmpty) return 0;
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
    return stale.length;
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

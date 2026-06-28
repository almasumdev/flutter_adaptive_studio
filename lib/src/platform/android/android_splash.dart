/// Generates the Android splash — the headline feature.
///
/// API 31+ gets the real `SplashScreen` API wiring: a centre icon (a *static*
/// drawable generated from `image`, or a ready-made `AnimatedVectorDrawable`
/// XML supplied via `animated_icon` and used verbatim), an optional icon
/// background, and an optional bottom **branding** image. Pre-31 falls back to a
/// classic `windowBackground` layer-list with the resting logo (centred) and
/// branding (bottom). Dark variants are emitted via `-night` resources.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../config/config.dart';
import '../../config/config_loader.dart';
import '../../geometry/adaptive_geometry.dart';
import '../../graphic/bounds.dart';
import '../../graphic/svg_color.dart';
import '../../graphic/svg_document.dart';
import '../../io/res_writer.dart';
import '../../logger.dart';
import '../../raster/image_rasterizer.dart';
import '../../raster/svg_rasterizer.dart';
import '../../vector/vector_drawable_writer.dart';
import '../platform_generator.dart';
import 'android_manifest_editor.dart';
import 'android_paths.dart';
import 'android_styles_editor.dart';

class AndroidSplash {
  AndroidSplash({
    required this.splash,
    required this.loader,
    required this.paths,
    required this.writer,
    required this.logger,
    this.fallbackLogoSource,
  });

  final AndroidSplashConfig splash;
  final ConfigLoader loader;
  final AndroidPaths paths;
  final ResWriter writer;
  final Logger logger;

  /// Logo to use for the **pre-31** static launch logo when the splash has no
  /// `image:` (typically an animated-only splash). The Android < 12
  /// windowBackground can't run an animation, so without this the launch screen
  /// would be a bare colour. Wired to the app icon's foreground / root `source`.
  final String? fallbackLogoSource;

  static const _ns = 'http://schemas.android.com/apk/res/android';
  static const _name = 'splash_icon';

  /// Separate resource name for the pre-31 windowBackground centre logo. It's a
  /// **raster** (PNG/WebP), kept distinct from the v31 vector [_name] so the
  /// density bitmaps can't shadow the crisp vector on API 31+.
  static const _legacyName = 'splash_icon_legacy';
  static const _branding = 'splash_branding';

  /// Pre-31 branding raster, kept distinct from the v31 vector [_branding] (same
  /// reason as [_legacyName]): a VectorDrawable can't paint in `windowBackground`
  /// on API 21–23, so an SVG branding gets a per-density raster sibling for the
  /// launch layer-list while the crisp vector stays in the API 31+ slot.
  static const _legacyBranding = 'splash_branding_legacy';
  static const _bgImage = 'splash_bg';
  static const _rasterExts = {'.png', '.jpg', '.jpeg', '.webp', '.bmp', '.gif'};

  /// Centre-logo box size (dp) in the pre-31 layer-list. The rasters are
  /// rendered at this size per density so the logo is a consistent dp on every
  /// device — including API 21–22, where the item's `width`/`height` is ignored
  /// and the drawable's intrinsic size is used instead.
  static const _legacyBoxDp = 192;

  /// Raster (non-SVG) logos have no measurable art bounds, so they fill this
  /// fraction of the square — a comfortable, mask-free size on the pre-31 splash.
  static const _legacyRasterFill = 0.7;

  static const _legacyDensities = {
    'mdpi': 1.0,
    'hdpi': 1.5,
    'xhdpi': 2.0,
    'xxhdpi': 3.0,
    'xxxhdpi': 4.0,
  };

  GenerationReport generate() {
    final report = GenerationReport();

    // ---- Background colours ----
    final bg = splash.background ?? '#FFFFFF';
    writer.upsertColor(paths.valuesDir, 'splash_background', bg.toUpperCase());
    if (splash.background == null) {
      logger.skip('splash background: none given, defaulting to #FFFFFF');
    }
    if (splash.backgroundDark != null) {
      writer.upsertColor(paths.valuesNightDir, 'splash_background',
          splash.backgroundDark!.toUpperCase());
    }
    if (splash.iconBackground != null) {
      writer.upsertColor(paths.valuesDir, 'splash_icon_background',
          splash.iconBackground!.toUpperCase());
    }
    if (splash.iconBackgroundDark != null) {
      writer.upsertColor(paths.valuesNightDir, 'splash_icon_background',
          splash.iconBackgroundDark!.toUpperCase());
    }

    // ---- System bar colours (status + navigation), if configured ----
    _writeSystemBarColors();

    // ---- Full-bleed background image (pre-31 + fallback only) ----
    final bgImageRef = _resolveBackgroundImage(report);

    // ---- Centre icon (animated AVD, or a static logo) ----
    final icon = _resolveIcon(report);

    // ---- Bottom branding image ----
    // Two refs: the crisp vector (slotRef) for the API 31+ branding slot, and a
    // raster (layerRef) for the pre-31 windowBackground (where a vector can't
    // paint on API 21–23). They're the same name unless the source is an SVG.
    final branding = _resolveBranding(report);

    // ---- API 31+ SplashScreen theme ----
    _writeV31Styles(paths.valuesV31Dir,
        launchParent: '@android:style/Theme.Light.NoTitleBar',
        icon: icon,
        brandingRef: branding.slotRef,
        night: false);
    _writeV31Styles(paths.valuesNightV31Dir,
        launchParent: '@android:style/Theme.Black.NoTitleBar',
        icon: icon,
        brandingRef: branding.slotRef,
        night: true);
    if (splash.brandingMode != BrandingMode.bottom &&
        branding.slotRef != null) {
      logger.warn('branding_mode only affects the pre-31 splash + Flutter '
          'fallback; the Android 12+ system splash always bottom-centres it.');
    }
    if (bgImageRef != null) {
      logger.warn('background_image applies to the pre-31 splash + Flutter '
          'fallback only; the Android 12+ system splash uses the solid '
          '`background` colour (the API takes a colour, not an image).');
    }
    report.written
      ..add('values-v31/styles.xml')
      ..add('values-night-v31/styles.xml');
    logger.step('API 31+ SplashScreen theme (+ night) written');
    logger.warn('SplashScreen API needs compileSdk >= 31. If the build fails '
        'with "windowSplashScreen... not found", set compileSdk to 34 in '
        'android/app/build.gradle(.kts).');

    // ---- Pre-31 classic splash ----
    _writeLegacyStyles(paths.valuesDir,
        launchParent: '@android:style/Theme.Light.NoTitleBar', night: false);
    _writeLegacyStyles(paths.valuesNightDir,
        launchParent: '@android:style/Theme.Black.NoTitleBar', night: true);
    // Written to drawable/ AND drawable-v21/ (+ any night variants) so the
    // stock Flutter drawable-v21/launch_background.xml can't shadow ours on
    // API 21+ devices. The @color/icon refs resolve their `-night` flavours
    // automatically, so one theme-agnostic XML covers light and dark.
    final launchFiles = _writeLaunchBackgrounds(
        iconRef: icon.layerRef,
        brandingRef: branding.layerRef,
        bgImageRef: bgImageRef);
    report.written.add('values/styles.xml (LaunchTheme)');
    report.written.addAll(launchFiles);
    logger.step('pre-31 classic splash written (drawable/ + drawable-v21/)');

    // ---- Optional: lock orientation on the launcher activity (main manifest) ----
    if (splash.screenOrientation != null) {
      final changed = AndroidManifestEditor(paths.manifest)
          .setLaunchOrientation(splash.screenOrientation!);
      if (changed) {
        report.written.add('AndroidManifest.xml (screenOrientation)');
        logger.step('screenOrientation=${splash.screenOrientation} → manifest');
        logger.warn('screen_orientation is app-wide and on the shared manifest '
            '— `revert` will NOT undo it (use version control).');
      }
    }

    return report;
  }

  // --------------------------------------------------------------- centre icon

  /// Resolves the centre icon into drawables and returns how to wire it: an
  /// `animated_icon` (a ready-made AnimatedVectorDrawable `.xml`, used verbatim)
  /// takes priority; otherwise a static `image`. Animated icons are used **as
  /// authored** — never keyline-reshaped, since that would break the animation.
  _IconPlan _resolveIcon(GenerationReport report) {
    // The pre-31 windowBackground centre logo is ALWAYS a raster. A
    // VectorDrawable (or AVD) referenced from `windowBackground` is inflated by
    // the platform before AppCompat's vector compat layer is active, so it
    // silently fails to paint on API 21–23 (you'd see the colour but no logo).
    // Rasterise the static `image:` instead — a bitmap always renders. (The
    // API 31+ slot below still uses the crisp vector / AVD.)
    final legacyRef = _emitLegacyIcon(report);

    if (splash.animatedIcon != null) {
      if (_copyAvd(splash.animatedIcon!, splash.animatedIconDark, report)) {
        _warnAnimatedKeyline();
        if (legacyRef == null) {
          logger.warn('pre-31 splash: an animated_icon cannot be a '
              'windowBackground drawable, and no static `image:` (or app logo) '
              'was available — Android < 12 will show the background colour '
              'only. Add a static `image:` for a resting logo there.');
        } else if (splash.image == null) {
          logger.detail('pre-31 splash: using the app logo as the static '
              'launch logo (set splash `image:` to override).');
        }
        return _IconPlan(slotRef: _name, layerRef: legacyRef, animated: true);
      }
      // Fall through to static if the AVD couldn't be used.
    }
    final image = splash.image;
    if (image != null) {
      if (_emitDrawable(image, _name, report,
          role: 'splash image', square: true)) {
        // Dark variant → drawable-night/splash_icon, picked up automatically by
        // the night API-31 theme.
        if (splash.imageDark != null) {
          _emitDrawable(splash.imageDark!, _name, report,
              role: 'splash image (dark)', square: true, night: true);
        }
        return _IconPlan(slotRef: _name, layerRef: legacyRef, animated: false);
      }
    } else if (splash.animatedIcon == null) {
      logger.skip(
          'splash icon: no image or animated_icon (background-only splash)');
      report.skipped.add('splash icon (none)');
    }
    return _IconPlan(slotRef: null, layerRef: legacyRef, animated: false);
  }

  // ----------------------------------------------------- pre-31 raster logo

  /// Rasterises the static centre logo into per-density PNG/WebP under
  /// `drawable-<density>/` (+ `-night`) for the pre-31 windowBackground, and
  /// returns its resource base name — or null when there's no static `image:`
  /// (an animated-only or background-only splash).
  String? _emitLegacyIcon(GenerationReport report) {
    // Prefer the splash `image:`; otherwise fall back to the app logo so an
    // animated-only splash still shows a mark on Android < 12 (where the
    // animated icon doesn't apply) instead of a bare colour.
    final usingFallback = splash.image == null;
    final src = splash.image ?? fallbackLogoSource;
    if (src == null) return null;
    if (!_rasterizeLegacyIcon(src, report, night: false)) return null;
    // A dark variant only exists for an explicit splash `image_dark:`.
    if (!usingFallback && splash.imageDark != null) {
      _rasterizeLegacyIcon(splash.imageDark!, report, night: true);
    }
    final fmt = splash.imageFormat;
    logger.step('pre-31 splash logo (raster, ${fmt.name}'
        '${usingFallback ? ', from app logo' : ''}) → '
        'drawable-*/$_legacyName${fmt.extension}');
    return _legacyName;
  }

  /// Renders [source] (SVG or raster) into a transparent square at each density
  /// for the pre-31 splash logo. Returns true if any density was written.
  bool _rasterizeLegacyIcon(String source, GenerationReport report,
      {required bool night}) {
    final abs = loader.resolveAsset(source);
    if (!File(abs).existsSync()) {
      logger.warn('pre-31 splash logo source not found: $abs');
      report.skipped.add('pre-31 splash logo (file not found)');
      return false;
    }
    final ext = p.extension(abs).toLowerCase();
    final fmt = splash.imageFormat;
    final outExt = fmt.extension;

    if (ext == '.svg') {
      final SvgDocument doc;
      try {
        doc = SvgDocument.parse(File(abs).readAsStringSync());
      } on Exception catch (e) {
        logger.error('pre-31 splash logo parse error: $e');
        report.warnings.add('pre-31 splash logo parse error: $e');
        return false;
      }
      final fit = _legacyFitFraction(doc);
      var any = false;
      _legacyDensities.forEach((density, mult) {
        final sizePx = (_legacyBoxDp * mult).round();
        // Transparent canvas (no backgroundArgb) — the layer-list paints the
        // colour behind it.
        final image =
            const SvgRasterizer().rasterize(doc, sizePx, fitFraction: fit);
        final dir = _legacyDensityDir(density, night);
        File(p.join(dir, '$_legacyName$outExt'))
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(ImageRasterizer.encode(image, fmt));
        report.written.add('${night ? 'drawable-night' : 'drawable'}'
            '-$density/$_legacyName$outExt');
        _removeStaleLegacySibling(density, outExt, night, report);
        any = true;
      });
      if (any) report.warnings.addAll(doc.warnings);
      return any;
    }

    if (_rasterExts.contains(ext)) {
      const rasterizer = ImageRasterizer();
      var any = false;
      _legacyDensities.forEach((density, mult) {
        final out =
            p.join(_legacyDensityDir(density, night), '$_legacyName$outExt');
        if (rasterizer.renderFittedPng(
          sourcePath: abs,
          canvasPx: (_legacyBoxDp * mult).round(),
          fillFraction: _legacyRasterFill,
          outPath: out,
          format: fmt,
        )) {
          report.written.add('${night ? 'drawable-night' : 'drawable'}'
              '-$density/$_legacyName$outExt');
          _removeStaleLegacySibling(density, outExt, night, report);
          any = true;
        }
      });
      return any;
    }

    logger.skip('pre-31 splash logo "$source": unsupported ($ext) — '
        'use SVG or a raster image');
    report.skipped.add('pre-31 splash logo (unsupported $ext)');
    return false;
  }

  /// `drawable[-night]-<density>` directory for the legacy raster logo.
  String _legacyDensityDir(String density, bool night) => night
      ? p.join(paths.resDir, 'drawable-night-$density')
      : paths.drawableDensityDir(density);

  /// Fraction of the square the SVG art fills, reproducing the API 31+ keyline
  /// look (the art's bounding box inscribed in the 2/3 safe circle) so the
  /// pre-31 logo matches the size of the system splash icon on API 31+.
  double _legacyFitFraction(SvgDocument doc) {
    final canvas = splash.iconBackground != null ? 240.0 : 288.0;
    final safeDiameter = canvas * 2 / 3;
    final art = doc.artBounds();
    final w = (art?.width ?? doc.viewportWidth).abs();
    final h = (art?.height ?? doc.viewportHeight).abs();
    final longest = math.max(w, h);
    final diagonal = math.sqrt(w * w + h * h);
    if (longest == 0 || diagonal == 0) return 0.6;
    // SvgRasterizer fits the longest side to `fraction * canvas`; the vector
    // keyline fits the *diagonal* to the safe diameter. Convert between them.
    return (longest / diagonal) * (safeDiameter / canvas);
  }

  /// Drops a same-name legacy logo left in the other raster format by a previous
  /// run, so a stale PNG can't shadow a fresh WebP (or vice-versa).
  void _removeStaleLegacySibling(
      String density, String keepExt, bool night, GenerationReport report) {
    for (final e in const ['.png', '.webp']) {
      if (e == keepExt) continue;
      final f =
          File(p.join(_legacyDensityDir(density, night), '$_legacyName$e'));
      if (f.existsSync()) {
        f.deleteSync();
        report.removed.add('${night ? 'drawable-night' : 'drawable'}'
            '-$density/$_legacyName$e (stale)');
      }
    }
  }

  // ----------------------------------------------------------------- branding

  /// Emits the full-bleed background image (+ dark) and returns its base name,
  /// or null when none is configured/usable. Stretched to fill the window on the
  /// pre-31 splash; the API 31+ splash takes a colour only (see generate()).
  ///
  /// Because the background image is used ONLY on the pre-31 windowBackground
  /// (where a VectorDrawable can't paint on API 21–23), an SVG source is
  /// rasterised to a `drawable[-night]-nodpi` bitmap — a raster always inflates,
  /// so it can never break the launch background on old devices.
  String? _resolveBackgroundImage(GenerationReport report) {
    final src = splash.backgroundImage;
    if (src == null) return null;
    final dark = splash.backgroundImageDark;
    if (_isSvg(src)) {
      if (!_rasterizeFillImage(src, report, night: false)) return null;
      if (dark != null) {
        _isSvg(dark)
            ? _rasterizeFillImage(dark, report, night: true)
            : _emitDrawable(dark, _bgImage, report,
                role: 'splash background image (dark)',
                square: false,
                fill: true,
                night: true);
      }
      logger.step('background image (raster, ${splash.imageFormat.name}) → '
          'drawable-nodpi/$_bgImage${splash.imageFormat.extension}');
      return _bgImage;
    }
    if (!_emitDrawable(src, _bgImage, report,
        role: 'splash background image', square: false, fill: true)) {
      return null;
    }
    if (dark != null) {
      _emitDrawable(dark, _bgImage, report,
          role: 'splash background image (dark)',
          square: false,
          fill: true,
          night: true);
    }
    logger.step('background image → drawable/$_bgImage');
    return _bgImage;
  }

  /// Rasterises an SVG fill background to a single `drawable[-night]-nodpi`
  /// bitmap (the layer-list stretches it to the window), so it inflates on API
  /// 21–23. Rendered at the viewBox aspect (longest side 1024) and cropped to it,
  /// so the no-gravity stretch fills full-bleed instead of letterboxing.
  bool _rasterizeFillImage(String source, GenerationReport report,
      {required bool night}) {
    final abs = loader.resolveAsset(source);
    if (!File(abs).existsSync()) {
      logger.warn('splash background image not found: $abs');
      report.skipped.add('splash background image (file not found)');
      return false;
    }
    final SvgDocument doc;
    try {
      doc = SvgDocument.parse(File(abs).readAsStringSync());
    } on Exception catch (e) {
      logger.error('splash background image parse error: $e');
      report.warnings.add('splash background image parse error: $e');
      return false;
    }
    // Render the whole viewBox into a square (it letterboxes), then crop to the
    // viewBox's own rectangle so the bitmap carries the source aspect.
    const sq = 1024;
    final vw = doc.viewportWidth <= 0 ? 1.0 : doc.viewportWidth;
    final vh = doc.viewportHeight <= 0 ? 1.0 : doc.viewportHeight;
    final s = sq / math.max(vw, vh);
    final w = (vw * s).round().clamp(1, sq);
    final h = (vh * s).round().clamp(1, sq);
    final square = const SvgRasterizer().rasterize(doc, sq);
    final image = (w == sq && h == sq)
        ? square
        : img.copyCrop(square,
            x: ((sq - w) / 2).round(),
            y: ((sq - h) / 2).round(),
            width: w,
            height: h);
    final fmt = splash.imageFormat;
    final dir =
        p.join(paths.resDir, night ? 'drawable-night-nodpi' : 'drawable-nodpi');
    File(p.join(dir, '$_bgImage${fmt.extension}'))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(ImageRasterizer.encode(image, fmt));
    report.written.add('${night ? 'drawable-night-nodpi' : 'drawable-nodpi'}'
        '/$_bgImage${fmt.extension}');
    // A stale vector or other-format sibling could otherwise shadow this raster.
    for (final stale in [
      File(p.join(
          night ? paths.drawableNightDir : paths.drawableDir, '$_bgImage.xml')),
      File(p.join(
          dir, '$_bgImage${fmt.extension == '.png' ? '.webp' : '.png'}')),
    ]) {
      if (stale.existsSync()) {
        stale.deleteSync();
        report.removed.add('${p.basename(stale.path)} (stale)');
      }
    }
    report.warnings.addAll(doc.warnings);
    return true;
  }

  /// Emits the bottom branding drawables and returns a [_BrandingPlan] of how to
  /// wire them: `slotRef` feeds the API 31+ branding slot (a crisp vector for an
  /// SVG source), `layerRef` feeds the pre-31 windowBackground (always a raster,
  /// since a vector can't paint there on API 21–23). A `branding:` image wins;
  /// otherwise `branding_text:` is rendered to a wordmark. An empty plan
  /// (`slotRef == null`) means no branding was configured/usable.
  _BrandingPlan _resolveBranding(GenerationReport report) {
    final src = splash.branding;
    if (src != null) {
      if (!_emitDrawable(src, _branding, report,
          role: 'splash branding', square: false)) {
        return const _BrandingPlan(slotRef: null, layerRef: null);
      }
      if (splash.brandingDark != null) {
        _emitDrawable(splash.brandingDark!, _branding, report,
            role: 'splash branding (dark)', square: false, night: true);
      }
      logger.step('branding → drawable/$_branding');
      // A raster branding is already a bitmap (legacy-safe); only an SVG needs a
      // rasterised sibling for the pre-31 launch layer-list.
      final layerRef = _isSvg(src)
          ? _emitLegacyBranding(src, splash.brandingDark, report)
          : _branding;
      return _BrandingPlan(slotRef: _branding, layerRef: layerRef);
    }

    final text = splash.brandingText;
    if (text == null) return const _BrandingPlan(slotRef: null, layerRef: null);
    final lightArgb = SvgColor.parse(
            splash.brandingTextColor ?? _defaultBrandingTextColor(false))
        .argb;
    if (!_emitBrandingText(text, lightArgb, report, night: false)) {
      return const _BrandingPlan(slotRef: null, layerRef: null);
    }
    // A dark wordmark is emitted when a dark text colour or dark background is
    // configured (so the `-night` resource contrasts the dark splash).
    if (splash.brandingTextColorDark != null || splash.backgroundDark != null) {
      final darkArgb = SvgColor.parse(
              splash.brandingTextColorDark ?? _defaultBrandingTextColor(true))
          .argb;
      _emitBrandingText(text, darkArgb, report, night: true);
    }
    logger.step('branding text "$text" → drawable-*/$_branding');
    // Text branding is already a per-density raster → the same name is
    // legacy-safe for the pre-31 launch layer.
    return const _BrandingPlan(slotRef: _branding, layerRef: _branding);
  }

  /// Rasterises an SVG [src] branding into per-density `splash_branding_legacy`
  /// bitmaps (+ `-night` from [darkSrc]) for the pre-31 windowBackground, and
  /// returns its base name. Falls back to the vector [_branding] ref if the SVG
  /// can't be rasterised (still works on API 24+).
  String? _emitLegacyBranding(
      String src, String? darkSrc, GenerationReport report) {
    if (!_rasterizeLegacyBranding(src, report, night: false)) return _branding;
    if (darkSrc != null && _isSvg(darkSrc)) {
      _rasterizeLegacyBranding(darkSrc, report, night: true);
    }
    logger.step('pre-31 branding (raster, ${splash.imageFormat.name}) → '
        'drawable-*/$_legacyBranding${splash.imageFormat.extension}');
    return _legacyBranding;
  }

  /// Renders an SVG branding [source] into the 200×80dp branding slot at each
  /// density (aspect-preserved + centred, like [_brandingVd]), written to
  /// `drawable[-night]-<density>/`. Returns true if any density was written.
  bool _rasterizeLegacyBranding(String source, GenerationReport report,
      {required bool night}) {
    final abs = loader.resolveAsset(source);
    if (!File(abs).existsSync()) return false;
    final SvgDocument doc;
    try {
      doc = SvgDocument.parse(File(abs).readAsStringSync());
    } on Exception catch (e) {
      logger.warn('pre-31 branding parse error: $e');
      report.warnings.add('pre-31 branding parse error: $e');
      return false;
    }
    const slotW = 200, slotH = 80, margin = 0.9;
    final fmt = splash.imageFormat;
    var any = false;
    _legacyDensities.forEach((density, mult) {
      final canvasW = (slotW * mult).round();
      final canvasH = (slotH * mult).round();
      // Render the art tightly to a square, trim, then letterbox into the slot —
      // so its aspect matches the slot and the layer can't distort it.
      final rendered = const SvgRasterizer()
          .rasterize(doc, math.max(canvasW, canvasH), fitFraction: 0.95);
      final tight = _trimTransparent(rendered);
      final scale = math.min(
          canvasW * margin / tight.width, canvasH * margin / tight.height);
      final w = (tight.width * scale).round().clamp(1, canvasW);
      final h = (tight.height * scale).round().clamp(1, canvasH);
      final scaled = ImageRasterizer.resizeSmart(tight, w, h);
      final canvas = img.Image(width: canvasW, height: canvasH, numChannels: 4);
      img.compositeImage(canvas, scaled,
          dstX: ((canvasW - w) / 2).round(), dstY: ((canvasH - h) / 2).round());
      final dir = _legacyDensityDir(density, night);
      File(p.join(dir, '$_legacyBranding${fmt.extension}'))
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(ImageRasterizer.encode(canvas, fmt));
      report.written.add('${night ? 'drawable-night' : 'drawable'}'
          '-$density/$_legacyBranding${fmt.extension}');
      _removeStaleLegacyBrandingSibling(density, fmt.extension, night, report);
      any = true;
    });
    if (any) report.warnings.addAll(doc.warnings);
    return any;
  }

  /// Drops a same-name legacy branding raster left in the other format by a
  /// previous run, so a stale PNG can't shadow a fresh WebP (or vice-versa).
  void _removeStaleLegacyBrandingSibling(
      String density, String keepExt, bool night, GenerationReport report) {
    for (final e in const ['.png', '.webp']) {
      if (e == keepExt) continue;
      final f =
          File(p.join(_legacyDensityDir(density, night), '$_legacyBranding$e'));
      if (f.existsSync()) {
        f.deleteSync();
        report.removed.add('${night ? 'drawable-night' : 'drawable'}'
            '-$density/$_legacyBranding$e (stale)');
      }
    }
  }

  /// Trims fully-transparent margins so the art can be scaled into the slot.
  static img.Image _trimTransparent(img.Image src) {
    final t = img.findTrim(src, mode: img.TrimMode.transparent);
    if (t[2] <= 0 || t[3] <= 0) return src;
    return img.copyCrop(src, x: t[0], y: t[1], width: t[2], height: t[3]);
  }

  /// True when [source] resolves to an `.svg` asset.
  bool _isSvg(String source) =>
      p.extension(loader.resolveAsset(source)).toLowerCase() == '.svg';

  /// Default branding-text colour: dark text on a light background, light text
  /// on a dark one.
  String _defaultBrandingTextColor(bool night) {
    final bg = (night ? splash.backgroundDark : splash.background) ??
        splash.background ??
        (night ? '#000000' : '#FFFFFF');
    return _isLightColor(bg) ? '#000000' : '#FFFFFF';
  }

  /// Renders [text] as a bottom wordmark, letterboxed into the 200×80dp branding
  /// slot at each density (so the API 31+ system can't distort it and the pre-31
  /// layer shows a consistent dp size), written to `drawable[-night]-<density>/`.
  bool _emitBrandingText(String text, int colorArgb, GenerationReport report,
      {required bool night}) {
    final tight = _renderTextTight(text, colorArgb);
    if (tight == null) {
      logger.warn('branding text: could not render "$text"');
      return false;
    }
    const slotW = 200, slotH = 80, margin = 0.9;
    final fmt = splash.imageFormat;
    var any = false;
    _legacyDensities.forEach((density, mult) {
      final canvasW = (slotW * mult).round();
      final canvasH = (slotH * mult).round();
      final scale = math.min(
          canvasW * margin / tight.width, canvasH * margin / tight.height);
      final w = (tight.width * scale).round().clamp(1, canvasW);
      final h = (tight.height * scale).round().clamp(1, canvasH);
      final scaled = ImageRasterizer.resizeSmart(tight, w, h);
      final canvas = img.Image(width: canvasW, height: canvasH, numChannels: 4);
      img.compositeImage(canvas, scaled,
          dstX: ((canvasW - w) / 2).round(), dstY: ((canvasH - h) / 2).round());
      final dir = _legacyDensityDir(density, night);
      File(p.join(dir, '$_branding${fmt.extension}'))
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(ImageRasterizer.encode(canvas, fmt));
      report.written.add('${night ? 'drawable-night' : 'drawable'}'
          '-$density/$_branding${fmt.extension}');
      any = true;
    });
    return any;
  }

  /// Draws [text] with the bundled font and trims to the glyph bounds, so the
  /// caller can scale the tight wordmark into the branding slot.
  img.Image? _renderTextTight(String text, int colorArgb) {
    final canvas =
        img.Image(width: text.length * 60 + 80, height: 96, numChannels: 4);
    img.drawString(canvas, text,
        font: img.arial48,
        x: 8,
        y: 8,
        color: img.ColorRgba8((colorArgb >> 16) & 0xFF, (colorArgb >> 8) & 0xFF,
            colorArgb & 0xFF, 0xFF));
    final t = img.findTrim(canvas, mode: img.TrimMode.transparent);
    if (t[2] <= 0 || t[3] <= 0) return null;
    return img.copyCrop(canvas, x: t[0], y: t[1], width: t[2], height: t[3]);
  }

  /// Emits a drawable [base] from [source]: SVG → VectorDrawable, raster → a
  /// density-independent `drawable-nodpi` PNG. [square] centres the art in a
  /// square canvas (the icon); otherwise aspect is preserved (the branding).
  bool _emitDrawable(String source, String base, GenerationReport report,
      {required String role,
      required bool square,
      bool fill = false,
      bool night = false}) {
    final abs = loader.resolveAsset(source);
    if (!File(abs).existsSync()) {
      logger.warn('$role source not found: $abs');
      report.skipped.add('$role (file not found)');
      return false;
    }
    final ext = p.extension(abs).toLowerCase();
    final drawableDir = night ? paths.drawableNightDir : paths.drawableDir;

    if (ext == '.svg') {
      final SvgDocument doc;
      try {
        doc = SvgDocument.parse(File(abs).readAsStringSync());
      } on Exception catch (e) {
        logger.error('$role parse error: $e');
        report.warnings.add('$role parse error: $e');
        return false;
      }
      final xml = fill
          ? _fillVd(doc)
          : (square ? _squareIconVd(doc) : _brandingVd(doc));
      writer.writeText(p.join(drawableDir, '$base.xml'), xml);
      report.written.add('${night ? 'drawable-night' : 'drawable'}/$base.xml');
      report.warnings.addAll(doc.warnings);
      return true;
    }

    if (_rasterExts.contains(ext)) {
      final src = img.decodeImage(File(abs).readAsBytesSync());
      if (src == null) {
        logger.warn('$role: could not decode $abs');
        report.skipped.add('$role (decode failed)');
        return false;
      }
      // nodpi → used as-authored across densities; downscale only if huge.
      const maxDim = 512;
      final longest = math.max(src.width, src.height);
      final out = longest > maxDim
          ? img.copyResize(src,
              width: (src.width * maxDim / longest).round(),
              height: (src.height * maxDim / longest).round(),
              interpolation: img.Interpolation.average)
          : src;
      final dir = p.join(
          paths.resDir, night ? 'drawable-night-nodpi' : 'drawable-nodpi');
      File(p.join(dir, '$base.png'))
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(img.encodePng(out));
      report.written.add(
          '${night ? 'drawable-night-nodpi' : 'drawable-nodpi'}/$base.png');
      return true;
    }

    logger.skip(
        '$role "$source": unsupported ($ext) — use SVG or a raster image');
    report.skipped.add('$role (unsupported $ext)');
    return false;
  }

  /// Builds the centre-icon VectorDrawable to the Android 12 SplashScreen
  /// keyline spec so the launcher's circular mask never clips it.
  ///
  /// The system masks the icon to a centred circle of **2/3 the canvas** —
  /// 288dp canvas / ⌀192dp safe circle (no icon background), or 240/⌀160 (with
  /// one). We **inscribe the art's bounding box in that circle** (diagonal ≤
  /// diameter) so even a square logo's corners stay inside the mask.
  String _squareIconVd(SvgDocument doc) {
    final canvas = splash.iconBackground != null ? 240.0 : 288.0;
    final safeDiameter = canvas * 2 / 3; // ⌀160 or ⌀192
    final art = doc.artBounds();
    final w = (art?.width ?? doc.viewportWidth).abs();
    final h = (art?.height ?? doc.viewportHeight).abs();
    final diagonal = math.sqrt(w * w + h * h);
    final cx = art?.centerX ?? doc.viewportWidth / 2;
    final cy = art?.centerY ?? doc.viewportHeight / 2;
    final scale = diagonal == 0 ? 1.0 : safeDiameter / diagonal;
    final fit = AdaptiveFit(
      scale: scale,
      translateX: canvas / 2 - scale * cx,
      translateY: canvas / 2 - scale * cy,
    );
    return VectorDrawableWriter()
        .build(doc, viewport: canvas, fit: fit, sizeDp: canvas);
  }

  /// Branding wordmark VD, letterboxed onto the **200×80dp** branding slot the
  /// Android 12 SplashScreen reserves for `windowSplashScreenBrandingImage`.
  ///
  /// The system scales the branding drawable to fill that fixed-aspect slot, so
  /// a tightly-trimmed wide/short wordmark (e.g. ~6:1) gets stretched vertically
  /// to the 2.5:1 slot. By emitting the drawable AT the slot size with the art
  /// scaled-to-fit (aspect preserved) and centred, the drawable's own aspect
  /// matches the slot — filling it can no longer distort the art.
  String _brandingVd(SvgDocument doc) {
    const slotW = 200.0; // Android branding image slot (dp)
    const slotH = 80.0;
    const margin = 0.9; // leave a little breathing room inside the slot
    final art =
        doc.artBounds() ?? Bounds(0, 0, doc.viewportWidth, doc.viewportHeight);
    final w = art.width > 0 ? art.width : doc.viewportWidth;
    final h = art.height > 0 ? art.height : doc.viewportHeight;
    final scale =
        (w <= 0 || h <= 0) ? 1.0 : math.min(slotW / w, slotH / h) * margin;
    final fit = AdaptiveFit(
      scale: scale,
      translateX: slotW / 2 - scale * (art.minX + w / 2),
      translateY: slotH / 2 - scale * (art.minY + h / 2),
    );
    return VectorDrawableWriter().build(
      doc,
      viewport: slotW,
      viewportHeight: slotH,
      fit: fit,
      sizeDp: slotW,
      sizeDpHeight: slotH,
    );
  }

  /// Full-bleed VD: maps the SVG viewBox 1:1 so a layer-list item (no gravity)
  /// stretches it to the window bounds as a background.
  String _fillVd(SvgDocument doc) {
    final w = doc.viewportWidth <= 0 ? 1.0 : doc.viewportWidth;
    final h = doc.viewportHeight <= 0 ? 1.0 : doc.viewportHeight;
    return VectorDrawableWriter().build(
      doc,
      viewport: w,
      viewportHeight: h,
      fit: const AdaptiveFit(scale: 1, translateX: 0, translateY: 0),
      sizeDp: w,
      sizeDpHeight: h,
    );
  }

  /// Uses a ready-made AnimatedVectorDrawable XML **verbatim**, copying it to
  /// `@drawable/splash_icon` (+ dark). The file must be a self-contained
  /// `<animated-vector>` (inline base vector + animators via `aapt:attr`);
  /// external `@drawable`/`@anim` references must be added by the developer.
  /// Author it in any AVD tool (e.g. Shapeshifter → "Export → Animated Vector
  /// Drawable") — we don't transform it, so nothing is lost in conversion.
  bool _copyAvd(String source, String? darkSource, GenerationReport report) {
    final abs = loader.resolveAsset(source);
    final ext = p.extension(abs).toLowerCase();
    if (ext != '.xml') {
      logger.warn('splash animated_icon "$source": must be an AnimatedVector '
          'Drawable .xml. Export your animation to an AVD XML and point '
          'animated_icon at it.');
      report.skipped.add('splash animated_icon (not .xml)');
      return false;
    }
    if (!File(abs).existsSync()) {
      logger.warn('splash animated_icon not found: $abs');
      report.skipped.add('splash animated_icon (file not found)');
      return false;
    }
    final xml = File(abs).readAsStringSync();
    if (!xml.contains('animated-vector')) {
      logger.warn(
          'splash animated_icon "$source": not an <animated-vector> XML.');
      report.skipped.add('splash animated_icon (not an AVD)');
      return false;
    }
    writer.writeText(p.join(paths.drawableDir, '$_name.xml'), xml);
    report.written.add('drawable/$_name.xml (AnimatedVectorDrawable, as-is)');
    logger.step('animated icon (AVD XML, used as-is) → drawable/$_name.xml');

    if (darkSource != null) {
      final dAbs = loader.resolveAsset(darkSource);
      if (File(dAbs).existsSync()) {
        writer.writeText(p.join(paths.drawableNightDir, '$_name.xml'),
            File(dAbs).readAsStringSync());
        report.written.add('drawable-night/$_name.xml (AVD, as-is)');
      }
    }
    return true;
  }

  void _warnAnimatedKeyline() {
    logger.warn('Animated splash icons are masked to the 2/3 keyline circle '
        'too — design the animation inside the ⌀192dp (no icon background) or '
        '⌀160dp safe circle so it is not clipped. (Used as authored — not '
        'reshaped, to preserve the animation.)');
  }

  void _writeV31Styles(String dir,
      {required String launchParent,
      required _IconPlan icon,
      String? brandingRef,
      required bool night}) {
    final editor = AndroidStylesEditor(p.join(dir, 'styles.xml'));
    final launch = editor.ensureStyle('LaunchTheme', parent: launchParent);
    editor.upsertItem(launch, 'android:windowSplashScreenBackground',
        '@color/splash_background');
    if (icon.slotRef != null) {
      editor.upsertItem(launch, 'android:windowSplashScreenAnimatedIcon',
          '@drawable/${icon.slotRef}');
    }
    if (icon.animated) {
      editor.upsertItem(launch, 'android:windowSplashScreenAnimationDuration',
          '${splash.durationMs}');
    }
    if (splash.iconBackground != null) {
      editor.upsertItem(launch, 'android:windowSplashScreenIconBackgroundColor',
          '@color/splash_icon_background');
    }
    if (brandingRef != null) {
      editor.upsertItem(launch, 'android:windowSplashScreenBrandingImage',
          '@drawable/$brandingRef');
    }
    _applyFullscreen(editor, launch);
    _applySystemBars(editor, launch, night: night);
    // No `postSplashScreenTheme` — that attribute exists only in the androidx
    // core-splashscreen *compat* library, not the Android framework (it fails
    // to link). Flutter hands off to the normal theme via the
    // `io.flutter.embedding.android.NormalTheme` <meta-data> in the manifest.
    // Scrub it from styles written by an earlier version of this tool.
    editor.removeItem(launch, 'android:postSplashScreenTheme');
    editor.save();
  }

  void _writeLegacyStyles(String dir,
      {required String launchParent, required bool night}) {
    final editor = AndroidStylesEditor(p.join(dir, 'styles.xml'));
    final launch = editor.ensureStyle('LaunchTheme', parent: launchParent);
    editor.upsertItem(
        launch, 'android:windowBackground', '@drawable/launch_background');
    _applyFullscreen(editor, launch);
    _applySystemBars(editor, launch, night: night);
    final normal = editor.ensureStyle('NormalTheme', parent: launchParent);
    editor.upsertItem(
        normal, 'android:windowBackground', '?android:colorBackground');
    editor.save();
  }

  /// Sets (or scrubs) `windowFullscreen` on the launch theme per config, so the
  /// splash hides the status/navigation bars when requested.
  void _applyFullscreen(AndroidStylesEditor editor, XmlElement launch) {
    if (splash.fullscreen) {
      editor.upsertItem(launch, 'android:windowFullscreen', 'true');
      editor.upsertItem(
          launch, 'android:windowLayoutInDisplayCutoutMode', 'shortEdges');
    } else {
      editor.removeItem(launch, 'android:windowFullscreen');
      editor.removeItem(launch, 'android:windowLayoutInDisplayCutoutMode');
    }
  }

  // --------------------------------------------------------------- system bars

  /// Writes the opaque status/navigation bar colours to `colors.xml` (+ night).
  /// `transparent` bars need no colour resource (they use `@android:color/
  /// transparent`), so only real hex values are emitted.
  void _writeSystemBarColors() {
    void write(String? light, String? dark, String name) {
      if (light != null && !_isTransparent(light)) {
        writer.upsertColor(paths.valuesDir, name, light.toUpperCase());
      }
      final d = dark ?? light;
      if (d != null && !_isTransparent(d)) {
        writer.upsertColor(paths.valuesNightDir, name, d.toUpperCase());
      }
    }

    write(
        splash.statusBarColor, splash.statusBarColorDark, 'splash_status_bar');
    write(splash.navigationBarColor, splash.navigationBarColorDark,
        'splash_navigation_bar');
  }

  /// Applies status/navigation bar colour + icon-brightness items to a launch
  /// theme. A no-op when neither bar is configured, so it never disturbs the
  /// platform defaults. [night] selects the dark-mode colour/brightness.
  void _applySystemBars(AndroidStylesEditor editor, XmlElement launch,
      {required bool night}) {
    final statusColor = night
        ? (splash.statusBarColorDark ?? splash.statusBarColor)
        : splash.statusBarColor;
    final navColor = night
        ? (splash.navigationBarColorDark ?? splash.navigationBarColor)
        : splash.navigationBarColor;
    if (statusColor == null && navColor == null) return;

    // Required for statusBarColor / navigationBarColor to take effect.
    editor.upsertItem(
        launch, 'android:windowDrawsSystemBarBackgrounds', 'true');

    if (statusColor != null) {
      editor.upsertItem(launch, 'android:statusBarColor',
          _barColorRef(statusColor, 'splash_status_bar'));
      editor.upsertItem(launch, 'android:windowLightStatusBar',
          '${_lightBar(statusColor, night, splash.statusBarIconBrightness, splash.statusBarIconBrightnessDark)}');
    }
    if (navColor != null) {
      editor.upsertItem(launch, 'android:navigationBarColor',
          _barColorRef(navColor, 'splash_navigation_bar'));
      editor.upsertItem(launch, 'android:windowLightNavigationBar',
          '${_lightBar(navColor, night, splash.navigationBarIconBrightness, splash.navigationBarIconBrightnessDark)}');
    }
  }

  /// A drawable/colour reference for a bar: the framework transparent colour for
  /// `transparent`, otherwise the `@color/<name>` resource we emitted.
  String _barColorRef(String value, String name) =>
      _isTransparent(value) ? '@android:color/transparent' : '@color/$name';

  /// Resolves `windowLight*Bar` (true ⇒ dark icons, for a light bar). Honours an
  /// explicit brightness override; otherwise auto-derives from the bar colour
  /// (or, for a transparent bar, the splash background it reveals).
  bool _lightBar(String barColor, bool night, SystemBarIconBrightness? light,
      SystemBarIconBrightness? dark) {
    final override = night ? (dark ?? light) : light;
    if (override != null) return override == SystemBarIconBrightness.dark;
    final ref = _isTransparent(barColor)
        ? (night
            ? (splash.backgroundDark ?? splash.background)
            : splash.background)
        : barColor;
    return ref != null && _isLightColor(ref);
  }

  static bool _isTransparent(String v) =>
      v.trim().toLowerCase() == 'transparent';

  /// True when [hex] is a perceptually light colour (so the system bar should use
  /// dark icons). Falls back to false (light icons) if it can't be parsed.
  static bool _isLightColor(String hex) {
    try {
      final argb = SvgColor.parse(hex).argb;
      final r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
      return (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.5;
    } on Object {
      return false;
    }
  }

  /// Android gravity string for the branding item, per [BrandingMode].
  String get _brandingGravity => switch (splash.brandingMode) {
        BrandingMode.bottomLeft => 'bottom|left',
        BrandingMode.bottomRight => 'bottom|right',
        BrandingMode.bottom => 'bottom|center_horizontal',
      };

  /// Writes `launch_background.xml` to **every** drawable bucket the OS could
  /// resolve `@drawable/launch_background` from. A stock Flutter project ships
  /// `drawable-v21/launch_background.xml`, and on API 21+ (i.e. essentially every
  /// device) the `-v21` qualifier WINS over plain `drawable/` — so writing only
  /// `drawable/` leaves the stale white default in `-v21` shadowing our splash.
  /// We always write `drawable/` + `drawable-v21/`, and overwrite any `-night`
  /// variants the project shipped (night has higher qualifier precedence than
  /// version, so a stale `drawable-night/` would shadow us in dark mode).
  List<String> _writeLaunchBackgrounds(
      {String? iconRef, String? brandingRef, String? bgImageRef}) {
    final xml = _buildLaunchBackgroundXml(
        iconRef: iconRef, brandingRef: brandingRef, bgImageRef: bgImageRef);
    final written = <String>[];
    // Always written (covers pre-21 and API 21+ respectively).
    for (final dir in const ['drawable', 'drawable-v21']) {
      writer.writeText(p.join(paths.resDir, dir, 'launch_background.xml'), xml);
      written.add('$dir/launch_background.xml');
    }
    // Only overwrite night variants that already exist — don't create new ones
    // (the colour/icon refs resolve their own `-night` flavours at runtime).
    for (final dir in const ['drawable-night', 'drawable-night-v21']) {
      final f = File(p.join(paths.resDir, dir, 'launch_background.xml'));
      if (f.existsSync()) {
        writer.writeText(f.path, xml);
        written.add('$dir/launch_background.xml');
      }
    }
    return written;
  }

  String _buildLaunchBackgroundXml(
      {String? iconRef, String? brandingRef, String? bgImageRef}) {
    final b = XmlBuilder();
    b.processing('xml', 'version="1.0" encoding="utf-8"');
    b.comment(' Generated by flutter_adaptive_studio — do not edit. ');
    b.element('layer-list', namespaceUris: {'android': _ns}, nest: () {
      b.element('item', nest: () {
        b.attribute('drawable', '@color/splash_background', namespaceUri: _ns);
      });
      // Full-bleed background image over the colour (no gravity → fills bounds).
      if (bgImageRef != null) {
        b.element('item', nest: () {
          b.attribute('drawable', '@drawable/$bgImageRef', namespaceUri: _ns);
        });
      }
      if (iconRef != null) {
        b.element('item', nest: () {
          b.attribute('drawable', '@drawable/$iconRef', namespaceUri: _ns);
          b.attribute('gravity', splash.gravity, namespaceUri: _ns);
          b.attribute('width', '${_legacyBoxDp}dp', namespaceUri: _ns);
          b.attribute('height', '${_legacyBoxDp}dp', namespaceUri: _ns);
        });
      }
      if (brandingRef != null) {
        // Placement mirrors the native branding image (default bottom-centre).
        b.element('item', nest: () {
          b.attribute('drawable', '@drawable/$brandingRef', namespaceUri: _ns);
          b.attribute('gravity', _brandingGravity, namespaceUri: _ns);
          b.attribute('bottom', '${splash.brandingBottomPadding}dp',
              namespaceUri: _ns);
        });
      }
    });
    return b.buildDocument().toXmlString(pretty: true, indent: '    ');
  }
}

/// How a resolved centre icon should be wired into the splash themes.
class _IconPlan {
  const _IconPlan(
      {required this.slotRef, required this.layerRef, required this.animated});

  /// Drawable for the API 31+ `windowSplashScreenAnimatedIcon` slot (no `@`).
  final String? slotRef;

  /// Drawable for the pre-31 centred layer-list item (the resting frame).
  final String? layerRef;

  /// True when [slotRef] is a real AnimatedVectorDrawable (sets duration).
  final bool animated;
}

/// How resolved branding drawables should be wired into the splash. [slotRef]
/// (a crisp vector for an SVG source) feeds the API 31+ branding slot; [layerRef]
/// (always a raster) feeds the pre-31 windowBackground, where a vector can't
/// paint on API 21–23. They share a name unless the source is an SVG. Both null
/// means no branding.
class _BrandingPlan {
  const _BrandingPlan({required this.slotRef, required this.layerRef});

  /// Drawable base name for `windowSplashScreenBrandingImage` (no `@`), or null.
  final String? slotRef;

  /// Drawable base name for the pre-31 layer-list branding item, or null.
  final String? layerRef;
}

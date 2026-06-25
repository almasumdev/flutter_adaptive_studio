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
import '../../vector/vector_drawable_writer.dart';
import '../platform_generator.dart';
import 'android_manifest_editor.dart';
import 'android_paths.dart';
import 'android_styles_editor.dart';
import 'splash_templates.dart';

class AndroidSplash {
  AndroidSplash({
    required this.splash,
    required this.loader,
    required this.paths,
    required this.writer,
    required this.logger,
  });

  final AndroidSplashConfig splash;
  final ConfigLoader loader;
  final AndroidPaths paths;
  final ResWriter writer;
  final Logger logger;

  static const _ns = 'http://schemas.android.com/apk/res/android';
  static const _name = 'splash_icon';
  static const _branding = 'splash_branding';
  static const _bgImage = 'splash_bg';
  static const _rasterExts = {'.png', '.jpg', '.jpeg', '.webp', '.bmp', '.gif'};

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

    // ---- Full-bleed background image (pre-31 + fallback only) ----
    final bgImageRef = _resolveBackgroundImage(report);

    // ---- Centre icon (animated AVD, or a static logo) ----
    final icon = _resolveIcon(report);

    // ---- Bottom branding image ----
    final brandingRef = _resolveBranding(report);

    // ---- API 31+ SplashScreen theme ----
    _writeV31Styles(paths.valuesV31Dir,
        launchParent: '@android:style/Theme.Light.NoTitleBar',
        icon: icon,
        brandingRef: brandingRef);
    _writeV31Styles(paths.valuesNightV31Dir,
        launchParent: '@android:style/Theme.Black.NoTitleBar',
        icon: icon,
        brandingRef: brandingRef);
    if (splash.brandingMode != BrandingMode.bottom && brandingRef != null) {
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
        launchParent: '@android:style/Theme.Light.NoTitleBar');
    _writeLegacyStyles(paths.valuesNightDir,
        launchParent: '@android:style/Theme.Black.NoTitleBar');
    // One launch_background.xml suffices: @color/splash_background and the icon
    // /branding @drawable refs resolve to their `-night` variants automatically.
    _writeLaunchBackground(paths.drawableDir,
        iconRef: icon.layerRef,
        brandingRef: brandingRef,
        bgImageRef: bgImageRef);
    report.written
      ..add('values/styles.xml (LaunchTheme)')
      ..add('drawable/launch_background.xml');
    logger.step('pre-31 classic splash written');

    // ---- Flutter fallback drop-in (for Android < 12 / app-theme splash) ----
    _writeFallbackGlue(brandingRef, bgImageRef, report);

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

  /// Emits the `FasSplash` Flutter widget + SDK gate + guide so devices without
  /// the native SplashScreen API can show an app-themed splash that matches.
  void _writeFallbackGlue(
      String? brandingRef, String? bgImageRef, GenerationReport report) {
    final bgLight = SvgColor.parse(splash.background ?? '#FFFFFF').argb;
    final bgDark =
        SvgColor.parse(splash.backgroundDark ?? splash.background ?? '#000000')
            .argb;
    final dir = p.join(loader.projectRoot, 'flutter_adaptive_studio', 'splash');
    writer.writeText(
        p.join(dir, 'fas_splash.dart'),
        splashFallbackDart(
          bgLightArgb: bgLight,
          bgDarkArgb: bgDark,
          // The splash `image:` (NOT the app icon) is the Flutter logo source.
          logoAsset: splash.image,
          brandingAsset: brandingRef == null ? null : splash.branding,
          // Themed bottom branding, mirroring the native `-night` drawable.
          brandingDarkAsset: brandingRef == null ? null : splash.brandingDark,
          brandingAlignment: _brandingAlignment,
          brandingBottomDp: splash.brandingBottomPadding,
          backgroundImageAsset:
              bgImageRef == null ? null : splash.backgroundImage,
          backgroundImageDarkAsset:
              bgImageRef == null ? null : splash.backgroundImageDark,
        ));
    writer.writeText(p.join(dir, 'SPLASH.md'), splashGuide);
    report.written.add('flutter_adaptive_studio/splash/ (FasSplash + guide)');
    logger.step('Flutter fallback splash → flutter_adaptive_studio/splash/');
  }

  // --------------------------------------------------------------- centre icon

  /// Resolves the centre icon into drawables and returns how to wire it: an
  /// `animated_icon` (a ready-made AnimatedVectorDrawable `.xml`, used verbatim)
  /// takes priority; otherwise a static `image`. Animated icons are used **as
  /// authored** — never keyline-reshaped, since that would break the animation.
  _IconPlan _resolveIcon(GenerationReport report) {
    if (splash.animatedIcon != null) {
      if (_copyAvd(splash.animatedIcon!, splash.animatedIconDark, report)) {
        _warnAnimatedKeyline();
        // The AVD has no separate resting frame → reuse it for the pre-31 layer.
        return const _IconPlan(slotRef: _name, layerRef: _name, animated: true);
      }
      // Fall through to static if the AVD couldn't be used.
    }
    final image = splash.image;
    if (image != null) {
      if (_emitDrawable(image, _name, report,
          role: 'splash image', square: true)) {
        // Dark variant → drawable-night/splash_icon, picked up automatically by
        // the night API-31 theme and the pre-31 launch_background on dark mode.
        if (splash.imageDark != null) {
          _emitDrawable(splash.imageDark!, _name, report,
              role: 'splash image (dark)', square: true, night: true);
        }
        return const _IconPlan(
            slotRef: _name, layerRef: _name, animated: false);
      }
    } else if (splash.animatedIcon == null) {
      logger.skip(
          'splash icon: no image or animated_icon (background-only splash)');
      report.skipped.add('splash icon (none)');
    }
    return const _IconPlan(slotRef: null, layerRef: null, animated: false);
  }

  // ----------------------------------------------------------------- branding

  /// Emits the full-bleed background image (+ dark) and returns its base name,
  /// or null when none is configured/usable. Stretched to fill the window on the
  /// pre-31 splash; the API 31+ splash takes a colour only (see generate()).
  String? _resolveBackgroundImage(GenerationReport report) {
    final src = splash.backgroundImage;
    if (src == null) return null;
    if (!_emitDrawable(src, _bgImage, report,
        role: 'splash background image', square: false, fill: true)) {
      return null;
    }
    if (splash.backgroundImageDark != null) {
      _emitDrawable(splash.backgroundImageDark!, _bgImage, report,
          role: 'splash background image (dark)',
          square: false,
          fill: true,
          night: true);
    }
    logger.step('background image → drawable/$_bgImage');
    return _bgImage;
  }

  /// Emits the bottom branding drawable (+ dark) and returns its base name, or
  /// null when no branding source is configured/usable.
  String? _resolveBranding(GenerationReport report) {
    final src = splash.branding;
    if (src == null) return null;
    if (!_emitDrawable(src, _branding, report,
        role: 'splash branding', square: false)) {
      return null;
    }
    if (splash.brandingDark != null) {
      _emitDrawable(splash.brandingDark!, _branding, report,
          role: 'splash branding (dark)', square: false, night: true);
    }
    logger.step('branding → drawable/$_branding');
    return _branding;
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
      String? brandingRef}) {
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
    // No `postSplashScreenTheme` — that attribute exists only in the androidx
    // core-splashscreen *compat* library, not the Android framework (it fails
    // to link). Flutter hands off to the normal theme via the
    // `io.flutter.embedding.android.NormalTheme` <meta-data> in the manifest.
    // Scrub it from styles written by an earlier version of this tool.
    editor.removeItem(launch, 'android:postSplashScreenTheme');
    editor.save();
  }

  void _writeLegacyStyles(String dir, {required String launchParent}) {
    final editor = AndroidStylesEditor(p.join(dir, 'styles.xml'));
    final launch = editor.ensureStyle('LaunchTheme', parent: launchParent);
    editor.upsertItem(
        launch, 'android:windowBackground', '@drawable/launch_background');
    _applyFullscreen(editor, launch);
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

  /// Android gravity string for the branding item, per [BrandingMode].
  String get _brandingGravity => switch (splash.brandingMode) {
        BrandingMode.bottomLeft => 'bottom|left',
        BrandingMode.bottomRight => 'bottom|right',
        BrandingMode.bottom => 'bottom|center_horizontal',
      };

  /// Flutter `Alignment` for the fallback branding, per [BrandingMode].
  String get _brandingAlignment => switch (splash.brandingMode) {
        BrandingMode.bottomLeft => 'Alignment.bottomLeft',
        BrandingMode.bottomRight => 'Alignment.bottomRight',
        BrandingMode.bottom => 'Alignment.bottomCenter',
      };

  void _writeLaunchBackground(String dir,
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
          b.attribute('width', '192dp', namespaceUri: _ns);
          b.attribute('height', '192dp', namespaceUri: _ns);
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
    writer.writeText(p.join(dir, 'launch_background.xml'),
        b.buildDocument().toXmlString(pretty: true, indent: '    '));
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

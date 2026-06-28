/// Writes `lib/fas_splash.g.dart` — the platform-agnostic config the runtime
/// `AdaptiveSplash` consumes.
///
/// This is intentionally NOT tied to the Android generator: the in-app splash
/// runs on Android **and** iOS, so it's generated whenever *either* platform has
/// a splash (an iOS-only project gets it too). The base values match the Android
/// splash (falling back to iOS when there's no Android block); the iOS overrides
/// (`iosBackground*` / `iosLogo*`) match the iOS `LaunchScreen`, so the widget
/// looks right on each platform. The logo/branding are rasterised to PNG and
/// base64-embedded, so the app needs no assets, no `flutter_svg`, and no
/// `device_info_plus`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../config/config_loader.dart';
import '../graphic/svg_color.dart';
import '../graphic/svg_document.dart';
import '../logger.dart';
import '../raster/image_rasterizer.dart';
import '../raster/svg_rasterizer.dart';
import 'android/splash_templates.dart';
import 'platform_generator.dart';

class SplashConfigWriter {
  SplashConfigWriter({
    required this.config,
    required this.loader,
    required this.logger,
  });

  final AdaptiveStudioConfig config;
  final ConfigLoader loader;
  final Logger logger;

  /// Centre-logo raster size (4× the 192dp logical box → crisp on high-DPI).
  static const _logoPx = 768;
  static const _logoSizeDp = 192;

  /// App-logo fallback when a splash has no `image:` of its own (the app icon
  /// foreground, else the root `source`) — matching the native splash fallback.
  String? get _fallbackLogo =>
      config.android?.icon?.adaptive?.foreground ?? config.source;

  /// Generates `lib/fas_splash.g.dart` when any splash is configured.
  void write(GenerationReport report) {
    final aSplash = config.android?.splash;
    final iSplash = config.ios?.splash;
    if (aSplash == null && iSplash == null) return;

    // ---- Base (Android-primary; falls back to iOS for an iOS-only project) ----
    final bgLightSrc = aSplash?.background ?? iSplash?.background ?? '#FFFFFF';
    final bgDarkSrc = aSplash?.backgroundDark ??
        iSplash?.backgroundDark ??
        aSplash?.background ??
        iSplash?.background ??
        '#000000';
    final logoSrc = aSplash?.image ??
        (aSplash == null ? iSplash?.image : null) ??
        _fallbackLogo;
    final logoDarkSrc =
        aSplash?.imageDark ?? (aSplash == null ? iSplash?.imageDark : null);

    // Branding (Android only — the iOS launch screen has none).
    String? brandingLightB64, brandingDarkB64, brandingText;
    if (aSplash?.branding != null) {
      brandingLightB64 = _b64(_brandingPng(aSplash!.branding!));
      brandingDarkB64 = aSplash.brandingDark != null
          ? _b64(_brandingPng(aSplash.brandingDark!))
          : null;
    } else if (aSplash?.brandingText != null) {
      brandingText = aSplash!.brandingText;
    }

    // Full-bleed background image (Android only).
    final bgImgLightB64 = aSplash?.backgroundImage != null
        ? _b64(_bgImagePng(aSplash!.backgroundImage!))
        : null;
    final bgImgDarkB64 = aSplash?.backgroundImageDark != null
        ? _b64(_bgImagePng(aSplash!.backgroundImageDark!))
        : null;

    // ---- iOS overrides — only when they differ from the base, mirroring the
    // iOS LaunchScreen resolution in ios_splash.dart. ----
    int? iosBgLight, iosBgDark, iosLogoSize;
    String? iosLogoB64, iosLogoDarkB64;
    if (iSplash != null && aSplash != null) {
      final iBg = iSplash.background ?? aSplash.background ?? '#FFFFFF';
      final iBgDark = iSplash.backgroundDark ?? aSplash.backgroundDark;
      if (iBg.toUpperCase() != bgLightSrc.toUpperCase()) {
        iosBgLight = SvgColor.parse(iBg).argb;
      }
      if (iBgDark != null && iBgDark.toUpperCase() != bgDarkSrc.toUpperCase()) {
        iosBgDark = SvgColor.parse(iBgDark).argb;
      }
      final iLogo = iSplash.image ?? aSplash.image ?? _fallbackLogo;
      if (iLogo != null && iLogo != logoSrc) {
        iosLogoB64 = _b64(_logoPng(iLogo));
      }
      final iLogoDark = iSplash.imageDark ?? aSplash.imageDark;
      if (iLogoDark != null && iLogoDark != logoDarkSrc) {
        iosLogoDarkB64 = _b64(_logoPng(iLogoDark));
      }
      if (iSplash.logoSizePt != _logoSizeDp) iosLogoSize = iSplash.logoSizePt;
    }

    final out = splashConfigDart(
      bgLightArgb: SvgColor.parse(bgLightSrc).argb,
      bgDarkArgb: SvgColor.parse(bgDarkSrc).argb,
      logoB64: logoSrc == null ? null : _b64(_logoPng(logoSrc)),
      logoDarkB64: logoDarkSrc == null ? null : _b64(_logoPng(logoDarkSrc)),
      brandingLightB64: brandingLightB64,
      brandingDarkB64: brandingDarkB64,
      brandingText: brandingText,
      brandingTextColorLight: SvgColor.parse(
              aSplash?.brandingTextColor ?? _defaultTextColor(bgLightSrc))
          .argb,
      brandingTextColorDark: SvgColor.parse(aSplash?.brandingTextColorDark ??
              aSplash?.brandingTextColor ??
              _defaultTextColor(bgDarkSrc))
          .argb,
      brandingAlignment:
          _alignment(aSplash?.brandingMode ?? BrandingMode.bottom),
      brandingBottomDp: aSplash?.brandingBottomPadding ?? 48,
      bgImageLightB64: bgImgLightB64,
      bgImageDarkB64: bgImgDarkB64,
      logoSizeDp: _logoSizeDp,
      iosBgLightArgb: iosBgLight,
      iosBgDarkArgb: iosBgDark,
      iosLogoB64: iosLogoB64,
      iosLogoDarkB64: iosLogoDarkB64,
      iosLogoSizeDp: iosLogoSize,
      durationMs: aSplash?.durationMs ?? 800,
      showOnAllVersions: aSplash?.flutterSplashAllVersions ?? false,
    );

    final libDir = Directory(p.join(loader.projectRoot, 'lib'));
    final outPath = p.join(
        libDir.existsSync() ? libDir.path : loader.projectRoot,
        'fas_splash.g.dart');
    File(outPath)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(out);
    final rel = p.relative(outPath, from: loader.projectRoot);
    report.written.add(rel);
    logger
      ..step('in-app Flutter splash config → $rel')
      ..detail('wrap your app: '
          'runApp(AdaptiveSplash(config: fasSplash, child: const MyApp()));');
  }

  static String? _b64(Uint8List? bytes) =>
      bytes == null ? null : base64Encode(bytes);

  static String _alignment(BrandingMode mode) => switch (mode) {
        BrandingMode.bottomLeft => 'Alignment.bottomLeft',
        BrandingMode.bottomRight => 'Alignment.bottomRight',
        BrandingMode.bottom => 'Alignment.bottomCenter',
      };

  /// Dark text on a light background, light text on a dark one.
  static String _defaultTextColor(String bg) =>
      _isLight(bg) ? '#000000' : '#FFFFFF';

  static bool _isLight(String hex) {
    try {
      final argb = SvgColor.parse(hex).argb;
      final r = (argb >> 16) & 0xFF, g = (argb >> 8) & 0xFF, b = argb & 0xFF;
      return (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.5;
    } on Object {
      return false;
    }
  }

  // --------------------------------------------------------------- rasterising

  /// PNG bytes of the centre logo at [_logoPx]² (transparent), or null.
  Uint8List? _logoPng(String source) {
    final abs = loader.resolveAsset(source);
    if (!File(abs).existsSync()) return null;
    final ext = p.extension(abs).toLowerCase();
    const px = _logoPx;
    if (ext == '.svg') {
      final doc = _parse(abs);
      if (doc == null) return null;
      // Fit the art into ~85% of the box, centred — a comfortable splash logo.
      return img.encodePng(
          const SvgRasterizer().rasterize(doc, px, fitFraction: 0.85));
    }
    if (_isRaster(ext)) {
      final src = img.decodeImage(File(abs).readAsBytesSync());
      if (src == null) return null;
      final canvas = img.Image(width: px, height: px, numChannels: 4);
      final box = px * 0.7;
      final s = math.min(box / src.width, box / src.height);
      final w = (src.width * s).round().clamp(1, px);
      final h = (src.height * s).round().clamp(1, px);
      final scaled = ImageRasterizer.resizeSmart(src, w, h);
      img.compositeImage(canvas, scaled,
          dstX: ((px - w) / 2).round(), dstY: ((px - h) / 2).round());
      return img.encodePng(canvas);
    }
    return null;
  }

  /// Tight wordmark PNG bytes for an image branding (aspect-preserved), or null.
  Uint8List? _brandingPng(String source) {
    final abs = loader.resolveAsset(source);
    if (!File(abs).existsSync()) return null;
    final ext = p.extension(abs).toLowerCase();
    if (ext == '.svg') {
      final doc = _parse(abs);
      if (doc == null) return null;
      return img.encodePng(
          _trim(const SvgRasterizer().rasterize(doc, 512, fitFraction: 0.98)));
    }
    if (_isRaster(ext)) {
      final src = img.decodeImage(File(abs).readAsBytesSync());
      if (src == null) return null;
      return img.encodePng(_trim(_downscale(src, 1024)));
    }
    return null;
  }

  /// Full-bleed background PNG bytes (source aspect, ≤1080px long side), or null.
  Uint8List? _bgImagePng(String source) {
    final abs = loader.resolveAsset(source);
    if (!File(abs).existsSync()) return null;
    final ext = p.extension(abs).toLowerCase();
    if (ext == '.svg') {
      final doc = _parse(abs);
      if (doc == null) return null;
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
      return img.encodePng(image);
    }
    if (_isRaster(ext)) {
      final src = img.decodeImage(File(abs).readAsBytesSync());
      if (src == null) return null;
      return img.encodePng(_downscale(src, 1080));
    }
    return null;
  }

  SvgDocument? _parse(String abs) {
    try {
      return SvgDocument.parse(File(abs).readAsStringSync());
    } on Exception catch (e) {
      logger.warn('splash config: could not parse $abs: $e');
      return null;
    }
  }

  static bool _isRaster(String ext) =>
      const {'.png', '.jpg', '.jpeg', '.webp', '.bmp', '.gif'}.contains(ext);

  static img.Image _trim(img.Image src) {
    final t = img.findTrim(src, mode: img.TrimMode.transparent);
    if (t[2] <= 0 || t[3] <= 0) return src;
    return img.copyCrop(src, x: t[0], y: t[1], width: t[2], height: t[3]);
  }

  static img.Image _downscale(img.Image src, int maxLongest) {
    final longest = math.max(src.width, src.height);
    if (longest <= maxLongest) return src;
    return img.copyResize(src,
        width: (src.width * maxLongest / longest).round(),
        height: (src.height * maxLongest / longest).round(),
        interpolation: img.Interpolation.average);
  }
}

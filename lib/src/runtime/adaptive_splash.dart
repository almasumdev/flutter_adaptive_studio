/// In-app Flutter splash that mirrors the native one and removes itself.
///
/// You wrap your app once — `runApp(AdaptiveSplash(config: fasSplash, child:
/// MyApp()))` — and the package does the rest: it paints a splash that matches
/// the native one (background, centred logo, branding), holds it briefly while
/// your first screen settles, then fades to your app. Everything (colours, the
/// rasterised logo bytes, branding, timing) comes from the generated
/// [FasSplashConfig] in `fas_splash.g.dart`, so there's nothing to wire up and
/// no extra dependency to add.
///
/// By default it shows only **where there's no native animated splash** — i.e.
/// Android API < 31 (on API 31+ the system `SplashScreen` already covers
/// startup). Set [FasSplashConfig.showOnAllVersions] (or pass [force]) to show
/// it on every version.
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/widgets.dart';

import 'android_sdk.dart';

/// Generated splash configuration. Emitted by the CLI into `fas_splash.g.dart` —
/// you never write this by hand. All colours are 0xAARRGGBB ints; all artwork is
/// pre-rasterised PNG bytes baked into the generated file.
@immutable
class FasSplashConfig {
  /// Creates a splash configuration. The CLI emits this into `fas_splash.g.dart`
  /// — you never construct it by hand.
  const FasSplashConfig({
    required this.backgroundLight,
    required this.backgroundDark,
    this.logo,
    this.logoDark,
    this.brandingLight,
    this.brandingDark,
    this.brandingText,
    this.brandingTextColorLight = 0xFF000000,
    this.brandingTextColorDark = 0xFFFFFFFF,
    this.brandingAlignment = Alignment.bottomCenter,
    this.brandingBottomPadding = 48,
    this.backgroundImageLight,
    this.backgroundImageDark,
    this.logoSize = 192,
    this.iosBackgroundLight,
    this.iosBackgroundDark,
    this.iosLogo,
    this.iosLogoDark,
    this.iosLogoSize,
    this.duration = const Duration(milliseconds: 800),
    this.fadeDuration = const Duration(milliseconds: 350),
    this.showOnAllVersions = false,
  });

  /// Splash background colour (0xAARRGGBB) for light appearance.
  final int backgroundLight;

  /// Splash background colour (0xAARRGGBB) for dark (system) appearance.
  final int backgroundDark;

  /// Centre logo PNG bytes (already rasterised), or null for a colour-only splash.
  final Uint8List? logo;

  /// Optional dark-appearance variant of [logo].
  final Uint8List? logoDark;

  /// Bottom branding image PNG bytes (light). Null when branding is text
  /// (see [brandingText]) or absent.
  final Uint8List? brandingLight;

  /// Dark-appearance variant of [brandingLight].
  final Uint8List? brandingDark;

  /// Text wordmark, used when no branding image is configured.
  final String? brandingText;

  /// Colour (0xAARRGGBB) of [brandingText] in light appearance.
  final int brandingTextColorLight;

  /// Colour (0xAARRGGBB) of [brandingText] in dark appearance.
  final int brandingTextColorDark;

  /// Branding placement within the splash.
  final Alignment brandingAlignment;

  /// Branding distance from the bottom edge (logical px).
  final double brandingBottomPadding;

  /// Full-bleed background image PNG bytes (light), drawn behind the logo.
  final Uint8List? backgroundImageLight;

  /// Dark-appearance variant of [backgroundImageLight].
  final Uint8List? backgroundImageDark;

  /// Centre-logo edge length (logical px).
  final double logoSize;

  /// **iOS overrides.** On iOS the splash matches the iOS `LaunchScreen` instead
  /// of the Android one: these supply the iOS-specific background/logo/size when
  /// they differ. Each is null when there's nothing iOS-specific to apply (the
  /// widget then falls back to the Android values above). Branding is never drawn
  /// on iOS — the iOS launch screen has none. This is the light-appearance
  /// background override.
  final int? iosBackgroundLight;

  /// iOS dark-appearance background override (0xAARRGGBB), or null to reuse the
  /// Android value.
  final int? iosBackgroundDark;

  /// iOS centre-logo PNG bytes override, or null to reuse [logo].
  final Uint8List? iosLogo;

  /// iOS dark-appearance logo override, or null.
  final Uint8List? iosLogoDark;

  /// iOS centre-logo edge length (logical px) override, or null to reuse [logoSize].
  final double? iosLogoSize;

  /// How long the splash is held before it begins to fade out.
  final Duration duration;

  /// How long the fade-out animation runs.
  final Duration fadeDuration;

  /// When true the splash shows on every OS version; when false (default) only
  /// where there's no native animated splash (Android API < 31).
  final bool showOnAllVersions;
}

/// Wraps your app and shows the matching Flutter splash over it until startup
/// settles, then fades out. See [FasSplashConfig].
class AdaptiveSplash extends StatefulWidget {
  const AdaptiveSplash({
    super.key,
    required this.config,
    required this.child,
    this.ready,
    this.force,
  });

  /// The generated configuration (`fasSplash` from `fas_splash.g.dart`).
  final FasSplashConfig config;

  /// Your app — typically the `MaterialApp`. It builds underneath the splash.
  final Widget child;

  /// Optional readiness signal: when given, the splash is held until BOTH this
  /// future completes AND [FasSplashConfig.duration] has elapsed. Use it to keep
  /// the splash up until your async startup is done.
  final Future<void>? ready;

  /// Overrides [FasSplashConfig.showOnAllVersions] when set: `true` forces the
  /// splash on every version, `false` restricts it to API < 31.
  final bool? force;

  @override
  State<AdaptiveSplash> createState() => _AdaptiveSplashState();
}

class _AdaptiveSplashState extends State<AdaptiveSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: widget.config.fadeDuration,
    value: 1,
  );
  bool _show = true;

  @override
  void initState() {
    super.initState();
    _drive();
  }

  Future<void> _drive() async {
    final showOnAll = widget.force ?? widget.config.showOnAllVersions;
    // Hold the splash only where there's no native animated splash to follow:
    // forced, non-Android, or Android API < 31. On API 31+ the system splash
    // already covered startup, so we fade out immediately (the matched image
    // makes that frame seamless).
    final hold = showOnAll || _noNativeAnimatedSplash();
    if (hold) {
      await Future.wait<void>([
        Future<void>.delayed(widget.config.duration),
        if (widget.ready != null) widget.ready!.catchError((_) {}),
      ]);
    }
    if (!mounted) return;
    await _fade.reverse();
    if (mounted) setState(() => _show = false);
  }

  /// True when the platform has no Android-12 `SplashScreen` to hand off from —
  /// any non-Android target, or Android below API 31.
  static bool _noNativeAnimatedSplash() {
    final sdk = androidSdkInt();
    return sdk == null || sdk < 31;
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_show)
            FadeTransition(
              opacity: _fade,
              child: IgnorePointer(child: _SplashView(config: widget.config)),
            ),
        ],
      ),
    );
  }
}

/// The splash visual: background (colour + optional image), centred logo, and
/// bottom branding (image or text). Theme-aware via the **system** brightness,
/// matching the native `-night` resources.
class _SplashView extends StatelessWidget {
  const _SplashView({required this.config});

  final FasSplashConfig config;

  @override
  Widget build(BuildContext context) {
    final dark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    // On iOS the splash matches the iOS LaunchScreen (its own background/logo,
    // no branding); elsewhere it matches the Android splash.
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;

    final bgLight =
        (isIos ? config.iosBackgroundLight : null) ?? config.backgroundLight;
    final bgDark = (isIos
            ? (config.iosBackgroundDark ?? config.iosBackgroundLight)
            : null) ??
        config.backgroundDark;
    final bgColor = Color(dark ? bgDark : bgLight);

    final logoLight = (isIos ? config.iosLogo : null) ?? config.logo;
    final logoDark = (isIos ? (config.iosLogoDark ?? config.iosLogo) : null) ??
        config.logoDark ??
        config.logo;
    final logo = dark ? logoDark : logoLight;
    final logoSize = (isIos ? config.iosLogoSize : null) ?? config.logoSize;

    final bgImage = isIos
        ? null
        : (dark
            ? (config.backgroundImageDark ?? config.backgroundImageLight)
            : config.backgroundImageLight);
    final branding = isIos
        ? null
        : (dark
            ? (config.brandingDark ?? config.brandingLight)
            : config.brandingLight);
    final showText = !isIos && branding == null && config.brandingText != null;

    return ColoredBox(
      color: bgColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (bgImage != null)
            Positioned.fill(
              child: Image.memory(bgImage,
                  fit: BoxFit.cover, gaplessPlayback: true),
            ),
          if (logo != null)
            Center(
              child: Image.memory(logo,
                  width: logoSize, height: logoSize, gaplessPlayback: true),
            ),
          if (branding != null || showText)
            Align(
              alignment: config.brandingAlignment,
              child: Padding(
                padding: EdgeInsets.only(bottom: config.brandingBottomPadding),
                child: branding != null
                    ? Image.memory(branding, height: 40, gaplessPlayback: true)
                    : Text(
                        config.brandingText!,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(dark
                              ? config.brandingTextColorDark
                              : config.brandingTextColorLight),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

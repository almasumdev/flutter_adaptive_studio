/// Typed configuration model for flutter_adaptive_studio.
///
/// Design principle (locked with the user): **everything is optional with
/// sensible defaults.** No `android:` block → Android is skipped. A missing
/// optional asset is skipped with a log line, never a hard failure. The only
/// practical floor is that you must supply *a* source for whatever you want
/// generated.
library;

import 'package:meta/meta.dart';

/// Root configuration.
@immutable
class AdaptiveStudioConfig {
  const AdaptiveStudioConfig({this.source, this.android, this.ios});

  /// Global fallback source graphic, used when a more specific source is not
  /// given (e.g. `android.icon.adaptive.foreground`).
  final String? source;

  /// Android platform config. `null` means "don't touch Android".
  final AndroidConfig? android;

  /// iOS platform config. `null` means "don't touch iOS".
  final IosConfig? ios;

  bool get hasAndroid => android != null;
  bool get hasIos => ios != null;
}

/// iOS-specific configuration.
@immutable
class IosConfig {
  const IosConfig({this.icon, this.splash});

  final IosIconConfig? icon;
  final IosSplashConfig? splash;
}

/// iOS launch-screen configuration. iOS has no SplashScreen API — this drives a
/// `LaunchScreen.storyboard` via a centred-logo imageset + a background colour
/// set (both light/dark). Unset values fall back to the Android splash / root
/// source, so one config can cover both platforms.
@immutable
class IosSplashConfig {
  const IosSplashConfig({
    this.background,
    this.backgroundDark,
    this.image,
    this.imageDark,
    this.logoSizePt = 192,
  });

  final String? background;
  final String? backgroundDark;

  /// Centred logo (SVG or raster), shown transparent over the background.
  final String? image;
  final String? imageDark;

  /// Logo edge length in points on the launch screen.
  final int logoSizePt;
}

/// iOS app-icon configuration. iOS icons are a single square drawn as-is (the
/// system rounds the corners) and **must be opaque** — so a [background] is
/// composited under any transparency. One [image] (SVG or raster) drives every
/// size; [dark] and [tinted] add the iOS 18 appearance variants.
@immutable
class IosIconConfig {
  const IosIconConfig({
    this.image,
    this.background = '#FFFFFF',
    this.dark,
    this.backgroundDark = '#000000',
    this.tinted,
    this.padding = 0,
  });

  /// Icon source (SVG or raster). Falls back to the root `source` / the Android
  /// foreground, so a single logo can drive both platforms.
  final String? image;

  /// Opaque fill composited under the icon (iOS rejects transparent icons).
  final String background;

  /// iOS 18 dark-appearance source (optional).
  final String? dark;

  /// Opaque fill for the dark variant.
  final String backgroundDark;

  /// iOS 18 tinted-appearance source — a grayscale mark the system tints
  /// (optional; flattened on black).
  final String? tinted;

  /// Percent the art is inset from the icon edge (0 = use the source framing).
  final int padding;
}

/// Android-specific configuration.
@immutable
class AndroidConfig {
  const AndroidConfig({this.icon, this.splash, this.minSdk});

  final AndroidIconConfig? icon;

  /// Splash config — modelled now, generated in Phase 2.
  final AndroidSplashConfig? splash;

  /// Minimum Android SDK. Gates whether legacy (pre-26) mipmaps are emitted.
  final int? minSdk;
}

/// Android launcher-icon configuration.
@immutable
class AndroidIconConfig {
  const AndroidIconConfig({
    this.adaptive,
    this.legacy,
    this.round = false,
    this.playStore = false,
    this.themed,
    this.image,
    this.iconName = 'ic_launcher',
    this.effect = LegacyEffect.none,
  });

  final AdaptiveConfig? adaptive;

  /// Post-processing for the raster (legacy mipmap + store) icon, mirroring the
  /// Android Asset Studio / IconKitchen "effect" toggle. `none` is flat (modern
  /// default); `elevate` adds the classic Material drop shadow + sheen.
  final LegacyEffect effect;

  /// Explicit full-icon source for legacy mipmaps + the Play Store PNG. If
  /// absent, those are composed from the adaptive foreground + background.
  final String? image;

  /// Emit pre-API-26 mipmap PNGs. `null` ⇒ decide from `minSdk` (Phase 3).
  final bool? legacy;

  /// Emit `ic_launcher_round` and wire `android:roundIcon`.
  final bool round;

  /// Emit the 512² Play Store marketing PNG (Phase 3).
  final bool playStore;

  /// Full-colour light/dark icon via activity-alias (Phase 4).
  final ThemedIconConfig? themed;

  /// Resource base name. Defaults to Flutter's `ic_launcher`.
  final String iconName;
}

/// Adaptive icon layers (API 26+). All layers optional.
@immutable
class AdaptiveConfig {
  const AdaptiveConfig({
    this.foreground,
    this.background,
    this.monochrome,
    this.safeZone = const SafeZone.fit(),
  });

  /// Foreground source (SVG/vector or — later — raster).
  final String? foreground;

  /// Either a hex colour (`#RRGGBB`) or a path to an SVG/image.
  final String? background;

  /// Monochrome silhouette for Android 13 themed icons.
  final String? monochrome;

  final SafeZone safeZone;

  bool get backgroundIsColor =>
      background != null && background!.trimLeft().startsWith('#');
}

/// How foreground/monochrome art is fit into the 108dp adaptive canvas.
@immutable
class SafeZone {
  /// Measure the art's bounding box and scale it to fit the centred safe
  /// square (our quality win over a blind inset), leaving [defaultPadding]% of
  /// breathing room so the logo isn't flush to the masked edge.
  const SafeZone.fit()
      : mode = SafeZoneMode.fit,
        insetPercent = defaultPadding;

  /// Same measured-bbox fit, but with a caller-chosen padding percentage
  /// instead of the [defaultPadding] default.
  const SafeZone.inset(this.insetPercent) : mode = SafeZoneMode.inset;

  /// Default foreground padding (percent of the safe zone) when the user
  /// doesn't specify one. ~15% keeps the logo comfortably inside the mask.
  static const double defaultPadding = 15;

  /// Fill the whole canvas (no safe-zone handling).
  const SafeZone.none()
      : mode = SafeZoneMode.none,
        insetPercent = 0;

  final SafeZoneMode mode;
  final double insetPercent;
}

enum SafeZoneMode { fit, inset, none }

/// Raster-icon post-processing, mirroring Android Asset Studio / IconKitchen.
/// `none` → flat; `elevate` → soft drop shadow + top-left radial sheen (the
/// classic Material launcher look).
enum LegacyEffect { none, elevate }

/// Themed full-colour light/dark icon (Phase 4, opt-in).
@immutable
class ThemedIconConfig {
  const ThemedIconConfig({
    this.light,
    this.dark,
    this.background,
    this.backgroundDark,
  });

  final String? light;
  final String? dark;

  /// Background colour for the themed icons, overriding the adaptive icon's
  /// [AdaptiveConfig.background]. Null ⇒ inherit the adaptive background.
  final String? background;

  /// Background colour for the *dark* themed variant. Null ⇒ falls back to
  /// [background], then the adaptive background.
  final String? backgroundDark;
}

/// Where the bottom branding image sits in the splash.
enum BrandingMode { bottom, bottomLeft, bottomRight }

/// Android splash configuration.
@immutable
class AndroidSplashConfig {
  const AndroidSplashConfig({
    this.background,
    this.backgroundDark,
    this.backgroundImage,
    this.backgroundImageDark,
    this.image,
    this.imageDark,
    this.animatedIcon,
    this.animatedIconDark,
    this.durationMs = 1000,
    this.iconBackground,
    this.iconBackgroundDark,
    this.branding,
    this.brandingDark,
    this.brandingMode = BrandingMode.bottom,
    this.brandingBottomPadding = 48,
    this.gravity = 'center',
    this.fullscreen = false,
    this.screenOrientation,
  });

  final String? background;
  final String? backgroundDark;

  /// Full-bleed background image (SVG or raster) drawn behind the logo. Works on
  /// the pre-31 splash + Flutter fallback; the Android 12+ system splash takes a
  /// solid colour only, so it uses [background] there.
  final String? backgroundImage;
  final String? backgroundImageDark;

  /// Static centre logo (SVG or raster). Used when no [animatedIcon] is given —
  /// the common "logo in the middle" splash. Wired to the API 31+
  /// `windowSplashScreenAnimatedIcon` slot (which also accepts a still drawable)
  /// and the centred layer of the pre-31 splash.
  final String? image;

  /// Dark-mode variant of [image], emitted to `-night` so it shows in system
  /// dark mode (API 31+ and pre-31 alike).
  final String? imageDark;

  final String? animatedIcon;
  final String? animatedIconDark;
  final int durationMs;
  final String? iconBackground;

  /// Dark-mode variant of [iconBackground] (the API 31+ icon circle colour).
  final String? iconBackgroundDark;

  /// Bottom branding image (SVG or raster), as the native splash shows beneath
  /// the icon. Light variant; [brandingDark] supplies the `-night` version.
  final String? branding;
  final String? brandingDark;

  /// Branding placement on the pre-31 splash + Flutter fallback (the API 31+
  /// system splash always bottom-centres it).
  final BrandingMode brandingMode;

  /// Branding distance from the bottom edge, in dp.
  final int brandingBottomPadding;

  /// Android gravity for the centre image on the pre-31 splash (e.g. `center`,
  /// `fill`, `bottom`). The API 31+ system splash always centres it.
  final String gravity;

  /// Hide the status/navigation bars during the splash.
  final bool fullscreen;

  /// Lock the launch activity's orientation during the splash (e.g. `portrait`,
  /// `landscape`, `sensorPortrait`). Written to the **main** manifest, so it is
  /// app-wide and not undone by `revert`.
  final String? screenOrientation;

  /// True when there is any centre logo to render (animated or static).
  bool get hasIcon => animatedIcon != null || image != null;
}

/// Typed configuration model for flutter_adaptive_studio.
///
/// Design principle (locked with the user): **everything is optional with
/// sensible defaults.** No `android:` block → Android is skipped. A missing
/// optional asset is skipped with a log line, never a hard failure. The only
/// practical floor is that you must supply *a* source for whatever you want
/// generated.
library;

import 'package:meta/meta.dart';

import '../raster/image_format.dart';

export '../raster/image_format.dart' show ImageFormat;

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

/// iOS launch-screen configuration. iOS has no SplashScreen API. This drives a
/// `LaunchScreen.storyboard` via a centred-logo imageset + a background colour
/// set (both light/dark). Unset values fall back to the Android splash / root
/// source, so one config can cover both platforms.
@immutable
class IosSplashConfig {
  const IosSplashConfig({
    this.background,
    this.backgroundDark,
    this.backgroundImage,
    this.backgroundImageDark,
    this.image,
    this.imageDark,
    this.logoSizePt = 192,
  });

  final String? background;
  final String? backgroundDark;

  /// Full-bleed image (SVG or raster) painted behind the logo, scaled to fill
  /// the launch screen. Optional; the solid [background] shows through when
  /// unset. Falls back to the Android splash `background_image`.
  final String? backgroundImage;
  final String? backgroundImageDark;

  /// Centred logo (SVG or raster), shown transparent over the background.
  final String? image;
  final String? imageDark;

  /// Logo edge length in points on the launch screen.
  final int logoSizePt;
}

/// iOS app-icon configuration. iOS icons are a single square drawn as-is (the
/// system rounds the corners) and **must be opaque**, so a [background] is
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

  /// iOS 18 tinted-appearance source: a grayscale mark the system tints
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

  /// Splash-screen configuration, or null when no `splash:` block is present.
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
    this.legacyPadding,
    this.round = false,
    this.playStore = false,
    this.playStorePadding,
    this.themed,
    this.image,
    this.iconName = 'ic_launcher',
    this.effect = LegacyEffect.none,
    this.imageFormat = ImageFormat.png,
  });

  final AdaptiveConfig? adaptive;

  /// Encoding for the generated raster icon resources (legacy mipmaps + raster
  /// foreground density layers). The Play Store PNG is always PNG regardless.
  final ImageFormat imageFormat;

  /// Post-processing for the raster (legacy mipmap + store) icon, mirroring the
  /// Android Asset Studio / IconKitchen "effect" toggle. `none` is flat (modern
  /// default); `elevate` adds the classic Material drop shadow + sheen.
  final LegacyEffect effect;

  /// Source for the legacy mipmaps + the Play Store PNG. If absent, they're
  /// composed from the adaptive foreground + background. Either way the art is
  /// inset to match the adaptive foreground and iOS icon (see [legacyPadding]);
  /// pass `legacy_padding: 0` to use a finished icon edge-to-edge.
  final String? image;

  /// Emit pre-API-26 mipmap PNGs. `null` ⇒ decide from `minSdk`.
  final bool? legacy;

  /// Percent the legacy/store art is inset from the icon edge, overriding the
  /// adaptive safe zone for the raster outputs only. `null` ⇒ follow
  /// `adaptive.safe_zone`/`padding`. Applies whether the art comes from the
  /// adaptive foreground or an explicit [image]; set `0` to keep a finished
  /// [image] edge-to-edge.
  final int? legacyPadding;

  /// Emit `ic_launcher_round` and wire `android:roundIcon`.
  final bool round;

  /// Emit the 512² Play Store marketing PNG.
  final bool playStore;

  /// Percent the **Play Store** PNG's art is inset, independently of the legacy
  /// mipmaps. `null` follows the shared framing ([legacyPadding], else
  /// `adaptive.safe_zone`, else the default); set it to frame the marketing icon
  /// on its own (0-95, e.g. a roomier inset for Play's rounded presentation).
  final int? playStorePadding;

  /// Full-colour light/dark icon via activity-alias.
  final ThemedIconConfig? themed;

  /// Resource base name. Defaults to Flutter's `ic_launcher`.
  final String iconName;
}

/// How a vector (SVG) icon layer is emitted: as a crisp [vector] VectorDrawable
/// (default), or [raster] density PNGs. Raster is for art whose VectorDrawable
/// won't render everywhere, chiefly gradients: they rely on the `aapt:attr`
/// build-time feature that IDE previewers and some renderers don't resolve, so a
/// gradient icon can look flat or empty outside a real device build. Rasterising
/// bakes the gradients into pixels, which every tool and platform draws.
enum LayerFormat { vector, raster }

/// Adaptive icon layers (API 26+). All layers optional.
@immutable
class AdaptiveConfig {
  const AdaptiveConfig({
    this.foreground,
    this.background,
    this.monochrome,
    this.safeZone = const SafeZone.fit(),
    this.foregroundFormat = LayerFormat.vector,
  });

  /// Foreground source (SVG/vector or, later, raster).
  final String? foreground;

  /// Either a hex colour (`#RRGGBB`) or a path to an SVG/image.
  final String? background;

  /// Monochrome silhouette for Android 13 themed icons.
  final String? monochrome;

  final SafeZone safeZone;

  /// Whether an SVG [foreground] is emitted as a VectorDrawable ([vector],
  /// default) or baked to density PNGs ([raster]). Use `raster` for a
  /// gradient-heavy foreground that must render in previewers / non-Android
  /// targets, where VectorDrawable `aapt:attr` gradients aren't resolved. No
  /// effect on a raster foreground source (already PNGs).
  final LayerFormat foregroundFormat;

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

  /// Keep the source's own framing: map the whole viewBox (SVG) or full bitmap
  /// (raster) into the safe square, so the art's authored padding and aspect are
  /// preserved rather than trimmed. The escape hatch for art already drawn at
  /// adaptive-icon proportions.
  const SafeZone.asIs()
      : mode = SafeZoneMode.asIs,
        insetPercent = 0;

  final SafeZoneMode mode;
  final double insetPercent;
}

enum SafeZoneMode { fit, inset, none, asIs }

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

/// How a source **image** is sized into its slot.
///
/// [auto] measures the art's real bounding box and scales it to fill the slot,
/// trimming whatever transparent padding the source carries (the default, best
/// for a tightly-cropped logo). [asIs] uses the source exactly as drawn: its own
/// aspect ratio, inner padding, and relative size are preserved, just centred in
/// the slot. Applies to both SVG (whole viewBox) and transparent raster (the
/// full bitmap, margins kept). Shared by `branding_fit` and `image_fit`.
enum ArtFit { auto, asIs }

/// Brightness of the system-bar **icons** during the splash. `dark` icons suit a
/// light bar/background (maps to `windowLight*Bar = true`); `light` icons suit a
/// dark one. When unset, it's auto-derived from the bar/background colour.
enum SystemBarIconBrightness { light, dark }

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
    this.logoPadding,
    this.animatedIcon,
    this.animatedIconDark,
    this.durationMs = 1000,
    this.flutterSplashDuration,
    this.iconBackground,
    this.iconBackgroundDark,
    this.iconPadding,
    this.branding,
    this.brandingDark,
    this.brandingText,
    this.brandingTextColor,
    this.brandingTextColorDark,
    this.brandingMode = BrandingMode.bottom,
    this.brandingFit = ArtFit.auto,
    this.imageFit = ArtFit.auto,
    this.brandingBottomPadding = 48,
    this.gravity = 'center',
    this.fullscreen = false,
    this.screenOrientation,
    this.imageFormat = ImageFormat.png,
    this.statusBarColor,
    this.statusBarColorDark,
    this.statusBarIconBrightness,
    this.statusBarIconBrightnessDark,
    this.navigationBarColor,
    this.navigationBarColorDark,
    this.navigationBarIconBrightness,
    this.navigationBarIconBrightnessDark,
    this.flutterSplashAllVersions = false,
  });

  final String? background;
  final String? backgroundDark;

  /// Full-bleed background image (SVG or raster) drawn behind the logo. Works on
  /// the pre-31 splash + Flutter fallback; the Android 12+ system splash takes a
  /// solid colour only, so it uses [background] there.
  final String? backgroundImage;
  final String? backgroundImageDark;

  /// Static centre logo (SVG or raster). Used when no [animatedIcon] is given:
  /// the common "logo in the middle" splash. Wired to the API 31+
  /// `windowSplashScreenAnimatedIcon` slot (which also accepts a still drawable)
  /// and the centred layer of the pre-31 splash.
  final String? image;

  /// Dark-mode variant of [image], emitted to `-night` so it shows in system
  /// dark mode (API 31+ and pre-31 alike).
  final String? imageDark;

  /// Extra percent (0-95) the **in-app** splash logo is inset beyond the native
  /// keyline, for more breathing room. `null`/`0` ⇒ match the native splash
  /// icon size exactly. (The native splash icon is unaffected: it already
  /// follows the Android-12 keyline.)
  final int? logoPadding;

  final String? animatedIcon;
  final String? animatedIconDark;

  /// Native API 31+ animated-icon playback length (ms): the
  /// `windowSplashScreenAnimationDuration`. Only applies with an [animatedIcon].
  final int durationMs;

  /// How long the **in-app** [AdaptiveSplash] holds before fading (ms). Separate
  /// from [durationMs]; `null` ⇒ fall back to [durationMs], then a default.
  final int? flutterSplashDuration;

  final String? iconBackground;

  /// Dark-mode variant of [iconBackground] (the API 31+ icon circle colour).
  final String? iconBackgroundDark;

  /// Extra percent (0-95) the **native** splash icon is inset beyond the
  /// Android-12 keyline, so a tall/wide logo sits in a completely safe spot even
  /// when the OS treats it as an adaptive icon and masks it to the launcher
  /// shape (e.g. a `windowSplashScreenIconBackgroundColor` icon on Samsung One
  /// UI is scaled up + squircle-masked, clipping a logo drawn to the raw
  /// keyline). Independent of [logoPadding] (which is in-app only). `null` ⇒ a
  /// safe default is applied when [iconBackground] is set (the masked case),
  /// otherwise no extra inset.
  final int? iconPadding;

  /// Bottom branding image (SVG or raster), as the native splash shows beneath
  /// the icon. Light variant; [brandingDark] supplies the `-night` version.
  final String? branding;
  final String? brandingDark;

  /// Text branding shown when no [branding] image is given, rendered to a
  /// bottom wordmark (rasterised with a built-in font for the native splash, a
  /// crisp `Text` widget in the Flutter fallback). Ignored if [branding] is set.
  final String? brandingText;

  /// Colour for [brandingText]. Defaults to a contrasting tone derived from the
  /// background (dark text on a light background, light text on a dark one).
  final String? brandingTextColor;
  final String? brandingTextColorDark;

  /// Branding placement on the pre-31 splash + Flutter fallback (the API 31+
  /// system splash always bottom-centres it).
  final BrandingMode brandingMode;

  /// How a [branding] image is framed: [ArtFit.auto] trims and fills the slot;
  /// [ArtFit.asIs] keeps the source's own aspect ratio, inner padding, and size.
  final ArtFit brandingFit;

  /// How the centre [image] (splash logo) is framed on the native splash:
  /// [ArtFit.auto] (default) measures the real art and fills the Android-12 safe
  /// circle, trimming the source's own padding; [ArtFit.asIs] keeps the source's
  /// whole viewBox/bitmap (its padding and aspect), just centred and contained.
  /// Applies to both SVG and transparent raster.
  final ArtFit imageFit;

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

  /// Status-bar background during the splash: a hex colour (`#RRGGBB[AA]`) or
  /// the keyword `transparent`. Null leaves the platform default. Applies to the
  /// pre-31 launch theme and the API 31+ splash theme. [statusBarColorDark]
  /// supplies the dark-mode value (emitted to `-night`).
  final String? statusBarColor;
  final String? statusBarColorDark;

  /// Status-bar **icon** brightness (`dark` icons for a light bar, `light` for a
  /// dark one). Null auto-derives from the bar colour (or the background, when
  /// the bar is transparent). [statusBarIconBrightnessDark] overrides in dark
  /// mode.
  final SystemBarIconBrightness? statusBarIconBrightness;
  final SystemBarIconBrightness? statusBarIconBrightnessDark;

  /// Navigation-bar background during the splash: hex or `transparent`.
  /// [navigationBarColorDark] supplies the dark-mode value.
  final String? navigationBarColor;
  final String? navigationBarColorDark;

  /// Navigation-bar **icon** brightness (API 27+ `windowLightNavigationBar`).
  /// Null auto-derives from the bar/background colour.
  final SystemBarIconBrightness? navigationBarIconBrightness;
  final SystemBarIconBrightness? navigationBarIconBrightnessDark;

  /// Encoding for the pre-31 raster splash logo (`drawable-*/splash_icon_legacy`).
  /// The centre logo is rasterised, not a VectorDrawable, because
  /// `windowBackground` is inflated before AppCompat's vector support and a
  /// vector silently fails to paint on API 21-23. PNG is the safe default; WebP
  /// (lossless) is smaller and resolves identically on API 18+.
  final ImageFormat imageFormat;

  /// Force the in-app [AdaptiveSplash] (the generated `fas_splash.g.dart`) to
  /// show on **every** OS version. Default false: it shows only where there's no
  /// native animated splash (Android API < 31); on API 31+ the system
  /// `SplashScreen` already covers startup. Baked into the config as
  /// `showOnAllVersions` (also overridable per-call with `AdaptiveSplash(force:)`).
  final bool flutterSplashAllVersions;

  /// True when there is any centre logo to render (animated or static).
  bool get hasIcon => animatedIcon != null || image != null;
}

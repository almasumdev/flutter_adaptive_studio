/// Drop-in Flutter glue emitted for the splash feature: a `FasSplash` widget
/// that mirrors the native splash (background + centre logo + bottom branding)
/// for devices WITHOUT the Android 12 `SplashScreen` API (SDK < 31), plus an
/// SDK gate and a guide. These are *references* the developer wires in.
library;

/// The stock Flutter `launch_background.xml` (a plain `?android:colorBackground`
/// layer). `revert` restores this to `drawable/` and `drawable-v21/` instead of
/// deleting them — `LaunchTheme.windowBackground` still references
/// `@drawable/launch_background`, so removing the file outright would dangle that
/// reference and break the build.
const String stockLaunchBackgroundXml =
    '''<?xml version="1.0" encoding="utf-8"?>
<!-- Modify this file to customize your launch splash screen -->
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="?android:colorBackground" />

    <!-- You can insert your own image assets here -->
    <!-- <item>
        <bitmap
            android:gravity="center"
            android:src="@mipmap/launch_image" />
    </item> -->
</layer-list>
''';

String _hex8(int argb) =>
    '0x${(argb & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0').toUpperCase()}';

bool _isSvg(String? a) => a != null && a.toLowerCase().endsWith('.svg');

/// `Image.asset` can't render SVG — pick the right widget per asset type.
String _assetWidget(String asset, String sizeArgs) => _isSvg(asset)
    ? "SvgPicture.asset('$asset', $sizeArgs)"
    : "Image.asset('$asset', $sizeArgs)";

/// Statement that pre-decodes [asset] into its cache before the animation, so it
/// paints on the first frame instead of popping in mid-animation (which reads as
/// static). Block-scoped so multiple assets don't collide on the loader variable.
String _precacheStmt(String asset) => _isSvg(asset)
    ? '''{
        final loader = SvgAssetLoader('$asset');
        await svg.cache
            .putIfAbsent(loader.cacheKey(null), () => loader.loadBytes(null));
      }'''
    : "if (mounted) await precacheImage(const AssetImage('$asset'), context);";

/// Builds the `FasSplash` widget + SDK gate, with colours and asset paths baked
/// from the resolved splash config. Emits `SvgPicture.asset` for SVG sources
/// (and the `flutter_svg` import) and `Image.asset` for raster ones.
String splashFallbackDart({
  required int bgLightArgb,
  required int bgDarkArgb,
  String? logoAsset,
  String? brandingAsset,
  String? brandingDarkAsset,
  String? brandingText,
  int brandingTextColorLight = 0xFF000000,
  int brandingTextColorDark = 0xFFFFFFFF,
  String brandingAlignment = 'Alignment.bottomCenter',
  int brandingBottomDp = 48,
  String? backgroundImageAsset,
  String? backgroundImageDarkAsset,
}) {
  // A distinct dark branding asset is themed by the active app brightness,
  // mirroring the native `-night` branding drawable.
  final hasDarkBrand =
      brandingDarkAsset != null && brandingDarkAsset != brandingAsset;
  final hasBgImage = backgroundImageAsset != null;
  final hasBgImageDark = backgroundImageDarkAsset != null &&
      backgroundImageDarkAsset != backgroundImageAsset;
  final needsSvg = _isSvg(logoAsset) ||
      _isSvg(brandingAsset) ||
      (hasDarkBrand && _isSvg(brandingDarkAsset)) ||
      _isSvg(backgroundImageAsset) ||
      (hasBgImageDark && _isSvg(backgroundImageDarkAsset));
  final svgImport =
      needsSvg ? "import 'package:flutter_svg/flutter_svg.dart';\n" : '';
  final svgPubReq = needsSvg
      ? '\n// Requires: flutter_svg  (flutter pub add flutter_svg)'
      : '';

  final logo = logoAsset == null
      ? '// No `image:` configured — add a static logo for the Flutter splash.\n'
          '              const SizedBox.shrink()'
      : _assetWidget(logoAsset, 'width: 192, height: 192');

  // Decode every asset into its cache BEFORE the animation starts.
  final precacheBody = [
    if (logoAsset != null) _precacheStmt(logoAsset),
    if (brandingAsset != null) _precacheStmt(brandingAsset),
    if (hasDarkBrand) _precacheStmt(brandingDarkAsset),
    if (hasBgImage) _precacheStmt(backgroundImageAsset),
    if (hasBgImageDark) _precacheStmt(backgroundImageDarkAsset),
  ].join('\n    ');

  // Full-bleed background image (theme-aware), drawn behind the logo.
  final bgImageWidget = !hasBgImage
      ? ''
      : hasBgImageDark
          ? 'dark ? ${_assetWidget(backgroundImageDarkAsset, 'fit: BoxFit.cover')} '
              ': ${_assetWidget(backgroundImageAsset, 'fit: BoxFit.cover')}'
          : _assetWidget(backgroundImageAsset, 'fit: BoxFit.cover');
  final bgImageBlock = !hasBgImage
      ? ''
      : '''
          // Full-bleed background image — mirrors the pre-31 windowBackground.
          Positioned.fill(child: $bgImageWidget),''';

  // Theme-aware branding widget: an image when given, else a text wordmark
  // (mirroring the native rasterised text branding), else nothing.
  final hasTextBrand = brandingAsset == null && brandingText != null;
  final brandingWidget = brandingAsset != null
      ? (hasDarkBrand
          ? 'dark ? ${_assetWidget(brandingDarkAsset, 'height: 40')} '
              ': ${_assetWidget(brandingAsset, 'height: 40')}'
          : _assetWidget(brandingAsset, 'height: 40'))
      : hasTextBrand
          ? "Text('${brandingText.replaceAll(r'$', r'\$').replaceAll("'", r"\'")}', "
              'style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, '
              'color: dark ? const Color(${_hex8(brandingTextColorDark)}) '
              ': const Color(${_hex8(brandingTextColorLight)})))'
          : '';

  final brandingBlock = (brandingAsset == null && !hasTextBrand)
      ? ''
      : '''
          // Bottom branding — mirrors windowSplashScreenBrandingImage.
          Align(
            alignment: $brandingAlignment,
            child: Padding(
              padding: const EdgeInsets.only(bottom: $brandingBottomDp),
              child: FadeTransition(
                opacity: _fade,
                child: $brandingWidget,
              ),
            ),
          ),''';

  return '''
// Generated by flutter_adaptive_studio. Safe to edit.
//
// A Flutter splash that mirrors the native one for devices without the
// Android 12 SplashScreen API (SDK < 31). Unlike the native splash, this one
// runs inside your app, so it follows your app theme. See SPLASH.md.
//
// Requires: device_info_plus  (flutter pub add device_info_plus)$svgPubReq
// Declare the logo/branding assets under `assets:` in pubspec.yaml.

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
$svgImport
/// True only on devices that have no native themed splash (Android < 12).
/// On 31+ the OS splash already themed correctly — don't show [FasSplash].
///
/// Pass [forceInDebug] (default true) to ALWAYS show it in debug builds so you
/// can see/iterate on [FasSplash] even on a modern device/emulator. Release
/// builds ignore the flag and use the real SDK check.
Future<bool> fasNeedsFlutterSplash({bool forceInDebug = true}) async {
  if (forceInDebug && kDebugMode) return true;
  if (!Platform.isAndroid) return false;
  final info = await DeviceInfoPlugin().androidInfo;
  return info.version.sdkInt < 31;
}

/// Solid background + centred logo (+ bottom branding) with a fade + gentle
/// pop-up entrance (quick ease-out fade, slight-overshoot scale). Colours come
/// from `background` / `background_dark` in your config.
class FasSplash extends StatefulWidget {
  const FasSplash({super.key});

  @override
  State<FasSplash> createState() => _FasSplashState();
}

class _FasSplashState extends State<FasSplash>
    with SingleTickerProviderStateMixin {
  static const Color _bgLight = Color(${_hex8(bgLightArgb)});
  static const Color _bgDark = Color(${_hex8(bgDarkArgb)});

  /// Like easeOutBack but with a stronger back (2.2 vs 1.56) for a clear spring.
  static const Curve _overshoot = Cubic(0.34, 2.2, 0.64, 1.0);

  late final AnimationController _c;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    // Rests at 0 → opacity 0 / scale 0.4, so the art is invisible until
    // forward(): it can mount and decode while hidden (see _decodeThenAnimate)
    // instead of popping in mid-animation.
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _fade = CurvedAnimation(
        parent: _c, curve: const Interval(0.0, 0.6, curve: Curves.easeOut));
    _scale = Tween<double>(begin: 0.4, end: 1.0)
        .animate(CurvedAnimation(parent: _c, curve: _overshoot));
    _decodeThenAnimate();
  }

  /// Decode the assets, then start the animation one frame later. The art loads
  /// asynchronously; animating during the decode (worsened by startup jank)
  /// makes it appear only once near full size — i.e. static.
  Future<void> _decodeThenAnimate() async {
    $precacheBody
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: dark ? _bgDark : _bgLight,
      child: Stack(
        alignment: Alignment.center,
        children: [$bgImageBlock
          Center(
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(scale: _scale, child: $logo),
            ),
          ),$brandingBlock
        ],
      ),
    );
  }
}
''';
}

const String splashGuide = r'''
# Splash screen — native + Flutter fallback

## Requirement: compileSdk ≥ 31
The Android 12 `SplashScreen` attributes (`windowSplashScreenBackground`,
`windowSplashScreenAnimatedIcon`, `windowSplashScreenBrandingImage`, …) live in
SDK 31+. The generated `values-v31/` styles compile against them, so your
`android/app/build.gradle(.kts)` must use **compileSdk 31 or higher** (34
recommended). If you see `error: style attribute 'android:attr/windowSplashScreen…'
not found`, that's the fix.

## Icon keyline (why your logo isn't clipped)
Android 12 masks the splash icon to a **centred circle of 2/3 the canvas**:
288dp canvas → ⌀192dp safe circle (no icon background), or 240 → ⌀160 (with one).
Anything outside that circle is **cut**. The generator inscribes your logo's
bounding box inside the safe circle (diagonal ≤ diameter), so even a square logo's
corners stay visible. If your icon still looks small, it's because the circle is
only 2/3 of the canvas — that's the spec, not a bug.

flutter_adaptive_studio generated the **native** Android splash:

- **Android 12+ (API 31+):** the real `SplashScreen` API — `values-v31/styles.xml`
  (+ `-night`) with `windowSplashScreenBackground`, `windowSplashScreenAnimatedIcon`
  (your `image:`/`animated_icon:`), an optional `windowSplashScreenIconBackgroundColor`,
  and `windowSplashScreenBrandingImage` (your `branding:`). Themed by the **system**.

  The animated icon must be a ready-made **AnimatedVectorDrawable** (`.xml`),
  used verbatim — author it in any AVD tool (e.g. Shapeshifter → "Export →
  Animated Vector Drawable"). Lottie is **not** supported by the native splash
  (runtime-only) — use it in the Flutter fallback below instead. Animated icons
  are masked to the same keyline circle, so design the animation inside it (we
  don't reshape it).
- **Android < 12:** a classic `windowBackground` (`drawable/launch_background.xml`)
  with the logo centred and branding at the bottom (light/dark via `-night`). The
  centre logo is rendered to **per-density PNG/WebP** (`drawable-*/splash_icon_legacy`),
  not a VectorDrawable: `windowBackground` is inflated before AppCompat's vector
  support, so a vector logo silently fails to paint on API 21–23 (Android 5–6).
  A bitmap always renders. Choose the encoding with `image_format: png | webp`
  under `splash:`. For the same reason, an **SVG `branding:`** is rasterised to a
  per-density `drawable-*/splash_branding_legacy` sibling and an **SVG
  `background_image:`** to a `drawable-nodpi/splash_bg` bitmap for this layer —
  the crisp vectors are still used for the API 31+ slot. So everything in the
  pre-31 launch background is a bitmap: bulletproof on API 21–23.

  **An `animated_icon` does NOT apply here — Android < 12 can't run an animation
  in a `windowBackground`.** It needs a *still* logo. So the pre-31 launch logo
  comes from `splash.image:`; if you only set `animated_icon` (no `image:`), the
  generator falls back to your **app logo** (`icon.adaptive.foreground`, else the
  root `source:`) so the launch screen still shows a mark instead of a bare
  colour. Set `splash.image:` to control it explicitly.

## Keep the native splash during startup (no white flash) — `FasNativeSplash`
The OS shows the native splash only until Flutter paints its **first frame**.
If your app still has work to do then (load prefs, open a DB, check auth), that
first frame is blank/white and pops in late. `FasNativeSplash` holds the native
splash until *you* say the app is ready — by deferring the first frame.

It ships in the package (no generated file to copy). Add the dependency, then
import and call it like `flutter_native_splash`:

```sh
dart pub add flutter_adaptive_studio
```

```dart
import 'package:flutter_adaptive_studio/flutter_adaptive_studio.dart';

void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FasNativeSplash.preserve(widgetsBinding: binding); // hold the native splash
  runApp(const MyApp());
}

// ...after your async init / once your first screen is ready:
FasNativeSplash.remove(); // let Flutter paint; native splash hands off to your UI
```

This works on **every** API level (it's just the native splash, kept longer) and
is independent of the Flutter fallback below. Migrating from flutter_native_splash?
The `preserve`/`remove` signatures match, so it's a drop-in swap.

### Where to call `remove()`
Call it **right after `runApp()`** (synchronously), once you've finished the
startup work you wanted the native splash to cover. Do your async init BEFORE
`runApp()`, so the first frame `runApp()` schedules is already your real screen:

```dart
Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FasNativeSplash.preserve(widgetsBinding: binding);
  await loadEverything();        // prefs / DB / auth — keep it short (< ~2s)
  runApp(const MyApp());
  FasNativeSplash.remove();      // first real frame replaces the native splash
}
```

**Do NOT put `remove()` inside an `addPostFrameCallback`.** While the first frame
is deferred, that callback never fires — so `remove()` would never run and the
app stays stuck on the splash. Calling it synchronously after `runApp()` lets the
(now-allowed) first frame paint your real UI.

If you want to show your *own* animated loader during a long load instead of the
frozen native splash, call `remove()` synchronously right after the `runApp()`
that mounts the loader, then do the work behind it.

Guardrails: guarantee `remove()` runs on every path (wrap init in `try/finally`),
call it once, and keep the held time short — the native splash can't animate or
show progress, so hand off to Flutter quickly for long loads.

### Failsafe: `maxDuration` (recommended)
As a belt-and-braces guard against a forgotten/failed `remove()` stranding the
app on a frozen splash, pass a `maxDuration` to `preserve` — the splash releases
itself after it, no matter what:

```dart
FasNativeSplash.preserve(
  widgetsBinding: binding,
  maxDuration: const Duration(seconds: 10), // auto-release escape hatch
);
```

(`flutter_native_splash` has no such guard.) `preserve` is also a no-op if called
twice, so it can never double-defer the first frame.

## Why the Flutter fallback?
The native splash renders **before** your app code runs, so it can only follow
the **system** theme — and on **Android ≤ 9** there's no system dark mode at all,
so it always shows light. If you want the splash to follow your **app** theme on
those devices, show `FasSplash` as your first screen, gated by SDK version.

```dart
// 1) flutter pub add device_info_plus   (+ flutter_svg if your logo is SVG)
// 2) Declare your logo/branding under `assets:` in pubspec.yaml.
// 3) At app start:
final showFlutter = await fasNeedsFlutterSplash(); // true on Android < 12
// Debug builds force it ON by default so you can see it on any device/emulator.
// To test the real gate in debug: fasNeedsFlutterSplash(forceInDebug: false).
runApp(MyApp(showSplash: showFlutter));

// In your first route, if showSplash: show FasSplash for ~600ms (or until
// your app is ready), then navigate to home. On 31+ skip it entirely — the
// native splash already covered the launch.
```

## Avoiding a flicker at handoff
For a seamless transition, `FasSplash`'s background + logo geometry already match
the native splash. Keep the native splash short and render `FasSplash` on the
first frame so there's no visible gap (most noticeable on Android ≤ 9 going dark).

## Other splash options (set in your config)
- **Dark variants:** `background_dark`, `image_dark`, `icon_background_dark`,
  `branding_dark`, `animated_icon_dark` — emitted to `-night` and chosen by the
  system (native) / app theme (fallback).
- **`background_image`** (+ `_dark`) — full-bleed background behind the logo on
  the pre-31 splash + Flutter fallback. The Android 12+ system splash takes a
  colour only, so it uses `background` there.
- **`branding_text`** (+ `branding_text_color` / `_dark`) — a **text** wordmark
  shown when no `branding` image is given. Rendered with a built-in font for the
  native splash (a crisp `Text` widget in the Flutter fallback). The colour
  auto-contrasts the background when unset. For a brand typeface, use a
  `branding` SVG/PNG instead — the built-in font is generic.
- **`branding_mode`** (`bottom` / `bottom_left` / `bottom_right`) +
  **`branding_bottom_padding`** — branding placement (pre-31 + fallback; the
  system splash always bottom-centres).
- **`gravity`** — pre-31 centre-image alignment. **`fullscreen`** — hide the
  system bars. **`screen_orientation`** — lock orientation (app-wide; written to
  the shared manifest, so `revert` won't undo it).
- **`image_format`** (`png` / `webp`) — encoding for the pre-31 raster splash
  logo (`png` default; `webp` is smaller, supported on API 18+).
- **System bars during the splash** — `status_bar_color` and
  `navigation_bar_color` (each a hex value or `transparent`, with `_dark`
  variants) tint the status / bottom-navigation bars while the splash is up
  (set on the launch theme for both pre-31 and API 31+). `status_bar_icon_
  brightness` / `navigation_bar_icon_brightness` (`dark` | `light`, with `_dark`
  variants) choose the **icon** colour — `dark` icons for a light bar, `light`
  for a dark one; omit them and it's auto-derived from the bar/background
  colour. These set `statusBarColor` / `navigationBarColor` /
  `windowLightStatusBar` / `windowLightNavigationBar` on the theme, so they
  cover the **native** splash; your Flutter app should keep driving its own bars
  via `SystemChrome` once it's running.

## Flavors
One config, base + per-flavor overrides under `flavors:`. Generate a flavor with
`--flavor <name>` and the merged result is written to that flavor's
`android/app/src/<name>/res` overlay (it overrides `main` for that build):

```yaml
flutter_adaptive_studio:
  android: { ... }            # base config
  flavors:
    dev:  { android: { splash: { background: "#00C853" } } }
```
''';

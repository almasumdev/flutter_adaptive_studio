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
  with the logo centred and branding at the bottom. Light/dark via `-night`.

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
- **`branding_mode`** (`bottom` / `bottom_left` / `bottom_right`) +
  **`branding_bottom_padding`** — branding placement (pre-31 + fallback; the
  system splash always bottom-centres).
- **`gravity`** — pre-31 centre-image alignment. **`fullscreen`** — hide the
  system bars. **`screen_orientation`** — lock orientation (app-wide; written to
  the shared manifest, so `revert` won't undo it).

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

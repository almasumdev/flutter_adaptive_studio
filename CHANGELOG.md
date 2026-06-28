# Changelog

## 0.19.0

### Consistent icon padding (mipmap + Play Store match the rest)

A finished `icon.image` is now inset by the same `safe_zone` / `legacy_padding`
as the adaptive foreground — so the **legacy mipmaps** and the **Play Store
PNG** share one framing with the adaptive icon and the iOS icon, instead of
being used edge-to-edge.

- The inset follows `legacy_padding` if set, else the adaptive `safe_zone`, else
  the package default — the same rule every other generated icon uses.
- **Breaking:** a finished `icon.image` that was previously emitted as-is is now
  inset. Set **`legacy_padding: 0`** to keep an already-framed icon
  edge-to-edge. (A pure `icon.image` config with no adaptive safe zone and no
  `legacy_padding` is still used full-bleed.)

## 0.18.0

### Zero-dependency in-app splash (no more conflicts)

The package is now a **pure-Dart CLI** — install it with `dart pub global
activate flutter_adaptive_studio` and run `fas generate`. The in-app splash is
no longer a shipped library; it's **generated** into a self-contained
`lib/fas_splash.g.dart` that imports **only `package:flutter`**.

```dart
import 'fas_splash.g.dart'; // self-contained: config + AdaptiveSplash + FasNativeSplash

void main() => runApp(AdaptiveSplash(config: fasSplash, child: const MyApp()));
```

- **Your app depends on nothing from us**, so the generator's build-time deps
  (`image`, `xml`, …) can never conflict with your app's (e.g. an app using
  `flutter_local_notifications`, which pins `xml` 6.x). webp is kept.
- The generated file bakes in `AdaptiveSplash`, `FasNativeSplash`, and the
  config. The Android-API-level gate uses **core `dart:ffi`** (no `package:ffi`),
  so the app needs no extra dependency. (Generated splash targets Android + iOS;
  `dart:ffi` is unavailable on web.)
- **Breaking:** the package no longer exports a runtime library
  (`AdaptiveSplash`/`FasNativeSplash` are generated, not imported from the
  package). Re-run `generate` and import `fas_splash.g.dart` directly. The CLI
  and all generated native icon/splash output are unchanged.

## 0.17.0

### In-app splash — just wrap your app (no more glue folder)

The old `flutter_adaptive_studio/splash/` drop-in (a `FasSplash` widget you had
to read, wire into `main()`, plus `device_info_plus` and `flutter_svg` to add and
assets to declare) is **gone**. The splash widget now ships **in the package** —
you wrap your app once and everything is handled:

```dart
import 'package:flutter_adaptive_studio/flutter_adaptive_studio.dart';
import 'fas_splash.g.dart'; // the only generated file

void main() => runApp(AdaptiveSplash(config: fasSplash, child: const MyApp()));
```

- **`AdaptiveSplash`** (shipped) paints a splash that matches the native one
  (background, centred logo, branding — light/dark by system brightness), holds
  briefly while your first screen settles, then fades to your app.
- The generator now emits a **single** `lib/fas_splash.g.dart` — colours, timing,
  and the logo/branding/background **rasterised to PNG and base64-embedded**. So
  the app needs **no assets, no `flutter_svg`, and no `device_info_plus`**.
- By default the in-app splash shows only **where there's no native animated
  splash** (Android API < 31; on 31+ the system `SplashScreen` covers startup).
  Force it on every version with `AdaptiveSplash(force: true, …)` or
  `flutter_splash_all_versions: true` under `splash:`.
- The "API < 31" check reads `Build.VERSION.SDK_INT` via **`dart:ffi`** (libc
  `__system_property_get`) — so the package stays a plain Flutter package (no
  plugin, no Gradle/podspec) and can't conflict with your other dependencies.
- **Android + iOS, fully.** `fas_splash.g.dart` is now generated whenever *either*
  platform configures a splash (so an **iOS-only** project gets it too — it used
  to be Android-only and would leave the import dangling). The config also bakes
  **iOS overrides** (`iosBackground*` / `iosLogo*`): on iOS `AdaptiveSplash`
  matches the iOS `LaunchScreen` (its own background/logo, no branding), and on
  Android it matches the Android splash — automatically, from one wrap.
- `revert` removes `lib/fas_splash.g.dart` (and the old glue folder).
- Added a **runnable `example/` app** demonstrating `AdaptiveSplash` (with a
  "Replay splash" button).
- **README rewritten** around the new in-app splash flow, with a platform-support
  matrix, a **Requirements & limitations** section (compileSdk 34, iOS static
  launch, themed-icon SVG source), and an FAQ.
- **Dependencies:** now requires `xml ^7.0.1` and `image ^4.9.1`. ⚠️ This means
  the package can no longer be added alongside a dependency that pins `xml` 6.x
  (e.g. `flutter_local_notifications` on Windows).
- **`generator.dart` API narrowed** to the real programmatic surface
  (`AdaptiveStudio`, the CLI-command classes, `Logger`, `GenerationReport`).
  Internal config/SVG/vector types are no longer exported.

> Migration: delete the old `flutter_adaptive_studio/splash/` folder, drop the
> manual `device_info_plus`/`flutter_svg` deps you added for it, re-run
> `generate`, and wrap your app with `AdaptiveSplash` as above. `FasNativeSplash`
> (the native-splash keeper) is unchanged and still available.

## 0.16.0

### Pre-31 launch background — bulletproof on API 21–23

- **SVG `branding:` now renders on the pre-31 launch screen on every API level.**
  Previously an SVG branding was emitted as a VectorDrawable and referenced from
  `windowBackground` — which can't inflate a vector on **API 21–23** (Android
  5–6), so the branding silently failed to paint there (and risked dropping the
  whole launch background). It's now rasterised to a per-density
  `drawable-*/splash_branding_legacy` bitmap for the pre-31 layer, while the
  crisp **vector** is kept for the Android 12+ branding slot. (Text and raster
  branding were already bitmaps — unchanged.)
- **SVG `background_image:` is rasterised too** (to `drawable-nodpi/splash_bg`),
  for the same reason — it's only used on the pre-31 layer, where a vector can't
  paint on API 21–23. So **every layer** of the pre-31 launch background is now a
  bitmap: nothing in it can fail to inflate on old devices.
- `image_format: png | webp` controls the encoding of these new rasters as well,
  and `revert` cleans them up (along with text-branding density rasters, which it
  previously missed).

### `FasNativeSplash` — failsafe + double-preserve guard

- `preserve(...)` gains an optional **`maxDuration`** failsafe: if `remove()`
  isn't called within it, the splash auto-releases — so a forgotten `remove()`
  or an exception during startup can no longer strand the app on a frozen splash
  forever (the classic native-splash white-screen trap). It's opt-in; leaving it
  null keeps the original behaviour. `flutter_native_splash` has no such guard.
- `preserve(...)` called twice is now a **no-op** instead of double-deferring the
  first frame (which would have needed two `remove()`s to clear). Added an
  `isPreserved` getter. The `preserve`/`remove` signatures still match
  `flutter_native_splash`, so it stays a drop-in swap.

## 0.15.0

### New `sync` command

- `fas sync` (or `dart run flutter_adaptive_studio sync`) adds any options your
  `flutter_adaptive_studio.yaml` doesn't yet mention — as **commented**
  placeholders in the right section — **without touching your existing lines,
  values, or formatting**. It's the non-destructive way for existing users to
  pick up newly-added options (unlike `init --force`, which overwrites the
  whole file). Because every inserted line is a comment, it can never change
  behaviour or break the YAML; it's also idempotent.

## 0.14.0

### Splash — text branding

- New `branding_text:` renders a **text** wordmark at the bottom of the splash
  when no `branding` image is given (with `branding_text_color` / `_dark`,
  auto-contrasting the background when unset). It's rasterised with a built-in
  font for the native splash (pre-31 launch background + API 31+ branding slot,
  per density + `-night`) and emitted as a crisp `Text` widget in the Flutter
  fallback. For a brand typeface, use a `branding` SVG/PNG instead.

## 0.13.0

### Splash — system bars

- New: tint the **status bar** and **bottom navigation bar** during the splash.
  `status_bar_color` / `navigation_bar_color` take a hex value or `transparent`
  (each with a `_dark` variant), and `status_bar_icon_brightness` /
  `navigation_bar_icon_brightness` (`dark` | `light`, + `_dark`) set the bar
  **icon** colour — auto-derived from the bar/background colour when omitted.
  These set `statusBarColor` / `navigationBarColor` / `windowLightStatusBar` /
  `windowLightNavigationBar` on both the pre-31 launch theme and the API 31+
  splash theme (and their `-night` variants).
- Docs: branding already renders on the pre-31 launch background (it's the
  bottom layer of `launch_background.xml`) — now visible on Android 10+ after
  the 0.12.0 `-v21` fix.

## 0.12.0

### Splash (critical pre-31 fix)

- **The pre-31 launch splash now actually shows.** A stock Flutter project ships
  `drawable-v21/launch_background.xml`, and on API 21+ (virtually every device)
  Android resolves `@drawable/launch_background` to that `-v21` file — so the
  generator only writing `drawable/launch_background.xml` was **silently
  shadowed** by the stock white default, and the splash background/logo never
  appeared. We now write the launch background to **`drawable/` and
  `drawable-v21/`** (and overwrite any `-night` variants), so it shows on Android
  10 and friends.
- `revert` restores the **stock** `launch_background.xml` to `drawable/` +
  `drawable-v21/` (instead of deleting), so the `LaunchTheme` reference can't
  dangle and break the build.

## 0.11.0

### Splash (pre-31 launch background)

- **An animated-only splash no longer leaves the Android < 12 launch screen
  logo-less.** An `animated_icon` can't run in a pre-31 `windowBackground`, so
  when no static `splash.image:` is set the generator now falls back to your app
  logo (`icon.adaptive.foreground`, else the root `source:`) for the pre-31
  launch logo — the launch screen shows your mark instead of a bare colour. Set
  `splash.image:` to control it explicitly.

> Note: if your launch screen stays blank/white through a long startup, check
> that `FasNativeSplash.remove()` is called **synchronously right after
> `runApp()`** — not inside an `addPostFrameCallback`. While the first frame is
> deferred by `preserve()`, that callback never fires, so `remove()` there never
> runs and the app is stranded on a blank window.

## 0.10.0

### Splash (pre-31 reliability)

- **The pre-31 `windowBackground` splash logo is now rasterised** to per-density
  PNG/WebP (`drawable-*/splash_icon_legacy`) instead of being referenced as a
  VectorDrawable. `windowBackground` is inflated by the platform before
  AppCompat's vector support is active, so a vector logo silently failed to paint
  on **API 21–23** (Android 5–6) — you'd get the background colour but no logo.
  A bitmap always renders, so the old-device launch splash is now bulletproof.
  The crisp vector is still used for the Android 12+ `SplashScreen` slot.
- New `splash.image_format: png | webp` chooses the encoding for that raster
  logo (PNG default; WebP is smaller and resolves identically on API 18+).
- An `animated_icon` with no static `image:` now logs a warning — an AVD can't be
  a `windowBackground` drawable, so add an `image:` for a resting pre-31 logo.
- `revert` now also removes the per-density legacy splash rasters, WebP mipmaps,
  and the `src/main` Play Store PNG.

## 0.9.0

- Widened the `xml` constraint to `>=6.5.0 <8.0.0` so apps can depend on this
  package even when another dependency pins `xml` 6.x (e.g.
  `flutter_local_notifications`). The runtime `FasNativeSplash` uses no `xml`, so
  the app is unaffected; the generator dev-resolves to `xml` 7.x.
- Docs: call `FasNativeSplash.remove()` **right after `runApp()`**, not inside a
  post-frame callback — `deferFirstFrame` prevents that callback from firing, so
  `remove()` there would strand the app on the splash.

## 0.8.0

### Splash

- **`FasNativeSplash` now ships in the package** as a runtime API — import it and
  call `FasNativeSplash.preserve(widgetsBinding: …)` / `remove()` exactly like
  `flutter_native_splash`, instead of copying a generated file:

  ```dart
  import 'package:flutter_adaptive_studio/flutter_adaptive_studio.dart';
  ```

  The CLI no longer emits `fas_native_splash.dart` (it would collide with the
  imported class).

### Packaging (breaking)

- The package now depends on the Flutter SDK so it can expose the runtime API.
  Add it to `dependencies` (not `dev_dependencies`) if you use `FasNativeSplash`.
- The main library `package:flutter_adaptive_studio/flutter_adaptive_studio.dart`
  now exposes the **runtime** API (`FasNativeSplash`). The programmatic
  **generator** API moved to `package:flutter_adaptive_studio/generator.dart`.

## 0.7.0

### Splash

- New generated drop-in `flutter_adaptive_studio/splash/fas_native_splash.dart`
  with `FasNativeSplash.preserve({required widgetsBinding})` / `remove()` — keeps
  the native splash on screen through app startup (no white flash before your
  first screen is ready). Pure Flutter framework (`deferFirstFrame`/
  `allowFirstFrame`): no plugin, no native code, no extra dependencies. The
  signatures match `flutter_native_splash` for a drop-in migration.

## 0.6.0

### Android

- New `icon.image_format` option (`png` | `webp`): encode the generated launcher
  icon resources (legacy mipmaps + raster foreground density layers) as lossless
  WebP to shrink the app. The Play Store marketing icon is always PNG, per
  Google's requirement. Switching format cleans up the same-name file from the
  previous format so the two can't shadow each other.
- The Play Store icon is now written to `android/app/src/main/` (matching
  flutter_launcher_icons), not the `android/app` root; a copy left in the old
  location by earlier versions is removed.
- Fixed a "Duplicate resources" build failure: a stray
  `<color name="ic_launcher_background">` declared in another `values/*.xml`
  (e.g. an Android-Studio-generated `ic_launcher_background.xml`) is now stripped
  so `colors.xml` is the single source of truth.

## 0.5.0

### Docs

- Documented the short `fas` command across the example config + README and the
  `init` starter template (the `fas` alias itself shipped in 0.4.0).

## 0.4.0

### CLI

- Added a short `fas` executable alias. After
  `dart pub global activate flutter_adaptive_studio` you can run `fas generate`,
  `fas init`, etc. instead of typing the full package name.

## 0.3.0

### Android

- New `icon.legacy_padding` option: set the percent the composed legacy mipmap
  and Play Store art is inset, independently of `adaptive.safe_zone`. When
  unset, the legacy art keeps following the adaptive safe zone, and a finished
  `icon.image` keeps its own framing.

## 0.2.0

- Maintenance release (no functional changes).

## 0.1.0

First public release.

### Android

- Adaptive icons (API 26+) from SVG: foreground, background (colour or image),
  and **monochrome** Android 13 themed icon, with the art measured and fit into
  the adaptive safe zone for correct masking.
- Round icon, legacy mipmaps, and the 512² Play Store PNG.
- Opt-in full-colour light/dark icons via generated `activity-alias` wiring,
  with an optional per-variant background (`themed.background` /
  `themed.background_dark`) that overrides the adaptive background.
- Native Android 12 `SplashScreen`: your AnimatedVectorDrawable wired verbatim
  (`windowSplashScreenAnimatedIcon` + duration), a pre-31 classic splash, and a
  theme-following `FasSplash` Flutter fallback for older devices.
- Splash background image, icon background, bottom branding (200×80dp slot),
  gravity, fullscreen, and screen-orientation lock — all with dark variants.

### iOS

- Single-size 1024² `AppIcon.appiconset` (opaque) with iOS 18 **dark** and
  **tinted** appearance variants and a modern `Contents.json`.
- Launch screen: a patched `LaunchScreen.storyboard` driven by a
  `LaunchBackground` colour set and a `LaunchImage` image set (light/dark).
- iOS values fall back to the Android splash / root source, so one config can
  cover both platforms.

### Flavors

- A single `flavors:` map that deep-merges over the base config and writes to
  each flavor's Android resource overlay (`src/<flavor>/res`).
- A separate iOS `AppIcon-<flavor>` set, automatically wired into the flavor's
  build configurations (resolved from its scheme, falling back to the
  `Debug-<flavor>` convention).

### CLI

- `init`, `generate` (default), `doctor`, `preview`, and `revert` commands.
- `init` writes a fully-commented config documenting every option.
- Pure-Dart rasterization for all outputs — no system tools or FFI required.

# Changelog

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

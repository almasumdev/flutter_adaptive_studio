# Changelog

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

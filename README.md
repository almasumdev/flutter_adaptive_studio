# flutter_adaptive_studio

[![pub package](https://img.shields.io/pub/v/flutter_adaptive_studio.svg)](https://pub.dev/packages/flutter_adaptive_studio)

Vector-native, theme-aware, mask-correct launcher **icons** and a genuinely
**animated splash** for Flutter — generated the way native tooling does it, per
platform. A config-driven CLI that does what `flutter_launcher_icons` +
`flutter_native_splash` do, and fills the gaps both leave open.

One SVG drives **Android** (adaptive icon + native Android 12 splash + Flutter
fallback) and **iOS** (app icon + launch screen) — light, dark, and per-flavor.

## Why

The incumbents are raster-first: they resize one PNG and string-patch native
files. flutter_adaptive_studio is **vector-native**, so it can do things a
PNG pipeline can't:

- **Adaptive icons** (API 26+) straight from SVG — foreground / background /
  **monochrome** (Android 13 themed icon) — with the art measured and **fit into
  the adaptive safe zone**, so every launcher mask (circle, squircle, rounded
  square) looks right.
- **A real animated splash** — your AnimatedVectorDrawable is wired into the
  Android 12 `SplashScreen` API verbatim (`windowSplashScreenAnimatedIcon` +
  duration), with a pre-31 classic splash and a theme-following **Flutter
  fallback** widget for older devices. (`flutter_native_splash` feeds the
  "animated" slot a *static* image.)
- **iOS, modern** — a single-size 1024² app icon (Xcode 14+ generates every
  device size at build time) with iOS 18 **dark** and **tinted** variants, plus a
  `LaunchScreen.storyboard` driven by a colour set + logo image set (light/dark).
- **Flavors in one file** — a `flavors:` map that deep-merges over the base
  config and writes to each flavor's resource overlay (and, on iOS, wires the
  build configuration's app icon automatically).
- **Everything optional, great defaults.** A missing optional asset is skipped
  with a log line, never a hard failure. Native edits are structured (not blind
  string replacement) and most are undone by `revert`.

Pure-Dart throughout: adaptive icons and the animated splash are vector XML, and
raster outputs (legacy mipmaps, the Play Store PNG, iOS icons) are rendered by a
built-in rasterizer. **No system tools, no FFI, no setup.**

## Install

```sh
dart pub add dev:flutter_adaptive_studio
```

## Quick start

```sh
dart run flutter_adaptive_studio init       # write a fully-commented starter config
# edit flutter_adaptive_studio.yaml, drop your art in assets/, then:
dart run flutter_adaptive_studio generate
```

Prefer a shorter command? Activate it once and call `fas` from anywhere:

```sh
dart pub global activate flutter_adaptive_studio
fas init
fas generate
```

`init` writes a `flutter_adaptive_studio.yaml` documenting **every** option. A
minimal config:

```yaml
flutter_adaptive_studio:
  source: assets/logo.svg            # global fallback art

  android:
    icon:
      adaptive:
        foreground: assets/logo.svg
        background: "#E4ECE8"
        monochrome: assets/logo_mono.svg    # Android 13 themed icon
        safe_zone: fit                       # fit | inset:<pct> | none
      round: true
      play_store: true                       # 512² store icon
      legacy_padding: 15                     # % inset for legacy/store art (overrides safe_zone for these)
    splash:
      background: "#E4ECE8"
      background_dark: "#0C1413"
      image: assets/logo.svg                 # static logo (Flutter fallback + pre-31)
      animated_icon: assets/logo_anim.xml    # AnimatedVectorDrawable for Android 12+
      animated_icon_dark: assets/logo_anim_dark.xml
      branding: assets/wordmark.svg          # bottom branding (200×80dp slot)

  ios:
    icon:
      image: assets/logo.svg
      background: "#E4ECE8"                   # iOS icons must be opaque
      dark: assets/logo_dark.svg             # iOS 18 dark appearance
      tinted: assets/logo_mono.svg           # iOS 18 tinted appearance
    splash:
      background: "#E4ECE8"
      background_dark: "#0C1413"
      image: assets/logo.svg

  flavors:                                   # deep-merged over the base
    dev:
      android: { icon: { adaptive: { background: "#00C853" } } }
```

See [`example/`](example/) for a complete config + assets.

## Commands

```sh
dart run flutter_adaptive_studio <command> [options]   # local dev dependency
fas <command> [options]                                # after `dart pub global activate`
```

| Command    | What it does                                          |
| ---------- | ----------------------------------------------------- |
| `init`     | Write a fully-commented starter config                |
| `generate` | Generate icons + splash (the default command)         |
| `doctor`   | Validate the config and project                       |
| `preview`  | Write an HTML launcher-mask preview sheet             |
| `revert`   | Remove generated files                                |

Options: `-p/--project <path>`, `-c/--config <file>`, `-F/--flavor <name>`,
`-f/--force` (init), `-v/--verbose`, `-q/--quiet`.

## What it generates

**Android** — adaptive icon (`mipmap-anydpi-v26` + foreground/background/
monochrome drawables), round icon, legacy mipmaps, Play Store PNG; the Android 12
`SplashScreen` theme (`values-v31`, + `-night`) wired to your AVD, a pre-31
classic splash, and a drop-in `FasSplash` Flutter fallback; bottom branding.

**iOS** — `AppIcon.appiconset` (single-size 1024², light/dark/tinted) with a
modern `Contents.json`, a patched `LaunchScreen.storyboard`, and a
`LaunchBackground` colour set + `LaunchImage` image set. With `--flavor`, a
separate `AppIcon-<flavor>` set wired into the matching build configurations.

## Development

```sh
dart pub get
dart analyze
dart test
```

`example/` is the published usage sample. `reference/` (the two incumbent
packages, study-only), `example_2/` (a full dogfood app), `docs/`, and `tool/`
are excluded from the published package.

## License

[MIT](LICENSE).

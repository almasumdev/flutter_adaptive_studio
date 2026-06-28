<p align="center">
  <a href="https://pub.dev/packages/flutter_adaptive_studio"><img src="https://img.shields.io/pub/v/flutter_adaptive_studio.svg" alt="pub version"></a>
  <a href="https://pub.dev/packages/flutter_adaptive_studio/score"><img src="https://img.shields.io/pub/points/flutter_adaptive_studio" alt="pub points"></a>
  <a href="https://pub.dev/packages/flutter_adaptive_studio"><img src="https://img.shields.io/pub/likes/flutter_adaptive_studio" alt="pub likes"></a>
  <a href="https://github.com/almasumdev/flutter_adaptive_studio/stargazers"><img src="https://badgen.net/github/stars/almasumdev/flutter_adaptive_studio?icon=github" alt="GitHub stars"></a>
  <a href="https://github.com/almasumdev/flutter_adaptive_studio/network/members"><img src="https://badgen.net/github/forks/almasumdev/flutter_adaptive_studio?icon=github" alt="GitHub forks"></a>
  <a href="https://github.com/almasumdev/flutter_adaptive_studio/issues"><img src="https://badgen.net/github/open-issues/almasumdev/flutter_adaptive_studio?icon=github" alt="GitHub issues"></a>
  <a href="https://github.com/almasumdev/flutter_adaptive_studio/actions/workflows/ci.yml"><img src="https://github.com/almasumdev/flutter_adaptive_studio/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
  <a href="https://github.com/almasumdev/flutter_adaptive_studio/commits/main"><img src="https://badgen.net/github/last-commit/almasumdev/flutter_adaptive_studio?icon=github" alt="Last commit"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://dart.dev"><img src="https://img.shields.io/badge/Dart-3.6+-0175C2?logo=dart" alt="Dart"></a>
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-supported-02569B?logo=flutter" alt="Flutter"></a>
</p>

# Launcher Icons & Animated Splash Screen Generator for Flutter (Android & iOS)

**flutter_adaptive_studio** is a config-driven CLI that generates **launcher
icons** and **splash screens** for Flutter apps on **Android and iOS** from a
single SVG. It produces **adaptive icons** (foreground / background / monochrome
themed icon), legacy density mipmaps, the Play Store icon, iOS app icons (with
**dark** and **tinted** iOS 18 variants), a real **Android 12 animated
`SplashScreen`**, a bulletproof pre-31 splash, an iOS `LaunchScreen`, and a
drop-in **in-app Flutter splash** — all light/dark-aware and per-flavor. It does
what `flutter_launcher_icons` + `flutter_native_splash` do, and fills the gaps
both leave open.

> ⭐ **Find this useful?** [Star it on GitHub](https://github.com/almasumdev/flutter_adaptive_studio)
> and 👍 [like it on pub.dev](https://pub.dev/packages/flutter_adaptive_studio) —
> it helps other Flutter developers find a maintained icon + splash generator.

## Overview

flutter_adaptive_studio is **vector-native**: one SVG drives every output, so it
can do things a PNG-resize pipeline can't — measure your art and **fit it into
the adaptive safe zone** so every launcher mask looks right, and wire your
`AnimatedVectorDrawable` straight into the Android 12 `SplashScreen` API. Raster
outputs (legacy mipmaps, the Play Store PNG, iOS icons, the in-app splash bytes)
are produced by a built-in rasterizer. **No system tools, no native build step,
no plugin** — it's a pure-Dart generator plus a tiny Flutter runtime.

**What you can do with it:**

- Generate **Android adaptive icons** from SVG — foreground, background, and an Android 13 **monochrome themed** icon — fit to the adaptive safe zone for every mask.
- Generate **iOS app icons** — a single-size 1024² icon with iOS 18 **dark** and **tinted** variants and opaque compositing.
- Generate a real **Android 12 animated splash** (`windowSplashScreenAnimatedIcon`), a bulletproof pre-31 classic splash, and an **iOS `LaunchScreen`** — all light/dark aware.
- Drop an **in-app Flutter splash** (`AdaptiveSplash`) over your app that matches the native one and fades out — wrap your app once, nothing else to wire.
- Configure **flavors** in one file — a `flavors:` map deep-merges over the base and writes each flavor's resource overlay (and wires iOS build configs).

## Table of contents

- [Key features](#key-features)
- [Platform support](#platform-support)
- [Requirements & limitations](#requirements--limitations)
- [Roadmap](#roadmap)
- [Example](#example)
- [Other useful links](#other-useful-links)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Configuration](#configuration)
- [In-app splash (AdaptiveSplash)](#in-app-splash-adaptivesplash)
- [Keep the native splash up during startup](#keep-the-native-splash-up-during-startup)
- [Commands](#commands)
- [What it generates](#what-it-generates)
- [FAQ](#faq)
- [Support and feedback](#support-and-feedback)
- [About](#about)
  - [Contributors](#contributors)

## Key features

A complete launcher-icon + splash-screen toolkit for Android and iOS, driven by
one SVG-first config. Expand a group for details:

<details>
<summary><b>🎨 Android icons</b></summary>

- **Adaptive icons** (API 26+) — foreground / background / **monochrome** (Android 13 themed icon)
- **Safe-zone fit** — art measured and inset so every mask (circle, squircle, rounded square) looks right
- **Round** icon and the **512² Play Store** PNG
- **Legacy** density mipmaps for older launchers — **PNG or lossless WebP** (`image_format`)
- Optional **full-colour themed** light/dark icons (SVG source)

</details>

<details>
<summary><b>🍎 iOS icons</b></summary>

- Single-size **1024²** `AppIcon.appiconset` with a modern `Contents.json` (Xcode generates each device size at build)
- iOS 18 **dark** and **tinted** appearances
- **Opaque** compositing over a background colour (iOS icons can't be transparent)
- Per-**flavor** `AppIcon-<flavor>` set wired into the matching build configuration

</details>

<details>
<summary><b>✨ Native splash</b></summary>

- **Android 12 `SplashScreen`** — your `AnimatedVectorDrawable` wired verbatim (`windowSplashScreenAnimatedIcon` + duration), icon background, branding
- **Bulletproof pre-31** classic splash — centre logo rasterised to per-density PNG/WebP so it renders on Android 5–6 where a vector `windowBackground` won't
- **iOS `LaunchScreen.storyboard`** driven by a colour set + light/dark logo image set
- **Light / dark** everywhere (`-night` resources, iOS dark appearance)
- System **status / navigation bar** colour + icon brightness control

</details>

<details>
<summary><b>📱 In-app Flutter splash</b></summary>

- `AdaptiveSplash` — wrap your app once; it paints a splash matching the native one, holds while startup settles, then **fades out**
- Per-platform: matches the **iOS LaunchScreen** on iOS, the **Android splash** on Android
- Shows only where there's **no native animated splash** (Android API < 31) by default, or **force it on every version**
- Optional `ready` future — hold the splash until your async startup completes
- Zero assets, zero extra deps — artwork is **rasterised and base64-baked** into a generated file

</details>

<details>
<summary><b>🏷️ Branding & flavors</b></summary>

- Bottom **branding** — image wordmark or **text** (`branding_text`), placed bottom / bottom-left / bottom-right
- **Flavors in one file** — a `flavors:` map deep-merges over the base config and writes each flavor's resource overlay
- Full-bleed **background image** behind the splash logo

</details>

<details>
<summary><b>🛡️ Safe by default</b></summary>

- **Structured** native edits (real XML/plist parsing, not blind string replacement)
- **Idempotent** — re-run any time; existing wiring is detected, not duplicated
- A missing **optional** asset is skipped with a log line, never a hard failure
- **`revert`** undoes the generated files; **`doctor`** validates before you generate
- **`sync`** fills in newly-available config options without touching your values

</details>

## Platform support

Icons and splash behaviour differ by platform; here's what each one gets:

| Capability | Android | iOS |
|---|---|---|
| Launcher icon from SVG | ✅ adaptive (fg/bg) | ✅ 1024² |
| Round icon | ✅ | — |
| Monochrome / themed icon | ✅ (Android 13) | ✅ tinted (iOS 18) |
| Dark-appearance icon | — | ✅ (iOS 18) |
| Legacy density icons | ✅ 5 densities, PNG/WebP | n/a (Xcode generates) |
| Store icon | ✅ 512² Play Store | n/a |
| Native splash | ✅ Android 12 `SplashScreen` | ✅ `LaunchScreen.storyboard` |
| Animated splash icon | ✅ (AVD, API 31+) | ❌¹ |
| Pre-31 / legacy splash | ✅ classic `windowBackground` | n/a |
| Light / dark splash | ✅ (`-night`) | ✅ |
| Splash branding (image / text) | ✅ | ❌¹ |
| In-app Flutter splash (`AdaptiveSplash`) | ✅ | ✅ |
| Flavors | ✅ resource overlay | ✅ build-config wiring |

¹ iOS launch screens are **static** by Apple's design — there is no animated
launch API and no launch-screen branding. The motion + branding on iOS come from
the in-app `AdaptiveSplash`.

## Requirements & limitations

- **Android splash needs `compileSdk 34`.** The Android 12 `SplashScreen` styles
  reference API 31+ attributes. If your build fails with
  `windowSplashScreen… not found`, set `compileSdk` to 34 in
  `android/app/build.gradle`. (The generator also prints this reminder.)
- **iOS launch screens are static** — Apple has no animated launch API. Use the
  in-app `AdaptiveSplash` for motion/branding on iOS.
- **Full-colour themed light/dark icons require an SVG source** (they're skipped
  with a log line for raster sources). The Android 13 **monochrome** themed icon
  is always supported.
- **`branding_mode` and `background_image`** apply to the **pre-31** splash and
  the **in-app** splash. The Android 12 system splash always bottom-centres its
  branding and has no full-bleed background (OS behaviour).

## Roadmap

What's shipped and what's next — [contributions](#support-and-feedback) welcome.

**Shipped**

- ✅ Android **adaptive icons** (foreground / background / monochrome) with safe-zone fit
- ✅ Round icon, **512² Play Store** PNG, legacy mipmaps (PNG / **WebP**)
- ✅ iOS **1024²** app icon with iOS 18 **dark** + **tinted** variants
- ✅ Android 12 **animated `SplashScreen`** + bulletproof **pre-31** classic splash
- ✅ iOS **`LaunchScreen.storyboard`** + colour set + light/dark logo image set
- ✅ **In-app `AdaptiveSplash`** — wrap-your-app Flutter splash, native-matched, fades out
- ✅ `FasNativeSplash.preserve()/remove()` — keep the native splash up through startup
- ✅ Branding (image **or** text), full-bleed background image, system bar colours
- ✅ **Flavors** in one file (deep-merge + iOS build-config wiring)
- ✅ `init` / `sync` / `generate` / `doctor` / `preview` / `revert` commands

**Planned**

- ⬜ Full-colour themed icons from raster sources
- ⬜ macOS / Windows / Linux icon targets
- ⬜ Richer launcher-mask preview sheet

## Example

A complete, runnable sample lives in the
[`example/`](https://github.com/almasumdev/flutter_adaptive_studio/tree/main/example)
directory — a config + assets and a wired-up `AdaptiveSplash` app. Clone the
repository and run it, or copy any snippet from [Quick start](#quick-start)
below.

## Other useful links

- [API reference](https://pub.dev/documentation/flutter_adaptive_studio/latest/)
- [Source code on GitHub](https://github.com/almasumdev/flutter_adaptive_studio)
- [Changelog](https://github.com/almasumdev/flutter_adaptive_studio/blob/main/CHANGELOG.md)
- [Issue tracker](https://github.com/almasumdev/flutter_adaptive_studio/issues)

## Installation

```bash
flutter pub add flutter_adaptive_studio
```

Keep it in `dependencies` if you use the runtime widgets (`AdaptiveSplash` /
`FasNativeSplash`). If you only run the generator CLI, a dev dependency is
enough:

```bash
flutter pub add dev:flutter_adaptive_studio
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

## Configuration

`init` writes a `flutter_adaptive_studio.yaml` documenting **every** option;
`sync` adds newly-available options to an existing config without touching your
values. A representative config:

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
      play_store: true                       # 512² store icon (always PNG)
      legacy_padding: 15                     # % inset for legacy/store art
      image_format: webp                     # png (default) | webp
    splash:
      background: "#E4ECE8"
      background_dark: "#0C1413"
      image: assets/logo.svg                 # static logo (in-app + pre-31)
      image_format: png                      # png (default) | webp
      animated_icon: assets/logo_anim.xml    # AnimatedVectorDrawable, Android 12+
      animated_icon_dark: assets/logo_anim_dark.xml
      branding: assets/wordmark.svg          # bottom branding (or branding_text:)
      status_bar_color: transparent          # hex | transparent
      navigation_bar_color: "#E4ECE8"
      navigation_bar_color_dark: "#0C1413"
      status_bar_icon_brightness: dark       # dark | light (auto from colour if unset)

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

See [`example/`](https://github.com/almasumdev/flutter_adaptive_studio/tree/main/example)
for a complete config + assets.

## In-app splash (AdaptiveSplash)

Running `generate` writes `lib/fas_splash.g.dart` — a generated `fasSplash`
config with your colours, the rasterised logo bytes, branding, and timing all
baked in. Wrap your app once and the package does the rest: it paints a splash
that **matches the native one**, holds briefly while your first screen settles,
then **fades out**.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_adaptive_studio/flutter_adaptive_studio.dart';
import 'fas_splash.g.dart'; // generated — provides `fasSplash`

void main() {
  runApp(AdaptiveSplash(config: fasSplash, child: const MyApp()));
}
```

By default the in-app splash shows only **where there's no native animated
splash** — i.e. Android API < 31 (on API 31+ the system `SplashScreen` already
covered startup, and on iOS the LaunchScreen did). Force it on every version, or
hold it until async startup finishes:

```dart
AdaptiveSplash(
  config: fasSplash,
  force: true,            // show on every OS version (overrides the config)
  ready: bootstrap(),     // hold until this future completes (and duration elapses)
  child: const MyApp(),
);
```

On iOS it automatically matches your iOS `LaunchScreen` (its own background /
logo / size); on Android it matches the Android splash, including branding.

## Keep the native splash up during startup

`FasNativeSplash` is the `flutter_native_splash`-style `preserve`/`remove`, so
the native splash stays on screen until your app is ready — no white flash
before your first frame. Pure Flutter framework; works on every platform.

```dart
import 'package:flutter_adaptive_studio/flutter_adaptive_studio.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FasNativeSplash.preserve(widgetsBinding: binding);
  await loadEverything();       // your startup work — keep it short
  runApp(const MyApp());
  FasNativeSplash.remove();      // call right after runApp(), NOT in a
                                // post-frame callback (it won't fire while
                                // the first frame is deferred)
}
```

Migrating from `flutter_native_splash`? The signatures match — swap the import
and the class name.

## Commands

```sh
dart run flutter_adaptive_studio <command> [options]   # local dev dependency
fas <command> [options]                                # after `dart pub global activate`
```

| Command    | What it does                                          |
| ---------- | ----------------------------------------------------- |
| `init`     | Write a fully-commented starter config                |
| `sync`     | Add newly-available options to an existing config (commented; keeps your values) |
| `generate` | Generate icons + splash (the default command)         |
| `doctor`   | Validate the config and project                       |
| `preview`  | Write an HTML launcher-mask preview sheet             |
| `revert`   | Remove generated files                                |

Options: `-p/--project <path>`, `-c/--config <file>`, `-F/--flavor <name>`,
`-f/--force` (init), `-v/--verbose`, `-q/--quiet`.

## What it generates

**Android** — adaptive icon (`mipmap-anydpi-v26` + foreground/background/
monochrome drawables), round icon, legacy mipmaps (PNG or, with
`image_format: webp`, lossless WebP), and the 512² Play Store PNG; the Android 12
`SplashScreen` theme (`values-v31`, + `-night`) wired to your AVD, a bulletproof
pre-31 classic splash (centre logo rasterised to per-density PNG/WebP so it
renders on Android 5–6, where a vector `windowBackground` won't), bottom
branding, and `lib/fas_splash.g.dart` for the in-app `AdaptiveSplash`.

**iOS** — `AppIcon.appiconset` (single-size 1024², light/dark/tinted) with a
modern `Contents.json`, a patched `LaunchScreen.storyboard`, and a
`LaunchBackground` colour set + `LaunchImage` image set. With `--flavor`, a
separate `AppIcon-<flavor>` set wired into the matching build configurations.

## FAQ

**How is this different from `flutter_launcher_icons` + `flutter_native_splash`?**
Those are raster-first — they resize one PNG and string-patch native files.
flutter_adaptive_studio is **vector-native**: it fits adaptive icons into the
safe zone from SVG, wires a *real* `AnimatedVectorDrawable` into the Android 12
`SplashScreen` API (where `flutter_native_splash` feeds the "animated" slot a
static image), and ships a matching in-app Flutter splash. One config covers
icons **and** splash for both platforms.

**Do I need to install ImageMagick or any native tooling?**
No. It's pure Dart — adaptive icons and the animated splash are vector XML, and
raster outputs are produced by a built-in rasterizer. No system tools, no native
build step, no plugin.

**My Android build fails with `windowSplashScreen… not found`.**
Set `compileSdk` to 34 in `android/app/build.gradle`. The Android 12 splash
styles reference API 31+ attributes; see [Requirements & limitations](#requirements--limitations).

**Can I have an animated splash on iOS?**
The native iOS launch screen is static by Apple's design. Use the in-app
`AdaptiveSplash` for motion (and branding) on iOS — it matches your
`LaunchScreen` and fades into the app.

**Do I have to wrap my app with `AdaptiveSplash`?**
No — it's optional. If you only want native icons + splash, just run `generate`
and ignore `fas_splash.g.dart`. Wrapping with `AdaptiveSplash` adds the
native-matched, fade-out in-app splash (and covers Android < 31, which has no
system splash).

**Does re-running `generate` clobber my project?**
No. Native edits are structured (real XML/plist parsing) and **idempotent** — it
detects existing wiring instead of duplicating it. `revert` removes the
generated files, and `doctor` validates before you generate.

**Can I use raster (PNG) art instead of SVG?**
Yes for most outputs. SVG is required only for the optional full-colour themed
light/dark icons; everything else accepts PNG/JPEG/WebP (you lose the vector
crispness and safe-zone fitting on rasters).

## Support and feedback

- Found a bug or want a feature? Open an issue on the
  [issue tracker](https://github.com/almasumdev/flutter_adaptive_studio/issues).
- Questions and ideas are welcome via
  [GitHub Discussions](https://github.com/almasumdev/flutter_adaptive_studio/discussions).
- Pull requests are welcome — see the repository for contribution guidelines.

## About

flutter_adaptive_studio is an open-source, MIT-licensed, config-driven CLI that
generates launcher icons and splash screens for Flutter on Android and iOS from a
single SVG — adaptive icons, iOS app icons, a real Android 12 animated splash, an
iOS launch screen, and a matching in-app Flutter splash, all light/dark-aware and
per-flavor.

flutter_adaptive_studio is created and owned by **Nurullah Al Masum**.

### Contributors

flutter_adaptive_studio grows with its community — every contributor is listed here:

<a href="https://github.com/almasumdev/flutter_adaptive_studio/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=almasumdev/flutter_adaptive_studio" alt="flutter_adaptive_studio contributors"/>
</a>

Want to help? Pull requests are welcome — see [Support and feedback](#support-and-feedback).

## License

[MIT](LICENSE).

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

# Flutter Launcher Icons & Animated Splash Screen Generator (Android & iOS)

**flutter_adaptive_studio** is a config-driven CLI that generates **launcher icons**
and **splash screens** for Flutter apps on **Android and iOS** from a single SVG.
It produces **adaptive icons** (foreground, background, and an Android 13 monochrome
themed icon), legacy density mipmaps, the Play Store icon, **iOS app icons** with
**dark** and **tinted** iOS 18 variants, a real **Android 12 animated `SplashScreen`**,
a reliable pre-31 splash, an iOS `LaunchScreen`, and a drop-in **in-app Flutter
splash**. Everything is light and dark aware and works per flavor. It covers what
`flutter_launcher_icons` and `flutter_native_splash` do together, and fills the
gaps both leave open.

> ⭐ **Find this useful?** [Star it on GitHub](https://github.com/almasumdev/flutter_adaptive_studio)
> and 👍 [like it on pub.dev](https://pub.dev/packages/flutter_adaptive_studio) so other
> Flutter developers can find a maintained icon and splash generator.

## Overview

flutter_adaptive_studio is **vector native**. One SVG drives every output, so it can
do things a PNG-resize pipeline cannot. It measures your art and **fits it into the
adaptive safe zone** so every launcher mask looks right, and it wires your
`AnimatedVectorDrawable` straight into the Android 12 `SplashScreen` API. Raster
outputs (legacy mipmaps, the Play Store PNG, iOS icons, the in-app splash bytes) come
from a built-in rasterizer. There are **no system tools, no native build step, and no
plugin**. It is a pure-Dart generator plus a tiny Flutter runtime.

**What you can do with it:**

- Generate **Android adaptive icons** from SVG (foreground, background, and an Android 13 monochrome themed icon), fit to the adaptive safe zone for every mask.
- Generate **iOS app icons**: a single-size 1024² icon with iOS 18 dark and tinted variants and opaque compositing.
- Generate a real **Android 12 animated splash** (`windowSplashScreenAnimatedIcon`), a reliable pre-31 classic splash, and an **iOS `LaunchScreen`**, all light and dark aware.
- Drop an **in-app Flutter splash** (`AdaptiveSplash`) over your app that matches the native one and fades out. Wrap your app once, nothing else to wire.
- Configure **flavors** in one file. A `flavors:` map deep-merges over the base config and writes each flavor's resource overlay.

## Platform support

Icons and splash behavior differ by platform. Here is what each one gets:

| Capability | Android | iOS |
|---|---|---|
| Launcher icon from SVG | ✅ adaptive (fg/bg) | ✅ 1024² |
| Round icon | ✅ | n/a |
| Monochrome / themed icon | ✅ (Android 13) | ✅ tinted (iOS 18) |
| Dark-appearance icon | n/a | ✅ (iOS 18) |
| Legacy density icons | ✅ 5 densities, PNG/WebP | n/a (Xcode generates) |
| Store icon | ✅ 512² Play Store | n/a |
| Native splash | ✅ Android 12 `SplashScreen` | ✅ `LaunchScreen.storyboard` |
| Animated splash icon | ✅ (AVD, API 31+) | ❌¹ |
| Pre-31 / legacy splash | ✅ classic `windowBackground` | n/a |
| Light / dark splash | ✅ (`-night`) | ✅ |
| Splash branding (image / text) | ✅ | ❌¹ |
| In-app Flutter splash (`AdaptiveSplash`) | ✅ | ✅ |
| Flavors | ✅ resource overlay | ✅ build-config wiring |

¹ iOS launch screens are **static** by Apple's design. There is no animated launch
API and no launch-screen branding. Motion and branding on iOS come from the in-app
`AdaptiveSplash`.

## Table of contents

- [Key features](#key-features)
- [Requirements & limitations](#requirements--limitations)
- [Roadmap](#roadmap)
- [Example](#example)
- [Other useful links](#other-useful-links)
- [Installation](#installation)
- [Getting started](#getting-started)
  - [Quick start](#quick-start)
  - [Configuration](#configuration)
  - [In-app splash (AdaptiveSplash)](#in-app-splash-adaptivesplash)
  - [Keep the native splash up during startup](#keep-the-native-splash-up-during-startup)
  - [Commands](#commands)
  - [What it generates](#what-it-generates)
- [Comparison with flutter_launcher_icons & flutter_native_splash](#comparison-with-flutter_launcher_icons--flutter_native_splash)
- [Migrating from flutter_native_splash](#migrating-from-flutter_native_splash)
- [FAQ](#faq)
- [Support and feedback](#support-and-feedback)
- [About](#about)
  - [Contributors](#contributors)

## Key features

A complete launcher-icon and splash-screen toolkit for Android and iOS, driven by
one SVG-first config. Expand a group for details:

<details>
<summary><b>🎨 Android icons</b></summary>

- Adaptive icons (API 26+): foreground, background, and an Android 13 monochrome themed icon
- Safe-zone fit: art is measured and inset so every mask (circle, squircle, rounded square) looks right
- Round icon and the 512² Play Store PNG
- Legacy density mipmaps for older launchers, as PNG or lossless WebP (`image_format`)
- Optional full-color themed light and dark icons from an SVG source

</details>

<details>
<summary><b>🍎 iOS icons</b></summary>

- Single-size 1024² `AppIcon.appiconset` with a modern `Contents.json` (Xcode generates each device size at build)
- iOS 18 dark and tinted appearances
- Opaque compositing over a background color, since iOS icons cannot be transparent
- Per-flavor `AppIcon-<flavor>` set wired into the matching build configuration

</details>

<details>
<summary><b>✨ Native splash</b></summary>

- Android 12 `SplashScreen`: your `AnimatedVectorDrawable` wired verbatim (`windowSplashScreenAnimatedIcon` plus duration), icon background, and branding
- Reliable pre-31 classic splash: the center logo is rasterized to a per-density PNG or WebP so it renders on Android 5 and 6, where a vector `windowBackground` will not
- iOS `LaunchScreen.storyboard` driven by a color set plus a light and dark logo image set
- Light and dark everywhere (`-night` resources, iOS dark appearance)
- System status and navigation bar color plus icon-brightness control

</details>

<details>
<summary><b>📱 In-app Flutter splash</b></summary>

- `AdaptiveSplash`: wrap your app once and it paints a splash matching the native one, holds while startup settles, then fades out
- Per platform: matches the iOS `LaunchScreen` on iOS and the Android splash on Android
- Shows only where there is no native animated splash (Android API < 31) by default, or force it on every version
- Optional `ready` future to hold the splash until your async startup finishes
- Zero assets and zero extra dependencies: the artwork is rasterized and base64-baked into a generated file

</details>

<details>
<summary><b>🏷️ Branding & flavors</b></summary>

- Bottom branding as an image wordmark or as text (`branding_text`), placed bottom, bottom-left, or bottom-right
- Flavors in one file: a `flavors:` map deep-merges over the base config and writes each flavor's resource overlay
- Full-bleed background image behind the splash logo

</details>

<details>
<summary><b>🛡️ Safe by default</b></summary>

- Structured native edits with real XML and plist parsing, not blind string replacement
- Idempotent: re-run any time and existing wiring is detected, not duplicated
- A missing optional asset is skipped with a log line, never a hard failure
- `revert` undoes the generated files and `doctor` validates before you generate
- `sync` fills in newly-available config options without touching your values

</details>

## Requirements & limitations

- **Android splash needs `compileSdk 34`.** The Android 12 `SplashScreen` styles
  reference API 31+ attributes. If your build fails with `windowSplashScreen… not
  found`, set `compileSdk` to 34 in `android/app/build.gradle`. The generator also
  prints this reminder.
- **iOS launch screens are static.** Apple has no animated launch API. Use the in-app
  `AdaptiveSplash` for motion and branding on iOS.
- **The generated in-app splash targets Android and iOS.** Its Android-API gate uses
  `dart:ffi`, which is not available on web. If your app also targets web, guard the
  `AdaptiveSplash` usage, or it is a no-op there.
- **Full-color themed light and dark icons require an SVG source.** They are skipped
  with a log line for raster sources. The Android 13 monochrome themed icon is always
  supported.
- **`branding_mode` and `background_image` apply to the pre-31 splash and the in-app
  splash.** The Android 12 system splash always bottom-centers its branding and has no
  full-bleed background, which is OS behavior.

## Roadmap

Direction is driven by what users request on the
[issue tracker](https://github.com/almasumdev/flutter_adaptive_studio/issues):

- ⬜ Full-color themed icons from raster sources
- ⬜ macOS, Windows, and Linux icon targets
- ⬜ Richer launcher-mask preview sheet

Shipped milestones are in the
[changelog](https://github.com/almasumdev/flutter_adaptive_studio/blob/main/CHANGELOG.md).

## Example

A complete, runnable sample lives in the
[`example/`](https://github.com/almasumdev/flutter_adaptive_studio/tree/main/example)
directory: a config, assets, and a wired-up `AdaptiveSplash` app. Clone the repository
and run it, or copy any snippet from [Getting started](#getting-started) below.

## Other useful links

- [API reference](https://pub.dev/documentation/flutter_adaptive_studio/latest/)
- [Source code on GitHub](https://github.com/almasumdev/flutter_adaptive_studio)
- [Changelog](https://github.com/almasumdev/flutter_adaptive_studio/blob/main/CHANGELOG.md)
- [Issue tracker](https://github.com/almasumdev/flutter_adaptive_studio/issues)

## Installation

This is a **pure-Dart command-line tool**. Install it globally and run it from any
Flutter project, and your app gets **no dependency on this package**:

```bash
dart pub global activate flutter_adaptive_studio
```

> Global activation keeps the generator's build-time dependencies (`image`, `xml`,
> and so on) out of your app's resolution entirely, so they can never conflict with
> your app's packages. You can instead add it as a `dev_dependency` and run `dart run
> flutter_adaptive_studio …`, but then those dependencies participate in your app's
> resolution.

## Getting started

### Quick start

```sh
fas init        # write a fully-commented starter config
# edit flutter_adaptive_studio.yaml, drop your art in assets/, then:
fas generate    # writes native icons and splash, plus lib/fas_splash.g.dart
```

`fas` is the short alias from `dart pub global activate`. The full name
`flutter_adaptive_studio` works too.

### Configuration

`init` writes a `flutter_adaptive_studio.yaml` that documents every option. `sync`
adds newly-available options to an existing config without touching your values. A
representative config:

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
      legacy_padding: 15                     # % inset for legacy and store art
      image_format: webp                     # png (default) | webp
    splash:
      background: "#E4ECE8"
      background_dark: "#0C1413"
      image: assets/logo.svg                 # static logo (in-app + pre-31)
      animated_icon: assets/logo_anim.xml    # AnimatedVectorDrawable, Android 12+
      animated_icon_dark: assets/logo_anim_dark.xml
      branding: assets/wordmark.svg          # bottom branding (or branding_text:)
      status_bar_color: transparent          # hex | transparent
      navigation_bar_color: "#E4ECE8"
      status_bar_icon_brightness: dark       # dark | light (auto from color if unset)

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
for a complete config and assets.

### In-app splash (AdaptiveSplash)

Running `generate` writes `lib/fas_splash.g.dart`, a **self-contained** file that
holds the `fasSplash` config (colors, rasterized logo bytes, branding, timing) and
the `AdaptiveSplash` widget itself. It imports only `package:flutter`, so your app
depends on nothing from us. Wrap your app once and it paints a splash that matches the
native one, holds briefly while your first screen settles, then fades out.

```dart
import 'package:flutter/material.dart';

import 'fas_splash.g.dart'; // generated: provides fasSplash + AdaptiveSplash

void main() {
  runApp(AdaptiveSplash(config: fasSplash, child: const MyApp()));
}
```

By default the in-app splash shows only where there is no native animated splash,
which means Android API < 31. On API 31+ the system `SplashScreen` already covered
startup, and on iOS the `LaunchScreen` did. You can force it on every version, or hold
it until async startup finishes:

```dart
AdaptiveSplash(
  config: fasSplash,
  force: true,            // show on every OS version (overrides the config)
  ready: bootstrap(),     // hold until this future completes and the duration elapses
  child: const MyApp(),
);
```

On iOS it matches your iOS `LaunchScreen` (its own background, logo, and size). On
Android it matches the Android splash, including branding.

### Keep the native splash up during startup

`FasNativeSplash` is a `flutter_native_splash`-style `preserve` and `remove`, so the
native splash stays on screen until your app is ready, with no white flash before your
first frame. It is generated into `fas_splash.g.dart` alongside the splash, so it is
there once you have run `generate` and there is nothing extra to add.

```dart
import 'fas_splash.g.dart'; // FasNativeSplash is generated alongside AdaptiveSplash

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FasNativeSplash.preserve(widgetsBinding: binding);
  await loadEverything();        // your startup work, keep it short
  runApp(const MyApp());
  FasNativeSplash.remove();       // call right after runApp(), not in a post-frame
                                 // callback (it will not fire while the first frame
                                 // is deferred)
}
```

Migrating from `flutter_native_splash`? The `preserve` and `remove` signatures match,
so you point the import at the generated `fas_splash.g.dart` and rename the class.

### Commands

```sh
fas <command> [options]                                # after global activate
dart run flutter_adaptive_studio <command> [options]   # as a dev dependency
```

| Command    | What it does                                          |
| ---------- | ----------------------------------------------------- |
| `init`     | Write a fully-commented starter config                |
| `sync`     | Add newly-available options to an existing config (commented, keeps your values) |
| `generate` | Generate icons and splash (the default command)       |
| `doctor`   | Validate the config and environment                   |
| `preview`  | Write an HTML launcher-mask preview sheet             |
| `revert`   | Remove generated files                                |

Options: `-p/--project <path>`, `-c/--config <file>`, `-F/--flavor <name>`,
`-f/--force` (init), `-v/--verbose`, `-q/--quiet`, `-h/--help`.

Run `fas --help` (or `fas -h`) at any time to print the command list and every
option from the terminal. `fas init` also writes a fully-commented config, so the
options are documented right in your project.

### What it generates

**Android:** the adaptive icon (`mipmap-anydpi-v26` plus foreground, background, and
monochrome drawables), the round icon, legacy mipmaps (PNG, or lossless WebP with
`image_format: webp`), and the 512² Play Store PNG. For the splash, the Android 12
`SplashScreen` theme (`values-v31`, plus `-night`) wired to your AVD, a reliable pre-31
classic splash (the center logo rasterized to a per-density PNG or WebP so it renders
on Android 5 and 6, where a vector `windowBackground` will not), bottom branding, and
`lib/fas_splash.g.dart` for the in-app `AdaptiveSplash`.

**iOS:** the `AppIcon.appiconset` (single-size 1024², light, dark, and tinted) with a
modern `Contents.json`, a patched `LaunchScreen.storyboard`, and a `LaunchBackground`
color set plus a `LaunchImage` image set. With `--flavor`, a separate
`AppIcon-<flavor>` set wired into the matching build configurations.

## Comparison with flutter_launcher_icons & flutter_native_splash

`flutter_launcher_icons` and `flutter_native_splash` are raster-first: they resize one
PNG and string-patch native files. flutter_adaptive_studio is vector-native and covers
icons and splash for both platforms from one config.

| Capability | flutter_adaptive_studio | flutter_launcher_icons | flutter_native_splash |
|---|---|---|---|
| Covers | Icons and splash, one config | Icons only | Splash only |
| Source art | SVG, measured and mask-fit | PNG, resized | PNG |
| Adaptive safe-zone fit | Automatic, from the SVG | Manual padding | n/a |
| Android 12 animated splash | Real `AnimatedVectorDrawable` | n/a | Static image in the animated slot |
| iOS 18 dark and tinted icons | Yes | No | n/a |
| In-app Flutter splash | `AdaptiveSplash`, native-matched | No | Native keep-up only |
| Native file edits | Parsed XML and plist | String replace | String replace |
| Flavors | One file, deep-merge | Per-flavor config | Per-flavor config |
| App runtime dependency | None | None | Added for keep-up |

## Migrating from flutter_native_splash

flutter_adaptive_studio can take over both the icons and the splash:

1. Add your art and a `flutter_adaptive_studio.yaml` (run `fas init` for a starter),
   then run `fas generate`. It writes the native icon and splash files plus
   `lib/fas_splash.g.dart`.
2. If you used `flutter_native_splash`'s `preserve` and `remove` to hold the native
   splash through startup, switch to `FasNativeSplash`. The method names and signatures
   match, so point the import at the generated `fas_splash.g.dart` and rename the class:

```dart
// Before
import 'package:flutter_native_splash/flutter_native_splash.dart';
FlutterNativeSplash.preserve(widgetsBinding: binding);
FlutterNativeSplash.remove();

// After
import 'fas_splash.g.dart';
FasNativeSplash.preserve(widgetsBinding: binding);
FasNativeSplash.remove();
```

3. Re-running `generate` takes over the iOS `LaunchScreen` and the Android splash. On
   iOS it points the launch background at a color set and clears the previous
   full-screen launch image, so nothing from the old setup shadows your new background.

## FAQ

**How is this different from `flutter_launcher_icons` and `flutter_native_splash`?**
Those are raster-first: they resize one PNG and string-patch native files.
flutter_adaptive_studio is vector-native. It fits adaptive icons into the safe zone
from SVG, wires a real `AnimatedVectorDrawable` into the Android 12 `SplashScreen` API
(where `flutter_native_splash` feeds the "animated" slot a static image), and ships a
matching in-app Flutter splash. One config covers icons and splash for both platforms.

**Do I need to install ImageMagick or any native tooling?**
No. It is pure Dart. Adaptive icons and the animated splash are vector XML, and raster
outputs come from a built-in rasterizer. There are no system tools, no native build
step, and no plugin.

**My Android build fails with `windowSplashScreen… not found`.**
Set `compileSdk` to 34 in `android/app/build.gradle`. The Android 12 splash styles
reference API 31+ attributes. See
[Requirements & limitations](#requirements--limitations).

**Can I have an animated splash on iOS?**
The native iOS launch screen is static by Apple's design. Use the in-app
`AdaptiveSplash` for motion and branding on iOS. It matches your `LaunchScreen` and
fades into the app.

**Do I have to wrap my app with `AdaptiveSplash`?**
No, it is optional. If you only want native icons and splash, run `generate` and ignore
`fas_splash.g.dart`. Wrapping with `AdaptiveSplash` adds the native-matched, fade-out
in-app splash and covers Android < 31, which has no system splash.

**Does re-running `generate` clobber my project?**
No. Native edits are structured with real XML and plist parsing, and they are
idempotent, so existing wiring is detected instead of duplicated. `revert` removes the
generated files, and `doctor` validates before you generate.

**Can I use raster (PNG) art instead of SVG?**
Yes for most outputs. SVG is required only for the optional full-color themed light and
dark icons. Everything else accepts PNG, JPEG, or WebP, though you lose the vector
crispness and safe-zone fitting on rasters.

## Support and feedback

- Found a bug or want a feature? Open an issue on the
  [issue tracker](https://github.com/almasumdev/flutter_adaptive_studio/issues).
- Questions and ideas are welcome via
  [GitHub Discussions](https://github.com/almasumdev/flutter_adaptive_studio/discussions).
- Pull requests are welcome. See the repository for contribution guidelines.

## About

flutter_adaptive_studio is an open-source, MIT-licensed, config-driven CLI that
generates launcher icons and splash screens for Flutter on Android and iOS from a
single SVG: adaptive icons, iOS app icons, a real Android 12 animated splash, an iOS
launch screen, and a matching in-app Flutter splash, all light and dark aware and per
flavor.

flutter_adaptive_studio is created and owned by **Nurullah Al Masum**.

### Contributors

flutter_adaptive_studio grows with its community. Every contributor is listed here:

<a href="https://github.com/almasumdev/flutter_adaptive_studio/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=almasumdev/flutter_adaptive_studio" alt="flutter_adaptive_studio contributors"/>
</a>

Want to help? Pull requests are welcome. See [Support and feedback](#support-and-feedback).

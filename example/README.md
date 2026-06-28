# flutter_adaptive_studio — example

A **runnable** Flutter app that demonstrates the in-app splash (`AdaptiveSplash`)
and doubles as a showcase of what the generator produces from one set of SVG
sources.

## Run it

```sh
cd example
flutter pub get
dart run flutter_adaptive_studio generate   # writes the icons, native splash, and lib/fas_splash.g.dart
flutter run
```

On launch you'll see the native splash hand off seamlessly to `AdaptiveSplash`
(same background + logo + branding), which holds briefly and fades to the home
screen. Tap **Replay splash** to see it again; toggle your **system dark mode**
and replay to see the `-night` variant.

> The example config sets `flutter_splash_all_versions: true`, so the in-app
> splash shows even on a modern (API ≥ 31) emulator. In a real app you'd usually
> leave it off, so `AdaptiveSplash` only fills the gap on Android < 31.

## The entire integration

That's the whole thing — wrap your app once ([lib/main.dart](lib/main.dart)):

```dart
import 'package:flutter_adaptive_studio/flutter_adaptive_studio.dart';
import 'fas_splash.g.dart';

void main() => runApp(AdaptiveSplash(config: fasSplash, child: const MyApp()));
```

No assets to declare, no `flutter_svg`, no `device_info_plus`: the logo and
branding are rasterised and baked into `lib/fas_splash.g.dart` by `generate`.

## Sources it generates from

- [`flutter_adaptive_studio.yaml`](flutter_adaptive_studio.yaml) — the config
- `assets/` — the SVG/AVD/PNG sources it references:
  - `listkin_logo.svg`, `listkin_logo_dark.svg`, `listkin_logo_mono.svg` — the mark (light / dark / monochrome)
  - `avd_listkin_light.xml`, `avd_listkin_dark.xml` — AnimatedVectorDrawables for the native Android 12 splash
  - `wordmark.svg`, `wordmark_dark.svg` — bottom splash branding
  - `icon.png` — finished raster, used for legacy mipmaps + the Play Store icon

## What `generate` produces

- **In-app splash** — `lib/fas_splash.g.dart` (the `FasSplashConfig` consumed by
  the package's `AdaptiveSplash`), with the logo/branding base64-embedded.
- **Android** — adaptive icon (foreground + background + monochrome themed icon),
  round icon, legacy mipmaps, Play Store PNG; the native Android 12 `SplashScreen`
  with the AnimatedVectorDrawable (light/dark) and a bulletproof pre-31
  `windowBackground` splash.
- **iOS** — a 1024² app icon with iOS 18 dark + tinted variants, and a
  `LaunchScreen.storyboard` driven by a colour set + logo image set (light/dark).
- **Flavors** — `dart run flutter_adaptive_studio generate --flavor dev` writes
  Android resources to `src/dev/res` and a separate `AppIcon-dev` set,
  deep-merging the `flavors.dev` overrides over the base.

## Other commands

```sh
dart run flutter_adaptive_studio doctor     # validate config + project
dart run flutter_adaptive_studio sync       # add newly-released config options (commented)
dart run flutter_adaptive_studio preview    # HTML launcher-mask preview
dart run flutter_adaptive_studio revert     # remove generated files
```

Prefer a shorter command? `dart pub global activate flutter_adaptive_studio`
once, then use `fas` in place of `dart run flutter_adaptive_studio`.

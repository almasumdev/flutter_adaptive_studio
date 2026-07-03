# flutter_adaptive_studio: example

A **runnable** Flutter app that demonstrates the in-app splash (`AdaptiveSplash`)
and doubles as a showcase of what the generator produces from a single icon
source.

## Run it

```sh
cd example
flutter pub get
dart run flutter_adaptive_studio generate   # writes the icons, native splash, and lib/fas_splash.g.dart
flutter run
```

On launch you'll see the native splash hand off seamlessly to `AdaptiveSplash`
(same background + logo), which holds briefly and fades to the home
screen. Tap **Replay splash** to see it again; toggle your **system dark mode**
and replay to see the `-night` variant.

> The example config sets `flutter_splash_all_versions: true`, so the in-app
> splash shows even on a modern (API ≥ 31) emulator. In a real app you'd usually
> leave it off, so `AdaptiveSplash` only fills the gap on Android < 31.

## The entire integration

That's the whole thing: wrap your app once ([lib/main.dart](lib/main.dart)):

```dart
import 'package:flutter_adaptive_studio/flutter_adaptive_studio.dart';
import 'fas_splash.g.dart';

void main() => runApp(AdaptiveSplash(config: fasSplash, child: const MyApp()));
```

No assets to declare, no `flutter_svg`, no `device_info_plus`: the logo is
rasterised and baked into `lib/fas_splash.g.dart` by `generate`.

## Sources it generates from

- [`flutter_adaptive_studio.yaml`](flutter_adaptive_studio.yaml): the config
- `assets/`: the source it references:
  - `app_icon.webp`: the app icon mark (launcher icons, Play Store, and the splash logo)

## What `generate` produces

- **In-app splash**: `lib/fas_splash.g.dart` (the `FasSplashConfig` consumed by
  the package's `AdaptiveSplash`), with the logo base64-embedded.
- **Android**: adaptive icon (foreground + background),
  round icon, legacy mipmaps, Play Store PNG; the native Android 12 `SplashScreen`
  (static logo) and a bulletproof pre-31 `windowBackground` splash.
- **iOS**: a 1024² app icon, and a
  `LaunchScreen.storyboard` driven by a colour set + logo image set (light/dark).
- **Flavors**: `dart run flutter_adaptive_studio generate --flavor dev` writes
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

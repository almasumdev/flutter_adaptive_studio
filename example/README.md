# flutter_adaptive_studio — example

A self-contained config + source assets showing what the generator produces.

## Files

- [`flutter_adaptive_studio.yaml`](flutter_adaptive_studio.yaml) — the config
- `assets/` — the SVG/AVD/PNG sources it references:
  - `listkin_logo.svg`, `listkin_logo_dark.svg`, `listkin_logo_mono.svg` — the mark (light / dark / monochrome)
  - `avd_listkin_light.xml`, `avd_listkin_dark.xml` — AnimatedVectorDrawables for the native splash
  - `wordmark.svg`, `wordmark_dark.svg` — bottom splash branding
  - `icon.png` — finished raster, used for legacy mipmaps + the Play Store icon

## Run it

Copy `flutter_adaptive_studio.yaml` and `assets/` into a Flutter project, then:

```sh
dart run flutter_adaptive_studio init       # optional: write a fully-commented starter config
dart run flutter_adaptive_studio doctor     # validate config + project
dart run flutter_adaptive_studio generate   # write the icons + splash
dart run flutter_adaptive_studio generate --flavor dev
dart run flutter_adaptive_studio preview    # HTML launcher-mask preview
dart run flutter_adaptive_studio revert     # remove generated files
```

Prefer a shorter command? `dart pub global activate flutter_adaptive_studio`
once, then use `fas` in place of `dart run flutter_adaptive_studio` (e.g.
`fas generate`).

## What it generates

- **Android** — adaptive icon (foreground + background + monochrome themed icon), round icon, legacy mipmaps, Play Store PNG; a native Android 12 `SplashScreen` with the AnimatedVectorDrawable (light/dark), a pre-31 splash, and a Flutter fallback widget; bottom branding.
- **iOS** — a single-size 1024² app icon with iOS 18 dark + tinted variants, and a `LaunchScreen.storyboard` driven by a colour set + logo image set (light/dark).
- **Flavors** — `--flavor dev` writes Android resources to `src/dev/res` and a separate `AppIcon-dev` icon set, deep-merging the `flavors.dev` overrides over the base.

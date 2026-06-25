# Reference packages (vendored, read-only)

These are the two incumbent packages `flutter_adaptive_studio` aims to replace.
They are kept here **only as reference** while building — to study how they
implement Android/iOS generation and to validate the gaps we intend to fill.

> ⚠️ Not dependencies, not shipped. Exclude this `reference/` folder when publishing.
> The `.git` directories were stripped so these don't clash with our own repo.

## Provenance

| Package | Source repo | Version | Commit | Pulled |
|---|---|---|---|---|
| `flutter_launcher_icons` | https://github.com/fluttercommunity/flutter_launcher_icons | 0.14.4 | `10b86b1` (build: v0.14.4, 2025-06-10) | 2026-06-19 |
| `flutter_native_splash` | https://github.com/jonbhanson/flutter_native_splash | 2.4.8 | `3de495d` (2026-05-29) | 2026-06-19 |
| `AndroidAssetStudio` | https://github.com/romannurik/AndroidAssetStudio | — | `ac56496` (2022-11-22) | 2026-06-20 |

## Refresh them later

```bash
rm -rf flutter_launcher_icons flutter_native_splash
git clone --depth 1 https://github.com/fluttercommunity/flutter_launcher_icons.git flutter_launcher_icons
git clone --depth 1 https://github.com/jonbhanson/flutter_native_splash.git   flutter_native_splash
rm -rf flutter_launcher_icons/.git flutter_native_splash/.git
```

## Key findings (why they're here)

Both are **raster-only**: decode one PNG with the `image` package, `copyResize`
to fixed sizes, then string-patch native files. That single shortcut is the root
of every gap we exploit:

- **flutter_launcher_icons** — no vector in/out, no real 108/72/66dp safe-zone
  fit (only a runtime XML `<inset>` %), no `ic_launcher_round`, no Android
  light/dark icon (`activity-alias`), monochrome only from a PNG, iOS dark/tinted
  via the legacy per-size `luminosity` format (not the iOS 18 single-asset model).
  - quality root cause: `lib/utils.dart:11-27`, `lib/android.dart:332`
- **flutter_native_splash** — the "animated" Android-12 splash is a **static PNG**
  fed to `windowSplashScreenAnimatedIcon`; no `AnimatedVectorDrawable`, no
  `windowSplashScreenAnimationDuration`, no `postSplashScreenTheme` handoff. iOS
  is a static storyboard; "handoff" is just `deferFirstFrame`/`allowFirstFrame`
  with a known flash.
  - fake-animation evidence: `lib/android.dart:526-531`

### How the *good* tools do it (Android Asset Studio = IconKitchen's open lineage)

`AndroidAssetStudio` is Roman Nurik's open-source web generator; **IconKitchen**
(icon.kitchen) is his closed-source revamp of it — same approach. Studied to copy
their actual numbers (`app/pages/launcher-icon-generator.js`, `app/studio/imagelib/effects.js`):

- **Legacy mipmap geometry** (48dp/mdpi base, ×1.5/2/3/4 per density): per-shape
  *target rect* the art is fit into — `square: (5,5,38,38)` = **10.4% inset**,
  `circle: (2,2,44,44)` ≈ 4.2%. Corner radius = 3 @ 48dp. Center-inside by default.
  These match Android Studio's **desktop** generator byte-for-byte
  (`LauncherLegacyIconGenerator.buildTargetRectangles`).
- **The "Material look" is computed, not drawn**: AAS applies canvas *effects* —
  outer drop shadow `black α0.3, blur 0.7dp, +0.7dp`; inner bevels `±0.25dp
  white/black α0.2`; radial sheen `white 0.1→0` from top-left. Android Studio
  desktop bakes the equivalent into per-shape **stencil PNGs** (`back`/`mask`/`fore1`
  in `android.jar`). We reproduce the *computed* version in
  `lib/src/raster/icon_effects.dart` (`effect: elevate`).
- **What we do better**: AAS/IconKitchen rasterize the foreground at import; our
  SVG stays vector for the adaptive layers and is rasterized in pure Dart only for
  the legacy/store PNGs. Android Studio needs `layoutlib` to rasterize drawables;
  we don't.

#### Two techniques worth stealing (from `app/studio/imagelib/`)

- **Stepped 2× downsampling** (`drawing.js` `drawImageScaled`): *"when scaling
  down, downsample by at most a factor of 2 per iteration to avoid poor browser
  downsampling."* A single large box-average leaves an aliasing **grid** on flat
  fills (we hit exactly this). Adopted as `ImageRasterizer.resizeSmart` — halve
  repeatedly, then a final step — used for every raster downscale.
- **Alpha-bbox trim** (`analysis.js` `getTrimRect`): scan the source's alpha to
  its content bounding box and trim before fitting (their `defaultValueTrim: 1`),
  so art with transparent margins fills the target consistently. We do this for
  SVG via `artBounds`; not yet for raster sources (a possible future win — would
  let a raster logo with built-in padding fill like the SVG path does).

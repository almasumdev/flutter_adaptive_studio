# Changelog

## 0.27.0

### `auto`/`as_is` framing for the icon and the splash logo

The `auto`-vs-`as_is` choice that `branding_fit` already offered now covers the
launcher icon and the centre splash logo, for both SVG and transparent raster
sources. `auto` (the default) considers only the real art, trimming whatever
transparent padding the source carries so it fills its slot; `as_is` keeps the
source exactly as authored (its own padding, aspect, and relative size), just
centred and contained.

- **`icon.adaptive.safe_zone: as_is`.** A fourth `safe_zone` value. The whole
  viewBox (SVG) or full bitmap (raster) is mapped into the mask-safe square, so
  art you already drew at adaptive-icon proportions is placed verbatim instead of
  being re-measured and re-fit. Flows through the adaptive foreground, the
  monochrome layer, the themed icons, and the legacy mipmaps + Play Store PNG, so
  the whole icon set stays consistent.
- **`splash.image_fit: auto | as_is`.** Frames the centre splash logo the same
  way, across the Android-12 vector, the pre-31 raster, and the legacy layer.
  `as_is` honours a logo's own breathing room rather than filling the safe circle.

Raster `auto` now trims a source's transparent margins before fitting (matching
how SVG `auto` has always used the measured art bounds), so a padded PNG icon or
logo fills its slot the same way a padded SVG does. Set `as_is` to keep the
margins.

### `foreground_format: raster` for gradient icons

VectorDrawable expresses gradients only through `aapt:attr`, a build-time AAPT2
feature. A real device build renders them, but IDE previewers and some non-Android
(Compose Multiplatform) renderers read the raw XML without AAPT2, so a gradient
foreground can preview flat or empty. Set `icon.adaptive.foreground_format: raster`
to bake an SVG foreground to per-density PNGs instead of a VectorDrawable, with the
same safe-zone fit; gradients and clips are rendered into the pixels, so the icon
draws identically in every previewer, tool, and platform. Defaults to `vector`.

### SVG fidelity: shape transforms on gradients, and offset viewBoxes

Two rendering bugs that made a rich SVG come out close-but-not-exact are fixed:

- **A shape's own `transform` now applies to its gradient.** A
  `userSpaceOnUse` gradient lives in the referencing shape's user space, so a
  rotated (or scaled) shape must rotate its gradient with it. Previously the
  shape moved but the gradient did not, tilting every gradient on a transformed
  element (e.g. a coin whose rings use a `rotate(45)` gradient painted on a
  `rotate(-45)` circle: the two should cancel to a clean vertical sheen).
- **A non-zero `viewBox` origin is honoured.** Art authored away from (0,0)
  (`viewBox="205 15 494 494"`, common in Illustrator exports) is no longer
  shifted and clipped when rendered full-bleed or with `as_is`.
- **The safe-zone fit measures the art tightly.** Bounding an arc by its
  endpoints-plus-radii grossly over-sized any circle, and a `clip-path` let
  clipped-away geometry count, so a circle-heavy or texture-masked logo (a coin,
  a badge) was shrunk to a dot in the icon canvas. Arcs and cubics are now bounded
  to their real extent and clipped geometry no longer inflates the measurement, so
  the art fills the safe zone as intended.
- **Circles, ellipses and rounded rects emit cubic Béziers, not `A` arcs.** Some
  VectorDrawable / Compose-Multiplatform renderers silently drop arc commands,
  which made a gradient-filled circle disappear and an arc-based `<clip-path>`
  fail to clip (a coin rendering as just its unclipped background texture). The
  generated paths now use cubics, which every renderer draws.

### `sync` keeps options grouped

`sync` used to append every missing option to the bottom of its section, so over
releases new keys drifted away from the ones they belong with (a stray
`image_fit` or a split-up branding block). It now inserts each option at its
template position, right after the sibling it follows, so related keys stay
together. It also no longer drags a trailing section banner or the next section's
prose into the block it inserts.

## 0.26.0

### SVG: gradients and clip paths are now rendered, not flattened

A gradient-heavy SVG (a shiny "coin", a metallic wordmark, a duotone mark) used
to come out as a flat black shape with any `clip-path` ignored, because gradients
and clips were silently dropped. They are now first-class:

- **Gradients.** `<linearGradient>` and `<radialGradient>` fills are parsed with
  their stops (and per-stop opacity), `gradientUnits`, `gradientTransform`,
  `spreadMethod`, and `href`/`xlink:href` inheritance. The VectorDrawable emits a
  real inline `aapt:attr` `<gradient>` (so it stays crisp at every density), and
  the pure-Dart rasteriser evaluates the gradient per pixel for the legacy
  mipmaps and store icon.
- **Clip paths.** `clip-path="url(#id)"` on a group or shape is resolved from
  `<defs>` (each clip shape's own transform baked in) and emitted as a
  VectorDrawable `<clip-path>`; the rasteriser masks the fill to it.

The result: an icon or splash built from a rich SVG now matches the source art.
Filters, masks, `<text>` and `<image>` are still unsupported and dropped with a
warning.

## 0.25.8

### Splash: icon size back to the Android keyline, plus robustness fixes

- **The native splash icon fills the platform safe circle again.** It inscribes
  the ⌀192 keyline (or ⌀160 with an icon background) exactly as the Android
  splash guide specifies. The automatic inset added in 0.25.0-0.25.1 is removed:
  `icon_padding` still works but now defaults to `0`. Set it only if a particular
  OEM mask crops your logo and you want it tighter.
- **A stale splash icon no longer shadows the new one.** Switching the splash
  `image:` between a raster (PNG/WebP) and an SVG left the previous form on disk.
  Because a `nodpi` raster wins Android resource resolution over a plain
  `drawable/` vector, a leftover `drawable-nodpi/splash_icon.png` kept rendering
  as the splash no matter what the new vector contained (and a near-full-bleed
  one stayed clipped by the system circle mask). `generate` now deletes the stale
  sibling, and drops the emptied folder, when the source form changes. If you hit
  this, run `fas generate` once and rebuild with a clean install so the old
  resource leaves the APK.
- **An invisible `icon_background` is skipped.** If `icon_background` matches the
  splash `background` it would only force the OS adaptive-icon mask for no visible
  badge, so it is ignored with a warning. Set a different colour for a real badge.
- **New `fas --version`.** Prints the installed version.

## 0.25.1

### Splash: a gentler default inset for the native icon

0.25.0 started insetting a native splash icon that has an `icon_background`, so an
OEM adaptive mask can't clip it, but that default was heavier than it needed to
be. The clip is only a few pixels on the launchers that do it, so the default now
trims the keyline just slightly (a 150 dp safe circle instead of the full 160 dp
on the 240 dp canvas) rather than shrinking the logo. Set `icon_padding` if you
want more or less.

## 0.25.0

### Splash: a tall logo no longer gets clipped on the native splash

Setting `splash.icon_background` puts the Android 12+ system splash into a
"badged icon" mode, where the OS renders your icon like an adaptive app icon: it
scales the foreground up and masks it to the launcher shape (a squircle on
Samsung One UI, with a drop shadow and gloss). A logo that is taller or wider
than it is round then has its edge sliced off by that mask, even though the
generated drawable itself was correct and centred.

- **New `splash.icon_padding`.** It insets the native splash icon (the API 31+
  vector and the pre-31 raster) so the logo sits where the OEM mask cannot reach.
  It is separate from `logo_padding`, which only affects the in-app
  `AdaptiveSplash`.
- **A safe default now applies when `icon_background` is set.** Because that is
  the case the OS masks, the native splash icon is inset automatically so a
  full-height logo stays clear of the mask. Set `icon_padding` to tune it, or
  `icon_padding: 0` to keep the raw keyline. Splashes without an icon background
  render exactly as before.

## 0.24.0

### Splash: keep an SVG branding as you drew it

- **New `splash.branding_fit`.** By default (`auto`) an SVG `branding:` image is
  measured and scaled to fill the branding slot, which trims whatever padding you
  built into the file. Set `branding_fit: as_is` to place the SVG exactly as
  drawn: its own aspect ratio, inner padding, and size are kept, just centred in
  the slot. It applies to the native splash (API 31+ and the pre-31 raster) and
  the in-app `AdaptiveSplash` alike. A raster branding was already used as
  authored, and `branding_text` is unaffected.

### Icons: a separate padding for the Play Store icon

- **New `icon.play_store_padding`.** The 512² Play Store PNG used to share its
  inset with the legacy mipmaps (`legacy_padding`, else `safe_zone`). You can now
  set its padding on its own, for example a roomier margin for Play's
  rounded-corner presentation, without touching the launcher mipmaps. Left unset
  it still follows the shared framing, so existing configs are unchanged.

## 0.23.0

### Turning a feature off now cleans up after itself

Disabling a sub-feature used to leave its generated output in place, sometimes
inert and sometimes still active. `generate` now removes what it safely owns and
warns about the rest.

- **`round: false` actually disables the round icon.** Switching `round` off left
  `android:roundIcon` in the manifest and the round mipmaps on disk, so the
  launcher kept showing the round icon. `generate` now removes the
  `android:roundIcon` it set (a custom value you added yourself is left alone) and
  prunes the round mipmaps, so the setting takes effect.
- **Dropping the themed light and dark icons prunes what it owns and flags the
  rest.** The generated mipmaps and foreground drawables are removed once no
  `activity-alias` still references them. The `.FasIconLight` and `.FasIconDark`
  aliases and the `ic_launcher_*_background` colours live in shared files
  (AndroidManifest.xml, colors.xml) that the tool never rewrites on its own, so it
  names them and asks you to remove them in version control (or run `revert`),
  instead of leaving disabled cruft in the build.
- **Removing `monochrome` deletes the leftover monochrome drawable** rather than
  keeping an unused file in your resources.
- **Removing the whole `splash:` block warns about the splash files left behind.**
  They stay wired into your launch theme and manifest, so the tool points you at
  `revert` for a clean removal instead of half-editing shared files.

### `revert` warns before it can break a build

- **`revert` now flags the dangling manifest reference it can create.** When it
  deletes the themed mipmaps but your manifest still has the `.FasIconLight` and
  `.FasIconDark` `activity-alias` nodes that reference them, the next Android build
  fails on the missing `@mipmap/ic_launcher_light` until you restore the manifest
  (and colors.xml) from version control. `revert` now says exactly that, instead
  of leaving you to discover it at build time.

## 0.22.1

### Packaging

- The logo now ships as a pub.dev `screenshots:` entry, so it shows as the listing
  thumbnail beside search results instead of being embedded in the README header.
  `images/logo.webp` is included in the package for pub.dev to read.

## 0.22.0

### iOS splash: full-bleed background image

- **New `ios.splash.background_image`** (with a `background_image_dark` variant): a
  full-bleed image painted behind the centred logo on the iOS `LaunchScreen`, scaled
  to fill. Accepts an **SVG or raster** source; the solid `background` colour shows
  through when it's unset. It falls back to the Android splash `background_image`, so
  one config still covers both platforms. `generate` writes a `LaunchBackgroundImage`
  image set (light and dark) and inserts an image view **behind** the logo in the
  storyboard; dropping the option later removes the set, the image view, and its
  layout constraints again. `init` and `sync` document the new option.

### Housekeeping

- The in-file marker stamped into every generated resource now reads `Generated by
  flutter_adaptive_studio. Do not edit.` (punctuation only). Re-running `generate`
  will show this one-line diff in files generated by an earlier version.
- The `example/` app is trimmed to a single icon source (one `app_icon.webp` drives
  every launcher icon and a static splash), so the sample reads at a glance. No change
  to generated output.

## 0.21.1

### iOS: clean up a stale flutter_native_splash launch background

- **Fixed the iOS launch background not matching your config.** If the project
  previously used `flutter_native_splash`, its full-bleed `LaunchBackground`
  image view and matching `LaunchBackground.imageset` stayed in the launch
  screen and shadowed the color set this tool writes, so iOS showed the old
  background instead of the one you configured. `generate` now strips that image
  view (with its layout constraints and its `<image>` resource) and deletes the
  conflicting image set, leaving only the `LaunchBackground` color set.
- Housekeeping: removed an unused internal file and refreshed the docs. No change
  to generated output.

## 0.21.0

### In-app splash: closer native match + split timing

- **Consistent logo size.** The in-app logo is now a fixed **288 dp** box,
  transparent over the splash background, regardless of `icon_background` (it no
  longer shrinks to 240). One predictable size; `logo_padding` insets it.
- **Branding matches the native slot.** The in-app wordmark now fills the same
  **200×80 dp** slot the Android-12 splash reserves for branding (it was a fixed
  40 dp height), so it's the same size as the system splash.
- **Separate durations.** New **`flutter_splash_duration`** controls how long the
  in-app splash holds, independent of **`duration`**, which now only drives the
  native animated-icon playback (`windowSplashScreenAnimationDuration`, API 31+).
  `flutter_splash_duration` falls back to `duration` when unset, so existing
  configs are unchanged.

## 0.20.0

### In-app splash: native-matched logo + clearer timing

**Logo size now matches the native splash icon.** The in-app `AdaptiveSplash`
logo is sized to the Android-12 keyline: the art's bounding box inscribed in
the 2/3 safe circle of a 288 dp canvas (240 dp / ⌀160 when `icon_background` is
set), so it no longer looks larger than the system splash. New
**`logo_padding`** (percent) insets it further for extra breathing room.

**Timing is now predictable.** The in-app splash holds for the full `duration`
**only where there's no native splash to hand off from**: Android < 31. iOS (a
static `LaunchScreen`) and Android 12+ (the system `SplashScreen`) are **off by
default** to avoid a double-splash; opt in everywhere with
`flutter_splash_all_versions: true` or `AdaptiveSplash(force: true, ...)`.

- **Breaking:** iOS no longer shows the in-app splash by default (it has its own
  native launch screen), enable it with `flutter_splash_all_versions` / `force`
  if you want it.
- **Breaking:** the in-app logo default size changed (now matches the native
  icon instead of a fixed 192 dp box), set `logo_padding` to fine-tune.

## 0.19.0

### Consistent icon padding (mipmap + Play Store match the rest)

A finished `icon.image` is now inset by the same `safe_zone` / `legacy_padding`
as the adaptive foreground, so the **legacy mipmaps** and the **Play Store
PNG** share one framing with the adaptive icon and the iOS icon, instead of
being used edge-to-edge.

- The inset follows `legacy_padding` if set, else the adaptive `safe_zone`, else
  the package default: the same rule every other generated icon uses.
- **Breaking:** a finished `icon.image` that was previously emitted as-is is now
  inset. Set **`legacy_padding: 0`** to keep an already-framed icon
  edge-to-edge. (A pure `icon.image` config with no adaptive safe zone and no
  `legacy_padding` is still used full-bleed.)

## 0.18.0

### Zero-dependency in-app splash (no more conflicts)

The package is now a **pure-Dart CLI**: install it with `dart pub global
activate flutter_adaptive_studio` and run `fas generate`. The in-app splash is
no longer a shipped library; it's **generated** into a self-contained
`lib/fas_splash.g.dart` that imports **only `package:flutter`**.

```dart
import 'fas_splash.g.dart'; // self-contained: config + AdaptiveSplash + FasNativeSplash

void main() => runApp(AdaptiveSplash(config: fasSplash, child: const MyApp()));
```

- **Your app depends on nothing from us**, so the generator's build-time deps
  (`image`, `xml`, ...) can never conflict with your app's (e.g. an app using
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

### In-app splash: just wrap your app (no more glue folder)

The old `flutter_adaptive_studio/splash/` drop-in (a `FasSplash` widget you had
to read, wire into `main()`, plus `device_info_plus` and `flutter_svg` to add and
assets to declare) is **gone**. The splash widget now ships **in the package**,
you wrap your app once and everything is handled:

```dart
import 'package:flutter_adaptive_studio/flutter_adaptive_studio.dart';
import 'fas_splash.g.dart'; // the only generated file

void main() => runApp(AdaptiveSplash(config: fasSplash, child: const MyApp()));
```

- **`AdaptiveSplash`** (shipped) paints a splash that matches the native one
  (background, centred logo, branding, light/dark by system brightness), holds
  briefly while your first screen settles, then fades to your app.
- The generator now emits a **single** `lib/fas_splash.g.dart`: colours, timing,
  and the logo/branding/background **rasterised to PNG and base64-embedded**. So
  the app needs **no assets, no `flutter_svg`, and no `device_info_plus`**.
- By default the in-app splash shows only **where there's no native animated
  splash** (Android API < 31; on 31+ the system `SplashScreen` covers startup).
  Force it on every version with `AdaptiveSplash(force: true, ...)` or
  `flutter_splash_all_versions: true` under `splash:`.
- The "API < 31" check reads `Build.VERSION.SDK_INT` via **`dart:ffi`** (libc
  `__system_property_get`), so the package stays a plain Flutter package (no
  plugin, no Gradle/podspec) and can't conflict with your other dependencies.
- **Android + iOS, fully.** `fas_splash.g.dart` is now generated whenever *either*
  platform configures a splash (so an **iOS-only** project gets it too, it used
  to be Android-only and would leave the import dangling). The config also bakes
  **iOS overrides** (`iosBackground*` / `iosLogo*`): on iOS `AdaptiveSplash`
  matches the iOS `LaunchScreen` (its own background/logo, no branding), and on
  Android it matches the Android splash, automatically, from one wrap.
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

### Pre-31 launch background: bulletproof on API 21-23

- **SVG `branding:` now renders on the pre-31 launch screen on every API level.**
  Previously an SVG branding was emitted as a VectorDrawable and referenced from
  `windowBackground`, which can't inflate a vector on **API 21-23** (Android
  5-6), so the branding silently failed to paint there (and risked dropping the
  whole launch background). It's now rasterised to a per-density
  `drawable-*/splash_branding_legacy` bitmap for the pre-31 layer, while the
  crisp **vector** is kept for the Android 12+ branding slot. (Text and raster
  branding were already bitmaps, unchanged.)
- **SVG `background_image:` is rasterised too** (to `drawable-nodpi/splash_bg`),
  for the same reason: it's only used on the pre-31 layer, where a vector can't
  paint on API 21-23. So **every layer** of the pre-31 launch background is now a
  bitmap: nothing in it can fail to inflate on old devices.
- `image_format: png | webp` controls the encoding of these new rasters as well,
  and `revert` cleans them up (along with text-branding density rasters, which it
  previously missed).

### `FasNativeSplash`: failsafe + double-preserve guard

- `preserve(...)` gains an optional **`maxDuration`** failsafe: if `remove()`
  isn't called within it, the splash auto-releases, so a forgotten `remove()`
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
  `flutter_adaptive_studio.yaml` doesn't yet mention, as **commented**
  placeholders in the right section, **without touching your existing lines,
  values, or formatting**. It's the non-destructive way for existing users to
  pick up newly-added options (unlike `init --force`, which overwrites the
  whole file). Because every inserted line is a comment, it can never change
  behaviour or break the YAML; it's also idempotent.

## 0.14.0

### Splash: text branding

- New `branding_text:` renders a **text** wordmark at the bottom of the splash
  when no `branding` image is given (with `branding_text_color` / `_dark`,
  auto-contrasting the background when unset). It's rasterised with a built-in
  font for the native splash (pre-31 launch background + API 31+ branding slot,
  per density + `-night`) and emitted as a crisp `Text` widget in the Flutter
  fallback. For a brand typeface, use a `branding` SVG/PNG instead.

## 0.13.0

### Splash: system bars

- New: tint the **status bar** and **bottom navigation bar** during the splash.
  `status_bar_color` / `navigation_bar_color` take a hex value or `transparent`
  (each with a `_dark` variant), and `status_bar_icon_brightness` /
  `navigation_bar_icon_brightness` (`dark` | `light`, + `_dark`) set the bar
  **icon** colour, auto-derived from the bar/background colour when omitted.
  These set `statusBarColor` / `navigationBarColor` / `windowLightStatusBar` /
  `windowLightNavigationBar` on both the pre-31 launch theme and the API 31+
  splash theme (and their `-night` variants).
- Docs: branding already renders on the pre-31 launch background (it's the
  bottom layer of `launch_background.xml`), now visible on Android 10+ after
  the 0.12.0 `-v21` fix.

## 0.12.0

### Splash (critical pre-31 fix)

- **The pre-31 launch splash now actually shows.** A stock Flutter project ships
  `drawable-v21/launch_background.xml`, and on API 21+ (virtually every device)
  Android resolves `@drawable/launch_background` to that `-v21` file, so the
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
  launch logo: the launch screen shows your mark instead of a bare colour. Set
  `splash.image:` to control it explicitly.

> Note: if your launch screen stays blank/white through a long startup, check
> that `FasNativeSplash.remove()` is called **synchronously right after
> `runApp()`**, not inside an `addPostFrameCallback`. While the first frame is
> deferred by `preserve()`, that callback never fires, so `remove()` there never
> runs and the app is stranded on a blank window.

## 0.10.0

### Splash (pre-31 reliability)

- **The pre-31 `windowBackground` splash logo is now rasterised** to per-density
  PNG/WebP (`drawable-*/splash_icon_legacy`) instead of being referenced as a
  VectorDrawable. `windowBackground` is inflated by the platform before
  AppCompat's vector support is active, so a vector logo silently failed to paint
  on **API 21-23** (Android 5-6), you'd get the background colour but no logo.
  A bitmap always renders, so the old-device launch splash is now bulletproof.
  The crisp vector is still used for the Android 12+ `SplashScreen` slot.
- New `splash.image_format: png | webp` chooses the encoding for that raster
  logo (PNG default; WebP is smaller and resolves identically on API 18+).
- An `animated_icon` with no static `image:` now logs a warning: an AVD can't be
  a `windowBackground` drawable, so add an `image:` for a resting pre-31 logo.
- `revert` now also removes the per-density legacy splash rasters, WebP mipmaps,
  and the `src/main` Play Store PNG.

## 0.9.0

- Widened the `xml` constraint to `>=6.5.0 <8.0.0` so apps can depend on this
  package even when another dependency pins `xml` 6.x (e.g.
  `flutter_local_notifications`). The runtime `FasNativeSplash` uses no `xml`, so
  the app is unaffected; the generator dev-resolves to `xml` 7.x.
- Docs: call `FasNativeSplash.remove()` **right after `runApp()`**, not inside a
  post-frame callback: `deferFirstFrame` prevents that callback from firing, so
  `remove()` there would strand the app on the splash.

## 0.8.0

### Splash

- **`FasNativeSplash` now ships in the package** as a runtime API: import it and
  call `FasNativeSplash.preserve(widgetsBinding: ...)` / `remove()` exactly like
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
  with `FasNativeSplash.preserve({required widgetsBinding})` / `remove()`: keeps
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
  gravity, fullscreen, and screen-orientation lock, all with dark variants.

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
- Pure-Dart rasterization for all outputs: no system tools or FFI required.

# flutter_adaptive_studio — Android Plan

> Scope: **Android only.** iOS / web / macOS / windows are intentionally left as
> open extension points (see [Extensibility](#extensibility)). This document is the
> complete Android design; nothing here forces a platform decision elsewhere.

> ## ✅ Status: all Android phases implemented (2026-06-20)
> Phases 1–5 are built, analyzer-clean, covered by 20 tests, and dogfooded on
> [`example/`](../example/). Open decisions were resolved as: **rasteriser** =
> pure-Dart PNG pass-through + auto-detected system tool for SVG (bundled
> resvg-FFI remains the future production backend); **themed light/dark icon** =
> shipped opt-in (Phase 4). CLI: `generate | doctor | preview | revert`.

---

## 1. Context — why this exists

The two incumbents are both **raster-only**: they decode one PNG with the `image`
package, `copyResize` it to fixed sizes, and string-patch native files. That single
shortcut is the root of every gap (confirmed by reading their latest source — see
[`reference/README.md`](../reference/README.md)):

- **flutter_launcher_icons (0.14.4):** no vector in/out; no real 108/72/66dp
  safe-zone fit (just a runtime XML `<inset>` %); no `ic_launcher_round`; no Android
  light/dark icon; monochrome only from a PNG.
- **flutter_native_splash (2.4.8):** the "animated" Android-12 splash is a **static
  PNG** fed to `windowSplashScreenAnimatedIcon` — no `AnimatedVectorDrawable`, no
  `windowSplashScreenAnimationDuration`, no `postSplashScreenTheme` handoff.

**Outcome we want:** a vector-native, theme-aware, mask-correct Android generator
where the headline is a *genuinely animated* Android-12 splash (real AVD from a
Shapeshifter/SVG source) plus crisp adaptive icons — all opt-in, great defaults.

### Design principle (locked with user)
Everything is **opt-in with sensible defaults**. The only practical floor is "you
must give *a* source." No `android:` block → we don't touch Android. Missing optional
asset → skip that piece with a clear log line, never hard-fail.

---

## 2. The defining technical decision (settled)

Vector input is the whole value prop. The key realization: **the high-value Android
outputs need no rasterizer at all.**

| Output | Pipeline | Needs raster? |
|---|---|---|
| Adaptive foreground / background / monochrome | SVG → **VectorDrawable** (`<vector>`) | ❌ |
| Animated splash icon (API 31+) | Shapeshifter/SVG → **AnimatedVectorDrawable** (`<animated-vector>`) | ❌ |
| Legacy mipmaps (pre-API-26 PNG) | rasterize | ✅ |
| 512² Play Store icon | rasterize | ✅ |
| Pre-31 classic splash bitmap (optional) | rasterize | ✅ |

So rasterization is a **separable, pluggable concern**, not a blocker. We build the
vector transpiler first (covers API 26+ fully) and treat raster as a backend behind
an interface.

**Decisions:**
- **(B) SVG → VectorDrawable:** hand-rolled Dart transpiler on `package:xml`. Paths
  map 1:1 (`d` → `android:pathData`); `<g>` → `<group>`; rect/circle/ellipse →
  paths. Strip/approximate the unsupported subset (gradients → solid, filters/masks
  /text dropped) with warnings.
- **(C) Shapeshifter JSON → AVD:** parse the `.shapeshifter` JSON directly (it *is*
  JSON: `version`/`layers`/`timeline`). Emit a VectorDrawable + an `<animated-vector>`
  with `objectAnimator`s. Also accept a pre-exported AVD XML as pass-through.
- **(A) Rasterizer:** a `Rasterizer` interface with selectable backends. **Open
  decision — see [§8](#8-open-decisions).** Default candidate: bundled **resvg via
  FFI** (zero user friction) with a **process/shell-out** fallback and a **PNG
  pass-through** (user supplies PNGs for the few raster outputs). MVP (icons on API
  26+) ships without needing any of these.

---

## 3. Config schema (Android slice — all optional)

Read from `pubspec.yaml` under `flutter_adaptive_studio:` **or** a standalone
`flutter_adaptive_studio.yaml`. Per-flavor files supported later.

```yaml
flutter_adaptive_studio:
  source: assets/logo.svg            # global fallback source (optional)
  android:
    # ---- ICON (all keys optional) ----
    icon:
      adaptive:
        foreground: assets/logo_fg.svg        # SVG (vector) or PNG
        background: "#E4ECE8"                  # hex OR svg/png path
        monochrome: assets/logo_mono.svg       # Android 13 themed icon
        safe_zone: fit                         # fit(default) | inset:<pct> | none
      legacy: true                             # pre-API-26 mipmaps (default: auto by min_sdk)
      round: true                              # ic_launcher_round
      play_store: true                         # 512² marketing PNG
      themed:                                  # full-color light/dark via activity-alias
        light: assets/logo_light.svg           #   (opt-in; carries restart/permanence caveats)
        dark: assets/logo_dark.svg
      min_sdk: 21
    # ---- SPLASH (all keys optional) ----
    splash:
      background: "#E4ECE8"
      background_dark: "#0C1413"
      animated_icon: assets/files/logo_anim_light.shapeshifter   # Shapeshifter JSON / SVG anim / AVD
      animated_icon_dark: assets/files/logo_anim_dark.shapeshifter
      duration: 1000                            # ms, ≤ ~1000 for API 31+
      icon_background: "#FFFFFF"                 # optional API-31 icon bg
      branding: assets/branding.svg             # optional
```

---

## 4. What gets generated (Android)

Output base: `android/app/src/main/res/` (flavor-aware later). Density multipliers
mdpi 1.0 / hdpi 1.5 / xhdpi 2.0 / xxhdpi 3.0 / xxxhdpi 4.0.

### 4a. Adaptive icon (API 26+) — vector, no raster
- `mipmap-anydpi-v26/ic_launcher.xml` (+ `ic_launcher_round.xml` if `round`)
  referencing vector drawables:
  - `drawable/ic_launcher_foreground.xml` (`<vector>`, 108dp viewport, artwork
    **bbox-fit into the 66dp safe circle** — our quality win over a blind inset)
  - background: `@color/ic_launcher_background` (solid) **or**
    `drawable/ic_launcher_background.xml`
  - `drawable/ic_launcher_monochrome.xml` injected as `<monochrome>` when provided
- `values/colors.xml` ← background color entry (structured edit, not regex)

### 4b. Legacy mipmaps + store icon (raster, opt-in / min_sdk-gated)
- `mipmap-{mdpi…xxxhdpi}/ic_launcher.png` (48/72/96/144/192) and `_round.png`
- `ic_launcher-playstore.png` (512²) at project root or `android/app/`

### 4c. Themed full-color light/dark icon (opt-in — activity-alias)
- Two icon sets + `<activity-alias>` entries in the manifest, plus generated runtime
  glue (platform channel + Kotlin) that swaps the active alias **on background**
  (the Blinkit/Meesho pattern) to avoid the relaunch flash. Documented caveats:
  possible relaunch, aliases are permanent, OEM launcher variance.

### 4d. Splash — the headline
- **API 31+ (`values-v31/styles.xml`, `values-night-v31/styles.xml`):** real
  `windowSplashScreenAnimatedIcon` = `@drawable/splash_icon` (**AnimatedVectorDrawable**),
  `windowSplashScreenAnimationDuration`, `windowSplashScreenBackground`,
  optional `windowSplashScreenIconBackgroundColor`, and `postSplashScreenTheme`
  for a managed handoff. Icon artwork fit to the API-31 circular-mask safe region.
- `drawable/splash_icon.xml` (`<animated-vector>`) + `drawable/splash_icon_vector.xml`
  + `animator/*.xml` (or inline via `aapt:attr`). Dark variant under `drawable-night/`.
- **Pre-31 (`values/styles.xml`, `values-night/styles.xml`):** classic
  `windowBackground` → `drawable/launch_background.xml` layer-list (color + centered
  logo). Dark via `values-night`.
- All theme/style/manifest edits are **structured XML** (parse → mutate → serialize),
  idempotent via marker comments, with a real `revert`.

---

## 5. Shapeshifter JSON → AVD mapping (verified against listkin assets)

listkin's `.shapeshifter` files are 288×288, structure `{version, layers, timeline}`:
nested `<group>`s (`group_3` wraps `group_2`/`group_1`/`group`) with `pivotX/Y`,
`scaleX/Y`; leaf `path`s with `pathData` + `fillColor`; timeline blocks of
`{layerId, propertyName: scaleX/scaleY, startTime, endTime, fromValue, toValue,
interpolator: OVERSHOOT|FAST_OUT_SLOW_IN}` (staggered at 200 / 301 / 700ms, 1000ms total).

Mapping:
- root vector → `<vector>` viewport 288×288, width/height = target icon dp
- group → `<group android:name android:pivotX android:pivotY android:scaleX android:scaleY>`
- path → `<path android:name android:pathData android:fillColor>`
- each timeline block → `<objectAnimator android:propertyName="scaleX|scaleY"
  android:startOffset=startTime android:duration=(end-start)
  android:valueFrom=fromValue android:valueTo=toValue android:interpolator=…>`,
  grouped per target in a `<set>`; `OVERSHOOT` → `@android:interpolator/overshoot`,
  `FAST_OUT_SLOW_IN` → `@android:interpolator/fast_out_slow_in`
- `<animated-vector android:drawable="@drawable/splash_icon_vector">` with one
  `<target android:name="group_x" android:animation="@animator/group_x"/>` per group

**Risk:** path-morph (`pathData`) animation needs identical command structure
between keyframes. listkin only animates scale on groups (no path morph), so the
dogfood case is safe; we add a validator that warns when a morph is incompatible.

---

## 6. Package architecture

```
lib/src/
  config/       Config model + loader + validator (pubspec/yaml; everything optional)
  graphic/      SourceGraphic abstraction: SvgDocument | ShapeshifterDocument
                | VectorDrawableDocument  (Lottie later) — bbox + parse
  vector/       VectorDrawableWriter (SVG→VD), AvdWriter (Shapeshifter→AVD)  [no raster]
  raster/       Rasterizer interface + backends (resvg-ffi | process | png-passthrough)
  geometry/     adaptive_geometry.dart — 108/72/66dp safe-zone bbox-fit math
  platform/     PlatformGenerator interface  ← keeps iOS/web/etc. open
    android/    AndroidGenerator → AndroidIcons, AndroidSplash,
                AndroidManifestEditor, AndroidPaths (density/dir tables), templates
  io/           ResWriter — idempotent writes, marker comments, revert
bin/flutter_adaptive_studio.dart   # CLI: generate | revert | doctor | preview
```

**Reuse / steal:** density tables and res-dir layout from the reference packages;
flutter_native_splash's `package:xml` DOM editing pattern (good) — extend it to *all*
edits. **Avoid:** their regex/hardcoded-id patching and non-reverting `remove`.

---

## 7. Build sequencing (MVP → full Android)

1. **Scaffold + config + SVG→VectorDrawable + adaptive icon (fg/bg/mono, safe-zone
   fit, round).** Proves the transpiler + the quality value prop. *No rasterizer
   needed.* Dogfood: generate listkin's adaptive icon.
2. **Shapeshifter→AVD + animated splash (API 31+ AVD, duration, theme, handoff) +
   pre-31 fallback + `values-night`.** The headline. Dogfood: listkin's
   `logo_anim_light/dark.shapeshifter`.
3. **Rasterizer backend → legacy mipmaps + 512² store icon.** Lands the chosen
   backend from §8.
4. **Themed full-color light/dark icon (activity-alias + runtime glue).** Opt-in.
5. **Polish:** OEM mask **preview sheet**, config `doctor`/lint, `revert`.

---

## 8. Open decisions (need your call)

1. **Rasterizer backend** for legacy mipmaps + 512² (only affects §4b/§4c, phase 3):
   - **A — bundled resvg FFI:** zero user friction, best quality; we ship prebuilt
     binaries per-OS (more build/CI work).
   - **B — shell-out** to `resvg`/`rsvg-convert`/ImageMagick if present: simplest to
     build, but a system dependency the user must install.
   - **C — PNG pass-through:** user supplies PNGs for raster outputs; no native dep,
     least magic. (Good interim default.)
2. **Themed full-color light/dark icon (§4c)** — include now (opt-in) or defer to a
   later release given the relaunch/permanence/OEM caveats?

## Extensibility (other gates kept open)
`PlatformGenerator` + `SourceGraphic` + `Rasterizer` are the seams. Adding iOS later
is "implement `IosGenerator`" + an `ios:` config block; nothing in the Android path
hard-codes platform assumptions. Lottie input slots in as another `SourceGraphic`.

## Verification
- Unit: golden-file tests for VectorDrawable/AVD XML output; path-morph validator;
  config parsing (optional-everything, unknown-key tolerance).
- Integration: run `dart run flutter_adaptive_studio` against a copy of **listkin**;
  assert exact res/ tree + XML; `flutter build apk` succeeds.
- Manual: install on an API 33 device — confirm adaptive mask shapes, themed
  (monochrome) icon, and the **animated** API-31 splash actually animates and hands
  off to Flutter without a flash. Compare side-by-side with Android Studio output.
```

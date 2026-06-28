/// `init` — drops a commented starter `flutter_adaptive_studio.yaml` into the
/// target project so you don't hand-write config. Edit the asset paths, then run
/// `generate`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'logger.dart';

class Initializer {
  Initializer({required this.projectRoot, Logger? logger})
      : logger = logger ?? Logger();

  final String projectRoot;
  final Logger logger;

  /// The fully-commented starter config — every supported option. Exposed so
  /// `sync` can diff a user's config against it and fill in what's missing.
  static String get starterTemplate => _starter;

  /// Writes the starter config. Returns the path, or null if it already exists
  /// and [force] is false.
  String? run({bool force = false}) {
    final out = File(p.join(projectRoot, 'flutter_adaptive_studio.yaml'));
    if (out.existsSync() && !force) {
      logger.warn('flutter_adaptive_studio.yaml already exists — '
          'pass --force to overwrite.');
      return null;
    }
    out.writeAsStringSync(_starter);
    logger.success('Wrote ${p.basename(out.path)}');
    logger.info('Next: drop your logo in assets/, edit the paths, then run '
        '`generate`.');
    return out.path;
  }

  static const String _starter = '''
# flutter_adaptive_studio — configuration
#
# This starter lists EVERY supported option. The few that are uncommented are
# enough to generate adaptive icons after you drop in a logo; uncomment the
# rest as you need them. Asset paths are relative to this project's root, and
# unknown keys are ignored. Then run:
#   dart run flutter_adaptive_studio generate
# (or, after `dart pub global activate flutter_adaptive_studio`, just `fas generate`)

flutter_adaptive_studio:
  # Global fallback art, used when a more specific `foreground:`/`image:` is not
  # given. Usually you set the per-feature source instead of this.
  # source: assets/logo.svg

  android:
    # Minimum Android SDK. Influences whether legacy mipmaps are emitted when
    # `legacy:` below is left unset.
    # min_sdk: 21

    icon:
      adaptive:
        foreground: assets/logo.svg        # your logo (SVG or raster)
        background: "#FFFFFF"              # hex colour, or an SVG/PNG path
        # monochrome: assets/logo_mono.svg # Android 13 themed (tinted) icon — SVG only
        safe_zone: fit                     # fit (15% padding) | inset:<pct> | none
        # padding: 15                      # alias for `safe_zone: inset:<pct>` (wins if both set)

      round: true                          # also emit ic_launcher_round
      # icon_name: ic_launcher             # launcher resource base name
      # legacy: true                       # pre-API-26 mipmap PNGs
      # legacy_padding: 15                 # % the legacy/store art is inset (overrides the adaptive safe zone for these raster icons)
      # play_store: true                   # 512² Play Store icon (always PNG, per Google)
      # image_format: png                  # png | webp — encoding for the generated icon resources
      # image: assets/icon.png             # finished-icon source for legacy + play_store
      #                                    #   (otherwise they're rasterised from `foreground`)
      # effect: elevate                    # none | elevate (Material drop shadow + sheen)

      # --- full-colour light/dark icon via activity-alias (opt-in, SVG only) ---
      # themed:
      #   light: assets/logo.svg
      #   dark: assets/logo_dark.svg
      #   background: "#FFFFFF"             # themed-icon background (else inherits adaptive.background)
      #   background_dark: "#000000"        # dark themed variant (else inherits `background`)

    # --- splash screen (native Android 12 SplashScreen API, with fallbacks) ---
    # splash:
    #   background: "#FFFFFF"                      # light splash background (hex)
    #   background_dark: "#000000"                # dark / system-dark background (hex)
    #   background_image: assets/splash_bg.png    # full-bleed bg image (pre-31 + fallback; API 31+ uses the colour)
    #   background_image_dark: assets/splash_bg_dark.png
    #   image: assets/logo.svg                    # static centre logo (SVG or raster)
    #   image_dark: assets/logo_dark.svg          # dark-mode centre logo
    #   image_format: png                         # png | webp — encoding for the pre-31 raster splash logo
    #   icon_background: "#FFFFFF"                 # hex circle behind the icon (API 31+)
    #   icon_background_dark: "#111111"           # dark-mode icon circle
    #   gravity: center                           # pre-31 centre-image alignment (center, fill, bottom, …)
    #   fullscreen: false                         # hide status/nav bars during splash
    #   screen_orientation: portrait              # lock orientation (app-wide; not undone by revert)
    #   # --- system bars during the splash (status + bottom navigation) ---
    #   status_bar_color: "#E4ECE8"               # hex or `transparent`
    #   status_bar_color_dark: "#0C1413"
    #   status_bar_icon_brightness: dark          # dark | light icons (auto from colour if unset)
    #   status_bar_icon_brightness_dark: light
    #   navigation_bar_color: "#E4ECE8"           # hex or `transparent`
    #   navigation_bar_color_dark: "#0C1413"
    #   navigation_bar_icon_brightness: dark      # dark | light icons (auto from colour if unset)
    #   navigation_bar_icon_brightness_dark: light
    #   branding: assets/wordmark.svg             # bottom branding (SVG/raster, 200×80dp slot)
    #   branding_dark: assets/wordmark_dark.svg   # dark-mode branding variant
    #   branding_text: "My App"                   # text wordmark when no branding image is given
    #   branding_text_color: "#1F5560"            # branding text colour (auto-contrasts the bg if unset)
    #   branding_text_color_dark: "#E6F2F4"
    #   branding_mode: bottom                     # bottom | bottom_left | bottom_right (pre-31 + fallback)
    #   branding_bottom_padding: 48               # branding distance from bottom edge, dp
    #   # --- in-app Flutter splash (AdaptiveSplash) ---
    #   flutter_splash_all_versions: false        # show the in-app splash on every OS version
    #                                             #   (default: only where there's no native one, API < 31)
    #   # --- animated centre icon, instead of the static `image` above ---
    #   animated_icon: assets/logo_anim.xml       # ready-made AnimatedVectorDrawable (.xml), used as-is
    #   animated_icon_dark: assets/logo_anim_dark.xml
    #   duration: 1000                            # animated-icon duration, ms

  # --- iOS app icon (single-size 1024², opaque; same source as Android) ------
  # One source drives every size. iOS icons can't be transparent, so the art is
  # composited onto `background`. `dark`/`tinted` add the iOS 18 variants.
  # ios:
  #   icon:
  #     image: assets/logo.svg          # SVG or raster; falls back to root `source` / the Android foreground
  #     background: "#FFFFFF"           # opaque fill behind the icon
  #     dark: assets/logo_dark.svg      # iOS 18 dark appearance (optional)
  #     background_dark: "#000000"      # opaque fill behind the dark icon
  #     tinted: assets/logo_mono.svg    # iOS 18 tinted appearance (optional; grayscale)
  #     padding: 0                      # % the art is inset (0 = use the source's own framing)
  #   splash:                           # LaunchScreen — centred logo on a background colour
  #     background: "#FFFFFF"           # falls back to the Android splash background
  #     background_dark: "#000000"
  #     image: assets/logo.svg          # centred logo (transparent over the background)
  #     image_dark: assets/logo_dark.svg
  #     logo_size: 192                  # logo edge length in points

  # --- build flavors (one file, base + per-flavor overrides) -----------------
  # A flavor accepts EVERY key the config above supports — write it the same way.
  # It deep-merges over the base: keys you omit are inherited, scalars you set
  # replace, nested maps merge, and you can add a whole section the base lacks.
  # Output goes to that flavor's `src/<name>/res` overlay. Generate with:
  #   dart run flutter_adaptive_studio generate --flavor dev
  # flavors:
  #   dev:
  #     android:
  #       icon:
  #         adaptive:
  #           background: "#00C853"          # override just this; foreground inherited
  #       splash:
  #         background: "#00C853"
  #         branding_mode: bottom_right
  #   prod:
  #     android:
  #       icon:
  #         adaptive:
  #           foreground: assets/logo_prod.svg
''';
}

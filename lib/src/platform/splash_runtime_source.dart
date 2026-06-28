/// The self-contained runtime that the CLI bakes into the user's
/// `fas_splash.g.dart` (see [splashConfigDart]). It's a single raw string of
/// Dart so the generated file depends on **nothing but `package:flutter`** — no
/// `flutter_adaptive_studio`, no `image`/`xml`, no `package:ffi` — which is what
/// lets the app stay conflict-free.
///
/// Kept as a string (not a real library) on purpose: the published package is a
/// pure-Dart CLI with no Flutter dependency, so this Flutter code can't live in
/// `lib/` as analysed source. The `generated splash widget compiles` test
/// generates a file from this and analyses it, so breakage is still caught.
library;

/// The class/function bodies emitted after the config object. Imports and the
/// `fasSplash` instance are written separately by [splashConfigDart]; the
/// `_b64` helper is appended only when there are embedded bytes.
const String splashRuntimeSource = r'''
/// Immutable splash configuration consumed by [AdaptiveSplash]. Generated — all
/// colours are 0xAARRGGBB ints and all artwork is pre-rasterised PNG bytes.
@immutable
class FasSplashConfig {
  const FasSplashConfig({
    required this.backgroundLight,
    required this.backgroundDark,
    this.logo,
    this.logoDark,
    this.brandingLight,
    this.brandingDark,
    this.brandingText,
    this.brandingTextColorLight = 0xFF000000,
    this.brandingTextColorDark = 0xFFFFFFFF,
    this.brandingAlignment = Alignment.bottomCenter,
    this.brandingBottomPadding = 48,
    this.backgroundImageLight,
    this.backgroundImageDark,
    this.logoSize = 192,
    this.iosBackgroundLight,
    this.iosBackgroundDark,
    this.iosLogo,
    this.iosLogoDark,
    this.iosLogoSize,
    this.duration = const Duration(milliseconds: 800),
    this.fadeDuration = const Duration(milliseconds: 350),
    this.showOnAllVersions = false,
  });

  /// Splash background colour (0xAARRGGBB), light and dark (system) appearance.
  final int backgroundLight;
  final int backgroundDark;

  /// Centre logo PNG bytes (already rasterised), or null for a colour-only
  /// splash; [logoDark] is the optional dark-appearance variant.
  final Uint8List? logo;
  final Uint8List? logoDark;

  /// Bottom branding image PNG bytes (light / dark), or null.
  final Uint8List? brandingLight;
  final Uint8List? brandingDark;

  /// Text wordmark used when no branding image is configured, and its colours.
  final String? brandingText;
  final int brandingTextColorLight;
  final int brandingTextColorDark;

  /// Branding placement + distance from the bottom edge (logical px).
  final Alignment brandingAlignment;
  final double brandingBottomPadding;

  /// Full-bleed background image PNG bytes (light / dark), drawn behind the logo.
  final Uint8List? backgroundImageLight;
  final Uint8List? backgroundImageDark;

  /// Centre-logo edge length (logical px).
  final double logoSize;

  /// iOS overrides — used on iOS to match the iOS LaunchScreen (null = reuse the
  /// values above). Branding is never drawn on iOS.
  final int? iosBackgroundLight;
  final int? iosBackgroundDark;
  final Uint8List? iosLogo;
  final Uint8List? iosLogoDark;
  final double? iosLogoSize;

  /// How long the splash is held before it fades, and the fade length.
  final Duration duration;
  final Duration fadeDuration;

  /// When true the splash shows on every OS version; when false (default) only
  /// where there's no native animated splash (Android API < 31).
  final bool showOnAllVersions;
}

/// Wraps your app and shows the matching Flutter splash over it until startup
/// settles, then fades out. Wrap once: `runApp(AdaptiveSplash(config: fasSplash,
/// child: const MyApp()))`.
class AdaptiveSplash extends StatefulWidget {
  const AdaptiveSplash({
    super.key,
    required this.config,
    required this.child,
    this.ready,
    this.force,
  });

  /// The generated configuration (`fasSplash`).
  final FasSplashConfig config;

  /// Your app — typically the `MaterialApp`. It builds underneath the splash.
  final Widget child;

  /// Optional readiness signal: the splash is held until BOTH this future
  /// completes AND [FasSplashConfig.duration] has elapsed.
  final Future<void>? ready;

  /// Overrides [FasSplashConfig.showOnAllVersions] when set.
  final bool? force;

  @override
  State<AdaptiveSplash> createState() => _AdaptiveSplashState();
}

class _AdaptiveSplashState extends State<AdaptiveSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: widget.config.fadeDuration,
    value: 1,
  );
  bool _show = true;

  @override
  void initState() {
    super.initState();
    _drive();
  }

  Future<void> _drive() async {
    final showOnAll = widget.force ?? widget.config.showOnAllVersions;
    final hold = showOnAll || _noNativeAnimatedSplash();
    if (hold) {
      await Future.wait<void>([
        Future<void>.delayed(widget.config.duration),
        if (widget.ready != null) widget.ready!.catchError((_) {}),
      ]);
    }
    if (!mounted) return;
    await _fade.reverse();
    if (mounted) setState(() => _show = false);
  }

  /// True when the platform has no Android-12 `SplashScreen` to hand off from —
  /// any non-Android target, or Android below API 31.
  static bool _noNativeAnimatedSplash() {
    final sdk = _androidSdkInt();
    return sdk == null || sdk < 31;
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_show)
            FadeTransition(
              opacity: _fade,
              child: IgnorePointer(child: _SplashView(config: widget.config)),
            ),
        ],
      ),
    );
  }
}

/// The splash visual: background (colour + optional image), centred logo, and
/// bottom branding. Theme-aware via the system brightness.
class _SplashView extends StatelessWidget {
  const _SplashView({required this.config});

  final FasSplashConfig config;

  @override
  Widget build(BuildContext context) {
    final dark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark;
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;

    final bgLight =
        (isIos ? config.iosBackgroundLight : null) ?? config.backgroundLight;
    final bgDark = (isIos
            ? (config.iosBackgroundDark ?? config.iosBackgroundLight)
            : null) ??
        config.backgroundDark;
    final bgColor = Color(dark ? bgDark : bgLight);

    final logoLight = (isIos ? config.iosLogo : null) ?? config.logo;
    final logoDark = (isIos ? (config.iosLogoDark ?? config.iosLogo) : null) ??
        config.logoDark ??
        config.logo;
    final logo = dark ? logoDark : logoLight;
    final logoSize = (isIos ? config.iosLogoSize : null) ?? config.logoSize;

    final bgImage = isIos
        ? null
        : (dark
            ? (config.backgroundImageDark ?? config.backgroundImageLight)
            : config.backgroundImageLight);
    final branding = isIos
        ? null
        : (dark
            ? (config.brandingDark ?? config.brandingLight)
            : config.brandingLight);
    final showText = !isIos && branding == null && config.brandingText != null;

    return ColoredBox(
      color: bgColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (bgImage != null)
            Positioned.fill(
              child: Image.memory(bgImage,
                  fit: BoxFit.cover, gaplessPlayback: true),
            ),
          if (logo != null)
            Center(
              child: Image.memory(logo,
                  width: logoSize, height: logoSize, gaplessPlayback: true),
            ),
          if (branding != null || showText)
            Align(
              alignment: config.brandingAlignment,
              child: Padding(
                padding: EdgeInsets.only(bottom: config.brandingBottomPadding),
                child: branding != null
                    ? Image.memory(branding, height: 40, gaplessPlayback: true)
                    : Text(
                        config.brandingText!,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(dark
                              ? config.brandingTextColorDark
                              : config.brandingTextColorLight),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Keeps the **native** splash on screen while your app finishes starting up
/// (no white flash). Pure Flutter framework — defers the first frame until you
/// call [remove]. Drop-in for `flutter_native_splash`'s `preserve`/`remove`.
class FasNativeSplash {
  FasNativeSplash._();

  static WidgetsBinding? _binding;
  static Timer? _failsafe;

  /// Whether the first frame is currently being held back.
  static bool get isPreserved => _binding != null;

  /// Call right after `WidgetsFlutterBinding.ensureInitialized()`, before
  /// `runApp()`, to hold the native splash during startup. [maxDuration] is an
  /// optional failsafe that releases it automatically if [remove] is never
  /// called. Calling it twice is a no-op.
  static void preserve({
    required WidgetsBinding widgetsBinding,
    Duration? maxDuration,
  }) {
    if (_binding != null) return;
    _binding = widgetsBinding..deferFirstFrame();
    if (maxDuration != null) {
      _failsafe = Timer(maxDuration, () {
        if (_binding != null) {
          debugPrint('FasNativeSplash: maxDuration elapsed before remove() — '
              'releasing the splash as a failsafe.');
          remove();
        }
      });
    }
  }

  /// Lets Flutter paint its first frame. Call once your app is ready —
  /// idempotent, and a no-op if [preserve] was never called.
  static void remove() {
    _failsafe?.cancel();
    _failsafe = null;
    _binding?.allowFirstFrame();
    _binding = null;
  }
}

// Android API level via libc's __system_property_get, using only core dart:ffi
// (no package:ffi) so the app needs no extra dependency. Returns null off
// Android or on any failure — the splash then just shows (harmless). dart:ffi
// is unavailable on web, so the generated splash targets Android + iOS.
typedef _PropGetC = Int32 Function(Pointer<Uint8>, Pointer<Uint8>);
typedef _PropGetDart = int Function(Pointer<Uint8>, Pointer<Uint8>);
typedef _MallocC = Pointer<Uint8> Function(IntPtr);
typedef _MallocDart = Pointer<Uint8> Function(int);
typedef _FreeC = Void Function(Pointer<Uint8>);
typedef _FreeDart = void Function(Pointer<Uint8>);

int? _sdkCache;
bool _sdkResolved = false;

int? _androidSdkInt() {
  if (_sdkResolved) return _sdkCache;
  _sdkResolved = true;
  if (defaultTargetPlatform != TargetPlatform.android) return _sdkCache = null;
  try {
    final libc = DynamicLibrary.open('libc.so');
    final malloc = libc.lookupFunction<_MallocC, _MallocDart>('malloc');
    final free = libc.lookupFunction<_FreeC, _FreeDart>('free');
    final getProp =
        libc.lookupFunction<_PropGetC, _PropGetDart>('__system_property_get');
    const key = 'ro.build.version.sdk';
    final keyPtr = malloc(key.length + 1);
    final valPtr = malloc(92); // Android PROP_VALUE_MAX.
    try {
      final keyBytes = keyPtr.asTypedList(key.length + 1);
      for (var i = 0; i < key.length; i++) {
        keyBytes[i] = key.codeUnitAt(i);
      }
      keyBytes[key.length] = 0;
      final len = getProp(keyPtr, valPtr);
      if (len <= 0) return _sdkCache = null;
      final valBytes = valPtr.asTypedList(len);
      return _sdkCache = int.tryParse(String.fromCharCodes(valBytes));
    } finally {
      free(keyPtr);
      free(valPtr);
    }
  } on Object {
    return _sdkCache = null;
  }
}
''';

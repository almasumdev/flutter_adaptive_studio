/// Runtime API for the splash feature. This is the only part of the package the
/// app imports and calls at runtime; everything else is the generator (CLI) that
/// writes native files. Kept dependency-light (just `flutter`) and free of
/// `dart:io` so it works on every Flutter target.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

/// Keeps the **native** splash on screen while your app finishes starting up —
/// instead of a blank/white frame the instant Flutter's engine is ready but your
/// first screen isn't. It holds the windowBackground (Android < 12) /
/// SplashScreen (Android 12+) / iOS launch screen the OS already shows.
///
/// Pure Flutter framework: it defers the first frame until you call [remove].
/// No native code, no method channel.
///
/// ```dart
/// Future<void> main() async {
///   final binding = WidgetsFlutterBinding.ensureInitialized();
///   FasNativeSplash.preserve(widgetsBinding: binding);
///   await loadEverything();   // your startup work
///   runApp(const MyApp());
///   FasNativeSplash.remove();  // right after runApp() — NOT in a post-frame
///                              // callback (it won't fire while deferred)
/// }
/// ```
///
/// Migrating from `flutter_native_splash`? The `preserve`/`remove` signatures
/// match (the extra params are optional), so it's a drop-in swap — with two
/// robustness guards that package lacks: an optional [maxDuration] failsafe and
/// double-`preserve` protection (see below).
class FasNativeSplash {
  FasNativeSplash._();

  static WidgetsBinding? _binding;
  static Timer? _failsafe;

  /// Whether the first frame is currently being held back (between [preserve]
  /// and [remove]). Handy in tests or to avoid a double-call.
  static bool get isPreserved => _binding != null;

  /// Call right after `WidgetsFlutterBinding.ensureInitialized()` in `main()`,
  /// BEFORE `runApp()`. Holds back Flutter's first frame so the native splash
  /// stays visible during your startup work (async init, first build, etc.).
  ///
  /// [maxDuration] is an optional **failsafe**: if [remove] hasn't been called
  /// within it, the splash is released automatically. This is the safety net
  /// flutter_native_splash doesn't have — without it, a forgotten `remove()` or
  /// an exception thrown during startup strands the app on the splash *forever*
  /// (the frozen/white screen). Leave it null to match the classic behaviour;
  /// set e.g. `const Duration(seconds: 10)` for a guaranteed escape hatch.
  ///
  /// Calling [preserve] while already preserving is a no-op (it won't
  /// double-defer the first frame, which would otherwise need two [remove]s).
  static void preserve({
    required WidgetsBinding widgetsBinding,
    Duration? maxDuration,
  }) {
    if (_binding != null) return; // already holding the frame — don't re-defer.
    _binding = widgetsBinding..deferFirstFrame();
    if (maxDuration != null) {
      _failsafe = Timer(maxDuration, () {
        if (_binding != null) {
          debugPrint('FasNativeSplash: maxDuration ($maxDuration) elapsed '
              'before remove() — releasing the splash as a failsafe.');
          remove();
        }
      });
    }
  }

  /// Lets Flutter paint its first frame, replacing the native splash with your
  /// UI. Call once your app is ready. Idempotent — safe to call more than once,
  /// and a no-op if [preserve] was never called.
  static void remove() {
    _failsafe?.cancel();
    _failsafe = null;
    _binding?.allowFirstFrame();
    _binding = null;
  }
}

/// Runtime API for the splash feature. This is the only part of the package the
/// app imports and calls at runtime; everything else is the generator (CLI) that
/// writes native files. Kept dependency-light (just `flutter`) and free of
/// `dart:io` so it works on every Flutter target.
library;

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
/// void main() {
///   final binding = WidgetsFlutterBinding.ensureInitialized();
///   FasNativeSplash.preserve(widgetsBinding: binding);
///   runApp(const MyApp());
/// }
/// // ...once your first screen is ready to be shown:
/// FasNativeSplash.remove();
/// ```
///
/// Migrating from `flutter_native_splash`? The `preserve`/`remove` signatures
/// match, so it's a drop-in swap.
class FasNativeSplash {
  FasNativeSplash._();

  static WidgetsBinding? _binding;

  /// Call right after `WidgetsFlutterBinding.ensureInitialized()` in `main()`,
  /// BEFORE `runApp()`. Holds back Flutter's first frame so the native splash
  /// stays visible during your startup work (async init, first build, etc.).
  static void preserve({required WidgetsBinding widgetsBinding}) {
    _binding = widgetsBinding..deferFirstFrame();
  }

  /// Lets Flutter paint its first frame, replacing the native splash with your
  /// UI. Call once your app is ready. Safe to call more than once.
  static void remove() {
    _binding?.allowFirstFrame();
    _binding = null;
  }
}

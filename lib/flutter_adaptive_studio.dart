/// flutter_adaptive_studio — vector-native, theme-aware launcher icons and a
/// genuinely animated splash for Flutter (Android + iOS).
///
/// This main library is the **runtime** API your app imports. The headline is
/// [AdaptiveSplash] — wrap your app once and the in-app splash that matches the
/// native one is handled for you (no extra dependency, nothing to wire up).
/// After importing this library and the generated `fas_splash.g.dart`:
///
/// ```dart
/// void main() {
///   runApp(AdaptiveSplash(config: fasSplash, child: const MyApp()));
/// }
/// ```
///
/// For low-level control there's also [FasNativeSplash] (hold the *native*
/// splash through pre-`runApp` startup, like `flutter_native_splash`).
///
/// The icon/splash **generator** (the `flutter_adaptive_studio` CLI) lives in a
/// separate library — import `package:flutter_adaptive_studio/generator.dart` if
/// you need it programmatically.
library;

export 'src/runtime/adaptive_splash.dart';
export 'src/runtime/native_splash.dart';

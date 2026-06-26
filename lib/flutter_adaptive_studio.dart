/// flutter_adaptive_studio — vector-native, theme-aware launcher icons and a
/// genuinely animated splash for Flutter (Android + iOS).
///
/// This main library is the **runtime** API your app imports — currently
/// [FasNativeSplash], used like `flutter_native_splash`:
///
/// ```dart
/// import 'package:flutter_adaptive_studio/flutter_adaptive_studio.dart';
///
/// void main() {
///   final binding = WidgetsFlutterBinding.ensureInitialized();
///   FasNativeSplash.preserve(widgetsBinding: binding);
///   runApp(const MyApp());
/// }
/// ```
///
/// The icon/splash **generator** (the `flutter_adaptive_studio` CLI) lives in a
/// separate library so this one stays lightweight and `dart:io`-free — import
/// `package:flutter_adaptive_studio/generator.dart` if you need it
/// programmatically.
library;

export 'src/runtime/native_splash.dart';

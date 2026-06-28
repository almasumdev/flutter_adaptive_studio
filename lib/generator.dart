/// flutter_adaptive_studio — generator (CLI) API.
///
/// This is the programmatic surface behind the `flutter_adaptive_studio` command
/// that writes native icon/splash files. It uses `dart:io`. This is a pure-Dart
/// CLI: your app never depends on it. The in-app splash widget (`AdaptiveSplash`)
/// is **generated** into a self-contained `fas_splash.g.dart` that imports only
/// `package:flutter`.
///
/// The entry point is [AdaptiveStudio] (run generation); the other classes back
/// the individual CLI commands ([Initializer], [ConfigSync], [Doctor],
/// [Reverter]). Config parsing, SVG handling and the per-platform writers are
/// internal implementation details and not part of the public API.
library;

export 'src/config_sync.dart';
export 'src/doctor.dart';
export 'src/initializer.dart';
export 'src/logger.dart';
export 'src/platform/platform_generator.dart' show GenerationReport;
export 'src/reverter.dart';
export 'src/studio.dart';

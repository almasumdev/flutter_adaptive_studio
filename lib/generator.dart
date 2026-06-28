/// flutter_adaptive_studio — generator (CLI) API.
///
/// This is the programmatic surface behind the `flutter_adaptive_studio` command
/// that writes native icon/splash files. It uses `dart:io` and is **not** meant
/// to be imported by your app at runtime — for that, import the package's main
/// library (`package:flutter_adaptive_studio/flutter_adaptive_studio.dart`),
/// which exposes [FasNativeSplash] and [AdaptiveSplash].
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

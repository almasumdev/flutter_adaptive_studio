/// flutter_adaptive_studio — generator (CLI) API.
///
/// This is the programmatic surface behind the `flutter_adaptive_studio` command
/// that writes native icon/splash files. It uses `dart:io` and is **not** meant
/// to be imported by your app at runtime — for that, import the package's main
/// library (`package:flutter_adaptive_studio/flutter_adaptive_studio.dart`),
/// which exposes [FasNativeSplash].
library;

export 'src/config/config.dart';
export 'src/config/config_loader.dart' show ConfigLoader, ConfigException;
export 'src/config_sync.dart';
export 'src/doctor.dart';
export 'src/geometry/adaptive_geometry.dart';
export 'src/graphic/svg_document.dart';
export 'src/initializer.dart';
export 'src/logger.dart';
export 'src/platform/platform_generator.dart';
export 'src/preview/preview_generator.dart';
export 'src/reverter.dart';
export 'src/studio.dart';
export 'src/vector/svg_writer.dart';
export 'src/vector/vector_drawable_writer.dart';

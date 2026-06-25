/// flutter_adaptive_studio — vector-native, theme-aware, mask-correct launcher
/// icons and (soon) animated splash screens for Flutter.
///
/// Public API surface. The CLI in `bin/` is a thin wrapper over [AdaptiveStudio].
library;

export 'src/config/config.dart';
export 'src/config/config_loader.dart' show ConfigLoader, ConfigException;
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

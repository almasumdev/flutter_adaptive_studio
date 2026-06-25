/// Android platform entry point. Dispatches to icon generation now; splash
/// (Phase 2) plugs in here next.
library;

import '../../config/config.dart';
import '../../config/config_loader.dart';
import '../../io/res_writer.dart';
import '../../logger.dart';
import '../platform_generator.dart';
import 'android_icons.dart';
import 'android_paths.dart';
import 'android_splash.dart';

class AndroidGenerator extends PlatformGenerator {
  AndroidGenerator({
    required this.config,
    required this.loader,
    required this.logger,
    this.flavor,
  });

  final AdaptiveStudioConfig config;
  final ConfigLoader loader;
  final Logger logger;

  /// Build flavor → output goes to the `src/<flavor>/res` overlay.
  final String? flavor;

  @override
  String get name => 'Android';

  @override
  GenerationReport generate() {
    final report = GenerationReport();
    final android = config.android;
    if (android == null) {
      report.skipped.add('android (no android config)');
      return report;
    }

    final paths = AndroidPaths(loader.projectRoot, sourceSet: flavor ?? 'main');
    if (!paths.exists) {
      logger.warn('No android/ folder at ${loader.projectRoot} — skipping.');
      report.skipped.add('android (no android/ folder)');
      return report;
    }

    final writer = ResWriter(logger);

    if (android.icon != null) {
      report.merge(AndroidIcons(
        config: config,
        iconConfig: android.icon!,
        loader: loader,
        paths: paths,
        writer: writer,
        logger: logger,
      ).generate());
    } else {
      report.skipped.add('android.icon (not configured)');
    }

    if (android.splash != null) {
      report.merge(AndroidSplash(
        splash: android.splash!,
        loader: loader,
        paths: paths,
        writer: writer,
        logger: logger,
      ).generate());
    } else {
      report.skipped.add('android.splash (not configured)');
    }

    return report;
  }
}

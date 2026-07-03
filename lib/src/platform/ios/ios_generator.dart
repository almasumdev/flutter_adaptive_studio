/// iOS platform entry point. Dispatches to icon + splash generation.
library;

import '../../config/config.dart';
import '../../config/config_loader.dart';
import '../../logger.dart';
import '../platform_generator.dart';
import 'ios_icons.dart';
import 'ios_paths.dart';
import 'ios_splash.dart';

class IosGenerator extends PlatformGenerator {
  IosGenerator({
    required this.config,
    required this.loader,
    required this.logger,
    this.flavor,
  });

  final AdaptiveStudioConfig config;
  final ConfigLoader loader;
  final Logger logger;

  /// Build flavor → icons go to `AppIcon-<flavor>.appiconset`. The launch screen
  /// is shared (one storyboard), so it always uses the merged config.
  final String? flavor;

  @override
  String get name => 'iOS';

  @override
  GenerationReport generate() {
    final report = GenerationReport();
    final ios = config.ios;
    if (ios == null) {
      report.skipped.add('ios (no ios config)');
      return report;
    }

    final paths = IosPaths(loader.projectRoot);
    if (!paths.exists) {
      logger.warn('No ios/ folder at ${loader.projectRoot}; skipping.');
      report.skipped.add('ios (no ios/ folder)');
      return report;
    }

    if (ios.icon != null) {
      report.merge(IosIcons(
        config: config,
        iconConfig: ios.icon!,
        loader: loader,
        paths: paths,
        logger: logger,
        flavor: flavor,
      ).generate());
    } else {
      report.skipped.add('ios.icon (not configured)');
    }

    if (ios.splash != null) {
      report.merge(IosSplash(
        config: config,
        splash: ios.splash!,
        loader: loader,
        paths: paths,
        logger: logger,
      ).generate());
    } else {
      report.skipped.add('ios.splash (not configured)');
    }

    return report;
  }
}

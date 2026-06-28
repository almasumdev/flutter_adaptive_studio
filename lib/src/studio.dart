/// Top-level orchestrator: load config → run the configured platform generators.
library;

import 'config/config_loader.dart';
import 'logger.dart';
import 'platform/android/android_generator.dart';
import 'platform/ios/ios_generator.dart';
import 'platform/platform_generator.dart';
import 'platform/splash_config_writer.dart';

class AdaptiveStudio {
  AdaptiveStudio({
    required this.projectRoot,
    this.configPath,
    this.flavor,
    Logger? logger,
  }) : logger = logger ?? Logger();

  final String projectRoot;
  final String? configPath;

  /// Optional build flavor — merges the `flavors.<flavor>` config overrides and
  /// writes resources into the `src/<flavor>/res` overlay.
  final String? flavor;
  final Logger logger;

  /// Runs generation for every configured platform. Returns the combined report,
  /// or `null` if no config was found.
  GenerationReport? run() {
    final loader = ConfigLoader(projectRoot);
    final config = loader.load(explicitPath: configPath, flavor: flavor);
    if (config == null) {
      logger.error('No `flutter_adaptive_studio` config found (checked '
          'flutter_adaptive_studio.yaml and pubspec.yaml).');
      return null;
    }
    if (flavor != null) logger.info('▸ flavor: $flavor → src/$flavor/res');

    final report = GenerationReport();
    if (config.hasAndroid) {
      logger.info('▸ Android');
      report.merge(
        AndroidGenerator(
                config: config, loader: loader, logger: logger, flavor: flavor)
            .generate(),
      );
    } else {
      logger.skip('android: not configured');
    }

    if (config.hasIos) {
      logger.info('▸ iOS');
      report.merge(
        IosGenerator(
                config: config, loader: loader, logger: logger, flavor: flavor)
            .generate(),
      );
    } else {
      logger.skip('ios: not configured');
    }

    // In-app splash config (the package's AdaptiveSplash). Platform-agnostic, so
    // it's written once for whichever platform(s) configured a splash — including
    // an iOS-only project.
    SplashConfigWriter(config: config, loader: loader, logger: logger)
        .write(report);

    return report;
  }
}

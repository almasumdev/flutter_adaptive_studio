/// `doctor` — validates config + environment before generating. Reports what's
/// configured, whether referenced sources exist, and which rasteriser backend
/// is available, without writing anything.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'config/config.dart';
import 'config/config_loader.dart';
import 'logger.dart';
import 'platform/android/android_paths.dart';
import 'raster/rasterizer_factory.dart';

/// Validates config and environment, reporting issues without writing anything.
class Doctor {
  /// Creates a doctor for [projectRoot], optionally scoped to [configPath]/[flavor].
  Doctor(
      {required this.projectRoot, this.configPath, this.flavor, Logger? logger})
      : logger = logger ?? Logger();

  /// Absolute path to the Flutter project being checked.
  final String projectRoot;

  /// Explicit config file path, or null to auto-discover.
  final String? configPath;

  /// Flavor/source-set to check, or null for `main`.
  final String? flavor;

  /// Sink for diagnostic output.
  final Logger logger;

  /// Returns true if no blocking problems were found.
  bool run() {
    var ok = true;
    void check(bool pass, String msg) {
      logger.info('  ${pass ? '✓' : '⚠'} $msg');
      if (!pass) ok = false;
    }

    final loader = ConfigLoader(projectRoot);
    final AdaptiveStudioConfig? config;
    try {
      config = loader.load(explicitPath: configPath, flavor: flavor);
    } on ConfigException catch (e) {
      logger.error('Config error: ${e.message}');
      return false;
    }
    if (config == null) {
      logger.error('No flutter_adaptive_studio config found.');
      return false;
    }

    logger.info('Config');
    check(config.hasAndroid, 'android section present');

    final android = config.android;
    if (android != null) {
      final paths = AndroidPaths(projectRoot, sourceSet: flavor ?? 'main');
      check(paths.exists, 'android/ project folder exists');
      check(File(paths.manifest).existsSync(), 'AndroidManifest.xml found');

      final icon = android.icon;
      if (icon?.adaptive != null) {
        logger.info('Icon sources');
        _src(check, loader, icon!.adaptive!.foreground ?? config.source,
            'adaptive foreground');
        if (icon.adaptive!.background != null &&
            !icon.adaptive!.backgroundIsColor) {
          _src(check, loader, icon.adaptive!.background, 'adaptive background');
        }
        _srcOptional(check, loader, icon.adaptive!.monochrome, 'monochrome');
        _srcOptional(check, loader, icon.image, 'icon.image (legacy/store)');
        _srcOptional(check, loader, icon.themed?.light, 'themed light');
        _srcOptional(check, loader, icon.themed?.dark, 'themed dark');
      }

      if (android.splash != null) {
        logger.info('Splash sources');
        _srcOptional(
            check, loader, android.splash!.animatedIcon, 'animated_icon');
        _srcOptional(check, loader, android.splash!.animatedIconDark,
            'animated_icon_dark');
      }
    }

    final ios = config.ios;
    if (ios?.icon != null) {
      logger.info('iOS');
      check(Directory(p.join(projectRoot, 'ios')).existsSync(),
          'ios/ project folder exists');
      final iconSource = ios!.icon!.image ??
          config.source ??
          android?.icon?.adaptive?.foreground ??
          android?.icon?.image;
      _src(check, loader, iconSource, 'ios icon source');
      _srcOptional(check, loader, ios.icon!.dark, 'ios icon dark');
      _srcOptional(check, loader, ios.icon!.tinted, 'ios icon tinted');
    }

    logger.info('Environment');
    final svgStatus = RasterizerFactory().svgBackendStatus;
    final hasSvgTool = svgStatus.startsWith('SVG via');
    logger.info('  ${hasSvgTool ? '✓' : 'ℹ'} $svgStatus');
    if (!hasSvgTool) {
      logger.info('     (raster sources still work via pure-Dart; SVG legacy/'
          'store needs a tool or an icon.image PNG)');
    }

    logger.info('');
    logger
        .info(ok ? 'doctor: ready to generate.' : 'doctor: see ⚠ items above.');
    return ok;
  }

  void _src(void Function(bool, String) check, ConfigLoader loader,
      String? source, String label) {
    if (source == null) {
      check(false, '$label: not set');
      return;
    }
    check(File(loader.resolveAsset(source)).existsSync(),
        '$label: $source (${p.extension(source)})');
  }

  void _srcOptional(void Function(bool, String) check, ConfigLoader loader,
      String? source, String label) {
    if (source == null) return; // optional + absent → silent
    check(File(loader.resolveAsset(source)).existsSync(), '$label: $source');
  }
}

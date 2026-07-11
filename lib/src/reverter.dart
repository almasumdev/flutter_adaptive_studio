/// `revert` removes the files flutter_adaptive_studio fully owns (generated
/// drawables, mipmaps, animators, v31 styles, store PNG, glue/preview folder).
///
/// Shared files it only *edits* (AndroidManifest.xml, values/colors.xml,
/// values/styles.xml) are left intact and the user is pointed at version control.
/// Reverting a structured edit cleanly is VCS's job, not ours.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'config/config_loader.dart';
import 'logger.dart';
import 'platform/android/android_manifest_editor.dart';
import 'platform/android/android_paths.dart';
import 'platform/android/android_themed_icons.dart';
import 'platform/android/splash_templates.dart';
import 'platform/ios/ios_paths.dart';
import 'platform/ios/pbxproj_editor.dart';
import 'platform/ios/xcode_scheme.dart';

/// Removes the files flutter_adaptive_studio fully owns, leaving shared edits to VCS.
class Reverter {
  /// Creates a reverter for [projectRoot], optionally scoped to [configPath]/[flavor].
  Reverter(
      {required this.projectRoot, this.configPath, this.flavor, Logger? logger})
      : logger = logger ?? Logger();

  /// Absolute path to the Flutter project being reverted.
  final String projectRoot;

  /// Explicit config file path, or null to auto-discover.
  final String? configPath;

  /// Revert the `src/<flavor>/res` overlay instead of `main`.
  final String? flavor;

  /// Sink for diagnostic output.
  final Logger logger;

  /// Deletes owned generated files and returns the number of items removed.
  int run() {
    final loader = ConfigLoader(projectRoot);
    final config = loader.load(explicitPath: configPath, flavor: flavor);
    final name = config?.android?.icon?.iconName ?? 'ic_launcher';
    final paths = AndroidPaths(projectRoot, sourceSet: flavor ?? 'main');

    var removed = 0;
    void rm(String path) {
      final f = File(path);
      if (f.existsSync()) {
        f.deleteSync();
        removed++;
        logger.detail('removed ${p.relative(path, from: projectRoot)}');
      }
    }

    // Adaptive mipmap XML (base + round) and vector layers.
    for (final v in ['', '_round']) {
      rm(p.join(paths.mipmapAnydpiV26, '$name$v.xml'));
    }
    for (final v in ['_foreground', '_monochrome', '_background']) {
      rm(p.join(paths.drawableDir, '$name$v.xml'));
    }
    // Themed light/dark owned files (mipmap XML + round sibling + foreground
    // vector), sourced from the same helper `generate` uses so they can't drift.
    for (final variant in ThemedIconAssets.variants) {
      for (final f in ThemedIconAssets.ownedFiles(paths, name, variant)) {
        rm(f);
      }
    }
    // Splash drawables.
    for (final dir in [paths.drawableDir, paths.drawableNightDir]) {
      rm(p.join(dir, 'splash_icon.xml'));
      rm(p.join(dir, 'splash_icon_vector.xml'));
      rm(p.join(dir, 'splash_icon_static.xml'));
      rm(p.join(dir, 'splash_branding.xml'));
      rm(p.join(dir, 'splash_bg.xml'));
    }
    // Launch backgrounds: we overwrite drawable/ + drawable-v21/, which
    // LaunchTheme.windowBackground references, so RESTORE the stock Flutter
    // template there (deleting would dangle that ref and break the build), and
    // remove the night variants we may have written.
    for (final dir in ['drawable', 'drawable-v21']) {
      final f = File(p.join(paths.resDir, dir, 'launch_background.xml'));
      if (f.existsSync()) {
        f.writeAsStringSync(stockLaunchBackgroundXml);
        removed++;
        logger.detail('restored stock $dir/launch_background.xml');
      }
    }
    for (final dir in ['drawable-night', 'drawable-night-v21']) {
      rm(p.join(paths.resDir, dir, 'launch_background.xml'));
    }
    // Raster splash drawables (nodpi). The bg image can be PNG or WebP.
    for (final dir in ['drawable-nodpi', 'drawable-night-nodpi']) {
      rm(p.join(paths.resDir, dir, 'splash_icon.png'));
      rm(p.join(paths.resDir, dir, 'splash_branding.png'));
      for (final e in ['.png', '.webp']) {
        rm(p.join(paths.resDir, dir, 'splash_bg$e'));
      }
    }
    // Pre-31 raster splash logo + branding, per density (PNG or WebP, + night).
    for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      for (final base in ['drawable', 'drawable-night']) {
        for (final e in ['.png', '.webp']) {
          rm(p.join(paths.resDir, '$base-$d', 'splash_icon_legacy$e'));
          rm(p.join(paths.resDir, '$base-$d', 'splash_branding_legacy$e'));
          // Text branding renders a per-density `splash_branding` raster too.
          rm(p.join(paths.resDir, '$base-$d', 'splash_branding$e'));
        }
      }
    }
    // Animators.
    final animDir = Directory(paths.animatorDir);
    if (animDir.existsSync()) {
      for (final f in animDir.listSync().whereType<File>()) {
        if (p.basename(f.path).startsWith('splash_')) {
          f.deleteSync();
          removed++;
        }
      }
    }
    // API 31 styles (splash-only, owned by us).
    rm(p.join(paths.valuesV31Dir, 'styles.xml'));
    rm(p.join(paths.valuesNightV31Dir, 'styles.xml'));
    // Legacy mipmaps + store icon (PNG or WebP).
    for (final d in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      for (final e in ['.png', '.webp']) {
        rm(p.join(paths.mipmapDir(d), '$name$e'));
        rm(p.join(paths.mipmapDir(d), '${name}_round$e'));
      }
    }
    // Play Store PNG now lives in src/main; clean the legacy android/app copy too.
    rm(p.join(paths.mainSrcDir, '$name-playstore.png'));
    rm(p.join(paths.appDir, '$name-playstore.png'));

    // iOS assets. A flavor's whole AppIcon-<flavor>.appiconset is ours; the base
    // AppIcon.appiconset is shared, so only our PNGs go. The LaunchBackground
    // colour set is wholly ours.
    final ios = IosPaths(projectRoot);
    if (flavor != null) {
      final set = Directory(ios.appIconSet(flavor));
      if (set.existsSync()) {
        set.deleteSync(recursive: true);
        removed++;
      }
      // Reset the build setting we wired, so it doesn't dangle at the now-deleted
      // AppIcon-<flavor> set. Only touches configs that actually carry the key.
      final reset = PbxprojEditor(ios.pbxproj).setAppIcon(flavor!, 'AppIcon',
          onlyConfigs: XcodeScheme.buildConfigs(ios.scheme(flavor!)),
          insertIfMissing: false);
      if (reset.changed) {
        removed++;
        logger.detail(
            'reset ${reset.configs.join(', ')} app icon → AppIcon in project.pbxproj');
      }
    } else {
      for (final f in [
        'Icon-1024.png',
        'Icon-1024-dark.png',
        'Icon-1024-tinted.png'
      ]) {
        rm(p.join(ios.appIconSet(), f));
      }
    }
    final colorset =
        Directory(p.join(ios.xcassetsDir, 'LaunchBackground.colorset'));
    if (colorset.existsSync()) {
      colorset.deleteSync(recursive: true);
      removed++;
    }

    // In-app splash config (current location, lib/ or project root) + the
    // legacy `flutter_adaptive_studio/` glue folder older versions generated.
    for (final f in [
      File(p.join(projectRoot, 'lib', 'fas_splash.g.dart')),
      File(p.join(projectRoot, 'fas_splash.g.dart')),
    ]) {
      if (f.existsSync()) {
        f.deleteSync();
        removed++;
        logger.detail('removed ${p.relative(f.path, from: projectRoot)}');
      }
    }
    final glue = Directory(p.join(projectRoot, 'flutter_adaptive_studio'));
    if (glue.existsSync()) {
      glue.deleteSync(recursive: true);
      removed++;
      logger.detail('removed flutter_adaptive_studio/');
    }

    // If the themed activity-aliases remain in the (shared) manifest, they now
    // reference the mipmaps we just deleted, so the next Android build breaks.
    // This is a hard failure, not just leftover cruft, so warn specifically
    // ahead of the generic shared-files note below.
    final themedAliases =
        AndroidManifestEditor(paths.manifest).themedAliasVariants();
    if (themedAliases.isNotEmpty) {
      final refs = themedAliases.map((v) => '@mipmap/${name}_$v').join(', ');
      final aliases = themedAliases.map(ThemedIconAssets.aliasName).join(' / ');
      logger.warn(
          'Removed the themed mipmaps ($refs), but AndroidManifest.xml still '
          'has the $aliases <activity-alias> node(s) referencing them. The next '
          "Android build will FAIL ('resource mipmap/${name}_${themedAliases.first} "
          'not found\') until you restore AndroidManifest.xml (and '
          'values/colors.xml) from version control, or delete those alias '
          'node(s) by hand.');
    }

    logger.success('Reverted $removed generated item(s).');
    logger.warn(
        'Edits to shared files (AndroidManifest.xml, values/colors.xml, '
        'values/styles.xml, AppIcon.appiconset/Contents.json) were NOT reverted. '
        'Use version control for those.');
    return removed;
  }
}

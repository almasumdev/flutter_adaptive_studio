/// Resolves the standard Android resource locations within a Flutter project.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

class AndroidPaths {
  AndroidPaths(this.projectRoot, {String sourceSet = 'main'})
      : _sourceSet = sourceSet;

  final String projectRoot;
  final String _sourceSet;

  /// `android/app/src/<sourceSet>`.
  String get _srcDir =>
      p.join(projectRoot, 'android', 'app', 'src', _sourceSet);

  /// `android/app/src/<sourceSet>/res`. For a flavor source set this is the
  /// Gradle resource overlay — it overrides `main/res` for that flavor's build.
  String get resDir => p.join(_srcDir, 'res');

  /// `android/app`.
  String get appDir => p.join(projectRoot, 'android', 'app');

  /// Always the **main** manifest — flavors overlay resources (icons, colours,
  /// styles), not the manifest, so the shared `android:icon`/aliases there apply
  /// to every flavor and the flavor's `res/` swaps the actual drawables.
  String get manifest => p.join(
      projectRoot, 'android', 'app', 'src', 'main', 'AndroidManifest.xml');

  /// Density-independent vector drawables live here.
  String get drawableDir => p.join(resDir, 'drawable');

  /// Dark (night) vector drawables.
  String get drawableNightDir => p.join(resDir, 'drawable-night');

  /// Adaptive icon XML (API 26+).
  String get mipmapAnydpiV26 => p.join(resDir, 'mipmap-anydpi-v26');

  /// ObjectAnimator XML for AnimatedVectorDrawables.
  String get animatorDir => p.join(resDir, 'animator');

  String get valuesDir => p.join(resDir, 'values');
  String get valuesNightDir => p.join(resDir, 'values-night');

  /// Android 12+ (API 31) SplashScreen theme attributes.
  String get valuesV31Dir => p.join(resDir, 'values-v31');
  String get valuesNightV31Dir => p.join(resDir, 'values-night-v31');

  /// Density-specific mipmap dir for a multiplier name (e.g. `xhdpi`).
  String mipmapDir(String density) => p.join(resDir, 'mipmap-$density');

  /// Density-specific drawable dir (e.g. `drawable-xhdpi`).
  String drawableDensityDir(String density) =>
      p.join(resDir, 'drawable-$density');

  /// True if the target looks like a Flutter Android project.
  bool get exists => Directory(p.join(projectRoot, 'android')).existsSync();
}

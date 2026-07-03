/// Resolves the standard iOS app-icon locations within a Flutter project.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

class IosPaths {
  IosPaths(this.projectRoot);

  final String projectRoot;

  /// `ios/Runner`.
  String get runnerDir => p.join(projectRoot, 'ios', 'Runner');

  /// `ios/Runner/Assets.xcassets`.
  String get xcassetsDir => p.join(runnerDir, 'Assets.xcassets');

  /// The app-icon set directory. Base build uses Flutter's `AppIcon.appiconset`;
  /// a flavor uses `AppIcon-<flavor>.appiconset` (wire it per scheme via
  /// `ASSETCATALOG_COMPILER_APPICON_NAME`).
  String appIconSet([String? flavor]) => p.join(xcassetsDir,
      flavor == null ? 'AppIcon.appiconset' : 'AppIcon-$flavor.appiconset');

  /// `ios/Runner.xcodeproj/project.pbxproj`: where build-configuration settings
  /// (e.g. `ASSETCATALOG_COMPILER_APPICON_NAME`) live.
  String get pbxproj =>
      p.join(projectRoot, 'ios', 'Runner.xcodeproj', 'project.pbxproj');

  /// The shared scheme for [flavor]: `.../xcshareddata/xcschemes/<flavor>.xcscheme`.
  String scheme(String flavor) => p.join(projectRoot, 'ios', 'Runner.xcodeproj',
      'xcshareddata', 'xcschemes', '$flavor.xcscheme');

  /// True if the target looks like a Flutter iOS project.
  bool get exists => Directory(p.join(projectRoot, 'ios')).existsSync();
}

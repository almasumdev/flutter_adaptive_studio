/// Reads the build configurations a shared Xcode scheme actually uses.
///
/// A Flutter iOS flavor is a **scheme** (`flutter run --flavor dev` runs the
/// `dev` scheme), and the scheme's action nodes carry `buildConfiguration="..."`
/// attributes naming the exact configs to build. Reading those is authoritative:
/// it doesn't assume the common `Debug-<flavor>` naming convention, so it
/// works even when a project names its configs differently.
library;

import 'dart:io';

import 'package:xml/xml.dart';

class XcodeScheme {
  /// Every distinct `buildConfiguration` referenced by the scheme at
  /// [schemePath] (Launch/Test/Profile/Analyze/Archive actions). Empty if the
  /// file is absent or unparseable. The caller then falls back to convention.
  static Set<String> buildConfigs(String schemePath) {
    final file = File(schemePath);
    if (!file.existsSync()) return const {};
    try {
      return XmlDocument.parse(file.readAsStringSync())
          .descendants
          .whereType<XmlElement>()
          .map((e) => e.getAttribute('buildConfiguration'))
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toSet();
    } on XmlException {
      return const {};
    }
  }
}

/// Surgically sets a build setting on a flavor's build configurations inside
/// `project.pbxproj`, without a full pbxproj parser.
///
/// Why this is safe without parsing the whole (OpenStep-plist) format: inside an
/// Xcode `buildSettings = { … }` block there are **no nested braces** — values
/// are scalars, quoted strings, or `( … )` arrays. So a build-settings block
/// runs from its `{` to the very next `}`. We scope to the `XCBuildConfiguration`
/// section, find each configuration by its trailing `name = …;`, and set exactly
/// one key inside that object's build-settings block — touching nothing else.
///
/// If the project doesn't follow the standard Flutter flavor convention (no
/// `*-<flavor>` configurations), we change nothing and report it, so the caller
/// can fall back to printing a manual instruction.
library;

import 'dart:io';

/// Outcome of [PbxprojEditor.setAppIcon].
class PbxprojResult {
  PbxprojResult(this.configs, this.backupPath);

  /// Build configurations that carry the flavor (e.g. `Debug-dev`,
  /// `Release-dev`, `Profile-dev`). Empty ⇒ nothing matched / file absent.
  final List<String> configs;

  /// Where the pre-edit file was backed up, or `null` if nothing was written
  /// (no match, or the setting was already correct).
  final String? backupPath;

  /// True when the file was actually modified this run.
  bool get changed => backupPath != null;

  /// True when matching configs were found (whether or not a write was needed).
  bool get matched => configs.isNotEmpty;
}

class PbxprojEditor {
  PbxprojEditor(this.path);

  /// Path to `project.pbxproj`.
  final String path;

  static const _key = 'ASSETCATALOG_COMPILER_APPICON_NAME';

  /// Sets `ASSETCATALOG_COMPILER_APPICON_NAME = "<iconSet>"` on the build
  /// configurations belonging to [flavor]. Idempotent; backs the file up to
  /// `<path>.bak` (once) before the first real change.
  ///
  /// [onlyConfigs] (e.g. the configs named by the flavor's scheme) restricts the
  /// match to exactly those names; when null/empty it falls back to the
  /// `Debug-<flavor>` naming convention. [insertIfMissing] false touches only
  /// configs that already carry the key (used by `revert` to reset, not add).
  PbxprojResult setAppIcon(
    String flavor,
    String iconSet, {
    Set<String>? onlyConfigs,
    bool insertIfMissing = true,
  }) {
    final file = File(path);
    if (!file.existsSync()) return PbxprojResult(const [], null);
    final original = file.readAsStringSync();

    final section = _section(original);
    if (section == null) return PbxprojResult(const [], null);

    final value = '"$iconSet"';
    final keyRe = RegExp('$_key = [^;\\n]*;');
    final explicit = onlyConfigs != null && onlyConfigs.isNotEmpty;
    final targets = <({String name, int open, int close, String newInner})>[];

    for (final m in RegExp(r'buildSettings = \{').allMatches(original)) {
      if (m.start < section.start) continue;
      if (m.start >= section.end) break;
      final open = m.end - 1; // index of '{'
      final close = original.indexOf('}', open + 1); // no nested braces here
      if (close < 0 || close > section.end) continue;

      // The object's own name follows its build-settings block.
      final nameM = RegExp(r'name = "?([^";]+)"?;')
          .firstMatch(original.substring(close, section.end));
      if (nameM == null) continue;
      final name = nameM.group(1)!;
      final matches =
          explicit ? onlyConfigs.contains(name) : _belongs(name, flavor);
      if (!matches) continue;

      final inner = original.substring(open + 1, close);
      final String newInner;
      if (keyRe.hasMatch(inner)) {
        newInner = inner.replaceFirst(keyRe, '$_key = $value;');
      } else {
        if (!insertIfMissing) continue; // reset mode: don't add where absent
        // Insert as the first setting, matching the block's indentation.
        final indent =
            RegExp(r'\n([ \t]+)\S').firstMatch(inner)?.group(1) ?? '\t\t\t\t';
        newInner = '\n$indent$_key = $value;$inner';
      }
      targets.add((name: name, open: open, close: close, newInner: newInner));
    }

    if (targets.isEmpty) return PbxprojResult(const [], null);

    // Splice from the last config backwards so earlier indices stay valid.
    targets.sort((a, b) => b.open.compareTo(a.open));
    var body = original;
    for (final t in targets) {
      body =
          body.substring(0, t.open + 1) + t.newInner + body.substring(t.close);
    }
    final names = [for (final t in targets.reversed) t.name];

    if (body == original) return PbxprojResult(names, null); // already correct

    final backup = '$path.bak';
    if (!File(backup).existsSync()) File(backup).writeAsStringSync(original);
    file.writeAsStringSync(body);
    return PbxprojResult(names, backup);
  }

  /// `name == flavor` or `name` ends with `-<flavor>` (the Flutter convention:
  /// `Debug-dev` / `Release-dev` / `Profile-dev`), case-insensitive.
  static bool _belongs(String name, String flavor) {
    final n = name.toLowerCase();
    final f = flavor.toLowerCase();
    return n == f || n.endsWith('-$f');
  }

  /// Bounds of the `XCBuildConfiguration` section, so a target's or scheme's
  /// `name = …` can never be mistaken for a build configuration.
  static ({int start, int end})? _section(String s) {
    final a = s.indexOf('/* Begin XCBuildConfiguration section */');
    if (a < 0) return null;
    final b = s.indexOf('/* End XCBuildConfiguration section */', a);
    return b < 0 ? null : (start: a, end: b);
  }
}

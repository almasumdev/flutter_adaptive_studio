import 'dart:io';

import 'package:flutter_adaptive_studio/generator.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// The complete public config surface, as a nested tree mirroring the YAML.
/// This is the contract: every key here must be documented in the `init`
/// starter **under its correct parent**. A leaf value of `null` just marks "this
/// is a documented option"; the structure (the nesting) is what's asserted.
const Map<String, dynamic> _schema = {
  'source': null,
  'android': {
    'min_sdk': null,
    'icon': {
      'icon_name': null,
      'legacy': null,
      'legacy_padding': null,
      'round': null,
      'play_store': null,
      'image_format': null,
      'image': null,
      'effect': null,
      'adaptive': {
        'foreground': null,
        'background': null,
        'monochrome': null,
        'safe_zone': null,
        'padding': null,
      },
      'themed': {
        'light': null,
        'dark': null,
        'background': null,
        'background_dark': null,
      },
    },
    'splash': {
      'background': null,
      'background_dark': null,
      'background_image': null,
      'background_image_dark': null,
      'image': null,
      'image_dark': null,
      'icon_background': null,
      'icon_background_dark': null,
      'gravity': null,
      'fullscreen': null,
      'screen_orientation': null,
      'branding': null,
      'branding_dark': null,
      'branding_mode': null,
      'branding_bottom_padding': null,
      'animated_icon': null,
      'animated_icon_dark': null,
      'duration': null,
    },
  },
  'ios': {
    'icon': {
      'image': null,
      'background': null,
      'dark': null,
      'background_dark': null,
      'tinted': null,
      'padding': null,
    },
    'splash': {
      'background': null,
      'background_dark': null,
      'image': null,
      'image_dark': null,
      'logo_size': null,
    },
  },
};

/// Every `key.path` in a (possibly nested) map, including intermediate parents.
Set<String> _paths(Map<dynamic, dynamic> m, [String prefix = '']) {
  final out = <String>{};
  m.forEach((k, v) {
    final path = prefix.isEmpty ? '$k' : '$prefix.$k';
    out.add(path);
    if (v is Map) out.addAll(_paths(v, path));
  });
  return out;
}

/// Renders the starter and reconstructs the YAML tree it documents: each
/// commented config line is uncommented (indentation preserved), and prose /
/// banner / section-rule comments are dropped, leaving valid YAML to parse.
Map<dynamic, dynamic> _starterTree(String projectRoot) {
  Initializer(projectRoot: projectRoot, logger: Logger(level: LogLevel.quiet))
      .run();
  final starter = File(p.join(projectRoot, 'flutter_adaptive_studio.yaml'))
      .readAsStringSync();

  final yaml = StringBuffer();
  final keyLine = RegExp(r'^\s*[A-Za-z_][\w]*\s*:');
  for (final line in starter.split('\n')) {
    // Peel one leading "# " marker, keeping the indentation before it. Lines
    // with no leading marker (already-active YAML) pass through untouched.
    final m = RegExp(r'^(\s*)#\s?(.*)$').firstMatch(line);
    final candidate = m == null ? line : '${m.group(1)}${m.group(2)}';
    // Keep only real key lines; drop prose ("This starter lists…"), banners and
    // "# --- section ---" rules, which aren't valid YAML.
    if (keyLine.hasMatch(candidate)) yaml.writeln(candidate);
  }

  final doc = loadYaml(yaml.toString());
  return (doc as Map)['flutter_adaptive_studio'] as Map;
}

void main() {
  late Directory project;
  setUp(() => project = Directory.systemTemp.createTempSync('fas_init_'));
  tearDown(() => project.deleteSync(recursive: true));

  test('init starter documents every config key under its correct parent', () {
    // Structural guard: parse the tree the starter documents and assert every
    // schema path is present at the right place. This is what catches a key
    // that's documented in one section but missing from another — the exact
    // "ios.icon.background_dark was absent" bug.
    final documented = _paths(_starterTree(project.path));
    final expected = _paths(_schema);
    final missing = expected.difference(documented).toList()..sort();
    expect(missing, isEmpty,
        reason: 'init starter is missing these documented paths: $missing');
  });

  test('init starter mentions every key the loader parses (new-key backstop)',
      () {
    // Auto-derived backstop: scrape every `['snake_case']` the loader reads from
    // its own source and assert the starter mentions each. Needs no maintenance
    // — it flags a brand-new option wired into the loader but never documented,
    // even before it's added to _schema above.
    Initializer(
            projectRoot: project.path, logger: Logger(level: LogLevel.quiet))
        .run();
    final yaml = File(p.join(project.path, 'flutter_adaptive_studio.yaml'))
        .readAsStringSync();
    final loaderSrc =
        File('lib/src/config/config_loader.dart').readAsStringSync();
    final keys = RegExp(r"\['([a-z][a-z_]+)'\]")
        .allMatches(loaderSrc)
        .map((m) => m.group(1)!)
        .toSet()
      ..remove('flutter_adaptive_studio'); // the wrapper key, not an option

    final missing = keys.where((k) => !yaml.contains('$k:')).toList()..sort();
    expect(missing, isEmpty,
        reason: 'init starter never mentions loader keys: $missing');
  });
}

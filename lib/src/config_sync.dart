/// `sync` — fills a user's `flutter_adaptive_studio.yaml` with any options it
/// doesn't yet mention, added as **commented** placeholders in the right
/// section, without touching a single existing line.
///
/// This is the non-destructive counterpart to `init --force`: when the package
/// gains new options, existing users run `sync` to surface them in their config
/// (keeping their values, ordering, and custom comments intact). Because every
/// inserted line is a comment, it can never break the YAML.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'initializer.dart';
import 'logger.dart';

class ConfigSync {
  ConfigSync({required this.projectRoot, this.configPath, Logger? logger})
      : logger = logger ?? Logger();

  final String projectRoot;

  /// Explicit config file; otherwise `flutter_adaptive_studio.yaml` in the root.
  final String? configPath;
  final Logger logger;

  /// A key line (active or commented) in a config file, with its dotted path.
  /// The comment marker allows several spaces (`#   key:`) since the starter
  /// indents commented keys past the `#`.
  static final _keyRe = RegExp(r'^(\s*)(#\s*)?([A-Za-z_][\w]*)\s*:');

  /// Peels a single `# ` so a commented key reads at its uncommented column —
  /// matching the starter's convention (and the init template test).
  static final _commentRe = RegExp(r'^(\s*)#\s?(.*)$');

  /// Adds missing options as commented placeholders. Returns the number added,
  /// 0 if already complete, or -1 if no config file was found.
  int run() {
    final file = _locate();
    if (file == null) {
      logger.warn('No flutter_adaptive_studio.yaml found in $projectRoot — '
          'run `init` first.');
      return -1;
    }

    final userLines = file.readAsStringSync().split('\n');
    final templateLines = Initializer.starterTemplate.split('\n');

    final templateEntries = _parse(templateLines);
    final present = _parse(userLines).map((e) => e.path).toSet();

    // Missing template options whose PARENT is already present in the user file
    // are "roots": insert each root's whole subtree (a leaf is just one line; a
    // missing section brings its children). Deeper-missing entries ride along in
    // an ancestor's block (their parent isn't present, so they're not roots).
    final inserts = <String, List<String>>{};
    final addedKeys = <String>[];
    for (final e in templateEntries) {
      if (present.contains(e.path)) continue;
      final parent = _parent(e.path);
      if (parent.isNotEmpty && !present.contains(parent)) continue;
      final block = _subtree(templateLines, templateEntries, e);
      (inserts[parent] ??= <String>[]).addAll(block);
      addedKeys.add(e.path.split('.').last);
    }

    if (inserts.isEmpty) {
      logger.success('Config already lists every option — nothing to add.');
      return 0;
    }

    final merged = _applyInserts(userLines, inserts);
    file.writeAsStringSync(merged.join('\n'));

    logger.success('Added ${addedKeys.length} option(s) to '
        '${p.relative(file.path, from: projectRoot)} as commented '
        'placeholders — uncomment what you need.');
    logger.detail('added: ${addedKeys.join(', ')}');
    logger.info('Existing values and formatting were left untouched.');
    return addedKeys.length;
  }

  File? _locate() {
    if (configPath != null) {
      final f = File(configPath!);
      return f.existsSync() ? f : null;
    }
    final standalone =
        File(p.join(projectRoot, 'flutter_adaptive_studio.yaml'));
    return standalone.existsSync() ? standalone : null;
  }

  /// Parses [lines] into key entries with their dotted path (e.g.
  /// `flutter_adaptive_studio.android.splash.image`), tracking nesting by the
  /// **logical** indent (a commented `#   key:` counts at its uncommented
  /// column). Prose comments (`# --- … ---`) are ignored.
  List<_Entry> _parse(List<String> lines) {
    final out = <_Entry>[];
    final stack = <_Entry>[];
    for (var i = 0; i < lines.length; i++) {
      final m = _keyRe.firstMatch(lines[i]);
      if (m == null) continue;
      final key = m.group(3)!;
      final indent = _logicalIndent(lines[i]);
      while (stack.isNotEmpty && stack.last.indent >= indent) {
        stack.removeLast();
      }
      final path = [
        for (final a in stack) a.path.split('.').last,
        key,
      ].join('.');
      final entry = _Entry(i, indent, path);
      out.add(entry);
      stack.add(entry);
    }
    return out;
  }

  /// The leading-space count of [line] as if uncommented (so `    #   key:` and
  /// `      key:` both read as indent 6).
  static int _logicalIndent(String line) {
    final m = _commentRe.firstMatch(line);
    final text = m == null ? line : '${m.group(1)}${m.group(2)}';
    return text.length - text.trimLeft().length;
  }

  static String _parent(String path) {
    final i = path.lastIndexOf('.');
    return i < 0 ? '' : path.substring(0, i);
  }

  /// The template lines covering [root]'s subtree: from its line up to (but not
  /// including) the next entry at the same-or-shallower indent, trailing blanks
  /// trimmed. A leaf yields one line; a section yields its whole block.
  List<String> _subtree(List<String> lines, List<_Entry> entries, _Entry root) {
    var end = lines.length;
    for (final e in entries) {
      if (e.line > root.line && e.indent <= root.indent) {
        end = e.line;
        break;
      }
    }
    while (end > root.line + 1 && lines[end - 1].trim().isEmpty) {
      end--;
    }
    return lines.sublist(root.line, end);
  }

  /// Inserts each parent's collected lines at the end of that section in the
  /// user file (bottom-up, so earlier indices stay valid).
  List<String> _applyInserts(
      List<String> lines, Map<String, List<String>> inserts) {
    final entries = _parse(lines);
    final byPath = {for (final e in entries) e.path: e};
    final jobs = <_Job>[];
    inserts.forEach((parent, ins) {
      final header = byPath[parent];
      if (header == null) return;
      jobs.add(_Job(_sectionEnd(lines, entries, header), ins));
    });
    jobs.sort((a, b) => b.at.compareTo(a.at));
    final out = [...lines];
    for (final job in jobs) {
      out.insertAll(job.at, job.lines);
    }
    return out;
  }

  /// Index just past the last line of [header]'s section (trailing blanks
  /// trimmed) — where new children should go.
  int _sectionEnd(List<String> lines, List<_Entry> entries, _Entry header) {
    var end = lines.length;
    for (final e in entries) {
      if (e.line > header.line && e.indent <= header.indent) {
        end = e.line;
        break;
      }
    }
    while (end > header.line + 1 && lines[end - 1].trim().isEmpty) {
      end--;
    }
    return end;
  }
}

class _Entry {
  _Entry(this.line, this.indent, this.path);
  final int line;
  final int indent;
  final String path;
}

class _Job {
  _Job(this.at, this.lines);
  final int at;
  final List<String> lines;
}

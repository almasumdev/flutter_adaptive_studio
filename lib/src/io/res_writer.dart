/// Filesystem writer for Android `res/` outputs.
///
/// Generated drawable XML files are fully owned by us and overwritten wholesale.
/// Shared resource files like `values/colors.xml` are edited **structurally**
/// (parse → upsert one entry → re-serialise) so we never clobber the user's
/// other colours, a direct fix for the incumbents' regex string-surgery.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

class ResWriter {
  ResWriter(this.logger);

  /// Accepts anything with a `detail(String)` method (our Logger).
  final dynamic logger;

  final List<String> written = [];

  /// Files (or entries) we deleted to keep the build consistent, surfaced in
  /// the generation report's `removed` list.
  final List<String> removed = [];

  /// Writes [content] to [absPath], creating parent directories as needed.
  void writeText(String absPath, String content) {
    final file = File(absPath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    written.add(absPath);
    logger.detail('wrote ${p.basename(absPath)}');
  }

  /// Inserts or updates a single `<color name="[name]">[hex]</color>` entry in
  /// `values/colors.xml`, preserving every other entry.
  void upsertColor(String valuesDir, String name, String hex) {
    final file = File(p.join(valuesDir, 'colors.xml'));
    XmlDocument doc;
    XmlElement resources;

    if (file.existsSync()) {
      doc = XmlDocument.parse(file.readAsStringSync());
      resources = doc.rootElement;
    } else {
      doc = XmlDocument([
        XmlProcessing('xml', 'version="1.0" encoding="utf-8"'),
        XmlElement(XmlName.parts('resources')),
      ]);
      resources = doc.rootElement;
    }

    final existing = resources.childElements.where(
        (e) => e.name.local == 'color' && e.getAttribute('name') == name);
    if (existing.isNotEmpty) {
      final el = existing.first;
      el.children
        ..clear()
        ..add(XmlText(hex));
    } else {
      resources.children.add(XmlElement(
        XmlName.parts('color'),
        [XmlAttribute(XmlName.parts('name'), name)],
        [XmlText(hex)],
      ));
    }

    file.parent.createSync(recursive: true);
    file.writeAsStringSync(doc.toXmlString(pretty: true, indent: '    '));
    written.add(file.path);
    logger.detail('upserted @color/$name in colors.xml');

    // Resolve duplicates: a `<color name="$name">` declared in a *different*
    // file in the same values dir (e.g. an Android-Studio-generated
    // `ic_launcher_background.xml`) collides with ours at build time
    // ("Duplicate resources"). colors.xml is our single source of truth, so we
    // strip the stray copy, deleting the file if that empties it.
    _removeDuplicateColor(valuesDir, name, keep: file);
  }

  /// Removes a `<color name="[name]">` element from every `*.xml` in [valuesDir]
  /// except [keep], deleting any file left with no resources.
  void _removeDuplicateColor(String valuesDir, String name,
      {required File keep}) {
    final dir = Directory(valuesDir);
    if (!dir.existsSync()) return;
    for (final entity in dir.listSync()) {
      if (entity is! File) continue;
      if (p.extension(entity.path).toLowerCase() != '.xml') continue;
      if (p.equals(entity.path, keep.path)) continue;

      final content = entity.readAsStringSync();
      if (!content.contains('name="$name"')) continue; // cheap pre-check

      final XmlDocument doc;
      try {
        doc = XmlDocument.parse(content);
      } on XmlException {
        continue; // not our concern if it doesn't even parse
      }
      final root = doc.rootElement;
      if (root.name.local != 'resources') continue;

      final dupes = root.childElements
          .where(
              (e) => e.name.local == 'color' && e.getAttribute('name') == name)
          .toList();
      if (dupes.isEmpty) continue;
      for (final e in dupes) {
        root.children.remove(e);
      }

      final base = p.basename(entity.path);
      if (root.childElements.isEmpty) {
        entity.deleteSync();
        removed.add('$base (duplicate @color/$name)');
        logger.step('removed $base: duplicate @color/$name (kept colors.xml)');
      } else {
        entity.writeAsStringSync(doc.toXmlString(pretty: true, indent: '    '));
        removed.add('@color/$name in $base (duplicate)');
        logger.step('stripped duplicate @color/$name from $base');
      }
    }
  }
}

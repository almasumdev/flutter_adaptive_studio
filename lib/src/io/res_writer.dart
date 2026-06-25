/// Filesystem writer for Android `res/` outputs.
///
/// Generated drawable XML files are fully owned by us and overwritten wholesale.
/// Shared resource files like `values/colors.xml` are edited **structurally**
/// (parse → upsert one entry → re-serialise) so we never clobber the user's
/// other colours — a direct fix for the incumbents' regex string-surgery.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

class ResWriter {
  ResWriter(this.logger);

  /// Accepts anything with a `detail(String)` method (our Logger).
  final dynamic logger;

  final List<String> written = [];

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
  }
}

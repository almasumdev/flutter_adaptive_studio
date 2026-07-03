/// Structured editor for an Android `styles.xml`.
///
/// Loads an existing file (preserving every other style/item) or creates a
/// Flutter-shaped one, then lets callers ensure a `<style>` and upsert its
/// `<item>`s. Re-serialised via the XML DOM, no string surgery.
library;

import 'dart:io';

import 'package:xml/xml.dart';

class AndroidStylesEditor {
  AndroidStylesEditor(this.path) {
    final file = File(path);
    if (file.existsSync()) {
      _doc = XmlDocument.parse(file.readAsStringSync());
    } else {
      _doc = XmlDocument([
        XmlProcessing('xml', 'version="1.0" encoding="utf-8"'),
        XmlElement(XmlName.parts('resources')),
      ]);
      _created = true;
    }
  }

  final String path;
  late final XmlDocument _doc;
  bool _created = false;

  XmlElement get _resources => _doc.rootElement;

  /// Finds the `<style name="...">`, creating it (with [parent]) if absent.
  XmlElement ensureStyle(String name, {required String parent}) {
    final found = _resources.childElements.where(
        (e) => e.name.local == 'style' && e.getAttribute('name') == name);
    if (found.isNotEmpty) return found.first;
    final style = XmlElement(XmlName.parts('style'), [
      XmlAttribute(XmlName.parts('name'), name),
      XmlAttribute(XmlName.parts('parent'), parent),
    ]);
    _resources.children.add(style);
    return style;
  }

  /// Inserts or updates `<item name="[itemName]">[value]</item>` in [style].
  void upsertItem(XmlElement style, String itemName, String value) {
    final found = style.childElements.where(
        (e) => e.name.local == 'item' && e.getAttribute('name') == itemName);
    if (found.isNotEmpty) {
      found.first.children
        ..clear()
        ..add(XmlText(value));
    } else {
      style.children.add(XmlElement(
        XmlName.parts('item'),
        [XmlAttribute(XmlName.parts('name'), itemName)],
        [XmlText(value)],
      ));
    }
  }

  /// Removes [itemName] from [style] if present (used when a feature is off).
  void removeItem(XmlElement style, String itemName) {
    style.children.removeWhere((n) =>
        n is XmlElement &&
        n.name.local == 'item' &&
        n.getAttribute('name') == itemName);
  }

  void save() {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(_doc.toXmlString(pretty: true, indent: '    '));
  }

  bool get wasCreated => _created;
}

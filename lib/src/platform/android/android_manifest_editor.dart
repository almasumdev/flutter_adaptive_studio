/// Structured (DOM-based) edits to `AndroidManifest.xml`.
///
/// We parse → mutate the `<application>` node → re-serialise. No regex on raw
/// XML and no dependence on hardcoded scaffold ids (the brittle approach the
/// incumbents take). Edits are idempotent: if nothing changes, nothing is written.
library;

import 'dart:io';

import 'package:xml/xml.dart';

class AndroidManifestEditor {
  AndroidManifestEditor(this.manifestPath);

  final String manifestPath;

  /// Ensures `android:icon` (and, when [round] is true, `android:roundIcon`) on
  /// `<application>`. Returns true if the file was modified.
  bool ensureIconAttributes(String iconName, {required bool round}) {
    final file = File(manifestPath);
    if (!file.existsSync()) return false;

    final doc = XmlDocument.parse(file.readAsStringSync());
    final app = doc.rootElement.childElements
        .where((e) => e.name.local == 'application')
        .cast<XmlElement?>()
        .firstWhere((_) => true, orElse: () => null);
    if (app == null) return false;

    var changed = false;
    changed |= _ensure(app, 'android:icon', '@mipmap/$iconName');
    if (round) {
      changed |= _ensure(app, 'android:roundIcon', '@mipmap/${iconName}_round');
    }

    if (changed) {
      file.writeAsStringSync(doc.toXmlString(pretty: true, indent: '    '));
    }
    return changed;
  }

  static bool _ensure(XmlElement el, String attr, String value) {
    if (el.getAttribute(attr) == value) return false;
    el.setAttribute(attr, value);
    return true;
  }

  /// Sets `android:screenOrientation` on the launcher `<activity>`. Returns true
  /// if the file was modified. App-wide — not just the splash.
  bool setLaunchOrientation(String orientation) {
    final file = File(manifestPath);
    if (!file.existsSync()) return false;
    final doc = XmlDocument.parse(file.readAsStringSync());
    XmlElement? launcher;
    for (final activity in doc.rootElement.descendantElements
        .where((e) => e.name.local == 'activity')) {
      final isLauncher = activity.descendantElements.any((e) =>
          e.name.local == 'category' &&
          e.getAttribute('android:name') == 'android.intent.category.LAUNCHER');
      if (isLauncher) {
        launcher = activity;
        break;
      }
    }
    if (launcher == null) return false;
    if (!_ensure(launcher, 'android:screenOrientation', orientation)) {
      return false;
    }
    file.writeAsStringSync(doc.toXmlString(pretty: true, indent: '    '));
    return true;
  }

  /// Wires up activity-aliases for full-colour light/dark icon switching.
  ///
  /// **Non-destructive:** the launcher `<activity>` keeps its LAUNCHER category
  /// (so `flutter run`, which only resolves `<activity>` launchers — not
  /// `<activity-alias>` — keeps working, and the default icon still shows). One
  /// alias per [variants] entry is *added* `enabled="false"`; the runtime glue
  /// enables the chosen one. Idempotent: existing aliases are left untouched and
  /// only missing ones are appended. Returns true if it modified the file.
  bool configureThemedAliases({
    required String iconName,
    required List<String> variants,
    required bool round,
  }) {
    final file = File(manifestPath);
    if (!file.existsSync() || variants.isEmpty) return false;
    final doc = XmlDocument.parse(file.readAsStringSync());
    final app = doc.rootElement.childElements
        .where((e) => e.name.local == 'application')
        .cast<XmlElement?>()
        .firstWhere((_) => true, orElse: () => null);
    if (app == null) return false;

    // Resolve the launcher activity for targetActivity — but DON'T modify it.
    XmlElement? launcher;
    for (final activity
        in app.childElements.where((e) => e.name.local == 'activity')) {
      final hasLauncher = activity.descendantElements.any((e) =>
          e.name.local == 'category' &&
          e.getAttribute('android:name') == 'android.intent.category.LAUNCHER');
      if (hasLauncher) {
        launcher = activity;
        break;
      }
    }
    if (launcher == null) return false;
    final targetActivity =
        launcher.getAttribute('android:name') ?? '.MainActivity';

    var changed = false;
    for (final v in variants) {
      final aliasName = '.FasIcon${_cap(v)}';
      final exists = app.childElements.any((e) =>
          e.name.local == 'activity-alias' &&
          e.getAttribute('android:name') == aliasName);
      if (exists) continue;
      app.children.add(_alias(
        name: aliasName,
        icon: '@mipmap/${iconName}_$v',
        roundIcon: round ? '@mipmap/${iconName}_${v}_round' : null,
        targetActivity: targetActivity,
      ));
      changed = true;
    }

    if (changed) {
      file.writeAsStringSync(doc.toXmlString(pretty: true, indent: '    '));
    }
    return changed;
  }

  static XmlElement _alias({
    required String name,
    required String icon,
    String? roundIcon,
    required String targetActivity,
  }) {
    final attrs = [
      XmlAttribute(XmlName.parts('android:name'), name),
      // Disabled by default: keeps the MainActivity launcher as the sole entry
      // so `flutter run` resolves it and no duplicate launcher icon appears.
      XmlAttribute(XmlName.parts('android:enabled'), 'false'),
      XmlAttribute(XmlName.parts('android:exported'), 'true'),
      XmlAttribute(XmlName.parts('android:icon'), icon),
      if (roundIcon != null)
        XmlAttribute(XmlName.parts('android:roundIcon'), roundIcon),
      XmlAttribute(XmlName.parts('android:targetActivity'), targetActivity),
    ];
    final filter = XmlElement(XmlName.parts('intent-filter'), [], [
      XmlElement(XmlName.parts('action'), [
        XmlAttribute(
            XmlName.parts('android:name'), 'android.intent.action.MAIN')
      ]),
      XmlElement(XmlName.parts('category'), [
        XmlAttribute(
            XmlName.parts('android:name'), 'android.intent.category.LAUNCHER')
      ]),
    ]);
    return XmlElement(XmlName.parts('activity-alias'), attrs, [filter]);
  }

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

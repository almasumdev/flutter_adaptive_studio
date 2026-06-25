/// Loads [AdaptiveStudioConfig] from a project.
///
/// Resolution order (first hit wins):
///   1. an explicit config file passed via `--config`
///   2. `flutter_adaptive_studio.yaml` in the project root
///   3. the `flutter_adaptive_studio:` section of `pubspec.yaml`
///
/// Parsing is deliberately tolerant: unknown keys are ignored (so config stays
/// forward-compatible) and missing optional keys fall back to defaults.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'config.dart';

/// Thrown only for genuinely malformed config (e.g. wrong shape), never for a
/// merely-absent optional value.
class ConfigException implements Exception {
  ConfigException(this.message);
  final String message;
  @override
  String toString() => 'ConfigException: $message';
}

class ConfigLoader {
  ConfigLoader(this.projectRoot);

  /// Absolute path to the target Flutter project.
  final String projectRoot;

  /// Returns the parsed config, or `null` if no config could be found.
  ///
  /// When [flavor] is given, the matching `flavors:` entry is deep-merged over
  /// the base config (one file, base + per-flavor overrides — no separate config
  /// file per flavor). The `flavors:` key itself never reaches the parser.
  AdaptiveStudioConfig? load({String? explicitPath, String? flavor}) {
    final raw = _readRawSection(explicitPath);
    if (raw == null) return null;
    if (raw is! Map) {
      throw ConfigException(
          'Expected a map at the `flutter_adaptive_studio` root.');
    }

    // Pull `flavors:` out of the base so it's never parsed as config.
    final base = <dynamic, dynamic>{...raw}..remove('flavors');
    if (flavor == null) return _parseRoot(base);

    final flavors = raw['flavors'];
    if (flavors is! Map || flavors[flavor] is! Map) {
      final names = flavors is Map ? flavors.keys.join(', ') : '(none)';
      throw ConfigException(
          'No `flavors.$flavor` section in the config. Defined flavors: $names');
    }
    return _parseRoot(_deepMerge(base, flavors[flavor] as Map));
  }

  /// Recursively merges [override] onto [base]: nested maps merge key-by-key;
  /// scalars and lists from [override] replace those in [base].
  static Map<dynamic, dynamic> _deepMerge(
      Map<dynamic, dynamic> base, Map<dynamic, dynamic> override) {
    final out = <dynamic, dynamic>{...base};
    override.forEach((k, v) {
      final existing = out[k];
      out[k] = (existing is Map && v is Map) ? _deepMerge(existing, v) : v;
    });
    return out;
  }

  /// All flavor names declared in the config (empty if none / no config).
  List<String> flavorNames({String? explicitPath}) {
    final raw = _readRawSection(explicitPath);
    final flavors = raw is Map ? raw['flavors'] : null;
    return flavors is Map
        ? flavors.keys.map((k) => k.toString()).toList()
        : const [];
  }

  /// Locates and reads the config map from one of the supported sources.
  ///
  /// Standalone files may either be "bare" (keys at the root) or "wrapped" under
  /// a top-level `flutter_adaptive_studio:` key; both are accepted.
  Object? _readRawSection(String? explicitPath) {
    if (explicitPath != null) {
      final file = File(explicitPath);
      if (!file.existsSync()) {
        throw ConfigException('Config file not found: $explicitPath');
      }
      return _unwrap(loadYaml(file.readAsStringSync()));
    }

    final standalone =
        File(p.join(projectRoot, 'flutter_adaptive_studio.yaml'));
    if (standalone.existsSync()) {
      return _unwrap(loadYaml(standalone.readAsStringSync()));
    }

    final pubspec = File(p.join(projectRoot, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      final doc = loadYaml(pubspec.readAsStringSync());
      if (doc is Map && doc['flutter_adaptive_studio'] != null) {
        return doc['flutter_adaptive_studio'];
      }
    }
    return null;
  }

  /// Unwraps a top-level `flutter_adaptive_studio:` key if the file uses one.
  static Object? _unwrap(Object? doc) {
    if (doc is Map && doc['flutter_adaptive_studio'] != null) {
      return doc['flutter_adaptive_studio'];
    }
    return doc;
  }

  AdaptiveStudioConfig _parseRoot(Map<dynamic, dynamic> raw) {
    return AdaptiveStudioConfig(
      source: _str(raw['source']),
      android:
          raw['android'] is Map ? _parseAndroid(raw['android'] as Map) : null,
      ios: raw['ios'] is Map ? _parseIos(raw['ios'] as Map) : null,
    );
  }

  IosConfig _parseIos(Map<dynamic, dynamic> raw) {
    final icon = raw['icon'];
    final splash = raw['splash'];
    return IosConfig(
      icon: icon is Map
          ? IosIconConfig(
              image: _str(icon['image']),
              background: _str(icon['background']) ?? '#FFFFFF',
              dark: _str(icon['dark']),
              backgroundDark: _str(icon['background_dark']) ?? '#000000',
              tinted: _str(icon['tinted']),
              padding: _int(icon['padding']) ?? 0,
            )
          : null,
      splash: splash is Map
          ? IosSplashConfig(
              background: _str(splash['background']),
              backgroundDark: _str(splash['background_dark']),
              image: _str(splash['image']),
              imageDark: _str(splash['image_dark']),
              logoSizePt: _int(splash['logo_size']) ?? 192,
            )
          : null,
    );
  }

  AndroidConfig _parseAndroid(Map<dynamic, dynamic> raw) {
    return AndroidConfig(
      minSdk: _int(raw['min_sdk']),
      icon: raw['icon'] is Map ? _parseIcon(raw['icon'] as Map) : null,
      splash: raw['splash'] is Map ? _parseSplash(raw['splash'] as Map) : null,
    );
  }

  AndroidIconConfig _parseIcon(Map<dynamic, dynamic> raw) {
    return AndroidIconConfig(
      iconName: _str(raw['icon_name']) ?? 'ic_launcher',
      legacy: _bool(raw['legacy']),
      legacyPadding: _int(raw['legacy_padding']),
      imageFormat: _imageFormat(raw['image_format']),
      round: _bool(raw['round']) ?? false,
      playStore: _bool(raw['play_store']) ?? false,
      image: _str(raw['image']),
      effect: _effect(raw['effect']),
      adaptive: raw['adaptive'] is Map
          ? _parseAdaptive(raw['adaptive'] as Map)
          : null,
      themed: raw['themed'] is Map
          ? ThemedIconConfig(
              light: _str((raw['themed'] as Map)['light']),
              dark: _str((raw['themed'] as Map)['dark']),
              background: _str((raw['themed'] as Map)['background']),
              backgroundDark: _str((raw['themed'] as Map)['background_dark']),
            )
          : null,
    );
  }

  AdaptiveConfig _parseAdaptive(Map<dynamic, dynamic> raw) {
    return AdaptiveConfig(
      foreground: _str(raw['foreground']),
      background: _str(raw['background']),
      monochrome: _str(raw['monochrome']),
      // `padding: <pct>` is a friendly alias for `safe_zone: inset:<pct>` and
      // wins when both are given (it's the more specific knob).
      safeZone: raw['padding'] != null
          ? SafeZone.inset((_int(raw['padding']) ?? 15).toDouble())
          : _parseSafeZone(raw['safe_zone']),
    );
  }

  SafeZone _parseSafeZone(Object? value) {
    if (value == null) return const SafeZone.fit();
    if (value is num) return SafeZone.inset(value.toDouble());
    final text = value.toString().trim().toLowerCase();
    if (text == 'fit') return const SafeZone.fit();
    if (text == 'none') return const SafeZone.none();
    if (text.startsWith('inset')) {
      final parts = text.split(':');
      final pct = parts.length > 1 ? double.tryParse(parts[1].trim()) : null;
      return SafeZone.inset(pct ?? 16);
    }
    return const SafeZone.fit();
  }

  AndroidSplashConfig _parseSplash(Map<dynamic, dynamic> raw) {
    return AndroidSplashConfig(
      background: _str(raw['background']),
      backgroundDark: _str(raw['background_dark']),
      backgroundImage: _str(raw['background_image']),
      backgroundImageDark: _str(raw['background_image_dark']),
      image: _str(raw['image']),
      imageDark: _str(raw['image_dark']),
      animatedIcon: _str(raw['animated_icon']),
      animatedIconDark: _str(raw['animated_icon_dark']),
      durationMs: _int(raw['duration']) ?? 1000,
      iconBackground: _str(raw['icon_background']),
      iconBackgroundDark: _str(raw['icon_background_dark']),
      branding: _str(raw['branding']),
      brandingDark: _str(raw['branding_dark']),
      brandingMode: _brandingMode(raw['branding_mode']),
      brandingBottomPadding: _int(raw['branding_bottom_padding']) ?? 48,
      gravity: _str(raw['gravity']) ?? 'center',
      fullscreen: _bool(raw['fullscreen']) ?? false,
      screenOrientation: _str(raw['screen_orientation']),
    );
  }

  static BrandingMode _brandingMode(Object? v) {
    final s = v?.toString().trim().toLowerCase().replaceAll('_', '');
    return switch (s) {
      'bottomleft' => BrandingMode.bottomLeft,
      'bottomright' => BrandingMode.bottomRight,
      _ => BrandingMode.bottom,
    };
  }

  /// Resolves a config-relative asset path against the project root.
  String resolveAsset(String relativeOrAbsolute) {
    if (p.isAbsolute(relativeOrAbsolute)) return relativeOrAbsolute;
    return p.normalize(p.join(projectRoot, relativeOrAbsolute));
  }

  static LegacyEffect _effect(Object? v) {
    final s = v?.toString().trim().toLowerCase();
    return switch (s) {
      'elevate' || 'shadow' || 'elevated' => LegacyEffect.elevate,
      _ => LegacyEffect.none,
    };
  }

  static ImageFormat _imageFormat(Object? v) {
    final s = v?.toString().trim().toLowerCase();
    return switch (s) {
      'webp' => ImageFormat.webp,
      _ => ImageFormat.png,
    };
  }

  static String? _str(Object? v) => v?.toString();
  static int? _int(Object? v) =>
      v is int ? v : (v is String ? int.tryParse(v) : null);
  static bool? _bool(Object? v) =>
      v is bool ? v : (v is String ? v.toLowerCase() == 'true' : null);
}

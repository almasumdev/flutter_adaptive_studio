/// Parses SVG colour values into an ARGB value plus an Android-ready hex string.
///
/// Supports `#rgb`, `#rrggbb`, `#rrggbbaa`/`#rgba`, `rgb()/rgba()`, `none`,
/// `transparent`, `currentColor`, and a small set of named colours common in
/// icon art. Anything unrecognised resolves to opaque black with a flag so the
/// caller can warn.
library;

class SvgColor {
  const SvgColor._(this.argb, {this.isNone = false, this.recognised = true});

  /// 0xAARRGGBB.
  final int argb;
  final bool isNone;
  final bool recognised;

  static const SvgColor none = SvgColor._(0x00000000, isNone: true);
  static const SvgColor black = SvgColor._(0xFF000000);

  /// Wraps a raw 0xAARRGGBB value (e.g. a gradient stop with baked opacity).
  factory SvgColor.fromArgb(int argb) => SvgColor._(argb);

  int get alpha => (argb >> 24) & 0xFF;

  /// Android `android:fillColor`/`strokeColor` value. Emits `#RRGGBB` when fully
  /// opaque, `#AARRGGBB` otherwise.
  String get androidHex {
    final hex = argb.toRadixString(16).padLeft(8, '0').toUpperCase();
    return alpha == 0xFF ? '#${hex.substring(2)}' : '#$hex';
  }

  /// Opacity in 0..1, suitable for `android:fillAlpha`/`strokeAlpha`.
  double get opacity => alpha / 255.0;

  /// `#RRGGBB` (no alpha): for SVG `fill`/`stroke`, which take opacity
  /// separately.
  String get rgbHex =>
      '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  static SvgColor parse(String? value, {SvgColor fallback = black}) {
    if (value == null) return fallback;
    var v = value.trim().toLowerCase();
    if (v.isEmpty) return fallback;
    if (v == 'none') return none;
    if (v == 'transparent') return none;
    if (v == 'currentcolor') return black;

    if (v.startsWith('#')) return _parseHex(v.substring(1));
    if (v.startsWith('rgb')) return _parseRgb(v);

    final named = _named[v];
    if (named != null) return SvgColor._(named);

    return const SvgColor._(0xFF000000, recognised: false);
  }

  static SvgColor _parseHex(String h) {
    String r, g, b, a = 'ff';
    switch (h.length) {
      case 3: // rgb
        r = h[0] * 2;
        g = h[1] * 2;
        b = h[2] * 2;
      case 4: // rgba
        r = h[0] * 2;
        g = h[1] * 2;
        b = h[2] * 2;
        a = h[3] * 2;
      case 6: // rrggbb
        r = h.substring(0, 2);
        g = h.substring(2, 4);
        b = h.substring(4, 6);
      case 8: // rrggbbaa
        r = h.substring(0, 2);
        g = h.substring(2, 4);
        b = h.substring(4, 6);
        a = h.substring(6, 8);
      default:
        return const SvgColor._(0xFF000000, recognised: false);
    }
    final value = int.parse('$a$r$g$b', radix: 16);
    return SvgColor._(value);
  }

  static SvgColor _parseRgb(String v) {
    final inside = v.substring(v.indexOf('(') + 1, v.indexOf(')'));
    final parts = inside.split(',').map((s) => s.trim()).toList();
    int channel(String s) {
      if (s.endsWith('%')) {
        return ((double.parse(s.substring(0, s.length - 1)) / 100) * 255)
            .round()
            .clamp(0, 255);
      }
      return double.parse(s).round().clamp(0, 255);
    }

    final r = channel(parts[0]);
    final g = channel(parts[1]);
    final b = channel(parts[2]);
    final a = parts.length > 3
        ? (double.parse(parts[3]) * 255).round().clamp(0, 255)
        : 255;
    return SvgColor._((a << 24) | (r << 16) | (g << 8) | b);
  }

  /// A pragmatic subset. Extend as real-world inputs demand.
  static const Map<String, int> _named = {
    'black': 0xFF000000,
    'white': 0xFFFFFFFF,
    'red': 0xFFFF0000,
    'green': 0xFF008000,
    'blue': 0xFF0000FF,
    'gray': 0xFF808080,
    'grey': 0xFF808080,
    'silver': 0xFFC0C0C0,
    'yellow': 0xFFFFFF00,
    'orange': 0xFFFFA500,
    'teal': 0xFF008080,
    'navy': 0xFF000080,
  };
}

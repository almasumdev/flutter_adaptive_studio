/// Reading a colour the user wrote in their config, as opposed to one found
/// inside their SVG art.
library;

import '../logger.dart';
import 'svg_color.dart';

/// The ARGB value of [value], a colour from the config under [key].
///
/// SVG art is read tolerantly, so an odd `fill` deep in a file degrades
/// quietly. A colour the user typed is different: if it does not parse, the
/// icon or splash comes out black and nothing says why. This keeps the same
/// black fallback but says so, naming the key and the value, so a typo such
/// as `#FFFFGG` is found from the output rather than from the device.
int configColorArgb(String value, String key, Logger logger) {
  final color = SvgColor.parse(value);
  if (!color.recognised) {
    logger.warn(
      '$key "$value" is not a colour this tool can read, so black is used. '
      'Use #rgb, #rrggbb, #rrggbbaa, rgb(), rgba() or a colour name.',
    );
  }
  return color.argb;
}

final _androidHexColor = RegExp(
  r'^#([0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$',
);

/// [value], a colour from the config under [key], as a hex string Android can
/// read in `colors.xml`.
///
/// Android accepts only `#RGB`, `#ARGB`, `#RRGGBB` and `#AARRGGBB` there, so a
/// colour name or an `rgb()` value copied in as typed breaks the app's resource
/// build. A value already in one of those forms is kept as written (upper
/// case), so existing configs come out byte for byte the same. Anything else is
/// converted, and one that cannot be read warns through [configColorArgb] and
/// becomes black.
String configColorAndroidHex(String value, String key, Logger logger) {
  final trimmed = value.trim();
  if (_androidHexColor.hasMatch(trimmed)) return trimmed.toUpperCase();
  return SvgColor.fromArgb(configColorArgb(value, key, logger)).androidHex;
}

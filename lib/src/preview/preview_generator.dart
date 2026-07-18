/// Generates an HTML "guideline preview" sheet: the composed adaptive icon
/// rendered under the common launcher mask shapes (circle, squircle, rounded
/// square, square) with the **Google adaptive-icon keylines** overlaid (the
/// 66dp safe circle, the 72dp safe square, and a centre crosshair), plus an
/// **iOS section** showing the app icon under Apple's squircle mask next to its
/// square (App Store) form, and the monochrome themed-icon preview.
///
/// This brings the Android-Studio "preview across masks + safe zone" experience
/// to the CLI, and adds the iOS side, so a dev can verify safe-zone fit and
/// corner clipping for both platforms before shipping. One self-contained HTML
/// file (inline SVG + CSS, a pure-CSS keyline toggle); no assets, no JS deps.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../config/config_loader.dart';
import '../geometry/adaptive_geometry.dart';
import '../graphic/svg_document.dart';
import '../logger.dart';
import '../vector/svg_writer.dart';

class PreviewGenerator {
  PreviewGenerator({
    required this.config,
    required this.loader,
    required this.logger,
  });

  final AdaptiveStudioConfig config;
  final ConfigLoader loader;
  final Logger logger;

  /// Writes the preview and returns its path, or null if nothing to preview.
  String? generate() {
    final adaptive = config.android?.icon?.adaptive;
    final fgSource = adaptive?.foreground ?? config.source;
    if (fgSource == null || p.extension(fgSource).toLowerCase() != '.svg') {
      logger.skip('preview: needs an SVG foreground');
      return null;
    }
    final fgAbs = loader.resolveAsset(fgSource);
    if (!File(fgAbs).existsSync()) {
      logger.warn('preview: foreground not found: $fgAbs');
      return null;
    }

    final bg = (adaptive != null && adaptive.backgroundIsColor)
        ? adaptive.background!
        : '#E0E0E0';
    final fg = SvgDocument.parse(File(fgAbs).readAsStringSync());
    // Compose the Android icon at the user's real safe-zone fill, so the
    // keylines show how their actual icon sits against the 66/72dp guides.
    final fill = AdaptiveGeometry.canvasFillFraction(
        adaptive?.safeZone ?? const SafeZone.fit());
    final composed =
        SvgWriter.compose(fg, backgroundHex: bg, size: 108, fillFraction: fill);

    // iOS icon: its own source if an SVG, else the shared Android foreground,
    // flattened onto the iOS background. Framing here is illustrative.
    final iosIcon = config.ios?.icon;
    final iosSrc = iosIcon?.image;
    SvgDocument iosDoc = fg;
    if (iosSrc != null && p.extension(iosSrc).toLowerCase() == '.svg') {
      final a = loader.resolveAsset(iosSrc);
      if (File(a).existsSync()) {
        iosDoc = SvgDocument.parse(File(a).readAsStringSync());
      }
    }
    final iosBg = iosIcon?.background ?? (bg == '#E0E0E0' ? '#FFFFFF' : bg);
    final iosComposed = SvgWriter.compose(iosDoc,
        backgroundHex: iosBg, size: 108, fillFraction: 0.86);

    String? mono;
    if (adaptive?.monochrome != null) {
      final mAbs = loader.resolveAsset(adaptive!.monochrome!);
      if (File(mAbs).existsSync()) {
        final mDoc = SvgDocument.parse(File(mAbs).readAsStringSync());
        mono = SvgWriter.compose(mDoc,
            backgroundHex: '#3E9AA6', size: 108, fillFraction: 0.6);
      }
    }

    final html = _html(composed, iosComposed, mono);
    final outDir =
        p.join(loader.projectRoot, 'flutter_adaptive_studio', 'preview');
    final outPath = p.join(outDir, 'icon_preview.html');
    File(outPath)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(html);
    logger.step('preview → flutter_adaptive_studio/preview/icon_preview.html');
    return outPath;
  }

  // -------------------------------------------------------------- SVG overlays

  /// The Google adaptive-icon keylines in the 108dp canvas: the 66dp safe
  /// circle (r 33), the 72dp safe square (18..90), a centre crosshair + dot.
  static const _androidKeylines = '<svg class="kl" viewBox="0 0 108 108" '
      'preserveAspectRatio="none" aria-hidden="true">'
      '<g fill="none" stroke="#1a73e8" stroke-width="0.6" opacity="0.85">'
      '<circle cx="54" cy="54" r="33"/>'
      '<rect x="18" y="18" width="72" height="72"/>'
      '<line x1="54" y1="6" x2="54" y2="102"/>'
      '<line x1="6" y1="54" x2="102" y2="54"/>'
      '</g><circle cx="54" cy="54" r="1.2" fill="#1a73e8"/></svg>';

  /// A superellipse (iOS/Pixel "squircle") path in a `size`-unit box.
  static String _squircle(double size, {double n = 5, int steps = 64}) {
    final a = size / 2;
    final sb = StringBuffer();
    for (var i = 0; i <= steps; i++) {
      final t = 2 * math.pi * i / steps;
      final ct = math.cos(t), st = math.sin(t);
      final x = a + a * _sgn(ct) * math.pow(ct.abs(), 2 / n);
      final y = a + a * _sgn(st) * math.pow(st.abs(), 2 / n);
      sb.write('${i == 0 ? 'M' : 'L'}${_n(x)} ${_n(y)} ');
    }
    return '${sb.toString().trimRight()} Z';
  }

  /// The mask-boundary outline for a shape, so the clip edge reads crisply.
  static String _edge(String shape) {
    final inner = switch (shape) {
      'circle' => '<circle cx="54" cy="54" r="53.5"/>',
      'squircle' =>
        '<path d="${_squircle(107, n: 5)}" transform="translate(0.5 0.5)"/>',
      'round' => '<rect x="0.5" y="0.5" width="107" height="107" rx="23.76"/>',
      _ => '<rect x="0.5" y="0.5" width="107" height="107"/>',
    };
    return '<svg class="edge" viewBox="0 0 108 108" preserveAspectRatio="none" '
        'aria-hidden="true"><g fill="none" stroke="#00000055" '
        'stroke-width="0.5">$inner</g></svg>';
  }

  /// The iOS keylines: the squircle mask outline plus a dashed "keep key
  /// content inside" inset at ~90%.
  static String get _iosKeylines {
    final outer = _squircle(107, n: 5);
    final inset = _squircle(107 * 0.9, n: 5);
    final off = 107 * 0.05 + 0.5;
    return '<svg class="kl" viewBox="0 0 108 108" preserveAspectRatio="none" '
        'aria-hidden="true">'
        '<g fill="none" stroke="#0a84ff" opacity="0.85">'
        '<path d="$outer" transform="translate(0.5 0.5)" stroke-width="0.7"/>'
        '<path d="$inset" transform="translate(${_n(off)} ${_n(off)})" '
        'stroke-width="0.5" stroke-dasharray="2 2"/>'
        '</g></svg>';
  }

  static double _sgn(double v) => v < 0 ? -1 : (v > 0 ? 1 : 0);

  static String _n(num v) {
    var s = v.toStringAsFixed(4);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return s;
  }

  // --------------------------------------------------------------------- HTML

  String _html(String android, String ios, String? mono) {
    String tile(String label, String shape, String svg,
            {required String keylines}) =>
        '''
      <figure class="tile m-$shape">
        <div class="art">
          <div class="icon">$svg</div>
          $keylines
          ${_edge(shape)}
        </div>
        <figcaption>$label</figcaption>
      </figure>''';

    final androidTiles = [
      tile('Circle', 'circle', android, keylines: _androidKeylines),
      tile('Squircle', 'squircle', android, keylines: _androidKeylines),
      tile('Rounded square', 'round', android, keylines: _androidKeylines),
      tile('Square', 'square', android, keylines: _androidKeylines),
    ].join('\n');

    final iosTiles = [
      tile('Home screen (squircle)', 'squircle', ios, keylines: _iosKeylines),
      tile('App Store (square)', 'square', ios, keylines: ''),
    ].join('\n');

    final monoSection = mono == null
        ? ''
        : '''
    <h2>Monochrome (Android 13 themed icon)</h2>
    <div class="row">
      ${tile('Tinted circle', 'circle', mono, keylines: _androidKeylines)}
    </div>''';

    return '''<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<title>flutter_adaptive_studio icon preview</title>
<style>
  body { font-family: system-ui, sans-serif; background:#fafafa; color:#222;
         margin:32px; }
  h1 { font-size:19px; margin:0 0 4px; }
  h2 { font-size:15px; margin:32px 0 12px; }
  .row { display:flex; gap:24px; flex-wrap:wrap; }
  .tile { margin:0; text-align:center; }
  .art { position:relative; width:132px; height:132px;
         box-shadow:0 1px 6px rgba(0,0,0,.18); }
  .art > * { position:absolute; inset:0; width:100%; height:100%; display:block; }
  .icon svg { width:100%; height:100%; display:block; }
  /* Launcher / OS masks applied to the icon layer only. */
  .m-circle   .icon { clip-path: circle(50%); }
  .m-squircle .icon { clip-path: url(#squircle); }
  .m-round    .icon { border-radius: 22%; overflow:hidden; }
  .m-square   .icon { }
  figcaption { margin-top:8px; font-size:12px; color:#666; }
  .legend { color:#555; font-size:12px; max-width:660px; line-height:1.5; }
  .sw { display:inline-block; width:10px; height:10px; border:1.5px solid;
        vertical-align:middle; margin:0 3px 0 10px; border-radius:2px; }
  .sw.a { border-color:#1a73e8; } .sw.i { border-color:#0a84ff; }
  .toggle { margin:14px 0 20px; font-size:13px; color:#333; user-select:none; }
  /* Pure-CSS keyline toggle: hidden unless the checkbox is checked. */
  .kl { display:none; }
  body:has(#kl:checked) .kl { display:block; }
  code { background:#eef; padding:1px 4px; border-radius:3px; }
</style></head>
<body>
  <!-- objectBoundingBox squircle clip, referenced by the mask + iOS tiles. -->
  <svg width="0" height="0" style="position:absolute"><defs>
    <clipPath id="squircle" clipPathUnits="objectBoundingBox">
      <path d="${_squircle(1, n: 5)}"/>
    </clipPath>
  </defs></svg>

  <h1>Icon guideline preview</h1>
  <p class="legend">Your composed icon under each platform's masks, with the
  official safe-zone keylines overlaid.
  <span class="sw a"></span>Google: 66dp safe circle + 72dp safe square + crosshair.
  <span class="sw i"></span>Apple: squircle mask + a dashed keep-content-inside inset.
  If artwork crosses a keyline it can be clipped; tighten <code>safe_zone</code>
  (Android) or <code>ios.icon.padding</code>.</p>

  <label class="toggle"><input type="checkbox" id="kl" checked> show keylines</label>

  <h2>Android adaptive icon (Google)</h2>
  <div class="row">
$androidTiles
  </div>

  <h2>iOS app icon (Apple)</h2>
  <div class="row">
$iosTiles
  </div>
$monoSection
</body></html>''';
  }
}

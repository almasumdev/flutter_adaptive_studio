/// Generates an HTML "OEM mask preview" sheet: the composed adaptive icon
/// rendered under the common launcher mask shapes (circle, squircle, rounded
/// square, square), plus the monochrome themed-icon preview. This brings the
/// Android-Studio "preview across masks" experience to the CLI so a dev can
/// verify safe-zone fit before shipping.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../config/config.dart';
import '../config/config_loader.dart';
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
    // Mirror the adaptive safe-zone fit (~72/108).
    final composed = SvgWriter.compose(fg,
        backgroundHex: bg, size: 256, fillFraction: 0.667);

    String? mono;
    if (adaptive?.monochrome != null) {
      final mAbs = loader.resolveAsset(adaptive!.monochrome!);
      if (File(mAbs).existsSync()) {
        final mDoc = SvgDocument.parse(File(mAbs).readAsStringSync());
        // White silhouette on a tinted ground, as themed icons render.
        mono = SvgWriter.compose(mDoc,
            backgroundHex: '#3E9AA6', size: 256, fillFraction: 0.6);
      }
    }

    final html = _html(composed, mono);
    final outDir =
        p.join(loader.projectRoot, 'flutter_adaptive_studio', 'preview');
    final outPath = p.join(outDir, 'icon_preview.html');
    File(outPath)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(html);
    logger.step('preview → flutter_adaptive_studio/preview/icon_preview.html');
    return outPath;
  }

  String _html(String composedSvg, String? monoSvg) {
    String tile(String label, String radiusOrClip, String svg) => '''
      <figure class="tile">
        <div class="mask" style="$radiusOrClip">$svg</div>
        <figcaption>$label</figcaption>
      </figure>''';

    final masks = [
      tile('Circle', 'border-radius:50%;', composedSvg),
      tile('Squircle', 'border-radius:42% / 40%;', composedSvg),
      tile('Rounded square', 'border-radius:22%;', composedSvg),
      tile('Square', 'border-radius:0;', composedSvg),
    ].join('\n');

    final monoSection = monoSvg == null
        ? ''
        : '''
    <h2>Monochrome (Android 13 themed icon)</h2>
    <div class="row">
      ${tile('Tinted circle', 'border-radius:50%;', monoSvg)}
    </div>''';

    return '''<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<title>flutter_adaptive_studio icon preview</title>
<style>
  body { font-family: system-ui, sans-serif; background:#fafafa; color:#222;
         margin:32px; }
  h1 { font-size:18px; } h2 { font-size:15px; margin-top:28px; }
  .row { display:flex; gap:24px; flex-wrap:wrap; }
  .tile { margin:0; text-align:center; }
  .mask { width:128px; height:128px; overflow:hidden; box-shadow:0 1px 6px rgba(0,0,0,.2); }
  .mask svg { width:100%; height:100%; display:block; }
  figcaption { margin-top:8px; font-size:12px; color:#666; }
  p.note { color:#888; font-size:12px; max-width:640px; }
</style></head>
<body>
  <h1>Adaptive icon: launcher mask preview</h1>
  <p class="note">The same 108dp adaptive icon under common OEM masks. If the
  artwork is clipped in any tile, tighten <code>safe_zone</code>.</p>
  <div class="row">
$masks
  </div>
$monoSection
</body></html>''';
  }
}

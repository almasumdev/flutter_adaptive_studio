/// Rasterizer abstraction for the few PNG-only outputs (legacy mipmaps + the
/// 512² Play Store icon). Vector outputs never touch this.
///
/// Backends (selected by [RasterizerFactory]):
///   - [ImageRasterizer] — pure Dart, raster sources (PNG/JPG/WebP/…)
///   - [SvgRasterizer]   — pure Dart, SVG sources (flattens + scan-fills paths)
///
/// Both are always available, so an SVG icon needs no system tool. The only
/// time a source is skipped is a genuinely unsupported extension.
library;

abstract class Rasterizer {
  String get name;

  /// Whether this backend can run in the current environment.
  bool get available;

  /// True if this backend can consume the given source file extension.
  bool supports(String extension);

  /// Renders [sourcePath] to a square PNG of [sizePx] at [outPath].
  /// Returns true on success.
  bool renderToPng({
    required String sourcePath,
    required int sizePx,
    required String outPath,
  });
}

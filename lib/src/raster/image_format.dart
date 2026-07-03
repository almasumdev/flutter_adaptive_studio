/// Output encoding for generated raster icons (mipmaps + drawable density PNGs).
///
/// PNG is the safe default. WebP (lossless) produces noticeably smaller
/// resources and is resolved by Android exactly like a PNG of the same resource
/// name. The Play Store marketing icon is always PNG (Google requires a 32-bit
/// PNG there), regardless of this setting.
library;

enum ImageFormat {
  png('.png'),
  webp('.webp');

  const ImageFormat(this.extension);

  /// File extension (including the dot) for this format.
  final String extension;
}

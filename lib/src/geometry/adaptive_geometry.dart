/// Adaptive-icon canvas geometry.
///
/// Android adaptive icons use a 108dp canvas; the inner 72dp square is the
/// "safe zone" that survives every launcher mask. Our quality win over the
/// incumbents (which paste the full image and lean on a blind XML `<inset>`) is
/// to **measure the real art bounding box and scale it to fit the safe zone**,
/// centred, so circular, squircle, and rounded-square masks all look right.
library;

import '../config/config.dart';
import '../graphic/bounds.dart';

class AdaptiveGeometry {
  /// VectorDrawable viewport for adaptive layers (the 108dp canvas).
  static const double canvas = 108.0;

  /// The 72dp guaranteed-visible safe square.
  static const double safeSquare = 72.0;

  /// Computes the transform that maps art (in viewBox/source coordinates,
  /// described by [art]) into the 108 canvas according to [zone].
  ///
  /// [fallbackViewport] is the source viewBox longest side, used when art
  /// bounds can't be measured.
  static AdaptiveFit fit(Bounds? art, SafeZone zone, double fallbackViewport) {
    final target = _targetSide(zone);
    if (art == null || art.longestSide == 0) {
      final scale =
          target / (fallbackViewport == 0 ? canvas : fallbackViewport);
      // Centre assuming art fills the viewBox.
      final tx = (canvas - fallbackViewport * scale) / 2;
      return AdaptiveFit(scale: scale, translateX: tx, translateY: tx);
    }
    final scale = target / art.longestSide;
    return AdaptiveFit(
      scale: scale,
      translateX: canvas / 2 - scale * art.centerX,
      translateY: canvas / 2 - scale * art.centerY,
    );
  }

  /// Like [fit], but chooses the art to fit based on [zone]: `as_is` maps the
  /// whole [viewBox] (its authored padding preserved), while every other mode
  /// fits the measured [artBounds]. [artBounds] may be null (unmeasurable), in
  /// which case the viewBox is used as a fallback.
  static AdaptiveFit fitDoc(Bounds? artBounds, Bounds viewBox, SafeZone zone) {
    final art = zone.mode == SafeZoneMode.asIs ? viewBox : artBounds;
    return fit(art, zone, viewBox.longestSide);
  }

  /// Target side the art's longest edge is scaled to, in 108dp units.
  ///
  /// `fit`/`inset` shrink the art inside the 72dp safe square by the requested
  /// padding (so 0% = flush to the masked edge, 15% = the default breathing
  /// room). `none` fills the whole 108dp canvas.
  static double _targetSide(SafeZone zone) => switch (zone.mode) {
        SafeZoneMode.fit ||
        SafeZoneMode.inset =>
          safeSquare * (1 - paddingFraction(zone)),
        // `as_is` fits the whole viewBox into the mask-safe square, honouring the
        // source's own padding rather than adding any.
        SafeZoneMode.asIs => safeSquare,
        SafeZoneMode.none => canvas,
      };

  /// Padding (0..1) the foreground is inset by inside the safe zone. The user
  /// picks any percentage 0-100; 0 = flush to the masked edge, 100 = vanishing.
  static double paddingFraction(SafeZone zone) =>
      (zone.mode == SafeZoneMode.none || zone.mode == SafeZoneMode.asIs)
          ? 0
          : (zone.insetPercent / 100).clamp(0, 1).toDouble();

  /// Foreground target as a fraction of the full 108dp canvas, used by raster
  /// layers that fit a source into the layer bitmap rather than a `<group>`.
  static double canvasFillFraction(SafeZone zone) => _targetSide(zone) / canvas;
}

/// A uniform scale + translate, expressed in VectorDrawable `<group>` semantics
/// (pivot 0, rotation 0): a point `p` maps to `scale * p + (translateX, translateY)`.
class AdaptiveFit {
  const AdaptiveFit({
    required this.scale,
    required this.translateX,
    required this.translateY,
  });

  final double scale;
  final double translateX;
  final double translateY;

  bool get isIdentity => scale == 1 && translateX == 0 && translateY == 0;
}

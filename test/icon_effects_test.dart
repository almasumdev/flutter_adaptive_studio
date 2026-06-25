import 'package:flutter_adaptive_studio/src/raster/icon_effects.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

/// The "elevate" post-process (Android Asset Studio / IconKitchen look): a soft
/// drop shadow beneath the shape, leaving the icon body intact.
void main() {
  test('elevate composites a drop shadow beneath the shape', () {
    const size = 192;
    final content = img.Image(width: size, height: size, numChannels: 4);
    for (var y = 30; y < 150; y++) {
      for (var x = 30; x < 162; x++) {
        content.setPixelRgba(x, y, 60, 150, 160, 255);
      }
    }

    final out = IconEffects.elevate(content);

    // A shadow lands in the transparent margin just below the square's edge.
    var sawShadow = false;
    for (var y = 150; y < 166; y++) {
      if (out.getPixel(96, y).a > 0) {
        sawShadow = true;
        break;
      }
    }
    expect(sawShadow, isTrue);

    // A far corner, away from the shape + shadow, stays transparent.
    expect(out.getPixel(2, 2).a, 0);
    // The icon body is still fully opaque.
    expect(out.getPixel(96, 90).a, 255);
  });
}

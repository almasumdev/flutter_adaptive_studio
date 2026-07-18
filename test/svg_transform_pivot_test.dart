import 'package:flutter_adaptive_studio/src/graphic/svg_document.dart';
import 'package:flutter_adaptive_studio/src/raster/svg_rasterizer.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

/// An SVG `transform` with a rotation pivot (`rotate(deg cx cy)`) must rotate
/// around that point, not the origin. This guards the `Matrix2D.rotate(a, cx,
/// cy)` = translate(cx,cy)·rotate·translate(-cx,-cy) handling that both the
/// rasteriser and the VectorDrawable writer rely on.
void main() {
  bool isRed(img.Pixel px) => px.r > 200 && px.g < 80 && px.b < 80;

  test('rotate(180 cx cy) pivots around (cx,cy), not the origin', () {
    // A 20x20 red square in the top-left quadrant, rotated 180 degrees around
    // the canvas centre (50,50). It must land in the bottom-right quadrant.
    final svg = '<svg viewBox="0 0 100 100">'
        '<rect x="10" y="10" width="20" height="20" fill="#FF0000" '
        'transform="rotate(180 50 50)"/></svg>';
    final im = const SvgRasterizer()
        .rasterize(SvgDocument.parse(svg), 100, fitArtBounds: false);

    // (10..30, 10..30) rotated 180 about (50,50) -> (70..90, 70..90).
    expect(isRed(im.getPixel(80, 80)), isTrue,
        reason: 'the square pivots to the bottom-right');
    expect(isRed(im.getPixel(20, 20)), isFalse,
        reason:
            'it leaves the top-left (an origin pivot would send it off-canvas)');
  });

  test('rotate(90 cx cy) pivots around the centre', () {
    // A wide bar across the top, rotated 90 degrees around (50,50) -> a vertical
    // bar down the right-centre column.
    final svg = '<svg viewBox="0 0 100 100">'
        '<rect x="20" y="10" width="60" height="10" fill="#FF0000" '
        'transform="rotate(90 50 50)"/></svg>';
    final im = const SvgRasterizer()
        .rasterize(SvgDocument.parse(svg), 100, fitArtBounds: false);

    // The horizontal bar y in [10,20] maps to a vertical bar x in [80,90].
    expect(isRed(im.getPixel(85, 50)), isTrue,
        reason: 'the bar became vertical on the right of centre');
    expect(isRed(im.getPixel(50, 15)), isFalse,
        reason: 'it is no longer horizontal across the top');
  });
}

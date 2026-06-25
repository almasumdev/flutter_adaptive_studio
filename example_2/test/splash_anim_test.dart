import 'package:example_2/splash.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('FasSplashDemo fades + scales the logo in over time',
      (tester) async {
    final fadeF = find.descendant(
        of: find.byType(FasSplashDemo), matching: find.byType(FadeTransition));
    final scaleF = find.descendant(
        of: find.byType(FasSplashDemo), matching: find.byType(ScaleTransition));
    double opacity() => tester.widget<FadeTransition>(fadeF.first).opacity.value;
    double scale() => tester.widget<ScaleTransition>(scaleF.first).scale.value;

    // The animation only starts after the SVG is decoded into svg.cache, so let
    // that real async work complete before we drive the clock.
    await tester.runAsync(() async {
      await tester.pumpWidget(const MaterialApp(home: FasSplashDemo()));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    // First frame after decode fires the post-frame callback → forward() (t≈0).
    await tester.pump();
    final o0 = opacity();
    final s0 = scale();

    await tester.pump(const Duration(milliseconds: 450));
    final o1 = opacity();
    final s1 = scale();

    await tester.pumpAndSettle();
    final o2 = opacity();
    final s2 = scale();

    // Starts faded out + shrunk, progresses, then settles at full size.
    expect(o0, lessThan(0.1), reason: 'should start ~invisible');
    expect(s0, lessThan(0.8), reason: 'should start shrunk (0.4)');
    expect(o1, greaterThan(o0), reason: 'opacity should grow');
    expect(s1, greaterThan(s0), reason: 'scale should grow');
    expect(o2, equals(1.0));
    expect(s2, closeTo(1.0, 0.02));
  });
}

// Smoke test for the example app. Because main.dart now boots through the
// SplashGate (which shows FasSplashDemo first), the test waits for the splash's
// SVG to decode and for the gate to elapse before exercising the counter.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:example_2/main.dart';
import 'package:example_2/splash.dart';

void main() {
  testWidgets('Boots into the splash, then the counter increments',
      (WidgetTester tester) async {
    // pumpWidget runs in the fake-async zone, so SplashGate's timer is fake
    // (advanceable with pump). The splash's SVG decode is real async, so we let
    // it complete via runAsync.
    await tester.pumpWidget(const MyApp());
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    // The splash gates the app first — the counter isn't visible yet.
    expect(find.byType(FasSplashDemo), findsOneWidget);
    expect(find.text('0'), findsNothing);

    // Advance past the 2200ms gate to reveal the home page.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    // Counter starts at 0, then increments on tap.
    expect(find.text('0'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
  });
}

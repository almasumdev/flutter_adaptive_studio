/// flutter_adaptive_studio — the programmatic API for the icon/splash generator.
///
/// This is a pure-Dart command-line tool; most users run the `fas` command
/// rather than import it. Import this only to drive generation from Dart — the
/// entry point is [AdaptiveStudio]. The in-app splash widget is **generated**
/// into a self-contained `fas_splash.g.dart` (it imports only `package:flutter`),
/// so your app never depends on this package.
library;

export 'generator.dart';

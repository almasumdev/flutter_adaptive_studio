/// The programmatic API for the flutter_adaptive_studio icon and splash generator.
///
/// This is a pure-Dart command-line tool; most users run the `fas` command
/// rather than import it. Import this only to drive generation from Dart. The
/// entry point is [AdaptiveStudio]. The in-app splash widget is **generated**
/// into a self-contained `fas_splash.g.dart` (it imports only `package:flutter`),
/// so your app never depends on this package.
library;

export 'generator.dart';

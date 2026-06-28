// Demo for flutter_adaptive_studio's in-app splash.
//
// The whole integration is the `AdaptiveSplash` wrapper around your app — the
// matching splash, the timing, the fade, and the cleanup are all handled by the
// package. `fasSplash` is the generated config (run
// `dart run flutter_adaptive_studio generate` to (re)create lib/fas_splash.g.dart).
import 'package:flutter/material.dart';
import 'package:flutter_adaptive_studio/flutter_adaptive_studio.dart';

import 'fas_splash.g.dart';

void main() => runApp(const Demo());

class Demo extends StatefulWidget {
  const Demo({super.key});

  @override
  State<Demo> createState() => _DemoState();
}

class _DemoState extends State<Demo> {
  // Bumping this key remounts AdaptiveSplash, so you can replay the splash
  // without restarting the app.
  int _run = 0;

  void _replay() => setState(() => _run++);

  @override
  Widget build(BuildContext context) {
    // This is the ONLY integration: wrap your app once.
    return AdaptiveSplash(
      key: ValueKey(_run),
      config: fasSplash,
      child: MaterialApp(
        title: 'AdaptiveSplash demo',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF1F5560),
          brightness: Brightness.light,
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: const Color(0xFF1F5560),
          brightness: Brightness.dark,
        ),
        home: _Home(onReplay: _replay),
      ),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home({required this.onReplay});

  final VoidCallback onReplay;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AdaptiveSplash demo')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bolt, size: 56),
              const SizedBox(height: 16),
              Text('Your app is running.',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text(
                'The splash you just saw was AdaptiveSplash — it matched the '
                'native launch screen, held briefly, then faded to here.\n\n'
                'Toggle your system dark mode and replay to see the -night '
                'variant. The splash carries no assets: the logo + branding are '
                'baked into fas_splash.g.dart.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: onReplay,
        icon: const Icon(Icons.replay),
        label: const Text('Replay splash'),
      ),
    );
  }
}

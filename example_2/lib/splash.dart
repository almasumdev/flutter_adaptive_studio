import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Flutter splash shown on top of the native one so a splash always appears —
/// including on Android 12+ where the OS splash is brief. Renders the splash
/// `image:` (not the app icon) with a fade + overshoot entrance. The generated,
/// SDK-gated equivalent lives at `flutter_adaptive_studio/splash/fas_splash.dart`.
class FasSplashDemo extends StatefulWidget {
  const FasSplashDemo({super.key});

  @override
  State<FasSplashDemo> createState() => _FasSplashDemoState();
}

class _FasSplashDemoState extends State<FasSplashDemo>
    with SingleTickerProviderStateMixin {
  static const Color _bgLight = Color(0xFFFFFFFF);
  static const Color _bgDark = Color(0xFF0E1A1C);
  static const String _logo = 'assets/listkin_logo.svg';
  // Light/dark branding, mirroring the native windowSplashScreenBrandingImage.
  static const String _brand = 'assets/wordmark.svg';
  static const String _brandDark = 'assets/wordmark_dark.svg';
  // 48dp matches the native pre-31 launch_background.xml / generated FasSplash.
  static const double _brandBottomDp = 48;

  /// Like easeOutBack but with a stronger back (2.2 vs 1.56) for a clear spring.
  static const Curve _overshoot = Cubic(0.34, 2.2, 0.64, 1);

  late final AnimationController _c;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    // Rests at 0 → opacity 0 / scale 0.4, so the logo is invisible until
    // forward(): it can mount and decode while hidden (see _decodeThenAnimate)
    // instead of popping in mid-animation.
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _fade = CurvedAnimation(
        parent: _c, curve: const Interval(0, 0.6, curve: Curves.easeOut));
    _scale = Tween<double>(begin: 0.4, end: 1)
        .animate(CurvedAnimation(parent: _c, curve: _overshoot));
    _decodeThenAnimate();
  }

  /// Decode the assets, then start the animation one frame later. `SvgPicture`
  /// loads asynchronously; animating during the decode (worsened by startup
  /// jank) makes the logo appear only once it's near full size — i.e. static.
  Future<void> _decodeThenAnimate() async {
    for (final asset in const [_logo, _brand, _brandDark]) {
      final loader = SvgAssetLoader(asset);
      await svg.cache
          .putIfAbsent(loader.cacheKey(null), () => loader.loadBytes(null));
      if (!mounted) return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: dark ? _bgDark : _bgLight,
      // Centre logo + bottom branding — the same layout the native splash uses.
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: SvgPicture.asset(_logo, width: 192, height: 192),
              ),
            ),
          ),
          // Bottom branding — light/dark variant chosen by the active theme.
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: _brandBottomDp),
              child: FadeTransition(
                opacity: _fade,
                child: SvgPicture.asset(dark ? _brandDark : _brand, height: 40),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows [FasSplashDemo] for [duration], then swaps to [child]. Always shows the
/// splash (the "build one always" demo) — a real app would gate this on
/// `fasNeedsFlutterSplash()` so it only runs where the native splash can't.
class SplashGate extends StatefulWidget {
  const SplashGate({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 2200),
  });

  final Widget child;
  final Duration duration;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.duration, () {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) =>
      _ready ? widget.child : const FasSplashDemo();
}

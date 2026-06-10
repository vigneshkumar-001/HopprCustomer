import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hopper/Presentation/Authentication/screens/mobile_screens.dart';

/// First-launch onboarding. Three quality intro pages tailored to Hoppr
/// (ride, package, track & safety) with a "Get Started" CTA. Shown once, then
/// the `onboarding_seen` flag routes straight to login afterwards.
class IntroScreens extends StatefulWidget {
  const IntroScreens({super.key});

  @override
  State<IntroScreens> createState() => _IntroScreensState();
}

class _IntroData {
  final IconData icon;
  final IconData accentIcon;
  final Color color;
  final String title;
  final String subtitle;

  /// Optional asset illustration. When set (and the file exists) it is shown
  /// instead of the built-in icon illustration; otherwise it falls back to the
  /// icon so the screen never breaks.
  final String? image;

  const _IntroData({
    required this.icon,
    required this.accentIcon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.image,
  });
}

class _IntroScreensState extends State<IntroScreens> {
  final PageController _pc = PageController();
  int _index = 0;

  static const Color _ink = Color(0xFF161A2E); // dark navy CTA
  static const Color _amber = Color(0xFFE79700); // brand amber

  static const List<_IntroData> _pages = [
    _IntroData(
      icon: Icons.directions_car_filled_rounded,
      accentIcon: Icons.bolt_rounded,
      color: Color(0xFF2563EB),
      image: 'assets/images/intro1.png',
      title: 'Book a ride in seconds',
      subtitle:
          'Cars and bikes at your fingertips — fast, affordable and always '
          'nearby, whenever you need to move.',
    ),
    _IntroData(
      icon: Icons.inventory_2_rounded,
      accentIcon: Icons.local_shipping_rounded,
      color: Color(0xFFE8A317),
      image: 'assets/images/intro2.png',
      title: 'Send anything, anywhere',
      subtitle:
          'Doorstep pickup and delivery across the city — your parcels '
          'handled quickly and with care.',
    ),
    _IntroData(
      icon: Icons.shield_rounded,
      accentIcon: Icons.my_location_rounded,
      color: Color(0xFF12B76A),
      image: 'assets/images/intro3.png',
      title: 'Track live, ride safe',
      subtitle:
          'Real-time tracking, verified drivers and a built-in safety '
          'toolkit — so every trip feels secure.',
    ),
  ];

  bool get _isLast => _index == _pages.length - 1;

  Future<void> _finish() async {
    // Tactile confirmation when the user taps "Get Started" or "Skip".
    HapticFeedback.mediumImpact();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_seen', true);
    } catch (_) {}
    if (!mounted) return;
    // Premium hand-off to login: the auth screen rises up from the bottom with a
    // graceful easeOutCubic settle (used for both "Get Started" and "Skip").
    Get.off(
      () => const MobileScreens(),
      transition: Transition.downToUp,
      curve: Curves.easeOutCubic,
      duration: const Duration(milliseconds: 480),
    );
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _pc.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Full-bleed illustration pages.
          PageView.builder(
            controller: _pc,
            onPageChanged: (i) => setState(() => _index = i),
            itemCount: _pages.length,
            itemBuilder: (ctx, i) => _page(ctx, _pages[i]),
          ),

          // Skip (top-right).
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _isLast ? 0 : 1,
                child: TextButton(
                  onPressed: _isLast ? null : _finish,
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Dots + CTA (bottom) over a soft scrim so they stay readable.
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00FFFFFF), Color(0xE6FFFFFF)],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 34, 24, 22),
                  child: Row(
                    children: [
                      Row(
                        children: List.generate(_pages.length, (i) {
                          final active = i == _index;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            margin: const EdgeInsets.only(right: 6),
                            height: 8,
                            width: active ? 24 : 8,
                            decoration: BoxDecoration(
                              color: active ? _ink : Colors.grey.shade400,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          );
                        }),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: _next,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 15,
                          ),
                          decoration: BoxDecoration(
                            color: _ink,
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: _ink.withOpacity(0.30),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _isLast ? 'Get Started' : 'Next',
                                style: const TextStyle(
                                  color: _amber,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                color: _amber,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _page(BuildContext context, _IntroData d) {
    // Illustration occupies the upper area; its bottom edge is a soft circular
    // curve (not a flat square). White shows below the curve. A larger factor
    // pulls the artwork lower down the screen.
    final imageHeight = MediaQuery.of(context).size.height * 0.90;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Curved-bottom illustration with a soft shadow under the arc for depth.
        Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: imageHeight + 6,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Shadow cast by the curved edge onto the white below.
                ClipPath(
                  clipper: _BottomArcClipper(),
                  child: Container(
                    height: imageHeight,
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.10),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                  ),
                ),
                // The illustration itself, clipped to the same arc.
                ClipPath(
                  clipper: _BottomArcClipper(),
                  child: SizedBox(
                    height: imageHeight,
                    width: double.infinity,
                    child:
                        d.image != null
                            ? Image.asset(
                              d.image!,
                              fit: BoxFit.cover,
                              alignment: Alignment.bottomCenter,
                              errorBuilder: (_, __, ___) => _fallbackBg(d),
                            )
                            : _fallbackBg(d),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Solid white top band fading into the artwork. Keeps the heading crisp
        // AND covers any text baked into the source image (so the in-code
        // title/subtitle are the only — typo-free — words shown).
        const Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: 400,
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFFFFFFF),
                    Color(0xFFFFFFFF),
                    Color(0x00FFFFFF),
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),
        ),

        // Heading + subtitle.
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 54, 28, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.title,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    color: Color(0xFF161A2E),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  d.subtitle,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _fallbackBg(_IntroData d) {
    return Container(
      color: const Color(0xFFFFF7EC),
      alignment: Alignment.center,
      child: _iconIllustration(d),
    );
  }

  Widget _iconIllustration(_IntroData d) {
    Widget dot(Color c, double size, {double opacity = 1}) => Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        color: c.withOpacity(opacity),
        shape: BoxShape.circle,
      ),
    );

    return SizedBox(
      height: 280,
      width: 280,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft gradient halo
          Container(
            height: 248,
            width: 248,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [d.color.withOpacity(0.18), d.color.withOpacity(0.05)],
              ),
            ),
          ),
          // Decorative accent dots
          Positioned(top: 22, right: 36, child: dot(d.color, 16, opacity: 0.5)),
          Positioned(
            bottom: 34,
            left: 30,
            child: dot(d.color, 12, opacity: 0.4),
          ),
          Positioned(top: 70, left: 22, child: dot(_amber, 9, opacity: 0.7)),
          Positioned(
            bottom: 64,
            right: 24,
            child: Container(
              height: 34,
              width: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Icon(d.accentIcon, size: 18, color: d.color),
            ),
          ),
          // Main icon disc
          Container(
            height: 132,
            width: 132,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: d.color.withOpacity(0.22),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Icon(d.icon, size: 62, color: d.color),
          ),
        ],
      ),
    );
  }
}

/// Clips the illustration so its bottom edge is a soft circular arc (instead of
/// a flat square edge), letting the white content area below flow up into it.
class _BottomArcClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    const curve = 52.0;
    return Path()
      ..lineTo(0, size.height - curve)
      ..quadraticBezierTo(
        size.width / 2,
        size.height + curve,
        size.width,
        size.height - curve,
      )
      ..lineTo(size.width, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

import 'package:flutter/material.dart';

/// A smooth "bottom sheet feel" page route: the new screen slides up from the
/// bottom while fading in, and the screen behind it eases slightly back. Used
/// for the location/destination search screens so tapping a from/destination
/// field opens the search with an Uber-style down-to-top animation.
///
/// Curve is [Curves.easeOutCubic] (gentle deceleration) so it never feels
/// snappy or janky.
Route<T> bottomUpRoute<T>(
  Widget page, {
  Duration duration = const Duration(milliseconds: 360),
  Duration reverseDuration = const Duration(milliseconds: 280),
  RouteSettings? settings,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    transitionDuration: duration,
    reverseTransitionDuration: reverseDuration,
    opaque: true,
    barrierColor: Colors.transparent,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );

      // Incoming screen: slide up from bottom + fade in.
      final slideUp = Tween<Offset>(
        begin: const Offset(0, 0.10),
        end: Offset.zero,
      ).animate(curved);

      // Outgoing (previous) screen: ease back a touch so it feels layered.
      final slideBack = Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(0, -0.04),
      ).animate(CurvedAnimation(
        parent: secondaryAnimation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ));

      return SlideTransition(
        position: slideBack,
        child: SlideTransition(
          position: slideUp,
          child: FadeTransition(opacity: curved, child: child),
        ),
      );
    },
  );
}

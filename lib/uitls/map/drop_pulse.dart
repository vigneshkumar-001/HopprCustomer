import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Animated "pulse" ripple(s) rendered as Google Map [Circle]s under a point
/// (e.g. the drop / destination pin). Timer-based, so it works in both
/// StatefulWidgets and GetX controllers (no TickerProvider needed).
///
/// Usage: create with an [onUpdate] that merges the circles into your map's
/// circle set and rebuilds, call [start] with the drop location, and [dispose]
/// when the screen closes.
class DropPulse {
  DropPulse({
    required this.onUpdate,
    this.color = const Color(0xFF15803D),
    this.maxRadiusMeters = 70,
    this.periodMs = 1500,
  });

  final void Function(Set<Circle>) onUpdate;
  final Color color;
  final double maxRadiusMeters;
  final int periodMs;

  static const int _tickMs = 50;

  Timer? _timer;
  double _t = 0;
  LatLng? _center;

  bool get isRunning => _timer != null;

  void start(LatLng center) {
    _center = center;
    _t = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: _tickMs), (_) {
      _t = (_t + _tickMs / periodMs) % 1.0;
      _emit();
    });
    _emit();
  }

  /// Move the pulse to a new location without restarting the animation.
  void moveTo(LatLng center) => _center = center;

  void _emit() {
    final c = _center;
    if (c == null) {
      onUpdate(const <Circle>{});
      return;
    }
    final circles = <Circle>{};
    // Two ripples offset by half a cycle for a continuous pulse.
    for (int i = 0; i < 2; i++) {
      final t = (_t + i * 0.5) % 1.0;
      final radius = maxRadiusMeters * t;
      final fade = (1.0 - t).clamp(0.0, 1.0);
      circles.add(
        Circle(
          circleId: CircleId('drop_pulse_$i'),
          center: c,
          radius: radius <= 0 ? 0.1 : radius,
          fillColor: color.withOpacity(0.16 * fade),
          strokeColor: color.withOpacity(0.45 * fade),
          strokeWidth: 1,
          consumeTapEvents: false,
        ),
      );
    }
    onUpdate(circles);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    onUpdate(const <Circle>{});
  }

  void dispose() => stop();
}

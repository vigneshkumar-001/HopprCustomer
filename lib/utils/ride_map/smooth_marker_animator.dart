import 'dart:async';
import 'dart:math';

import 'package:flutter/animation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Uber/Ola-grade smooth marker animation.
/// - Animates between socket updates.
/// - Dead-reckons between packets so marker doesn't "stop then teleport".
/// - Smooth bearing interpolation (prevents 359->1 flip).
///
/// Caller owns the [AnimationController] lifecycle.
class SmoothMarkerAnimator {
  SmoothMarkerAnimator({
    required LatLng initialPosition,
    required double initialBearing,
    required AnimationController controller,
    required this.onUpdate,
    this.deadReckonTick = const Duration(milliseconds: 100),
    this.deadReckonStopAfter = const Duration(seconds: 15),
    this.minSpeedMps = 1.0,
    this.maxSpeedMps = 30.0,
    this.defaultSpeedMps = 5.0,
  })  : _currentPos = initialPosition,
        _targetPos = initialPosition,
        _currentBearing = _wrap360(initialBearing),
        _targetBearing = _wrap360(initialBearing),
        _controller = controller {
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.addListener(_onAnimationTick);
    _controller.addStatusListener(_onStatus);
  }

  final void Function(LatLng position, double bearing) onUpdate;

  final Duration deadReckonTick;
  final Duration deadReckonStopAfter;
  final double minSpeedMps;
  final double maxSpeedMps;
  final double defaultSpeedMps;

  LatLng _currentPos;
  LatLng _targetPos;
  double _currentBearing;
  double _targetBearing;

  final AnimationController _controller;
  late final Animation<double> _animation;

  double _lastSpeedMps = 5.0;
  DateTime _lastUpdateTime = DateTime.now();

  Timer? _deadReckonTimer;
  DateTime? _deadStartAt;

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _currentPos = _targetPos;
      _currentBearing = _targetBearing;
      _startDeadReckoning();
    }
  }

  /// Call this every time a new socket position arrives.
  void updateToNewPosition(LatLng newPosition) {
    final now = DateTime.now();
    final elapsedSec = now.difference(_lastUpdateTime).inMilliseconds / 1000.0;
    _lastUpdateTime = now;

    final dist = _haversine(_currentPos, newPosition);
    if (elapsedSec > 0.0 && dist > 0.0) {
      _lastSpeedMps = (dist / elapsedSec).clamp(minSpeedMps, maxSpeedMps);
    } else if (_lastSpeedMps <= 0) {
      _lastSpeedMps = defaultSpeedMps;
    }

    final newBearing = _computeBearing(_currentPos, newPosition);

    _deadReckonTimer?.cancel();
    _deadStartAt = null;

    _targetPos = newPosition;
    _targetBearing = newBearing;
    _controller.forward(from: 0.0);
  }

  void _onAnimationTick() {
    final t = _animation.value;
    final pos = _lerpLatLng(_currentPos, _targetPos, t);
    final bearing = _slerpBearing(_currentBearing, _targetBearing, t);
    onUpdate(pos, bearing);
  }

  void _startDeadReckoning() {
    _deadReckonTimer?.cancel();
    if (_lastSpeedMps < minSpeedMps) return;

    _deadStartAt = DateTime.now();
    _deadReckonTimer = Timer.periodic(deadReckonTick, (_) {
      final start = _deadStartAt;
      if (start == null) return;
      if (DateTime.now().difference(start) > deadReckonStopAfter) {
        _deadReckonTimer?.cancel();
        return;
      }

      final dt = deadReckonTick.inMilliseconds / 1000.0;
      final projected = _projectPosition(_currentPos, _currentBearing, _lastSpeedMps * dt);
      _currentPos = projected;
      onUpdate(projected, _currentBearing);
    });
  }

  LatLng _projectPosition(LatLng from, double bearingDeg, double distanceMeters) {
    const R = 6371000.0;
    final d = distanceMeters / R;
    final bearing = bearingDeg * pi / 180.0;
    final lat1 = from.latitude * pi / 180.0;
    final lon1 = from.longitude * pi / 180.0;

    final lat2 = asin(
      sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(bearing),
    );
    final lon2 = lon1 +
        atan2(
          sin(bearing) * sin(d) * cos(lat1),
          cos(d) - sin(lat1) * sin(lat2),
        );
    return LatLng(lat2 * 180.0 / pi, lon2 * 180.0 / pi);
  }

  double _slerpBearing(double from, double to, double t) {
    double diff = _wrap360(to) - _wrap360(from);
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return _wrap360(from + diff * t);
  }

  LatLng _lerpLatLng(LatLng a, LatLng b, double t) {
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  double _computeBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * pi / 180.0;
    final lat2 = to.latitude * pi / 180.0;
    final dLon = (to.longitude - from.longitude) * pi / 180.0;
    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    return _wrap360(atan2(y, x) * 180.0 / pi);
  }

  double _haversine(LatLng a, LatLng b) {
    const R = 6371000.0;
    final dLat = (b.latitude - a.latitude) * pi / 180.0;
    final dLon = (b.longitude - a.longitude) * pi / 180.0;
    final sLat = sin(dLat / 2);
    final sLon = sin(dLon / 2);
    final aVal = sLat * sLat +
        cos(a.latitude * pi / 180.0) * cos(b.latitude * pi / 180.0) * sLon * sLon;
    return R * 2 * atan2(sqrt(aVal), sqrt(1 - aVal));
  }

  static double _wrap360(double deg) => (deg % 360.0 + 360.0) % 360.0;

  void dispose() {
    _deadReckonTimer?.cancel();
    _controller.removeListener(_onAnimationTick);
    _controller.removeStatusListener(_onStatus);
  }
}


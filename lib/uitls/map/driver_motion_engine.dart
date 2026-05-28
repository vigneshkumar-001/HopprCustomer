import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class DriverPose {
  final LatLng position;
  final DateTime t;
  final double? bearing;

  DriverPose({
    required this.position,
    DateTime? t,
    this.bearing,
  }) : t = t ?? DateTime.now();
}

/// Production-safe driver marker smoothing (Uber/Ola-like).
///
/// - Filters: stale packets, micro jitter, teleport jumps, out-of-order packets.
/// - Queue + segment animation with EMA smoothing and turn-rate clamp.
/// - Optional timestamp-based playback delay so motion looks continuous.
class DriverMotionEngine {
  DriverMotionEngine({
    required TickerProvider vsync,
    required this.onUpdate,
    this.onFrameSideEffects,
    Duration playbackDelay = const Duration(milliseconds: 600),
    Duration maxStale = const Duration(seconds: 20),
    Duration motionStepMinInterval = const Duration(milliseconds: 33),
    double minMoveMeters = 0.3,
    double hardJumpMeters = 120.0,
    int maxQueue = 10,
    Duration minSeg = const Duration(milliseconds: 450),
    Duration maxSeg = const Duration(milliseconds: 1200),
    Curve ease = Curves.easeInOutCubic,
    double emaAlphaSlow = 0.12,
    double emaAlphaFast = 0.30,
    double bearingEmaAlpha = 0.20,
    double maxTurnDegPerSec = 220.0,
    Duration maxFutureSkew = const Duration(seconds: 12),
    Duration outOfOrderTolerance = const Duration(milliseconds: 500),
    // When driver is stopped, GPS jitter can cause the marker to "dance".
    // We detect low implied speed (from timestamps) and ignore small moves.
    double stationarySpeedThresholdMps = 0.6,
    double stationaryIgnoreUnderMeters = 4.0,
  })  : _playbackDelay = playbackDelay,
        _maxStale = maxStale,
        _minUpdateInterval = motionStepMinInterval,
        _minMoveMeters = minMoveMeters,
        _hardJumpMeters = hardJumpMeters,
        _maxQueue = maxQueue,
        _minSeg = minSeg,
        _maxSeg = maxSeg,
        _ease = ease,
        _emaAlphaSlow = emaAlphaSlow,
        _emaAlphaFast = emaAlphaFast,
        _bearingEmaAlpha = bearingEmaAlpha,
        _maxTurnDegPerSec = maxTurnDegPerSec,
         _maxFutureSkew = maxFutureSkew,
         _outOfOrderTolerance = outOfOrderTolerance,
         _stationarySpeedThresholdMps = stationarySpeedThresholdMps,
         _stationaryIgnoreUnderMeters = stationaryIgnoreUnderMeters,
         _moveCtrl = AnimationController(vsync: vsync);

  final void Function(LatLng position, double bearing) onUpdate;
  final void Function(LatLng position)? onFrameSideEffects;

  final Duration _playbackDelay;
  final Duration _maxStale;
  final Duration _minUpdateInterval;

  final double _minMoveMeters;
  final double _hardJumpMeters;
  final int _maxQueue;
  final Duration _minSeg;
  final Duration _maxSeg;
  final Curve _ease;
  final double _emaAlphaSlow;
  final double _emaAlphaFast;
  final double _bearingEmaAlpha;
  final double _maxTurnDegPerSec;

  final Duration _maxFutureSkew;
  final Duration _outOfOrderTolerance;
  final double _stationarySpeedThresholdMps;
  final double _stationaryIgnoreUnderMeters;

  final List<DriverPose> _poseQueue = <DriverPose>[];
  final AnimationController _moveCtrl;

  bool _isAnimatingSegment = false;
  VoidCallback? _activeTick;

  LatLng? _lastReceivedPos;
  LatLng? _displayPos;
  LatLng? _emaPos;
  double _lastBearing = 0.0;

  DateTime? _lastPacketTs;
  DateTime _lastUpdateAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get hasFix => _displayPos != null;
  LatLng? get displayPosition => _displayPos;
  double get displayBearing => _lastBearing;

  void dispose() {
    if (_activeTick != null) _moveCtrl.removeListener(_activeTick!);
    _moveCtrl.dispose();
  }

  void clearQueue() => _poseQueue.clear();

  void reset(LatLng position, {double bearing = 0.0}) {
    _poseQueue.clear();
    _lastReceivedPos = position;
    _displayPos = position;
    _emaPos = position;
    _lastBearing = _wrap360(bearing);
    _isAnimatingSegment = false;
    _moveCtrl.stop();
    _moveCtrl.reset();
    _activeTick = null;
    _emit(position, _lastBearing, force: true);
  }

  /// Ingest a new server pose. Returns true if accepted.
  bool ingest(
    LatLng newPos, {
    DateTime? serverTs,
    double? bearing,
    DateTime? now,
  }) {
    final now0 = now ?? DateTime.now();
    DateTime ts = serverTs ?? now0;

    if (ts.isAfter(now0.add(_maxFutureSkew))) {
      ts = now0;
    }
    if (now0.difference(ts) > _maxStale) return false;

    final lastPkt = _lastPacketTs;
    if (lastPkt != null &&
        ts.isBefore(lastPkt.subtract(_outOfOrderTolerance))) {
      return false;
    }

    if (_lastReceivedPos != null) {
      final d = Geolocator.distanceBetween(
        _lastReceivedPos!.latitude,
        _lastReceivedPos!.longitude,
        newPos.latitude,
        newPos.longitude,
      );
      // Stationary jitter guard: if the implied speed is very low and the move is
      // small, treat it as GPS drift (prevents the car "dancing" while stopped).
      if (lastPkt != null) {
        final dtMs = ts.difference(lastPkt).inMilliseconds;
        if (dtMs > 200) {
          final implied = d / (dtMs / 1000.0);
          if (implied <= _stationarySpeedThresholdMps &&
              d <= _stationaryIgnoreUnderMeters) {
            _lastPacketTs = ts;
            return false;
          }
        }
      }
      if (d < _minMoveMeters) {
        _lastPacketTs = ts;
        return false;
      }
      if (d > _hardJumpMeters) {
        _lastPacketTs = ts;
        reset(newPos, bearing: bearing ?? _lastBearing);
        return true;
      }
    }
    _lastPacketTs = ts;
    _lastReceivedPos = newPos;

    if (_displayPos == null) {
      reset(newPos, bearing: bearing ?? 0.0);
      return true;
    }

    final shiftedTs = ts.add(_playbackDelay);
    _poseQueue.add(DriverPose(position: newPos, bearing: bearing, t: shiftedTs));
    if (_poseQueue.length > _maxQueue) {
      _poseQueue.removeRange(0, _poseQueue.length - _maxQueue);
    }

    _pumpMotion();
    return true;
  }

  void _pumpMotion() {
    if (_isAnimatingSegment) return;
    if (_poseQueue.isEmpty) return;
    if (_displayPos == null) return;

    final from = _displayPos!;
    final toPose = _poseQueue.removeAt(0);
    final to = toPose.position;

    final dist = Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
    if (dist < _minMoveMeters) {
      if (_poseQueue.isNotEmpty) _pumpMotion();
      return;
    }

    // Animation duration derived from distance and a conservative min speed.
    // Required clamp:
    // durationMs = clamp(distance / max(speedMps, 4.0) * 1000, 650, 1800)
    // Here we don't know real-time speed reliably from server, so we use the
    // conservative minimum speed bound (4 m/s) to keep motion smooth and fast.
    int dur = ((dist / math.max(4.0, 4.0)) * 1000).toInt();
    dur = dur.clamp(
      math.max(650, _minSeg.inMilliseconds),
      math.min(1800, _maxSeg.inMilliseconds),
    );
    final segDur = Duration(milliseconds: dur);

    final targetBearing = toPose.bearing ?? _computeBearing(from, to);
    final startBearing = _lastBearing;
    final bearingDelta = _shortestAngleDelta(startBearing, targetBearing);

    _isAnimatingSegment = true;

    _moveCtrl
      ..stop()
      ..reset()
      ..duration = segDur;

    if (_activeTick != null) _moveCtrl.removeListener(_activeTick!);
    _activeTick = () => _onTick(from, to, startBearing, bearingDelta);
    _moveCtrl.addListener(_activeTick!);

    _moveCtrl.forward().whenComplete(() {
      _displayPos = to;
      _lastBearing = _wrap360(startBearing + bearingDelta);
      _emit(_emaPos ?? to, _lastBearing, force: true);

      _isAnimatingSegment = false;
      if (_poseQueue.isNotEmpty) _pumpMotion();
    });
  }

  void _onTick(
    LatLng from,
    LatLng to,
    double startBearing,
    double bearingDelta,
  ) {
    final t = _ease.transform(_moveCtrl.value);

    final rawPos = LatLng(
      _lerp(from.latitude, to.latitude, t),
      _lerp(from.longitude, to.longitude, t),
    );

    final rawDist = Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
    final segSeconds = (_moveCtrl.duration?.inMilliseconds ?? 1) / 1000.0;
    final speedMps = (segSeconds > 0) ? (rawDist / segSeconds) : 0.0;
    final emaAlpha = (speedMps > 8.0) ? _emaAlphaFast : _emaAlphaSlow;

    _emaPos = (_emaPos == null) ? rawPos : _emaLatLng(_emaPos!, rawPos, emaAlpha);

    final targetB = _wrap360(startBearing + bearingDelta * t);
    final emaB = _emaAngle(_lastBearing, targetB, _bearingEmaAlpha);

    _lastBearing = _clampTurnRate(
      _lastBearing,
      emaB,
      1 / 60.0,
      _maxTurnDegPerSec,
    );

    _emit(_emaPos!, _lastBearing, force: false);
  }

  void _emit(LatLng pos, double bearing, {required bool force}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastUpdateAt) < _minUpdateInterval) return;
    _lastUpdateAt = now;
    onUpdate(pos, bearing);
    onFrameSideEffects?.call(pos);
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  double _wrap360(double a) => (a % 360 + 360) % 360;

  double _shortestAngleDelta(double from, double to) {
    double diff = _wrap360(to) - _wrap360(from);
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return diff;
  }

  double _emaAngle(double prevDeg, double targetDeg, double alpha) {
    final d = _shortestAngleDelta(prevDeg, targetDeg);
    return _wrap360(prevDeg + alpha * d);
  }

  LatLng _emaLatLng(LatLng prev, LatLng next, double alpha) {
    return LatLng(
      _lerp(prev.latitude, next.latitude, alpha),
      _lerp(prev.longitude, next.longitude, alpha),
    );
  }

  double _clampTurnRate(
    double current,
    double target,
    double dtSeconds,
    double maxDegPerSec,
  ) {
    final delta = _shortestAngleDelta(current, target);
    final maxDelta = maxDegPerSec * dtSeconds;
    final clamped = delta.clamp(-maxDelta, maxDelta);
    return _wrap360(current + clamped);
  }

  double _deg2rad(double d) => d * math.pi / 180.0;

  double _computeBearing(LatLng from, LatLng to) {
    final double lat1 = _deg2rad(from.latitude);
    final double lat2 = _deg2rad(to.latitude);
    final double dLon = _deg2rad(to.longitude - from.longitude);

    final double y = math.sin(dLon) * math.cos(lat2);
    final double x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final double brng = math.atan2(y, x);
    return _wrap360(brng * 180.0 / math.pi);
  }
}

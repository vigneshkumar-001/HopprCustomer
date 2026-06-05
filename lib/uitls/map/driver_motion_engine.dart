import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class DriverPose {
  final LatLng position;
  final DateTime t;
  final double? bearing;
  final int? packetIntervalMs;
  final bool hasServerBearing;

  DriverPose({
    required this.position,
    DateTime? t,
    this.bearing,
    this.packetIntervalMs,
    this.hasServerBearing = false,
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
    // Position smoothing is intentionally light: the eased segment lerp is
    // already smooth, and snap-to-route removes cross-track jitter. Heavy EMA
    // here just makes the marker lag its own heading -> the "crab/slide" look.
    double emaAlphaSlow = 0.40,
    double emaAlphaFast = 0.55,
    // Rotate quickly so the icon faces the travel direction instead of sliding
    // sideways through turns. (Uber/Ola-like snappy heading.)
    double bearingEmaAlpha = 0.40,
    double maxTurnDegPerSec = 540.0,
    Duration maxFutureSkew = const Duration(seconds: 12),
    Duration outOfOrderTolerance = const Duration(milliseconds: 500),
    bool enableDeadReckoning = true,
    bool requireBearingForDeadReckoning = false,
    Duration maxDeadReckonPacketGap = const Duration(seconds: 4),
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
        _enableDeadReckoning = enableDeadReckoning,
        _requireBearingForDeadReckoning = requireBearingForDeadReckoning,
        _maxDeadReckonPacketGap = maxDeadReckonPacketGap,
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
  final bool _enableDeadReckoning;
  final bool _requireBearingForDeadReckoning;
  final Duration _maxDeadReckonPacketGap;
  final double _stationarySpeedThresholdMps;
  final double _stationaryIgnoreUnderMeters;

  final List<DriverPose> _poseQueue = <DriverPose>[];
  final AnimationController _moveCtrl;

  bool _isAnimatingSegment = false;
  VoidCallback? _activeTick;
  Timer? _deadReckonTimer;
  DateTime _deadReckonStartAt = DateTime.fromMillisecondsSinceEpoch(0);

  static const Duration _deadReckonTick = Duration(milliseconds: 100);
  static const Duration _deadReckonStopAfter = Duration(seconds: 15);
  double _lastSpeedMps = 0.0;
  int? _lastPacketIntervalMs;
  bool _lastPacketHadBearing = false;

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
    _deadReckonTimer?.cancel();
    if (_activeTick != null) _moveCtrl.removeListener(_activeTick!);
    _moveCtrl.dispose();
  }

  void clearQueue() => _poseQueue.clear();

  void reset(LatLng position, {double bearing = 0.0}) {
    _deadReckonTimer?.cancel();
    _poseQueue.clear();
    _lastReceivedPos = position;
    _displayPos = position;
    _emaPos = position;
    _lastBearing = _wrap360(bearing);
    _isAnimatingSegment = false;
    _moveCtrl.stop();
    _moveCtrl.reset();
    _activeTick = null;
    _lastSpeedMps = 0.0;
    _emit(position, _lastBearing, force: true);
  }

  /// Ingest a new server pose. Returns true if accepted.
  bool ingest(
    LatLng newPos, {
    DateTime? serverTs,
    double? bearing,
    DateTime? now,
    bool allowDeadReckoning = true,
  }) {
    final now0 = now ?? DateTime.now();
    DateTime ts = serverTs ?? now0;

    // Real data arrived: stop dead-reckoning immediately.
    _deadReckonTimer?.cancel();

    if (ts.isAfter(now0.add(_maxFutureSkew))) {
      ts = now0;
    }
    if (now0.difference(ts) > _maxStale) return false;

    final lastPkt = _lastPacketTs;
    if (lastPkt != null &&
        ts.isBefore(lastPkt.subtract(_outOfOrderTolerance))) {
      return false;
    }

    final packetIntervalMs =
        lastPkt == null ? null : ts.difference(lastPkt).inMilliseconds;

    if (_lastReceivedPos != null) {
      final d = Geolocator.distanceBetween(
        _lastReceivedPos!.latitude,
        _lastReceivedPos!.longitude,
        newPos.latitude,
        newPos.longitude,
      );
      if (lastPkt != null) {
        final dtMs = ts.difference(lastPkt).inMilliseconds;
        if (dtMs > 0) {
          final implied = d / (dtMs / 1000.0);
          // Clamp to a sensible envelope to avoid crazy projections.
          _lastSpeedMps = implied.clamp(0.0, 30.0);
        }
      }
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
    _lastPacketIntervalMs =
        packetIntervalMs != null && packetIntervalMs > 0
            ? packetIntervalMs
            : _lastPacketIntervalMs;
    _lastPacketHadBearing = allowDeadReckoning && bearing != null;
    _lastReceivedPos = newPos;
    if (!allowDeadReckoning) {
      _lastSpeedMps = 0.0;
      _lastPacketIntervalMs = _maxDeadReckonPacketGap.inMilliseconds + 1;
    }

    if (_displayPos == null) {
      reset(newPos, bearing: bearing ?? 0.0);
      return true;
    }

    final shiftedTs = ts.add(_playbackDelay);
    _poseQueue.add(
      DriverPose(
        position: newPos,
        bearing: bearing,
        t: shiftedTs,
        packetIntervalMs: packetIntervalMs,
        hasServerBearing: bearing != null,
      ),
    );
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

    // Continuous-motion duration (Uber/Ola feel).
    //
    // The marker should still be gliding when the next packet arrives — not
    // race to the target and freeze (stop-and-go), and not fall further behind
    // every packet (lag). So we animate each segment over roughly the cadence
    // at which packets actually arrive, instead of deriving it from distance.
    final int? intervalMs = toPose.packetIntervalMs ?? _lastPacketIntervalMs;
    int dur;
    if (intervalMs != null && intervalMs > 0) {
      // Caught up (no buffered poses): stretch slightly past the interval so we
      // never run dry before the next packet lands -> continuous glide.
      // Behind (poses buffered): shrink below the interval to catch up smoothly
      // instead of accumulating lag.
      final double factor = _poseQueue.isEmpty ? 1.12 : 0.80;
      dur = (intervalMs * factor).round();
    } else {
      // First segment / unknown cadence: conservative distance-based guess.
      dur = ((dist / 6.0) * 1000).round();
    }
    dur = dur.clamp(_minSeg.inMilliseconds, _maxSeg.inMilliseconds);
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
      if (_poseQueue.isNotEmpty) {
        _pumpMotion();
      } else {
        _startDeadReckoningIfNeeded();
      }
    });
  }

  void _startDeadReckoningIfNeeded() {
    // Only when we have a fix, not currently animating, and no buffered poses.
    if (!_enableDeadReckoning) return;
    if (_displayPos == null) return;
    if (_isAnimatingSegment) return;
    if (_poseQueue.isNotEmpty) return;
    if (_requireBearingForDeadReckoning && !_lastPacketHadBearing) return;
    if (_lastPacketIntervalMs != null &&
        _lastPacketIntervalMs! > _maxDeadReckonPacketGap.inMilliseconds) {
      return;
    }

    // If implied speed is too low, driver is likely stopped -> no projection.
    if (_lastSpeedMps < 1.0) return;

    _deadReckonTimer?.cancel();
    _deadReckonStartAt = DateTime.now();

    _deadReckonTimer = Timer.periodic(_deadReckonTick, (_) {
      if (_displayPos == null) {
        _deadReckonTimer?.cancel();
        return;
      }
      if (_isAnimatingSegment || _poseQueue.isNotEmpty) {
        _deadReckonTimer?.cancel();
        return;
      }
      if (DateTime.now().difference(_deadReckonStartAt) > _deadReckonStopAfter) {
        _deadReckonTimer?.cancel();
        return;
      }

      final dt = _deadReckonTick.inMilliseconds / 1000.0;
      final projected = _projectPosition(_displayPos!, _lastBearing, _lastSpeedMps * dt);
      _displayPos = projected;
      _emaPos = projected;
      _emit(projected, _lastBearing, force: false);
    });
  }

  LatLng _projectPosition(LatLng from, double bearingDeg, double distanceMeters) {
    const R = 6371000.0;
    final d = distanceMeters / R;
    final bearing = _deg2rad(bearingDeg);
    final lat1 = _deg2rad(from.latitude);
    final lon1 = _deg2rad(from.longitude);

    final lat2 = math.asin(
      math.sin(lat1) * math.cos(d) + math.cos(lat1) * math.sin(d) * math.cos(bearing),
    );
    final lon2 = lon1 +
        math.atan2(
          math.sin(bearing) * math.sin(d) * math.cos(lat1),
          math.cos(d) - math.sin(lat1) * math.sin(lat2),
        );

    return LatLng(lat2 * 180.0 / math.pi, lon2 * 180.0 / math.pi);
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

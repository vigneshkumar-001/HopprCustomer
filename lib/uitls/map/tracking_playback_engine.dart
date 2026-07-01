import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// One time-stamped driver sample (position the customer should eventually show).
class _Sample {
  final LatLng pos;
  final double? bearing;
  // PLAYBACK time (ms) in the CLIENT clock domain. When the server stamps the
  // packet (serverEmittedAt/serverTime) we map that emit time into the client
  // clock and store it here, so the buffer reflects the TRUE inter-fix spacing
  // produced by the driver/server — not the moment the OS happened to deliver
  // the packet. Falls back to client arrival time when no server time is given.
  final int tMs;
  const _Sample(this.pos, this.bearing, this.tMs);
}

/// Jitter-buffer playback engine for the customer's driver marker.
///
/// Design (borrowed from media streaming): treat incoming driver fixes like a
/// media stream and PLAY THEM BACK ON A FIXED DELAY. A 60fps render loop renders
/// `renderTime = now - playbackDelay` and INTERPOLATES between the two buffered
/// samples that bracket it. Because we render slightly in the past, a late /
/// out-of-order / bursty packet still arrives BEFORE its render time, so the
/// marker never jumps, never teleports, and never steps backward — it only ever
/// glides forward between two real, time-ordered points. When the buffer runs
/// dry (signal loss / tunnel) it dead-reckons forward, bounded, easing to a stop.
///
/// Drop-in replacement for the old segment-animated `DriverMotionEngine`:
/// same `ingest / reset / clearQueue / hasFix / dispose` surface.
class TrackingPlaybackEngine {
  TrackingPlaybackEngine({
    required TickerProvider vsync,
    required this.onUpdate,
    this.onFrameSideEffects,
    Duration playbackDelay = const Duration(milliseconds: 1500),
    Duration maxPredict = const Duration(seconds: 5),
    double hardJumpMeters = 150.0,
    double maxTurnDegPerSec = 120.0,
    double posEmaAlpha = 0.45,
    double bearingEmaAlpha = 0.30,
    Duration minEmitInterval = const Duration(milliseconds: 33),
  })  : _playbackMs = playbackDelay.inMilliseconds,
        _maxPredictMs = maxPredict.inMilliseconds,
        _hardJump = hardJumpMeters,
        _maxTurnDegPerSec = maxTurnDegPerSec,
        _posAlpha = posEmaAlpha,
        _brgAlpha = bearingEmaAlpha,
        _minEmitMs = minEmitInterval.inMilliseconds {
    _ticker = vsync.createTicker(_onTick)..start();
  }

  final void Function(LatLng pos, double bearing) onUpdate;
  final void Function(LatLng pos)? onFrameSideEffects;

  final int _playbackMs;
  final int _maxPredictMs;
  final double _hardJump;
  final double _maxTurnDegPerSec;
  final double _posAlpha;
  final double _brgAlpha;
  final int _minEmitMs;

  final List<_Sample> _buf = <_Sample>[];
  late final Ticker _ticker;

  // Maps a server emit time into the client clock: clientTime ≈ serverTime +
  // offset. Estimated as the MINIMUM observed (arrival - serverEmit) across the
  // stream — i.e. the lowest-latency packet, the standard NTP-style floor. Using
  // server time (instead of arrival time) for buffer spacing means a burst of
  // packets the OS/network delivered together no longer collapses the sample
  // timeline into a fast catch-up glide; each sample keeps its real spacing.
  int? _serverClockOffsetMs;

  LatLng? _displayPos; // last EMITTED (rendered) position
  LatLng? _rawTarget; // last raw interpolation target (pre-EMA)
  double _lastBearing = 0.0;
  double _lastSpeedMps = 0.0;
  int _lastEmitAtMs = 0;

  bool get hasFix => _displayPos != null;
  LatLng? get displayPosition => _displayPos;
  double get displayBearing => _lastBearing;

  void dispose() {
    _ticker.dispose();
    _buf.clear();
  }

  void clearQueue() => _buf.clear();

  int get _now => DateTime.now().millisecondsSinceEpoch;

  /// Hard reset to a known position (first fix / teleport / phase switch).
  void reset(LatLng pos, {double bearing = 0.0}) {
    _buf
      ..clear()
      // Seed one sample in the past so the very next ingest can bracket it.
      ..add(_Sample(pos, bearing, _now - _playbackMs));
    _displayPos = pos;
    _rawTarget = pos;
    _lastBearing = _wrap360(bearing);
    _lastSpeedMps = 0.0;
    _emit(pos, _lastBearing, force: true);
  }

  /// Push a new (already cosmetically snapped) driver fix.
  ///
  /// [serverTs] is the server emit time (serverEmittedAt/serverTime). When
  /// present it drives the buffer timeline so bursty/coalesced delivery cannot
  /// distort the playback spacing; arrival time is used only as a fallback.
  void ingest(LatLng pos, {double? bearing, DateTime? serverTs}) {
    if (_displayPos == null) {
      reset(pos, bearing: bearing ?? 0.0);
      return;
    }
    final nowMs = _now;

    // Resolve this sample's playback time. Prefer the server emit time mapped
    // into the client clock; fall back to arrival time when unstamped.
    int tMs;
    if (serverTs != null) {
      final stMs = serverTs.millisecondsSinceEpoch;
      final observedOffset = nowMs - stMs; // = trueOffset + networkLatency(>=0)
      if (_serverClockOffsetMs == null ||
          observedOffset < _serverClockOffsetMs!) {
        _serverClockOffsetMs = observedOffset; // NTP-style min (lowest latency)
      }
      tMs = stMs + _serverClockOffsetMs!;
      // A mapped time must never run ahead of real arrival — that would push the
      // sample into the future relative to renderT and stall playback. Clamp.
      if (tMs > nowMs) tMs = nowMs;
    } else {
      tMs = nowMs;
    }

    if (_buf.isNotEmpty) {
      final last = _buf.last;
      final d = _dist(last.pos, pos);
      // Teleport guard: a single huge hop = GPS garbage / resumed-after-gap warp.
      // Re-seed instead of animating across the map.
      if (d > _hardJump) {
        reset(pos, bearing: bearing ?? _lastBearing);
        return;
      }
      // Keep the buffer strictly time-ordered. The controller already drops
      // stale/out-of-order packets by ts+seq, but clamp defensively so a tie
      // (or clock quirk) can never produce a zero/negative span downstream.
      if (tMs <= last.tMs) tMs = last.tMs + 1;
      // Update the live speed estimate from the real (server-spaced) interval.
      final dtMs = tMs - last.tMs;
      if (dtMs > 0) {
        final implied = d / (dtMs / 1000.0);
        _lastSpeedMps = implied.clamp(0.0, 35.0).toDouble();
      }
    }

    _buf.add(_Sample(pos, bearing, tMs));
    if (_buf.length > 120) _buf.removeRange(0, _buf.length - 120);
  }

  void _onTick(Duration _) {
    if (_displayPos == null || _buf.isEmpty) return;
    final renderT = _now - _playbackMs;

    // Find the last sample at/<= renderT (the "floor").
    int aIdx = -1;
    for (int i = 0; i < _buf.length; i++) {
      if (_buf[i].tMs <= renderT) {
        aIdx = i;
      } else {
        break;
      }
    }

    LatLng target;
    double targetBrg;

    if (aIdx < 0) {
      // renderT is before the earliest buffered sample (just connected): hold
      // at the earliest known point until playback "catches up" to real data.
      final first = _buf.first;
      target = first.pos;
      targetBrg = first.bearing ?? _lastBearing;
    } else if (aIdx < _buf.length - 1) {
      // Normal case: interpolate between the bracketing samples A..B.
      final a = _buf[aIdx];
      final b = _buf[aIdx + 1];
      final span = b.tMs - a.tMs;
      final t = span <= 0 ? 1.0 : ((renderT - a.tMs) / span).clamp(0.0, 1.0);
      target = _lerp(a.pos, b.pos, t);
      final course = _bearingBetween(a.pos, b.pos);
      // Prefer a provided heading (already route-aligned); fall back to course.
      targetBrg = b.bearing ?? a.bearing ?? course;
      // Prune consumed history but keep `a` as the floor.
      if (aIdx > 0) _buf.removeRange(0, aIdx);
    } else {
      // Buffer dry (renderT past newest sample): dead-reckon forward, bounded.
      final a = _buf.last;
      final ageMs = renderT - a.tMs;
      if (ageMs > 0 &&
          ageMs <= _maxPredictMs &&
          _lastSpeedMps > 0.8 &&
          a.bearing != null) {
        // Decay speed so a slowing/stopping driver coasts to a halt instead of
        // drifting ahead then snapping back when the next real fix lands.
        final decay = math.pow(0.92, ageMs / 100.0).toDouble();
        final dist = _lastSpeedMps * decay * (ageMs / 1000.0);
        target = _project(a.pos, a.bearing!, dist);
        targetBrg = a.bearing!;
      } else {
        target = a.pos; // hold (stopped / too long a gap)
        targetBrg = a.bearing ?? _lastBearing;
      }
    }

    // Light position EMA — removes residual micro-jitter without adding lag.
    final raw = _rawTarget;
    _rawTarget = target;
    final smoothed =
        raw == null ? target : _emaLatLng(_displayPos ?? target, target, _posAlpha);

    // Bearing: EMA + a real-car turn-rate clamp (no instant spins).
    final emaB = _emaAngle(_lastBearing, targetBrg, _brgAlpha);
    final clampedB = _clampTurn(_lastBearing, emaB, _maxTurnDegPerSec, 1 / 60.0);

    _displayPos = smoothed;
    _lastBearing = clampedB;
    _emit(smoothed, clampedB, force: false);
  }

  void _emit(LatLng pos, double bearing, {required bool force}) {
    final nowMs = _now;
    if (!force && nowMs - _lastEmitAtMs < _minEmitMs) return;
    _lastEmitAtMs = nowMs;
    onUpdate(pos, bearing);
    onFrameSideEffects?.call(pos);
  }

  // ---- geo / math helpers ----
  double _dist(LatLng a, LatLng b) => Geolocator.distanceBetween(
        a.latitude,
        a.longitude,
        b.latitude,
        b.longitude,
      );

  LatLng _lerp(LatLng a, LatLng b, double t) => LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );

  LatLng _emaLatLng(LatLng prev, LatLng next, double alpha) => LatLng(
        prev.latitude + (next.latitude - prev.latitude) * alpha,
        prev.longitude + (next.longitude - prev.longitude) * alpha,
      );

  double _wrap360(double a) => (a % 360 + 360) % 360;

  double _shortestDelta(double from, double to) {
    double d = _wrap360(to) - _wrap360(from);
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }

  double _emaAngle(double prev, double target, double alpha) =>
      _wrap360(prev + alpha * _shortestDelta(prev, target));

  double _clampTurn(double current, double target, double maxDegPerSec, double dt) {
    final delta = _shortestDelta(current, target);
    final maxStep = maxDegPerSec * dt;
    return _wrap360(current + delta.clamp(-maxStep, maxStep));
  }

  double _deg2rad(double d) => d * math.pi / 180.0;

  double _bearingBetween(LatLng a, LatLng b) {
    final lat1 = _deg2rad(a.latitude);
    final lat2 = _deg2rad(b.latitude);
    final dLon = _deg2rad(b.longitude - a.longitude);
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return _wrap360(math.atan2(y, x) * 180.0 / math.pi);
  }

  LatLng _project(LatLng from, double bearingDeg, double meters) {
    const r = 6371000.0;
    final d = meters / r;
    final brg = _deg2rad(bearingDeg);
    final lat1 = _deg2rad(from.latitude);
    final lon1 = _deg2rad(from.longitude);
    final lat2 = math.asin(
      math.sin(lat1) * math.cos(d) + math.cos(lat1) * math.sin(d) * math.cos(brg),
    );
    final lon2 = lon1 +
        math.atan2(
          math.sin(brg) * math.sin(d) * math.cos(lat1),
          math.cos(d) - math.sin(lat1) * math.sin(lat2),
        );
    return LatLng(lat2 * 180.0 / math.pi, lon2 * 180.0 / math.pi);
  }
}

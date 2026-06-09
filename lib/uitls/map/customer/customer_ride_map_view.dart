import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, HapticFeedback;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:hopper/uitls/map/customer/camera_utils.dart';
import 'package:hopper/uitls/map/customer/map_eta_distance_card.dart';
import 'package:hopper/uitls/map/customer/map_ui_config.dart';
import 'package:hopper/uitls/map/customer/marker_icon_cache.dart';
import 'package:hopper/uitls/map/driver_motion_engine.dart';
import 'package:hopper/uitls/map/route_tracking_math.dart';

enum RideMapMode { idle, toPickup, toDrop }

class CustomerRideMapView extends StatefulWidget {
  final VehicleType vehicleType;

  /// Live driver location updates (raw). Animations happen in-widget.
  final LatLng? driverLocation;

  /// Decoded route points.
  final List<LatLng> routePoints;

  final LatLng pickup;
  final LatLng drop;

  final RideMapMode mode;

  final String etaText;
  final String distanceText;
  final String? statusText;

  final EdgeInsets mapPadding;
  final ValueChanged<GoogleMapController>? onMapReady;

  const CustomerRideMapView({
    super.key,
    required this.vehicleType,
    required this.driverLocation,
    required this.routePoints,
    required this.pickup,
    required this.drop,
    required this.mode,
    required this.etaText,
    required this.distanceText,
    this.statusText,
    this.mapPadding = const EdgeInsets.only(
      bottom: MapUiConfig.defaultBottomPadding,
    ),
    this.onMapReady,
  });

  @override
  CustomerRideMapViewState createState() => CustomerRideMapViewState();
}

class CustomerRideMapViewState extends State<CustomerRideMapView>
    with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  String? _mapStyle;

  BitmapDescriptor? _vehIcon;
  BitmapDescriptor? _pickupIcon;
  BitmapDescriptor? _dropIcon;

  late final DriverMotionEngine _motion;
  LatLng? _vehiclePos;
  double _vehicleBearing = 0;

  List<LatLng> _fullRoute = const <LatLng>[];
  List<LatLng> _remainingRoute = const <LatLng>[];
  int _lastTrimIndex = 0;
  String _routeSig = '';

  Set<Polyline> _polylines = const <Polyline>{};
  Set<Marker> _markers = const <Marker>{};

  // --- animated map flourishes: progressive route draw, flowing comet line,
  // distance-aware radar pulse, and arrival celebration. All driven by a single
  // low-rate fx ticker so they stay cheap and never fight the motion engine. ---
  Set<Circle> _circles = const <Circle>{};
  Timer? _fxTimer;
  late final AnimationController _routeDrawCtrl;
  late final AnimationController _arrivalCtrl;
  late final AnimationController _completeCtrl; // ride-complete confetti
  double _flowPhase = 0.0;
  double _pulsePhase = 0.0;
  RideMapMode? _drawnForMode;
  // Camera is fit-to-bounds only the first time a valid route arrives per phase.
  // (The controller re-trims the route constantly, which must NOT keep refitting
  // the camera — that caused the map/car to "jump" every few seconds.)
  RideMapMode? _fittedForMode;
  bool _celebratedPickup = false;
  bool _celebratedDrop = false;
  LatLng? _arrivalCenter;

  DateTime _lastCameraAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _pauseFollowUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastFitAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastFitKey = '';
  bool _pendingFit = false;

  double _currentZoom = MapUiConfig.initialZoom;

  Timer? _markerFlushTimer;
  LatLng? _pendingMarkerPos;
  double? _pendingMarkerBearing;
  DateTime _lastMarkerCommitAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _markerMinInterval = Duration(milliseconds: 70);

  DateTime _lastPolylineTrimAt = DateTime.fromMillisecondsSinceEpoch(0);
  // Trim the travelled part of the route quickly so it tracks the marker
  // instead of lagging a few seconds behind.
  static const Duration _polyTrimInterval = Duration(milliseconds: 60);

  /// Adaptive follow zoom — better than a fixed zoom: wide when the driver is
  /// far from the active target and tightening automatically as they approach,
  /// like a polished Ola/Uber tracking view. North-up + flat, so these read
  /// comfortably (not "over-zoomed").
  double _adaptiveFollowZoom(LatLng vehiclePos, {bool recenter = false}) {
    final target =
        widget.mode == RideMapMode.toDrop ? widget.drop : widget.pickup;
    final gap = haversineDistanceMeters(vehiclePos, target);
    double z;
    if (gap > 2000) {
      z = 14.6; // far away: show plenty of road
    } else if (gap > 1200) {
      z = 15.0;
    } else if (gap > 600) {
      z = 15.6;
    } else if (gap > 300) {
      z = 16.2;
    } else if (gap > 140) {
      z = 16.7;
    } else {
      z = 17.0; // about to arrive: tight so the user sees the exact spot
    }
    // Recenter is an explicit "focus" tap -> nudge slightly tighter.
    if (recenter) z += 0.3;
    return z.clamp(MapUiConfig.minZoom, MapUiConfig.maxZoom);
  }

  double _bearingWithVehicleIconOffset(double bearing) {
    final offset =
        widget.vehicleType == VehicleType.bike
            ? MapUiConfig.bikeBearingIconOffsetDeg
            : MapUiConfig.carBearingIconOffsetDeg;
    return MapUiConfig.normalizeBearing(bearing + offset);
  }

  @override
  void initState() {
    super.initState();

    _routeDrawCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
    _arrivalCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _completeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _fxTimer = Timer.periodic(const Duration(milliseconds: 70), _onFxTick);

    _motion = DriverMotionEngine(
      vsync: this,
      onUpdate: (pos, bearing) {
        final snapped = _snapAndBearing(
          pos,
          rawBearing: bearing,
          toleranceMeters: MapUiConfig.snapToRouteToleranceMeters + 10.0,
        );
        _queueVehicleMarker(snapped.position, snapped.bearing);
      },
      onFrameSideEffects: (pos) {
        final snapped = _snapAndBearing(
          pos,
          rawBearing: _vehicleBearing,
          toleranceMeters: MapUiConfig.snapToRouteToleranceMeters + 10.0,
        );
        _maybeTrimRoute(snapped.position);
        _maybeFollowCamera(snapped.position);
        _maybeCelebrateArrival(snapped.position);
      },
      playbackDelay: const Duration(milliseconds: 220),
      minSeg: const Duration(milliseconds: 320),
      maxSeg: const Duration(milliseconds: 2600),
      // Lower gates so slow / stop-and-go traffic still moves the car instead of
      // freezing. Snap-to-route + the marker throttle still suppress jitter.
      minMoveMeters: 0.8,
      requireBearingForDeadReckoning: true,
      maxDeadReckonPacketGap: const Duration(seconds: 4),
      stationarySpeedThresholdMps: 0.35,
      stationaryIgnoreUnderMeters: 1.0,
    );

    _loadMapStyle();
    _loadIcons();
    _syncRoute(force: true);

    // IMPORTANT: never seed the vehicle marker from pickup/drop.
    // Driver location can arrive slightly later via socket; showing the car at
    // pickup is misleading and looks like a bug. We only render the vehicle
    // once we have a real driver fix.
    final initPos = widget.driverLocation;
    if (initPos != null) {
      _motion.reset(initPos, bearing: 0);
      _vehiclePos = initPos;
    }
  }

  @override
  void dispose() {
    _markerFlushTimer?.cancel();
    _fxTimer?.cancel();
    _routeDrawCtrl.dispose();
    _arrivalCtrl.dispose();
    _completeCtrl.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CustomerRideMapView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.vehicleType != widget.vehicleType) {
      _loadIcons();
    }

    // routePoints may be mutated in-place (RxList). Compare a lightweight
    // signature instead of relying on list identity.
    if (_computeRouteSig(widget.routePoints) != _routeSig) {
      _syncRoute(force: true);
      // Fit the camera ONLY the first time a valid route arrives for this phase.
      // The controller re-trims the route as the driver advances (signature
      // changes constantly); refitting on every trim made the map/car jump and
      // the route flash "partial". Subsequent trims keep the follow-camera.
      if (_fittedForMode != widget.mode &&
          _routeMatchesCurrentMode(widget.routePoints)) {
        _fittedForMode = widget.mode;
        _requestFitBounds(reason: 'route_first_for_mode', force: true);
      }
    }

    if (oldWidget.pickup != widget.pickup || oldWidget.drop != widget.drop) {
      _syncMarkers(force: true);
      _requestFitBounds(reason: 'pickup_drop_changed', force: true);
    }
    if (oldWidget.mode != widget.mode) {
      _syncRoute(force: true);
      _syncMarkers(force: true);
      _rebuildPolylines();
      // Drop the stale pickup-phase motion (queued poses + carried-over
      // bearing) so the car doesn't glide the wrong way into the drop leg. It
      // re-seeds at the current display pose and re-derives heading from the
      // drop route on the next location update.
      if (_vehiclePos != null) {
        _motion.reset(_vehiclePos!, bearing: _vehicleBearing);
      } else {
        _motion.clearQueue();
      }
      // New phase: allow exactly one fresh fit once its valid route arrives.
      _fittedForMode = null;
    }

    if (widget.driverLocation != null &&
        oldWidget.driverLocation != widget.driverLocation) {
      final snapped = _snapAndBearing(widget.driverLocation!);
      if (!_motion.hasFix) {
        // First live fix: set immediately (no long animation from pickup).
        _motion.reset(snapped.position, bearing: snapped.bearing);
        _vehiclePos = snapped.position;
        _vehicleBearing = snapped.bearing;
        _syncMarkers(force: true);
      } else {
        _motion.ingest(snapped.position, bearing: snapped.bearing);
      }
    }
  }

  bool _isNightNow() {
    final h = DateTime.now().hour;
    return h >= 19 || h < 6; // 7pm–6am -> dark theme
  }

  Future<void> _loadMapStyle() async {
    try {
      // Auto day/night: clean light style by day, clean dark style at night.
      final asset =
          _isNightNow()
              ? 'assets/map_style/map_style_dark.json'
              : 'assets/map_style.json';
      _mapStyle = await rootBundle.loadString(asset);
      if (_mapController != null) {
        await _mapController!.setMapStyle(_mapStyle);
      }
    } catch (_) {}
  }

  Future<void> _loadIcons() async {
    final dpr = ui.window.devicePixelRatio;
    try {
      _vehIcon = await MarkerIconCache.vehicleIcon(
        widget.vehicleType,
        dpr: dpr,
      );
    } catch (e) {
      if (kDebugMode) {
        AppLogger.log.w('vehicle icon load failed: $e');
      }
    }
    try {
      _pickupIcon = await MarkerIconCache.pickupPin(dpr: dpr);
      _dropIcon = await MarkerIconCache.dropPin(dpr: dpr);
    } catch (_) {}

    _syncMarkers(force: true);
  }

  void _syncRoute({required bool force}) {
    final pts = widget.routePoints;
    final sig = _computeRouteSig(pts);
    if (!force && sig == _routeSig) return;

    _routeSig = sig;
    if (!_routeMatchesCurrentMode(pts)) {
      _fullRoute = const <LatLng>[];
      _remainingRoute = const <LatLng>[];
      _lastTrimIndex = 0;
      _rebuildPolylines();
      return;
    }
    _fullRoute = List<LatLng>.unmodifiable(List<LatLng>.from(pts));
    _remainingRoute = _fullRoute;
    _lastTrimIndex = 0;
    final livePos = _vehiclePos ?? widget.driverLocation;
    if (livePos != null) {
      final snapped = _snapAndBearing(livePos);
      _vehiclePos = snapped.position;
      _vehicleBearing = snapped.bearing;
      _maybeTrimRoute(snapped.position, force: true);
    }
    _maybeStartRouteDraw();
    _rebuildPolylines();
  }

  bool _routeMatchesCurrentMode(List<LatLng> pts) {
    if (pts.length < 2) return true;
    final expected =
        widget.mode == RideMapMode.toDrop ? widget.drop : widget.pickup;
    final other =
        widget.mode == RideMapMode.toDrop ? widget.pickup : widget.drop;
    final toExpected = haversineDistanceMeters(pts.last, expected);
    // Generous absolute tolerance: road-snapping near residential drops (e.g. a
    // colony) can leave the route endpoint 100m+ from the exact pin. The old 90m
    // gate rejected those, so the drop polyline never rendered. Accept if it
    // clearly ends at the expected target...
    if (toExpected <= 220.0) return true;
    // ...or, as a fallback, if the endpoint is nearer the expected target than
    // the other anchor (rejects a stale opposite-phase route).
    final toOther = haversineDistanceMeters(pts.last, other);
    return toExpected < toOther;
  }

  void _requestFitBounds({required String reason, bool force = false}) {
    // Fit bounds only when it matters; never on every driver update.
    // Also don't fight the user: pause after user gestures.
    final now = DateTime.now();
    if (!force && now.isBefore(_pauseFollowUntil)) return;
    if (!force &&
        now.difference(_lastFitAt) < const Duration(milliseconds: 900)) {
      return;
    }

    final key =
        '${widget.mode}|route:$_routeSig|p:${widget.pickup.latitude.toStringAsFixed(5)},${widget.pickup.longitude.toStringAsFixed(5)}|d:${widget.drop.latitude.toStringAsFixed(5)},${widget.drop.longitude.toStringAsFixed(5)}';
    if (!force && key == _lastFitKey) return;

    _lastFitKey = key;
    _pendingFit = true;
    _maybeFitBounds(force: force);
  }

  Future<void> _maybeFitBounds({bool force = false}) async {
    if (!_pendingFit) return;
    if (_mapController == null) return;
    if (!force && DateTime.now().isBefore(_pauseFollowUntil)) return;

    final activeTarget =
        widget.mode == RideMapMode.toDrop ? widget.drop : widget.pickup;
    final extras = <LatLng>[
      if (_vehiclePos != null) _vehiclePos!,
      activeTarget,
    ];

    if (_fullRoute.length < 2 && extras.length < 2) return;

    _pendingFit = false;
    _lastFitAt = DateTime.now();

    final fitPoints =
        _fullRoute.length >= 2 ? <LatLng>[..._fullRoute, ...extras] : extras;
    await _animateBoundsSafe(focusPoints: fitPoints);
  }

  Future<void> _animateBoundsSafe({
    List<LatLng> focusPoints = const <LatLng>[],
  }) async {
    final controller = _mapController;
    if (controller == null) return;
    final pts = focusPoints;
    if (pts.length < 2) return;

    double minLat = pts.first.latitude;
    double maxLat = pts.first.latitude;
    double minLng = pts.first.longitude;
    double maxLng = pts.first.longitude;
    for (final p in pts.skip(1)) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final diag = Geolocator.distanceBetween(minLat, minLng, maxLat, maxLng);
    final target = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    final zoom =
        diag <= 250
            ? 16.8
            : diag <= 700
            ? 16.0
            : diag <= 1500
            ? 15.2
            : diag <= 3000
            ? 14.4
            : diag <= 6000
            ? 13.7
            : 13.0;
    try {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: target, zoom: zoom, bearing: 0, tilt: 0),
        ),
      );
    } catch (_) {}
  }

  String _computeRouteSig(List<LatLng> pts) {
    if (pts.length < 2) return 'len:${pts.length}';
    final idxs =
        <int>{
            0,
            pts.length - 1,
            (pts.length * 1 ~/ 4),
            (pts.length * 2 ~/ 4),
            (pts.length * 3 ~/ 4),
          }.toList()
          ..sort();

    final sb = StringBuffer('len:${pts.length}');
    for (final i in idxs) {
      final p = pts[i.clamp(0, pts.length - 1)];
      sb.write('|');
      sb.write(
        '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}',
      );
    }
    return sb.toString();
  }

  void _rebuildPolylines() {
    _polylines = _composePolylineSet();
    _syncMarkers(force: false);
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Animated map flourishes
  // ---------------------------------------------------------------------------

  /// Route polylines with two flourishes:
  ///  - progressive "draw-in" reveal when a new route appears, and
  ///  - a soft white "energy" comet that flows toward the destination.
  Set<Polyline> _composePolylineSet() {
    final set = <Polyline>{};
    final isPickup = widget.mode == RideMapMode.toPickup;
    final isDrop = widget.mode == RideMapMode.toDrop;
    if (!isPickup && !isDrop) return set;

    final active = _remainingRoute.length >= 2 ? _remainingRoute : _fullRoute;
    if (active.length < 2) return set;

    final drawT = Curves.easeOut.transform(_routeDrawCtrl.value);
    final revealing = drawT < 1.0;
    final drawn = revealing ? _revealPrefix(active, drawT) : active;
    if (drawn.length < 2) return set;

    set.add(
      Polyline(
        polylineId: const PolylineId('active_route'),
        points: drawn,
        color: isPickup ? Colors.grey.shade600 : const Color(0xFF111111),
        width: isPickup ? 4 : 5,
        zIndex: 1,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
        patterns:
            isPickup
                ? <PatternItem>[PatternItem.dash(20), PatternItem.gap(10)]
                : const <PatternItem>[],
      ),
    );

    // Flowing comet — a brand-blue "energy" pulse with a fading tail that runs
    // toward the destination. Only after the draw-in finishes and the line is
    // long enough to look intentional (never on a tiny stub near arrival).
    if (!revealing && drawn.length >= 6) {
      set.addAll(_flowCometPolylines(drawn));
    }
    return set;
  }

  /// Distance-aware radar pulse at the active target + one-shot arrival ripple.
  Set<Circle> _composeCircleSet() {
    final set = <Circle>{};
    final target =
        widget.mode == RideMapMode.toDrop
            ? widget.drop
            : widget.mode == RideMapMode.toPickup
            ? widget.pickup
            : null;

    if (target != null && !_arrivedForCurrentMode()) {
      final t = (math.sin(_pulsePhase) + 1) / 2; // 0..1
      set.add(
        Circle(
          circleId: const CircleId('target_pulse'),
          center: target,
          radius: 18.0 + 42.0 * t,
          fillColor: Colors.black.withValues(alpha: 0.08 * (1 - t)),
          strokeColor: Colors.black.withValues(alpha: 0.30 * (1 - t)),
          strokeWidth: 2,
          zIndex: 0,
        ),
      );
    }

    if (_arrivalCtrl.isAnimating && _arrivalCenter != null) {
      final v = _arrivalCtrl.value;
      final op = (1 - v) * 0.45;
      set.add(
        Circle(
          circleId: const CircleId('arrival_ripple'),
          center: _arrivalCenter!,
          radius: 16.0 + 95.0 * v,
          fillColor: Colors.green.withValues(alpha: op * 0.45),
          strokeColor: Colors.green.withValues(alpha: op),
          strokeWidth: 3,
          zIndex: 1,
        ),
      );
    }
    return set;
  }

  void _onFxTick(Timer _) {
    if (!mounted) return;
    if (widget.mode == RideMapMode.idle) return;

    _flowPhase = (_flowPhase + 0.045) % 1.0;

    // Pulse speeds up as the driver nears the active target ("getting closer").
    double step = 0.16;
    final v = _vehiclePos;
    final target =
        widget.mode == RideMapMode.toDrop ? widget.drop : widget.pickup;
    if (v != null) {
      final gap = haversineDistanceMeters(v, target);
      if (gap < 80) {
        step = 0.42;
      } else if (gap < 200) {
        step = 0.30;
      } else if (gap < 500) {
        step = 0.22;
      }
    }
    _pulsePhase += step;

    _polylines = _composePolylineSet();
    _circles = _composeCircleSet();
    if (mounted) setState(() {});
  }

  void _maybeStartRouteDraw() {
    if (_fullRoute.length < 2) return;
    if (_drawnForMode == widget.mode) return;
    _drawnForMode = widget.mode;
    _routeDrawCtrl
      ..reset()
      ..forward();
  }

  bool _arrivedForCurrentMode() =>
      widget.mode == RideMapMode.toDrop
          ? _celebratedDrop
          : widget.mode == RideMapMode.toPickup
          ? _celebratedPickup
          : false;

  void _maybeCelebrateArrival(LatLng pos) {
    final target =
        widget.mode == RideMapMode.toDrop
            ? widget.drop
            : widget.mode == RideMapMode.toPickup
            ? widget.pickup
            : null;
    if (target == null) return;
    if (haversineDistanceMeters(pos, target) > 28.0) return;
    final isDropArrival = widget.mode == RideMapMode.toDrop;
    if (isDropArrival) {
      if (_celebratedDrop) return;
      _celebratedDrop = true;
    } else {
      if (_celebratedPickup) return;
      _celebratedPickup = true;
    }
    _arrivalCenter = target;
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}
    _arrivalCtrl
      ..reset()
      ..forward();

    // Reaching the destination = trip complete -> celebrate (confetti + banner).
    if (isDropArrival) {
      try {
        HapticFeedback.heavyImpact();
      } catch (_) {}
      _completeCtrl
        ..reset()
        ..forward();
    }
  }

  double _polylineLength(List<LatLng> pts) {
    double total = 0;
    for (int i = 0; i < pts.length - 1; i++) {
      total += haversineDistanceMeters(pts[i], pts[i + 1]);
    }
    return total;
  }

  /// Returns the prefix of [pts] covering fraction [t] of its total length,
  /// with an interpolated tip so the reveal is smooth (not snapping per-vertex).
  List<LatLng> _revealPrefix(List<LatLng> pts, double t) {
    if (t >= 1.0) return pts;
    if (t <= 0.0 || pts.length < 2) return const <LatLng>[];
    final total = _polylineLength(pts);
    if (total <= 0) return pts;
    final targetLen = total * t;
    final out = <LatLng>[pts.first];
    double acc = 0;
    for (int i = 0; i < pts.length - 1; i++) {
      final segLen = haversineDistanceMeters(pts[i], pts[i + 1]);
      if (acc + segLen >= targetLen) {
        final f = segLen <= 0 ? 0.0 : (targetLen - acc) / segLen;
        out.add(
          LatLng(
            pts[i].latitude + (pts[i + 1].latitude - pts[i].latitude) * f,
            pts[i].longitude + (pts[i + 1].longitude - pts[i].longitude) * f,
          ),
        );
        return out;
      }
      out.add(pts[i + 1]);
      acc += segLen;
    }
    return out;
  }

  /// A premium "comet" that flows toward the destination: several graduated
  /// sub-segments in the app's brand blue, fading from a faint tail to a bright,
  /// slightly thicker head — so it reads as light travelling along the route,
  /// not a flat blob. Unique, on-brand, and subtle.
  List<Polyline> _flowCometPolylines(List<LatLng> route) {
    final total = _polylineLength(route);
    if (total < 120) return const <Polyline>[];

    final windowLen = (total * 0.18).clamp(60.0, 260.0);
    final head = total * _flowPhase;
    const segments = 6;
    // Mild white glow over the black route (no blue).
    const brand = Color(0xFFFFFFFF);

    final out = <Polyline>[];
    for (int i = 0; i < segments; i++) {
      final fromLen = head - windowLen * (segments - i) / segments;
      final toLen = head - windowLen * (segments - i - 1) / segments;
      final pts = _subPolylineByLength(
        route,
        fromLen.clamp(0.0, total),
        toLen.clamp(0.0, total),
      );
      if (pts.length < 2) continue;
      final headness = (i + 1) / segments; // 0 (tail) .. 1 (head)
      out.add(
        Polyline(
          polylineId: PolylineId('flow_$i'),
          points: pts,
          color: brand.withValues(alpha: 0.05 + 0.45 * headness),
          width: (3 + 4 * headness).round(),
          zIndex: 2 + i,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      );
    }

    // Soft white head core so the comet reads as a gentle glowing light moving
    // along the black route (mild, not harsh).
    final coreFrom = head - windowLen * 0.30;
    final corePts = _subPolylineByLength(
      route,
      coreFrom.clamp(0.0, total),
      head.clamp(0.0, total),
    );
    if (corePts.length >= 2) {
      out.add(
        Polyline(
          polylineId: const PolylineId('flow_core'),
          points: corePts,
          color: Colors.white.withValues(alpha: 0.55), // mild white head
          width: 3,
          zIndex: 2 + segments + 1,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      );
    }
    return out;
  }

  List<LatLng> _subPolylineByLength(
    List<LatLng> pts,
    double fromLen,
    double toLen,
  ) {
    if (toLen <= fromLen) return const <LatLng>[];
    final out = <LatLng>[];
    double acc = 0;
    for (int i = 0; i < pts.length - 1; i++) {
      final a = pts[i];
      final b = pts[i + 1];
      final segLen = haversineDistanceMeters(a, b);
      final segStart = acc;
      final segEnd = acc + segLen;
      if (segLen > 0 && segEnd >= fromLen && segStart <= toLen) {
        final f0 = ((fromLen - segStart) / segLen).clamp(0.0, 1.0);
        final f1 = ((toLen - segStart) / segLen).clamp(0.0, 1.0);
        final p0 = LatLng(
          a.latitude + (b.latitude - a.latitude) * f0,
          a.longitude + (b.longitude - a.longitude) * f0,
        );
        final p1 = LatLng(
          a.latitude + (b.latitude - a.latitude) * f1,
          a.longitude + (b.longitude - a.longitude) * f1,
        );
        if (out.isEmpty) out.add(p0);
        out.add(p1);
      }
      acc = segEnd;
      if (segStart > toLen) break;
    }
    return out;
  }

  void _syncMarkers({required bool force}) {
    if (!force && _markers.isNotEmpty) {
      // vehicle marker is updated separately; keep static markers.
      return;
    }

    final markers = <Marker>{
      if (widget.mode != RideMapMode.toDrop)
        Marker(
          markerId: const MarkerId('pickup'),
          position: widget.pickup,
          icon: _pickupIcon ?? BitmapDescriptor.defaultMarker,
          anchor: const Offset(0.5, MapUiConfig.pickupDropAnchorY),
          zIndexInt: 1,
          infoWindow: InfoWindow.noText,
        ),
      if (widget.mode == RideMapMode.toDrop)
        Marker(
          markerId: const MarkerId('drop'),
          position: widget.drop,
          icon: _dropIcon ?? BitmapDescriptor.defaultMarker,
          anchor: const Offset(0.5, MapUiConfig.pickupDropAnchorY),
          zIndexInt: 1,
          infoWindow: InfoWindow.noText,
        ),
    };

    // Include the vehicle marker once icons are ready.
    if (_vehiclePos != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('vehicle'),
          position: _vehiclePos!,
          rotation: _bearingWithVehicleIconOffset(_vehicleBearing),
          flat: true,
          anchor: const Offset(0.5, MapUiConfig.vehicleAnchorY),
          icon: _vehIcon ?? BitmapDescriptor.defaultMarker,
          zIndexInt: 2,
          infoWindow: InfoWindow.noText,
        ),
      );
    }

    _markers = markers;
    if (mounted) setState(() {});
  }

  void _queueVehicleMarker(LatLng pos, double bearing) {
    // Avoid rebuilding markers/state for micro-jitter.
    // Ignore <2m moves unless bearing changed meaningfully.
    final last = _vehiclePos;
    if (last != null) {
      final d = haversineDistanceMeters(last, pos);
      final bearingDelta = shortestAngleDelta(_vehicleBearing, bearing).abs();
      // Keep slow / crawling movement visible: only skip true micro-jitter.
      if (d < 0.4 && bearingDelta < 5.0) {
        return;
      }
    }

    _pendingMarkerPos = pos;
    _pendingMarkerBearing = bearing;
    if (_markerFlushTimer != null) return;
    _markerFlushTimer = Timer(_markerMinInterval, () {
      _markerFlushTimer = null;
      _commitVehicleMarker(force: false);
    });
  }

  void _commitVehicleMarker({required bool force}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastMarkerCommitAt) < _markerMinInterval) {
      return;
    }
    _lastMarkerCommitAt = now;

    final pos = _pendingMarkerPos ?? _vehiclePos;
    if (pos == null) return;

    _vehiclePos = pos;
    _vehicleBearing = _pendingMarkerBearing ?? _vehicleBearing;

    final next = <Marker>{};
    for (final m in _markers) {
      if (m.markerId.value != 'vehicle') next.add(m);
    }
    next.add(
      Marker(
        markerId: const MarkerId('vehicle'),
        position: pos,
        rotation: _bearingWithVehicleIconOffset(_vehicleBearing),
        flat: true,
        anchor: const Offset(0.5, MapUiConfig.vehicleAnchorY),
        icon: _vehIcon ?? BitmapDescriptor.defaultMarker,
        zIndexInt: 4,
        infoWindow: InfoWindow.noText,
      ),
    );
    _markers = next;
    if (mounted) setState(() {});
  }

  _SnappedPose _snapAndBearing(
    LatLng raw, {
    double? rawBearing,
    double? toleranceMeters,
  }) {
    // Always snap onto the FULL route in BOTH phases. `_lastTrimIndex` — used
    // as the snap-window base in `_nearestSnapCandidate` — is a `_fullRoute`-
    // space index, so snapping onto the trimmed `_remainingRoute` in drop mode
    // mis-indexed the window (biased the snap forward → visible gap) and took
    // the bearing from the wrong segment (→ car faced the wrong direction).
    // Pickup always used `_fullRoute` and was perfect; drop now matches it.
    final routeForSnap = _fullRoute;
    final fallbackBearing = rawBearing ?? _vehicleBearing;

    if (routeForSnap.length < 2) {
      return _SnappedPose(position: raw, bearing: fallbackBearing);
    }

    final nearest = _nearestSnapCandidate(raw, routeForSnap);
    if (nearest == null) {
      return _SnappedPose(position: raw, bearing: fallbackBearing);
    }

    // If we're too far from the route, don't snap. Snapping aggressively causes
    // "parallel road lock" and makes the vehicle appear to cut across streets.
    if (nearest.distanceMeters >
        (toleranceMeters ?? MapUiConfig.snapToRouteToleranceMeters)) {
      return _SnappedPose(position: raw, bearing: fallbackBearing);
    }

    final nextIdx = (nearest.segmentIndex + 1).clamp(
      0,
      routeForSnap.length - 1,
    );
    final prevIdx = nearest.segmentIndex.clamp(0, routeForSnap.length - 1);
    final prev = routeForSnap[prevIdx];
    final next = routeForSnap[nextIdx];

    final routeBearing = bearingBetween(prev, next);
    final bearingMismatch =
        rawBearing != null
            ? shortestAngleDelta(rawBearing, routeBearing).abs()
            : 0.0;
    if (rawBearing != null &&
        bearingMismatch > 85.0 &&
        nearest.distanceMeters > 4.0) {
      return _SnappedPose(position: raw, bearing: fallbackBearing);
    }

    final snappedMoveFromCurrent =
        _vehiclePos == null
            ? 0.0
            : Geolocator.distanceBetween(
              _vehiclePos!.latitude,
              _vehiclePos!.longitude,
              nearest.point.latitude,
              nearest.point.longitude,
            );
    final rawMoveFromCurrent =
        _vehiclePos == null
            ? 0.0
            : Geolocator.distanceBetween(
              _vehiclePos!.latitude,
              _vehiclePos!.longitude,
              raw.latitude,
              raw.longitude,
            );
    if (nearest.distanceMeters > 6.0 &&
        snappedMoveFromCurrent > rawMoveFromCurrent + 14.0) {
      return _SnappedPose(position: raw, bearing: fallbackBearing);
    }

    // Snap the heading toward the route tangent quickly so the vehicle points
    // where it is actually travelling (prevents the "sliding sideways" look).
    final smooth = smoothBearing(
      currentDeg: fallbackBearing,
      targetDeg: routeBearing,
      alpha: 0.5,
    );

    final resolved = _resolveDisplayPosition(
      raw: raw,
      snapped: nearest.point,
      maxSnapMeters:
          (toleranceMeters ?? MapUiConfig.snapToRouteToleranceMeters),
    );

    return _SnappedPose(position: resolved, bearing: smooth);
  }

  LatLng _resolveDisplayPosition({
    required LatLng raw,
    required LatLng snapped,
    required double maxSnapMeters,
  }) {
    final currentDisplay = _vehiclePos;
    if (currentDisplay == null) return snapped;

    final rawMove = Geolocator.distanceBetween(
      currentDisplay.latitude,
      currentDisplay.longitude,
      raw.latitude,
      raw.longitude,
    );
    final snappedMove = Geolocator.distanceBetween(
      currentDisplay.latitude,
      currentDisplay.longitude,
      snapped.latitude,
      snapped.longitude,
    );
    final rawToSnap = Geolocator.distanceBetween(
      raw.latitude,
      raw.longitude,
      snapped.latitude,
      snapped.longitude,
    );

    final likelySnapFreeze =
        rawMove >= 2.4 &&
        snappedMove < 0.9 &&
        rawToSnap <= maxSnapMeters &&
        rawToSnap >= 1.2;

    if (!likelySnapFreeze) {
      return snapped;
    }

    final alpha = rawToSnap <= 6.0 ? 0.35 : 0.55;
    return LatLng(
      snapped.latitude + (raw.latitude - snapped.latitude) * alpha,
      snapped.longitude + (raw.longitude - snapped.longitude) * alpha,
    );
  }

  NearestPointOnPolylineResult? _nearestSnapCandidate(
    LatLng raw,
    List<LatLng> routeForSnap,
  ) {
    final baseIndex = (_lastTrimIndex < 0 ? 0 : _lastTrimIndex).clamp(
      0,
      routeForSnap.length - 2,
    );
    final start = (baseIndex - 6).clamp(0, routeForSnap.length - 2);
    final end = (baseIndex + 22).clamp(0, routeForSnap.length - 2);

    NearestPointOnPolylineResult? bestWindow;
    final windowPoints = routeForSnap.sublist(start, end + 2);
    final windowNearest = nearestPointOnPolyline(raw, windowPoints);
    if (windowNearest != null) {
      bestWindow = NearestPointOnPolylineResult(
        point: windowNearest.point,
        segmentIndex: windowNearest.segmentIndex + start,
        t: windowNearest.t,
        distanceMeters: windowNearest.distanceMeters,
      );
    }

    final nearestGlobal = nearestPointOnPolyline(raw, routeForSnap);
    if (bestWindow == null) return nearestGlobal;
    if (nearestGlobal == null) return bestWindow;

    final windowIsCloseEnough =
        bestWindow.distanceMeters <=
        MapUiConfig.snapToRouteToleranceMeters + 12.0;
    final globalIsMuchBetter =
        nearestGlobal.distanceMeters + 8.0 < bestWindow.distanceMeters;
    final globalIsForwardEnough = nearestGlobal.segmentIndex + 2 >= baseIndex;

    if (windowIsCloseEnough || !globalIsMuchBetter || !globalIsForwardEnough) {
      return bestWindow;
    }
    return nearestGlobal;
  }

  int? _nearestIndexInWindow(
    LatLng current,
    List<LatLng> points, {
    required int lastIndex,
    int window = 28,
    double maxSnapMeters = 55,
  }) {
    if (points.length < 2) return null;
    final start = (lastIndex - window).clamp(0, points.length - 1);
    final end = (lastIndex + window).clamp(0, points.length - 1);

    int? bestIdx;
    double bestD = double.infinity;

    for (int i = start; i <= end; i++) {
      final p = points[i];
      final d = Geolocator.distanceBetween(
        current.latitude,
        current.longitude,
        p.latitude,
        p.longitude,
      );
      if (d < bestD) {
        bestD = d;
        bestIdx = i;
      }
    }
    if (bestIdx == null) return null;
    if (!bestD.isFinite || bestD > maxSnapMeters) return null;
    return bestIdx;
  }

  void _maybeTrimRoute(LatLng vehiclePos, {bool force = false}) {
    if (_fullRoute.length < 2) return;

    final now = DateTime.now();
    if (!force && now.difference(_lastPolylineTrimAt) < _polyTrimInterval) {
      return;
    }
    _lastPolylineTrimAt = now;

    final idx = _nearestIndexInWindow(
      vehiclePos,
      _fullRoute,
      lastIndex: _lastTrimIndex,
      window: 34,
      maxSnapMeters: MapUiConfig.snapToRouteToleranceMeters + 18.0,
    );
    if (idx == null) return;

    // Don't bounce backwards unless very small (GPS noise).
    if (idx + 2 < _lastTrimIndex) return;
    if ((idx - _lastTrimIndex).abs() < 1) return;

    final maxTrimStart = (_fullRoute.length - 2).clamp(
      0,
      _fullRoute.length - 1,
    );
    final clamped = idx.clamp(0, maxTrimStart);
    if (clamped <= _lastTrimIndex) return;

    _lastTrimIndex = clamped;
    _remainingRoute = List<LatLng>.unmodifiable(_fullRoute.sublist(clamped));

    _rebuildPolylines();
  }

  void _onUserGesture() {
    _pauseFollowUntil = DateTime.now().add(const Duration(seconds: 8));
  }

  void _maybeFollowCamera(LatLng vehiclePos) {
    if (_mapController == null) return;
    if (DateTime.now().isBefore(_pauseFollowUntil)) return;
    if (DateTime.now().difference(_lastCameraAt) <
        MapUiConfig.cameraFollowInterval) {
      return;
    }
    _lastCameraAt = DateTime.now();

    final z =
        widget.mode != RideMapMode.idle
            ? _adaptiveFollowZoom(vehiclePos)
            : CameraUtils.clampZoom(
              _currentZoom,
              min: MapUiConfig.followMinZoom,
              max: MapUiConfig.maxZoom,
            );

    // Center the driver. The bottom-sheet padding already lifts the effective
    // centre above the sheet, so north-up + centred reads clean (no weird
    // "driver stuck at the top" that the heading offset caused in north-up).
    final target = vehiclePos;
    try {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          // North-up: keep the map steady and let only the vehicle icon rotate
          // (clean Uber/Ola customer-tracking feel; avoids the disorienting
          // map spin that made turns look like the car was sliding).
          CameraPosition(target: target, zoom: z, bearing: 0, tilt: 0),
        ),
      );
    } catch (_) {}
  }

  Future<void> recenter() async {
    final pos = _vehiclePos ?? widget.driverLocation;
    if (_mapController == null || pos == null) return;
    _pauseFollowUntil = DateTime.fromMillisecondsSinceEpoch(0);
    // Ensure recenter always feels like a "focus" action (not stuck zoomed out).
    final z =
        widget.mode != RideMapMode.idle
            ? _adaptiveFollowZoom(pos, recenter: true)
            : CameraUtils.clampZoom(
              _currentZoom,
              min: MapUiConfig.followMinZoom,
              max: MapUiConfig.maxZoom,
            );
    final target = pos; // centered (see _maybeFollowCamera)
    try {
      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          // North-up (see _maybeFollowCamera).
          CameraPosition(target: target, zoom: z, bearing: 0, tilt: 0),
        ),
      );
    } catch (_) {}
  }

  Future<void> fitRoute({double padding = 80}) async {
    if (_mapController == null) return;
    try {
      final activeTarget =
          widget.mode == RideMapMode.toDrop ? widget.drop : widget.pickup;
      final extras = <LatLng>[
        if (_vehiclePos != null) _vehiclePos!,
        activeTarget,
      ];
      if (extras.length < 2) {
        await recenter();
        return;
      }
      final fitPoints =
          _fullRoute.length >= 2 ? <LatLng>[..._fullRoute, ...extras] : extras;
      await _animateBoundsSafe(focusPoints: fitPoints);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final initialTarget = widget.driverLocation ?? widget.pickup;

    return Stack(
      children: [
        Listener(
          onPointerDown: (_) => _onUserGesture(),
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: initialTarget,
              zoom: MapUiConfig.initialZoom,
            ),
            padding: widget.mapPadding,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            buildingsEnabled: false,
            indoorViewEnabled: false,
            mapToolbarEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: true,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            minMaxZoomPreference: const MinMaxZoomPreference(
              MapUiConfig.minZoom,
              MapUiConfig.maxZoom,
            ),
            markers: _markers,
            polylines: _polylines,
            circles: _circles,
            onMapCreated: (controller) async {
              _mapController = controller;
              if (_mapStyle != null) {
                try {
                  await controller.setMapStyle(_mapStyle);
                } catch (_) {}
              }
              widget.onMapReady?.call(controller);
              // If we had a route/mode update before map was ready, fit once.
              _maybeFitBounds();
            },
            onCameraMoveStarted: _onUserGesture,
            onTap: (_) => _onUserGesture(),
            onCameraMove: (pos) {
              _currentZoom = CameraUtils.clampZoom(
                pos.zoom,
                min: MapUiConfig.minZoom,
                max: MapUiConfig.maxZoom,
              );
            },
            gestureRecognizers: {
              Factory<OneSequenceGestureRecognizer>(
                () => EagerGestureRecognizer(),
              ),
            },
          ),
        ),
        Positioned(
          top: 102,
          right: 16,
          child: MapEtaDistanceCard(
            etaText: widget.etaText,
            distanceText: widget.distanceText,
            statusText: widget.statusText,
            iconOnlyCollapsed: true,
          ),
        ),

        // Ride-complete celebration: confetti burst + "Trip done" banner.
        // Only repaints while the controller animates (cheap, isolated).
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _completeCtrl,
              builder: (context, _) {
                final v = _completeCtrl.value;
                if (v <= 0.0 || v >= 1.0) return const SizedBox.shrink();
                final appear = Curves.easeOutBack.transform(
                  (v / 0.28).clamp(0.0, 1.0),
                );
                final fade = v > 0.82 ? (1 - (v - 0.82) / 0.18) : 1.0;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _ConfettiPainter(progress: v),
                      ),
                    ),
                    Center(
                      child: Opacity(
                        opacity: fade.clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: 0.85 + 0.15 * appear,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.86),
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Text(
                              'Trip done 🎉',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Lightweight, asset-free confetti for the ride-complete moment. Particles are
/// generated deterministically (no RNG) so it stays cheap and replay-stable.
class _ConfettiPainter extends CustomPainter {
  final double progress;
  _ConfettiPainter({required this.progress});

  static const List<Color> _colors = <Color>[
    Color(0xff357AE9), // brand blue
    Color(0xff3AC267), // green
    Color(0xffE79700), // amber
    Color(0xffFF6B6B), // coral
    Color(0xff5700D0), // purple
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * 0.30);
    const n = 46;
    final t = progress;
    final fade = (1.0 - t).clamp(0.0, 1.0);
    for (int i = 0; i < n; i++) {
      final ang = (i / n) * 2 * math.pi + (i % 5) * 0.21;
      final speed = 70.0 + (i % 7) * 30.0;
      final dx = math.cos(ang) * speed * t;
      final dy = math.sin(ang) * speed * t + 260.0 * t * t; // gravity fall
      final pos = origin + Offset(dx, dy);
      final paint =
          Paint()..color = _colors[i % _colors.length].withValues(alpha: fade);
      final w = 6.0 + (i % 3) * 2.0;
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(ang + t * 7.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: w, height: w * 0.5),
          const Radius.circular(1),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) =>
      old.progress != progress;
}

class _SnappedPose {
  final LatLng position;
  final double bearing;
  const _SnappedPose({required this.position, required this.bearing});
}

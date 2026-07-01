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
import 'package:hopper/uitls/map/customer/map_ui_config.dart';
import 'package:hopper/uitls/map/customer/marker_icon_cache.dart';
import 'package:hopper/uitls/map/tracking_playback_engine.dart';
import 'package:hopper/uitls/map/route_tracking_math.dart';

enum RideMapMode { idle, toPickup, toDrop }

/// Shared-ride active-route styling. Null (single ride) keeps the default look
/// untouched; the shared screen opts in per driver action:
///   - [mine]         → solid brand-blue "your route" (driver headed to you),
///   - [servingOther] → grey dashed "serving another rider" (driver detouring).
enum SharedRouteStyle { mine, servingOther }

class CustomerRideMapView extends StatefulWidget {
  final VehicleType vehicleType;

  /// Live driver location updates (raw). Animations happen in-widget.
  final LatLng? driverLocation;

  /// Server emit time (serverEmittedAt/serverTime) for [driverLocation]. Drives
  /// the playback engine's jitter buffer so bursty packet delivery does not
  /// distort marker timing. Null falls back to client arrival time.
  final DateTime? driverLocationTs;

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

  /// Shared-ride only. Null on single ride → default styling is unchanged.
  final SharedRouteStyle? sharedRouteStyle;

  /// Shared-ride only. When set, a GENERIC marker is drawn where the driver is
  /// heading next for ANOTHER rider (privacy-safe: location + type only). Null
  /// on single ride and whenever the driver's next stop is the customer's own.
  final LatLng? otherStop;
  final bool otherStopIsPickup;

  /// Shared-ride only. The grey "serving another rider" leg (driver → the other
  /// rider's stop). Drawn as a second dashed polyline in ADDITION to the main
  /// blue route (which is then the customer's own leg). Empty on single ride.
  final List<LatLng> otherRoute;

  /// Force the dark map style regardless of time of day (Uber-style shared ride).
  final bool forceDarkMap;

  const CustomerRideMapView({
    super.key,
    required this.vehicleType,
    required this.driverLocation,
    this.driverLocationTs,
    required this.routePoints,
    required this.pickup,
    required this.drop,
    required this.mode,
    required this.etaText,
    required this.distanceText,
    this.statusText,
    this.sharedRouteStyle,
    this.otherStop,
    this.otherStopIsPickup = true,
    this.otherRoute = const <LatLng>[],
    this.forceDarkMap = false,
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

  late final TrackingPlaybackEngine _motion;
  LatLng? _vehiclePos;
  double _vehicleBearing = 0;

  List<LatLng> _fullRoute = const <LatLng>[];
  List<LatLng> _remainingRoute = const <LatLng>[];
  int _lastTrimIndex = 0;
  // Forward-only marker progress along the route (fractional `_fullRoute`
  // index). The displayed marker must never step BACKWARD along the route on
  // GPS jitter (the stop/start "front-and-back" on the drop leg) — only on a
  // genuine reverse. Reset whenever the route/phase changes. Phase-symmetric:
  // the pickup leg already advances monotonically, so this is a no-op there.
  // Tracked purely for route trimming / diagnostics now — it no longer gates or
  // holds the marker (the restructured pipeline never holds; see _snapAndBearing).
  double _markerRouteProgress = -1.0;
  // Throttle for the drop-render diagnostic trace (one line ~per second).
  DateTime? _lastDropRenderLogAt;
  // [LIVETRACK] debug: throttle for the rendered-marker trace (grep "LIVETRACK").
  DateTime? _lastLiveTrackDrawLogAt;
  double? _lastTrimDistanceToTargetMeters;
  int _trimPausedCount = 0;
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
  DateTime _phaseSwitchRawUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _routeSnapSuspendedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  int _consecutiveSnapMisses = 0;

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
  // ignore: unused_element
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
    // Recenter is a "focus" tap — keep it MODERATE (Ola-style): capped so it
    // shows the car + surrounding roads instead of a tight "full zoom".
    if (recenter) return z.clamp(16.4, 16.8);
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

    _motion = TrackingPlaybackEngine(
      vsync: this,
      onUpdate: (pos, bearing) {
        // The render loop already interpolated between two real, time-ordered
        // samples (or dead-reckoned). Render the result directly — no per-frame
        // re-snap (that caused the lateral zig-zag).
        _queueVehicleMarker(pos, bearing);
      },
      onFrameSideEffects: (pos) {
        _maybeTrimRoute(pos);
        _maybeFollowCamera(pos);
        _maybeCelebrateArrival(pos);
      },
      // Jitter buffer: render ~1.5s behind real arrival so late / bursty / out-
      // of-order packets land BEFORE their render time -> no jump, no teleport,
      // no backward step; smooth even when fixes arrive every 2-5s.
      playbackDelay: const Duration(milliseconds: 1500),
      // Coast (dead-reckon) at most this long through a signal gap, then hold.
      maxPredict: const Duration(seconds: 5),
      // A real car cannot spin: cap rotation at 120 deg/s; EMA damps heading.
      maxTurnDegPerSec: 120.0,
      bearingEmaAlpha: 0.30,
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
    if (oldWidget.otherStop != widget.otherStop) {
      // The "another rider" stop appeared / moved / cleared — refresh markers.
      _syncMarkers(force: true);
    }
    if (oldWidget.otherRoute != widget.otherRoute) {
      _rebuildPolylines();
    }
    if (oldWidget.mode != widget.mode) {
      // BUILD FINGERPRINT — confirms the running build includes the drop-leg
      // forward-walker removal. If this line is absent from a drop-phase log,
      // the app was NOT rebuilt with the fix.
      AppLogger.log.w(
        '[drop-phase] mode ${oldWidget.mode} -> ${widget.mode} '
        'build=drop-eq-pickup-v3 routePts=${widget.routePoints.length}',
      );
      _syncRoute(force: true);
      _syncMarkers(force: true);
      _rebuildPolylines();
      _consecutiveSnapMisses = 0;
      // Phase switch is the riskiest moment for customer tracking visuals:
      // the driver has just transitioned from pickup flow to drop flow while the
      // new route may still be fetching or may not yet match the first started
      // packet. For a short warm-up, prefer raw GPS so we do not yank the car
      // back onto the stale pickup leg or an old drop polyline.
      final warmupUntil = DateTime.now().add(
        widget.mode == RideMapMode.toDrop
            ? const Duration(seconds: 4)
            : const Duration(seconds: 2),
      );
      _phaseSwitchRawUntil = warmupUntil;
      _routeSnapSuspendedUntil = warmupUntil;
      _lastTrimDistanceToTargetMeters = null;
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
        _motion.ingest(
          snapped.position,
          bearing: snapped.bearing,
          serverTs: widget.driverLocationTs,
        );
      }
    }
  }

  bool _isNightNow() {
    final h = DateTime.now().hour;
    return h >= 19 || h < 6; // 7pm–6am -> dark theme
  }

  Future<void> _loadMapStyle() async {
    try {
      // forceDarkMap (shared ride) always uses the dark style; otherwise auto
      // day/night: clean light style by day, clean dark style at night.
      final asset =
          (widget.forceDarkMap || _isNightNow())
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
    // New route (or phase switch -> new leg): the `_fullRoute` index space
    // changes, so re-baseline forward-progress. The next accepted fix sets the
    // floor afresh instead of being judged "backward" against the old route.
    _markerRouteProgress = -1.0;
    if (!_routeMatchesCurrentMode(pts)) {
      _fullRoute = const <LatLng>[];
      _remainingRoute = const <LatLng>[];
      _lastTrimIndex = 0;
      _lastTrimDistanceToTargetMeters = null;
      _rebuildPolylines();
      return;
    }
    _fullRoute = List<LatLng>.unmodifiable(List<LatLng>.from(pts));
    _remainingRoute = _fullRoute;
    _lastTrimIndex = 0;
    _lastTrimDistanceToTargetMeters = null;
    // Re-baseline the route trim against the CURRENT rendered marker, but do NOT
    // move the marker here. Its position is owned solely by the playback engine
    // (TrackingPlaybackEngine). Previously this re-snapped and ASSIGNED
    // `_vehiclePos`/`_vehicleBearing` on every ~10s route refetch, which yanked
    // the car to a fresh snap — the "route refresh causes visual glitch". Now a
    // route swap only updates the line; the car keeps gliding from the engine.
    final livePos = _vehiclePos;
    if (livePos != null) {
      _maybeTrimRoute(livePos, force: true);
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

  // True once the FIRST full-route fit has happened. After that the camera just
  // follows the driver; auto-fit never fires again (the rider reframes the full
  // route manually via the fit button). Stops the "auto zoom-in / re-fit" churn.
  bool _didInitialFit = false;

  void _requestFitBounds({required String reason, bool force = false}) {
    // Auto-fit ONLY once (the initial overview). Never auto-refit afterwards —
    // even on mode change (pickup → drop). Manual fitRoute() is unaffected.
    if (_didInitialFit) return;
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

    // On the DROP leg, frame the REMAINING route (vehicle -> drop), not the whole
    // pickup->drop route. The drop route is refreshed periodically (off-route
    // reroute), and each refit to the full route yanked the camera back to the
    // whole-trip extent — so the map "stayed zoomed out" near the drop and the
    // drop point was never clear. _remainingRoute is already trimmed forward as the
    // car advances, so framing it tightens the view automatically on approach.
    // Pickup keeps the full-route fit (it was already correct).
    final routeForFit =
        (widget.mode == RideMapMode.toDrop && _remainingRoute.length >= 2)
            ? _remainingRoute
            : _fullRoute;
    final fitPoints =
        routeForFit.length >= 2 ? <LatLng>[...routeForFit, ...extras] : extras;
    await _animateBoundsSafe(focusPoints: fitPoints);
    // Initial overview done → from now on the camera just follows the driver.
    _didInitialFit = true;
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
            : diag <= 12000
            ? 12.6
            : diag <= 25000
            ? 11.3
            : diag <= 50000
            ? 10.2
            : 9.3;
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

    // Shared-ride "serving another rider" leg: grey dashed, driver → other
    // rider's stop. Drawn independently of the main route / mode.
    final otherLeg = widget.otherRoute;
    if (otherLeg.length >= 2) {
      set.add(
        Polyline(
          polylineId: const PolylineId('other_leg'),
          points: otherLeg,
          color: Colors.grey.shade500,
          width: 5,
          zIndex: 1,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
          patterns: <PatternItem>[PatternItem.dash(20), PatternItem.gap(10)],
        ),
      );
    }

    final isPickup = widget.mode == RideMapMode.toPickup;
    final isDrop = widget.mode == RideMapMode.toDrop;
    if (!isPickup && !isDrop) return set;

    // BOTH legs render the forward-trimmed `_remainingRoute` so the already-
    // travelled portion progressively disappears behind the car (the Uber/Ola
    // route-progress feel). Previously the DROP leg drew the FULL route to dodge
    // an old "route line completes but the car is somewhere else" symptom, but
    // that left the trip leg showing a static, never-shrinking line.
    //
    // Re-enabling the trim on drop is safe now: `_maybeTrimRoute` only advances
    // the trim to a route point within the snap tolerance of the ALREADY
    // route-snapped car (and never recedes), so `_remainingRoute.first` always
    // coincides with the car — it can never be stranded behind a completed line.
    // The car-anchor just below additionally bridges any small residual gap.
    // Falls back to the full route until the first trim lands. The camera fit
    // already uses `_remainingRoute` (with the car in `extras`), unchanged.
    final baseActive =
        _remainingRoute.length >= 2 ? _remainingRoute : _fullRoute;
    if (baseActive.length < 2) return set;

    // Anchor the route to the live car so the polyline always visually emanates
    // from the vehicle (Uber/Ola feel). Bridge only a SMALL gap so an off-route
    // / simulator divergence never draws a long line cutting across the map.
    List<LatLng> active = baseActive;
    final car = _vehiclePos;
    if (car != null) {
      final gap = haversineDistanceMeters(car, baseActive.first);
      if (gap > 1.0 && gap <= 80.0) {
        active = <LatLng>[car, ...baseActive];
      }
    }

    final drawT = Curves.easeOut.transform(_routeDrawCtrl.value);
    final revealing = drawT < 1.0;
    final drawn = revealing ? _revealPrefix(active, drawT) : active;
    if (drawn.length < 2) return set;

    // Active-route style. Single ride (sharedRouteStyle == null) keeps the
    // existing grey/dark dashed look. Shared ride switches to the mockup's two
    // states: solid brand-blue for MY leg, grey dashed while serving another.
    final shared = widget.sharedRouteStyle;
    final Color routeColor;
    final double routeWidth;
    final List<PatternItem> routePatterns;
    switch (shared) {
      case SharedRouteStyle.mine:
        routeColor = const Color(0xFF006FD0); // "your route" — solid blue
        routeWidth = 6;
        routePatterns = const <PatternItem>[];
        break;
      case SharedRouteStyle.servingOther:
        routeColor = Colors.grey.shade600; // "serving another rider" — dashed
        routeWidth = 5;
        routePatterns = <PatternItem>[PatternItem.dash(20), PatternItem.gap(10)];
        break;
      case null:
        routeColor = isPickup ? Colors.grey.shade600 : const Color(0xFF111111);
        routeWidth = isPickup ? 4 : 6;
        routePatterns = <PatternItem>[PatternItem.dash(20), PatternItem.gap(10)];
        break;
    }

    set.add(
      Polyline(
        polylineId: const PolylineId('active_route'),
        points: drawn,
        color: routeColor,
        width: routeWidth.toInt(),
        zIndex: 1,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
        patterns: routePatterns,
      ),
    );

    // Flowing comet — a brand-blue "energy" glow toward the destination. Shown
    // on single ride and on MY shared leg, but suppressed while the driver is
    // serving another rider (grey dashed stays calm — it's not your turn yet).
    if (!revealing &&
        drawn.length >= 6 &&
        shared != SharedRouteStyle.servingOther) {
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
      // Pulse colour matches the pin: drop = green, pickup = black.
      final pulseColor =
          widget.mode == RideMapMode.toDrop
              ? const Color(0xFF15803D)
              : Colors.black;
      set.add(
        Circle(
          circleId: const CircleId('target_pulse'),
          center: target,
          radius: 18.0 + 42.0 * t,
          fillColor: pulseColor.withValues(alpha: 0.10 * (1 - t)),
          strokeColor: pulseColor.withValues(alpha: 0.35 * (1 - t)),
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
      // GENERIC "another rider" stop the driver is heading to first. Privacy-
      // safe: a neutral pin + a generic label, never the other rider's identity.
      if (widget.otherStop != null)
        Marker(
          markerId: const MarkerId('other_stop'),
          position: widget.otherStop!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueViolet,
          ),
          anchor: const Offset(0.5, 1.0),
          zIndexInt: 1,
          infoWindow: InfoWindow(
            title: widget.otherStopIsPickup
                ? 'Pickup stop for another rider'
                : 'Drop stop for another rider',
          ),
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

    // [LIVETRACK] Ground-truth of what the customer actually SEES: the rendered
    // car position. `moveM` is how far the icon moved since the last committed
    // frame; `backward=true` means it moved OPPOSITE to its heading (the
    // front-and-back step). Filter logs with: adb logcat | grep LIVETRACK
    final prevDrawn = kDebugMode ? _vehiclePos : null;
    if (prevDrawn != null) {
      final moveM = haversineDistanceMeters(prevDrawn, pos);
      final moveBrg = bearingBetween(prevDrawn, pos);
      final relToHeading = shortestAngleDelta(_vehicleBearing, moveBrg).abs();
      final backward = moveM > 0.5 && relToHeading > 110.0;
      if (backward ||
          _lastLiveTrackDrawLogAt == null ||
          now.difference(_lastLiveTrackDrawLogAt!) >=
              const Duration(milliseconds: 700)) {
        _lastLiveTrackDrawLogAt = now;
        AppLogger.log.w(
          '[LIVETRACK] draw mode=${widget.mode == RideMapMode.toDrop ? "drop" : "pickup"} '
          'pos=${pos.latitude.toStringAsFixed(6)},${pos.longitude.toStringAsFixed(6)} '
          'moveM=${moveM.toStringAsFixed(1)} backward=$backward '
          'brg=${_vehicleBearing.toStringAsFixed(0)} '
          'routeProg=${_markerRouteProgress.toStringAsFixed(1)}',
        );
      }
    }

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
    final now = DateTime.now();

    // Glue the marker to the route harder during the DROP leg. That route is the
    // actual trip path and the controller keeps it fresh with a frequent
    // off-route reroute (24m / 10s), so a wider snap tolerance keeps the car ON
    // the line instead of darting out to raw GPS — the "slide / front-and-back"
    // jitter — for the normal lane offset + route-simplification error seen on a
    // long drop route. Pickup keeps its tighter tolerance (already perfect).
    final double baseTol =
        toleranceMeters ?? MapUiConfig.snapToRouteToleranceMeters;
    final double effectiveTol =
        widget.mode == RideMapMode.toDrop ? baseTol + 16.0 : baseTol;

    if (widget.mode == RideMapMode.toDrop &&
        now.isBefore(_phaseSwitchRawUntil)) {
      return _SnappedPose(position: raw, bearing: fallbackBearing);
    }

    if (now.isBefore(_routeSnapSuspendedUntil)) {
      return _SnappedPose(position: raw, bearing: fallbackBearing);
    }

    if (routeForSnap.length < 2) {
      return _SnappedPose(position: raw, bearing: fallbackBearing);
    }

    final nearest = _nearestSnapCandidate(raw, routeForSnap);
    if (nearest == null) {
      return _SnappedPose(position: raw, bearing: fallbackBearing);
    }

    // If we're too far from the route, don't snap. Snapping aggressively causes
    // "parallel road lock" and makes the vehicle appear to cut across streets.
    if (nearest.distanceMeters > effectiveTol) {
      _noteSnapMiss(nearest.distanceMeters);
      // DIAGNOSTIC (drop leg, throttled): the marker is being shown at RAW GPS
      // because it is too far from the route to snap. If the drop "dump" is this
      // case, the route doesn't match the road the driver is on (reroute lag).
      if (kDebugMode &&
          widget.mode == RideMapMode.toDrop &&
          (_lastDropRenderLogAt == null ||
              now.difference(_lastDropRenderLogAt!) >=
                  const Duration(seconds: 1))) {
        _lastDropRenderLogAt = now;
        AppLogger.log.w(
          '[drop-render] RAW (off-route) snapDist=${nearest.distanceMeters.toStringAsFixed(1)} '
          'tol=${effectiveTol.toStringAsFixed(0)} misses=$_consecutiveSnapMisses '
          'routePts=${routeForSnap.length}',
        );
      }
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
      _noteSnapMiss(nearest.distanceMeters);
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
      _noteSnapMiss(nearest.distanceMeters);
      return _SnappedPose(position: raw, bearing: fallbackBearing);
    }

    // Render the SNAPPED GPS point itself (cosmetic lane-alignment onto the
    // route), NOT a route-vertex "progress" point.
    //
    // The driver feed arrives clean and monotonically forward (see [LIVETRACK]
    // recv: every step is a sane forward move), so projecting it onto the route
    // (`nearest.point`) follows the driver smoothly and keeps the car ON the line.
    // The previous approach rendered `_pointAtRouteProgress(forwardOnlyFloor)` —
    // a point on the COARSE / periodically-refetched route polyline indexed by a
    // monotonic counter. That counter↔vertex mapping jumped the target around
    // (and the motion engine animated the jumps), producing the 20-120m
    // back-and-forth seen in [LIVETRACK] draw (moveM=121 backward). Rendering the
    // real snapped fix removes that coupling entirely.
    final double candProgress = nearest.segmentIndex + nearest.t;
    if (candProgress > _markerRouteProgress) {
      _markerRouteProgress = candProgress; // tracked for route trimming only
    }
    _consecutiveSnapMisses = 0;

    // Snap the heading toward the route tangent quickly so the vehicle points
    // where it is actually travelling (prevents the "sliding sideways" look).
    final smooth = smoothBearing(
      currentDeg: fallbackBearing,
      targetDeg: routeBearing,
      alpha: 0.5,
    );

    final resolved = nearest.point;

    // [LIVETRACK] snap trace (both legs, throttled ~1/s). Shows how the raw GPS
    // was projected onto the route: `snapDist` = raw distance to the route,
    // `rawToRendered` = how far the rendered point is from raw, `cand` vs `floor`
    // = candidate vs forward-only progress (if cand<floor the raw projection
    // regressed and was clamped — the back-jitter source). grep LIVETRACK.
    if (kDebugMode &&
        (_lastDropRenderLogAt == null ||
            now.difference(_lastDropRenderLogAt!) >= const Duration(seconds: 1))) {
      _lastDropRenderLogAt = now;
      final rawToSnap = Geolocator.distanceBetween(
        raw.latitude,
        raw.longitude,
        resolved.latitude,
        resolved.longitude,
      );
      AppLogger.log.w(
        '[LIVETRACK] snap mode=${widget.mode == RideMapMode.toDrop ? "drop" : "pickup"} '
        'snapDist=${nearest.distanceMeters.toStringAsFixed(1)} '
        'rawToRendered=${rawToSnap.toStringAsFixed(1)} '
        'cand=${candProgress.toStringAsFixed(1)} '
        'floor=${_markerRouteProgress.toStringAsFixed(1)} tol=${effectiveTol.toStringAsFixed(0)}',
      );
    }

    return _SnappedPose(position: resolved, bearing: smooth);
  }

  void _noteSnapMiss(double distanceMeters) {
    _consecutiveSnapMisses++;
    // Alternate-route protection ONLY. This used to suspend snapping for 6-10s
    // after just TWO misses — so during the DROP leg every normal lane offset /
    // route-simplification gap dropped the marker onto raw GPS for seconds at a
    // time, which is exactly the "slide / shake / front-and-back" the customer
    // reported (the pickup leg never reaches this path, which is why pickup looks
    // perfect). Now we only stop snapping when the driver is CLEARLY on a
    // different road (far off) for MANY consecutive fixes, and only briefly; the
    // controller's off-route reroute then refreshes the line and snapping
    // resumes. Normal offsets stay glued to the route via the wider drop
    // tolerance in `_snapAndBearing`.
    if (widget.mode != RideMapMode.toDrop) return;
    if (_consecutiveSnapMisses < 5) return;
    if (distanceMeters <= MapUiConfig.snapToRouteToleranceMeters + 60.0) return;
    _routeSnapSuspendedUntil = DateTime.now().add(const Duration(seconds: 3));
    _consecutiveSnapMisses = 0;
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

    final nearest = _nearestSnapCandidate(vehiclePos, _fullRoute);
    if (nearest == null) return;
    if (nearest.distanceMeters >
        MapUiConfig.snapToRouteToleranceMeters + 18.0) {
      return;
    }
    final idx = nearest.segmentIndex + (nearest.t >= 0.60 ? 1 : 0);

    // Don't bounce backwards unless very small (GPS noise).
    if (idx + 2 < _lastTrimIndex) return;
    if ((idx - _lastTrimIndex).abs() < 1) return;

    final activeTarget =
        widget.mode == RideMapMode.toDrop ? widget.drop : widget.pickup;
    final currentGapToTarget = haversineDistanceMeters(vehiclePos, activeTarget);
    final previousGapToTarget = _lastTrimDistanceToTargetMeters;
    if (!force &&
        previousGapToTarget != null &&
        currentGapToTarget > previousGapToTarget + 26.0) {
      _trimPausedCount += 1;
      if (kDebugMode) {
        AppLogger.log.d(
          'ride map trim paused trim_paused_count=$_trimPausedCount '
          'current_gap_m=${currentGapToTarget.toStringAsFixed(1)} '
          'previous_gap_m=${previousGapToTarget.toStringAsFixed(1)}',
        );
      }
      return;
    }

    final maxTrimStart = (_fullRoute.length - 2).clamp(
      0,
      _fullRoute.length - 1,
    );
    final clamped = idx.clamp(0, maxTrimStart);
    if (clamped <= _lastTrimIndex) return;

    _lastTrimIndex = clamped;
    _lastTrimDistanceToTargetMeters = currentGapToTarget;
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

    // Steady focus on the driver at a fixed zoom — no adaptive zoom churn. The
    // rider reframes the whole route only via the fit button.
    final z =
        widget.mode != RideMapMode.idle
            ? 16.0
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
    // Resume following the driver (cancels a paused/full-route state).
    _pauseFollowUntil = DateTime.fromMillisecondsSinceEpoch(0);
    // Focus the driver at a fixed zoom 16 (not a tight "full zoom").
    final z =
        widget.mode != RideMapMode.idle
            ? 16.0
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
    // Manual "full route" view: pause driver-follow until the user recenters, so
    // the next location packet can't snap the camera back off the full route.
    _pauseFollowUntil = DateTime.now().add(const Duration(hours: 24));
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
      // Drop leg frames the remaining route (vehicle -> drop) so it tightens on
      // approach; pickup keeps the full-route fit. See _maybeFitBounds.
      final routeForFit =
          (widget.mode == RideMapMode.toDrop && _remainingRoute.length >= 2)
              ? _remainingRoute
              : _fullRoute;
      final fitPoints =
          routeForFit.length >= 2 ? <LatLng>[...routeForFit, ...extras] : extras;
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
        // (Removed) on-map ETA "clock" card + lat/lng debug readout — the ETA is
        // already shown in the bottom-sheet status card, and the coordinate pill
        // was debug-only clutter.

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

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
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
    with SingleTickerProviderStateMixin {
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
  static const Duration _markerMinInterval = Duration(milliseconds: 90);

  DateTime _lastPolylineTrimAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _polyTrimInterval = Duration(milliseconds: 260);

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
      },
      // Debounce raw GPS packets (ignore <5m moves).
      minMoveMeters: 5.0,
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
      _requestFitBounds(reason: 'route_changed');
    }

    if (oldWidget.pickup != widget.pickup || oldWidget.drop != widget.drop) {
      _syncMarkers(force: true);
      _requestFitBounds(reason: 'pickup_drop_changed');
    }
    if (oldWidget.mode != widget.mode) {
      _syncRoute(force: true);
      _syncMarkers(force: true);
      _rebuildPolylines();
      _requestFitBounds(reason: 'mode_changed');
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

  Future<void> _loadMapStyle() async {
    try {
      _mapStyle = await rootBundle.loadString('assets/map_style.json');
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
    _rebuildPolylines();
  }

  bool _routeMatchesCurrentMode(List<LatLng> pts) {
    if (pts.length < 2) return true;
    final expectedDestination =
        widget.mode == RideMapMode.toDrop ? widget.drop : widget.pickup;
    final endDistance = haversineDistanceMeters(pts.last, expectedDestination);
    return endDistance <= 90.0;
  }

  void _requestFitBounds({required String reason}) {
    // Fit bounds only when it matters; never on every driver update.
    // Also don't fight the user: pause after user gestures.
    final now = DateTime.now();
    if (now.isBefore(_pauseFollowUntil)) return;
    if (now.difference(_lastFitAt) < const Duration(milliseconds: 900)) return;

    final key =
        '${widget.mode}|route:$_routeSig|p:${widget.pickup.latitude.toStringAsFixed(5)},${widget.pickup.longitude.toStringAsFixed(5)}|d:${widget.drop.latitude.toStringAsFixed(5)},${widget.drop.longitude.toStringAsFixed(5)}';
    if (key == _lastFitKey) return;

    _lastFitKey = key;
    _pendingFit = true;
    _maybeFitBounds();
  }

  Future<void> _maybeFitBounds() async {
    if (!_pendingFit) return;
    if (_mapController == null) return;
    if (DateTime.now().isBefore(_pauseFollowUntil)) return;

    final extras = <LatLng>[
      if (_vehiclePos != null) _vehiclePos!,
      widget.pickup,
      if (widget.mode == RideMapMode.toDrop) widget.drop,
    ];

    if (_fullRoute.length < 2 && extras.length < 2) return;

    _pendingFit = false;
    _lastFitAt = DateTime.now();

    final bounds = boundsFromRoutePoints(_fullRoute, extraPoints: extras);
    final padding = 80.0;
    try {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, padding),
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
    final set = <Polyline>{};

    // Two-phase polyline system (Uber/Ola-like).
    // Phase 1: driver -> pickup (grey dashed).
    // Phase 2: pickup -> drop (blue solid), and we trim as driver advances
    // by updating `_remainingRoute`.
    if (widget.mode == RideMapMode.toPickup) {
      final pts = _remainingRoute.length >= 2 ? _remainingRoute : _fullRoute;
      if (pts.length >= 2) {
        set.add(
          Polyline(
            polylineId: const PolylineId('active_route'),
            points: pts,
            color: Colors.grey.shade600,
            width: 4,
            zIndex: 1,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            jointType: JointType.round,
            patterns: <PatternItem>[PatternItem.dash(20), PatternItem.gap(10)],
          ),
        );
      }
    } else if (widget.mode == RideMapMode.toDrop) {
      final remaining =
          _remainingRoute.length >= 2 ? _remainingRoute : _fullRoute;
      if (remaining.length >= 2) {
        set.add(
          Polyline(
            polylineId: const PolylineId('active_route'),
            points: remaining,
            color: const Color(0xFF000000),
            width: 5,
            zIndex: 1,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            jointType: JointType.round,
          ),
        );
      }
    }

    _polylines = set;
    _syncMarkers(force: false);
    if (mounted) setState(() {});
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
      // Keep slow movement smooth: allow sub-2m updates (traffic/crawling).
      if (d < 0.8 && bearingDelta < 6.0) {
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
    final routeForSnap =
        widget.mode == RideMapMode.toDrop && _remainingRoute.length >= 2
            ? _remainingRoute
            : _fullRoute;
    final fallbackBearing = rawBearing ?? _vehicleBearing;

    if (routeForSnap.length < 2) {
      return _SnappedPose(position: raw, bearing: fallbackBearing);
    }

    final nearest = nearestPointOnPolyline(raw, routeForSnap);
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
    final smooth = smoothBearing(
      currentDeg: fallbackBearing,
      targetDeg: routeBearing,
      alpha: 0.22,
    );

    return _SnappedPose(position: nearest.point, bearing: smooth);
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
            ? 17.0
            : CameraUtils.clampZoom(
              _currentZoom,
              min: MapUiConfig.followMinZoom,
              max: MapUiConfig.maxZoom,
            );

    final isActiveRide = widget.mode != RideMapMode.idle;

    final target = vehiclePos;
    try {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: target,
            zoom: z,
            bearing: isActiveRide ? _vehicleBearing : 0,
            tilt: isActiveRide ? 30.0 : 0,
          ),
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
            ? 17.0
            : CameraUtils.clampZoom(
              _currentZoom,
              min: MapUiConfig.followMinZoom,
              max: MapUiConfig.maxZoom,
            );
    try {
      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: pos,
            zoom: z,
            bearing: widget.mode != RideMapMode.idle ? _vehicleBearing : 0,
            tilt: widget.mode != RideMapMode.idle ? 30.0 : 0,
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> fitRoute({double padding = 80}) async {
    if (_mapController == null) return;
    try {
      // Prefer fitting the actual route polyline so the entire leg is visible.
      // Fallback to marker points if route isn't ready yet.
      final extras = <LatLng>[
        if (_vehiclePos != null) _vehiclePos!,
        widget.pickup,
        widget.drop,
      ];
      final hasRoute = _fullRoute.length >= 2;
      final bounds =
          hasRoute
              ? boundsFromRoutePoints(_fullRoute, extraPoints: extras)
              : CameraUtils.boundsFromPoints(extras);
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, padding),
      );
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
      ],
    );
  }
}

class _SnappedPose {
  final LatLng position;
  final double bearing;
  const _SnappedPose({required this.position, required this.bearing});
}

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/uitls/map/compact_marker_icons.dart';
import 'package:hopper/uitls/map/drop_pulse.dart';
import 'package:hopper/uitls/map/driver_motion_engine.dart';
import 'package:hopper/uitls/map/map_ui_defaults.dart';

enum RideType { single, shared }

enum VehicleType { car, bike }

class RideTrackingMap extends StatefulWidget {
  final RideType rideType;
  final VehicleType vehicleType;

  /// Raw (server) driver location updates. Movement smoothing happens inside
  /// this widget (via [DriverMotionEngine]).
  final LatLng? currentLocation;

  /// Full route points (decoded polyline from Directions API).
  final List<LatLng> routePoints;

  final LatLng pickupLocation;
  final LatLng destinationLocation;

  final ValueChanged<GoogleMapController>? onMapReady;

  /// Optional: when true, the camera follows the moving vehicle.
  final bool followVehicle;

  /// Optional padding for map (useful when bottom sheet overlays the map).
  final EdgeInsets mapPadding;

  const RideTrackingMap({
    super.key,
    required this.rideType,
    required this.vehicleType,
    required this.currentLocation,
    required this.routePoints,
    required this.pickupLocation,
    required this.destinationLocation,
    this.onMapReady,
    this.followVehicle = true,
    this.mapPadding = EdgeInsets.zero,
  });

  @override
  RideTrackingMapState createState() => RideTrackingMapState();
}

class RideTrackingMapState extends State<RideTrackingMap>
    with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;
  String? _mapStyle;

  late final DriverMotionEngine _motion;
  LatLng? _displayVehiclePos;
  double _displayBearing = 0.0;

  BitmapDescriptor? _vehicleIcon;
  BitmapDescriptor? _pickupIcon;
  BitmapDescriptor? _dropIcon;

  Set<Marker> _markers = const <Marker>{};
  Set<Polyline> _polylines = const <Polyline>{};
  Set<Circle> _circles = const <Circle>{};

  // Pulsing ripple under the drop/destination pin.
  late final DropPulse _dropPulse = DropPulse(
    onUpdate: (circles) {
      _circles = circles;
      if (mounted) setState(() {});
    },
  );

  List<LatLng> _fullRoute = const <LatLng>[];
  List<LatLng> _remainingRoute = const <LatLng>[];
  int _lastTrimIndex = 0;

  Timer? _driverMarkerFlushTimer;
  LatLng? _pendingMarkerPos;
  double? _pendingMarkerBearing;
  DateTime _lastMarkerCommitAt = DateTime.fromMillisecondsSinceEpoch(0);
  // The motion engine interpolates at ~30fps (its _minUpdateInterval = 33ms).
  // This widget throttle was 70ms (~14fps), DOWNSAMPLING that smooth glide to a
  // visible stutter. Set just under the engine's frame interval so every engine
  // frame is rendered (no aliasing) → the marker moves at the full ~30fps the
  // engine produces. build() is light (GoogleMap diffs only the moved marker),
  // so the extra commits are cheap. If a very low-end device janks, raise toward
  // ~45ms; do not go back above the engine's 33ms or stutter returns.
  static const Duration _markerMinInterval = Duration(milliseconds: 30);

  DateTime _lastPolylineTrimAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _polyTrimInterval = Duration(milliseconds: 180);

  DateTime _lastCameraAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _cameraInterval = Duration(milliseconds: 900);
  static const double _followZoom = 17.0;
  static const double _minFollowZoom = 17.0;

  DateTime _pauseAutoFollowUntil = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _userGesturePause = Duration(seconds: 5);

  double _bearingWithVehicleIconOffset(double bearing) {
    final offset =
        widget.vehicleType == VehicleType.bike
            ? MapUiDefaults.bikeBearingIconOffsetDeg
            : MapUiDefaults.carBearingIconOffsetDeg;
    return MapUiDefaults.normalizeBearing(bearing + offset);
  }

  @override
  void initState() {
    super.initState();

    _motion = DriverMotionEngine(
      vsync: this,
      onUpdate: (pos, bearing) {
        _queueVehicleMarkerUpdate(pos, bearing);
      },
      onFrameSideEffects: (pos) {
        _maybeTrimRoute(pos);
        _maybeFollowCamera(pos);
      },
      // Buffer ~0.8 of a packet interval against the driver's steady ~1s feed:
      // a small constant lag bought for near-zero stutter (Uber/Ola do the same).
      playbackDelay: const Duration(milliseconds: 800),
      // Clamp each segment to ~the real packet cadence so the marker keeps
      // gliding until the next packet lands instead of racing then freezing.
      minSeg: const Duration(milliseconds: 700),
      maxSeg: const Duration(milliseconds: 1500),
      minMoveMeters: 1.5,
      requireBearingForDeadReckoning: true,
      // > the 1s feed with margin: a single missed packet coasts smoothly, but
      // we stop projecting once the gap is clearly too large. Widened 2.5s→4.5s
      // to coast through the driver's foreground→background socket handoff when
      // they enter Google Maps navigation (that gap was freezing the marker then
      // jumping). The steady 1s feed is unaffected — packets always land first;
      // this only extends coasting during genuine multi-second gaps.
      maxDeadReckonPacketGap: const Duration(milliseconds: 4500),
      stationarySpeedThresholdMps: 0.35,
      stationaryIgnoreUnderMeters: 1.8,
    );

    _loadMapStyle();
    _loadIcons();

    _syncRouteFromWidget(force: true);
    _syncStaticMarkers(force: true);

    final initPos = widget.currentLocation ?? widget.pickupLocation;
    _motion.reset(initPos, bearing: 0.0);
    _displayVehiclePos = initPos;

    _dropPulse.start(widget.destinationLocation);
  }

  @override
  void dispose() {
    _driverMarkerFlushTimer?.cancel();
    _dropPulse.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant RideTrackingMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.vehicleType != widget.vehicleType) {
      _loadIcons();
    }

    if (!listEquals(oldWidget.routePoints, widget.routePoints)) {
      _syncRouteFromWidget(force: true);
    }

    if (oldWidget.pickupLocation != widget.pickupLocation ||
        oldWidget.destinationLocation != widget.destinationLocation) {
      _syncStaticMarkers(force: true);
      _syncRouteFromWidget(force: false);
      _dropPulse.moveTo(widget.destinationLocation);
    }

    if (widget.currentLocation != null &&
        oldWidget.currentLocation != widget.currentLocation) {
      _motion.ingest(widget.currentLocation!);
    }
  }

  Future<void> _loadMapStyle() async {
    try {
      final style = await rootBundle.loadString('assets/map_style.json');
      _mapStyle = style;
      if (_mapController != null) {
        await _mapController!.setMapStyle(_mapStyle);
      }
    } catch (_) {
      // ignore styling errors
    }
  }

  Future<void> _loadIcons() async {
    final dpr = ui.window.devicePixelRatio;
    try {
      _vehicleIcon = await CompactMarkerIcons.assetContained(
        assetPath:
            widget.vehicleType == VehicleType.bike
                ? AppImages.bikeImage
                : AppImages.carHop,
        sizeDp: MapUiDefaults.vehicleBadgeDiameterDp,
        dpr: dpr,
      );
    } catch (_) {
      _vehicleIcon = BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueAzure,
      );
    }

    try {
      // Labeled pin (white bubble + black pin) so pickup is clearly marked.
      _pickupIcon = await CompactMarkerIcons.labeledPin(
        label: 'Pickup',
        assetPath: AppImages.pin,
        tint: const Color(0xFF000000),
        bubbleWidthDp: 92,
        bubbleHeightDp: 38,
        pinWidthDp: MapUiDefaults.pickupDropPinWidthDp,
        fontSizeDp: 12,
        textAlign: TextAlign.center,
        dpr: dpr,
      );
    } catch (_) {
      _pickupIcon = BitmapDescriptor.defaultMarkerWithHue(
        MapUiDefaults.pickupDropMarkerHueGreen,
      );
    }

    try {
      // Labeled pin (white bubble + green pin) so drop is clearly marked.
      _dropIcon = await CompactMarkerIcons.labeledPin(
        label: 'Drop',
        assetPath: AppImages.pin,
        tint: const Color(0xFF15803D),
        bubbleWidthDp: 92,
        bubbleHeightDp: 38,
        pinWidthDp: MapUiDefaults.pickupDropPinWidthDp,
        fontSizeDp: 12,
        textAlign: TextAlign.center,
        dpr: dpr,
      );
    } catch (_) {
      _dropIcon = BitmapDescriptor.defaultMarkerWithHue(
        MapUiDefaults.pickupDropMarkerHueGreen,
      );
    }

    _syncStaticMarkers(force: true);
    _commitVehicleMarker(force: true);
  }

  void _syncRouteFromWidget({required bool force}) {
    final next = widget.routePoints;
    if (!force && listEquals(_fullRoute, next)) return;

    _fullRoute = List<LatLng>.unmodifiable(next);
    _remainingRoute = _fullRoute;
    _lastTrimIndex = 0;

    _polylines = MapUiDefaults.routePolylines(_remainingRoute, id: 'route');
    if (mounted) setState(() {});
  }

  void _syncStaticMarkers({required bool force}) {
    if (!force && _markers.isNotEmpty) return;

    final vehicle = _displayVehiclePos;
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('pickup'),
        position: widget.pickupLocation,
        icon: _pickupIcon ?? BitmapDescriptor.defaultMarker,
        anchor: const Offset(0.5, 1.0),
      ),
      Marker(
        markerId: const MarkerId('drop'),
        position: widget.destinationLocation,
        icon: _dropIcon ?? BitmapDescriptor.defaultMarker,
        anchor: const Offset(0.5, 1.0),
      ),
      if (vehicle != null)
        Marker(
          markerId: const MarkerId('vehicle'),
          position: vehicle,
          rotation: _bearingWithVehicleIconOffset(_displayBearing),
          anchor: const Offset(0.5, 0.5),
          flat: true,
          icon: _vehicleIcon ?? BitmapDescriptor.defaultMarker,
        ),
    };

    _markers = markers;
    if (mounted) setState(() {});
  }

  void _queueVehicleMarkerUpdate(LatLng pos, double bearing) {
    _pendingMarkerPos = pos;
    _pendingMarkerBearing = bearing;

    if (_driverMarkerFlushTimer != null) return;

    _driverMarkerFlushTimer = Timer(_markerMinInterval, () {
      _driverMarkerFlushTimer = null;
      _commitVehicleMarker(force: false);
    });
  }

  void _commitVehicleMarker({required bool force}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastMarkerCommitAt) < _markerMinInterval) {
      return;
    }
    _lastMarkerCommitAt = now;

    final pos = _pendingMarkerPos ?? _displayVehiclePos;
    if (pos == null) return;

    _displayVehiclePos = pos;
    _displayBearing = _pendingMarkerBearing ?? _displayBearing;

    final next = <Marker>{};
    for (final m in _markers) {
      if (m.markerId.value != 'vehicle') next.add(m);
    }
    next.add(
      Marker(
        markerId: const MarkerId('vehicle'),
        position: pos,
        rotation: _bearingWithVehicleIconOffset(_displayBearing),
        anchor: const Offset(0.5, 0.5),
        flat: true,
        icon: _vehicleIcon ?? BitmapDescriptor.defaultMarker,
      ),
    );
    _markers = next;
    if (mounted) setState(() {});
  }

  void _maybeTrimRoute(LatLng vehiclePos) {
    final now = DateTime.now();
    if (now.difference(_lastPolylineTrimAt) < _polyTrimInterval) return;
    _lastPolylineTrimAt = now;

    if (_fullRoute.length < 2) return;
    if (_remainingRoute.length < 2) return;

    final idx = _nearestRouteIndex(
      points: _fullRoute,
      fromIndex: _lastTrimIndex,
      current: vehiclePos,
      maxLookahead: 40,
      maxSnapMeters: 28.0,
    );

    if (idx == null) return;
    if (idx <= _lastTrimIndex) return;

    _lastTrimIndex = idx;
    _remainingRoute = _fullRoute.sublist(idx);
    _polylines = MapUiDefaults.routePolylines(_remainingRoute, id: 'route');
    if (mounted) setState(() {});
  }

  int? _nearestRouteIndex({
    required List<LatLng> points,
    required int fromIndex,
    required LatLng current,
    required int maxLookahead,
    required double maxSnapMeters,
  }) {
    if (points.length < 2) return null;
    final start = fromIndex.clamp(0, points.length - 1);
    final end = (start + maxLookahead).clamp(0, points.length - 1);

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

  void _maybeFollowCamera(LatLng vehiclePos) {
    if (!widget.followVehicle) return;
    if (_mapController == null) return;

    // pause if user recently dragged/zoomed
    if (DateTime.now().isBefore(_pauseAutoFollowUntil)) return;

    final now = DateTime.now();
    if (now.difference(_lastCameraAt) < _cameraInterval) return;
    _lastCameraAt = now;

    // Active ride tracking: keep navigation zoom at 17.0.
    final zoom = _followZoom;

    try {
      // Navigation mode (Uber-like): camera rotates to travel direction.
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: vehiclePos,
            zoom: zoom,
            bearing: _displayBearing,
            tilt: 30.0,
          ),
        ),
      );
    } catch (_) {}
  }

  double _currentZoom = _followZoom;

  void _onUserMapGesture() {
    _pauseAutoFollowUntil = DateTime.now().add(_userGesturePause);
  }

  /// Public: recentre camera immediately on the vehicle (if available).
  Future<void> recenterOnVehicle() async {
    _pauseAutoFollowUntil = DateTime.fromMillisecondsSinceEpoch(0);
    final pos = _displayVehiclePos ?? widget.currentLocation;
    if (_mapController == null || pos == null) return;
    try {
      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: pos,
            zoom: _followZoom,
            bearing: _displayBearing,
            tilt: 30.0,
          ),
        ),
      );
    } catch (_) {}
  }

  /// Public: fit bounds around (vehicle, pickup, drop) using a safe padding.
  Future<void> fitRouteBounds({double padding = 80}) async {
    if (_mapController == null) return;
    final pts = <LatLng>[
      if (_displayVehiclePos != null) _displayVehiclePos!,
      widget.pickupLocation,
      widget.destinationLocation,
    ];
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

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    try {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, padding),
      );
    } catch (_) {
      await Future.delayed(const Duration(milliseconds: 280));
      try {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, padding),
        );
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final initialTarget = widget.currentLocation ?? widget.pickupLocation;

    return Listener(
      onPointerDown: (_) => _onUserMapGesture(),
      child: GoogleMap(
        compassEnabled: true,
        rotateGesturesEnabled: false,
        tiltGesturesEnabled: false,
        myLocationEnabled: false,
        buildingsEnabled: false,
        indoorViewEnabled: false,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        mapToolbarEnabled: false,
        padding: widget.mapPadding,
        onCameraMoveStarted: _onUserMapGesture,
        onTap: (_) => _onUserMapGesture(),
        onCameraMove: (pos) {
          _currentZoom =
              pos.zoom
                  .clamp(MapUiDefaults.minZoom, MapUiDefaults.maxZoom)
                  .toDouble();
        },
        initialCameraPosition: CameraPosition(
          target: initialTarget,
          zoom: _followZoom,
          bearing: 0,
          tilt: 0,
        ),
        markers: _markers,
        polylines: _polylines,
        circles: _circles,
        minMaxZoomPreference: const MinMaxZoomPreference(
          MapUiDefaults.minZoom,
          MapUiDefaults.maxZoom,
        ),
        onMapCreated: (controller) async {
          _mapController = controller;
          if (_mapStyle != null) {
            try {
              await controller.setMapStyle(_mapStyle);
            } catch (_) {}
          }
          widget.onMapReady?.call(controller);
        },
        gestureRecognizers: {
          Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
        },
      ),
    );
  }
}

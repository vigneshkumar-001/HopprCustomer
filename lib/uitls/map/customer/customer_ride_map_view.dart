import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:hopper/uitls/map/customer/camera_utils.dart';
import 'package:hopper/uitls/map/customer/map_eta_distance_card.dart';
import 'package:hopper/uitls/map/customer/map_ui_config.dart';
import 'package:hopper/uitls/map/customer/marker_icon_cache.dart';
import 'package:hopper/uitls/map/customer/polyline_trim_utils.dart';
import 'package:hopper/uitls/map/driver_motion_engine.dart';

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
    this.mapPadding = const EdgeInsets.only(bottom: MapUiConfig.defaultBottomPadding),
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
  List<LatLng> _completedRoute = const <LatLng>[];
  int _trimIndex = 0;

  Set<Polyline> _polylines = const <Polyline>{};
  Set<Marker> _markers = const <Marker>{};

  DateTime _lastTrimAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _trimInterval = Duration(milliseconds: 240);

  DateTime _lastCameraAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _pauseFollowUntil = DateTime.fromMillisecondsSinceEpoch(0);

  double _currentZoom = MapUiConfig.initialZoom;

  Timer? _markerFlushTimer;
  LatLng? _pendingMarkerPos;
  double? _pendingMarkerBearing;
  DateTime _lastMarkerCommitAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _markerMinInterval = Duration(milliseconds: 120);

  @override
  void initState() {
    super.initState();

    _motion = DriverMotionEngine(
      vsync: this,
      onUpdate: (pos, bearing) => _queueVehicleMarker(pos, bearing),
      onFrameSideEffects: (pos) {
        _maybeTrimPolyline(pos);
        _maybeFollowCamera(pos);
      },
    );

    _loadMapStyle();
    _loadIcons();
    _syncRoute(force: true);

    final initPos = widget.driverLocation ?? widget.pickup;
    _motion.reset(initPos, bearing: 0);
    _vehiclePos = initPos;
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
    }

    if (oldWidget.pickup != widget.pickup || oldWidget.drop != widget.drop) {
      _syncMarkers(force: true);
    }
    if (oldWidget.mode != widget.mode) {
      _syncMarkers(force: true);
    }

    if (widget.driverLocation != null &&
        oldWidget.driverLocation != widget.driverLocation) {
      _motion.ingest(widget.driverLocation!);
    }
  }

  Future<void> _loadMapStyle() async {
    try {
      _mapStyle = await rootBundle.loadString(
        'assets/map_style/map_style_ride_clean.json',
      );
      if (_mapController != null) {
        await _mapController!.setMapStyle(_mapStyle);
      }
    } catch (_) {}
  }

  Future<void> _loadIcons() async {
    final dpr = ui.window.devicePixelRatio;
    try {
      _vehIcon = await MarkerIconCache.vehicleIcon(widget.vehicleType, dpr: dpr);
    } catch (e) {
      AppLogger.log.w('vehicle icon load failed: $e');
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
    _fullRoute = List<LatLng>.unmodifiable(List<LatLng>.from(pts));
    _trimIndex = 0;
    _completedRoute = const <LatLng>[];
    _remainingRoute = _fullRoute;
    _rebuildPolylines();
  }

  String _computeRouteSig(List<LatLng> pts) {
    if (pts.length < 2) return 'len:${pts.length}';
    final a = pts.first;
    final b = pts.last;
    return 'len:${pts.length}|a:${a.latitude.toStringAsFixed(6)},${a.longitude.toStringAsFixed(6)}|b:${b.latitude.toStringAsFixed(6)},${b.longitude.toStringAsFixed(6)}';
  }

  void _rebuildPolylines() {
    final set = <Polyline>{};

    if (_completedRoute.length > 1) {
      set.add(
        Polyline(
          polylineId: const PolylineId('route_completed'),
          points: _completedRoute,
          color: MapUiConfig.completedPolylineColor,
          width: MapUiConfig.polylineWidth,
          zIndex: MapUiConfig.completedPolylineZ,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      );
    }

    if (_remainingRoute.length > 1) {
      // Outline for better visibility on light/dark map styles.
      set.add(
        Polyline(
          polylineId: const PolylineId('route_remaining_outline'),
          points: _remainingRoute,
          color: MapUiConfig.polylineOutlineColor,
          width: MapUiConfig.polylineOutlineWidth,
          zIndex: MapUiConfig.activePolylineZ,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      );
      set.add(
        Polyline(
          polylineId: const PolylineId('route_remaining'),
          points: _remainingRoute,
          color: MapUiConfig.activePolylineColor,
          width: MapUiConfig.polylineWidth,
          zIndex: MapUiConfig.activePolylineZ + 1,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      );
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
          zIndex: 3,
          infoWindow: InfoWindow.noText,
        ),
      if (widget.mode != RideMapMode.toPickup)
        Marker(
          markerId: const MarkerId('drop'),
          position: widget.drop,
          icon: _dropIcon ?? BitmapDescriptor.defaultMarker,
          anchor: const Offset(0.5, MapUiConfig.pickupDropAnchorY),
          zIndex: 3,
          infoWindow: InfoWindow.noText,
        ),
    };

    // Include the vehicle marker once icons are ready.
    if (_vehiclePos != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('vehicle'),
          position: _vehiclePos!,
          rotation: _vehicleBearing,
          flat: true,
          anchor: const Offset(0.5, MapUiConfig.vehicleAnchorY),
          icon: _vehIcon ?? BitmapDescriptor.defaultMarker,
          zIndex: 4,
          infoWindow: InfoWindow.noText,
        ),
      );
    }

    _markers = markers;
    if (mounted) setState(() {});
  }

  void _queueVehicleMarker(LatLng pos, double bearing) {
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
        rotation: _vehicleBearing,
        flat: true,
        anchor: const Offset(0.5, MapUiConfig.vehicleAnchorY),
        icon: _vehIcon ?? BitmapDescriptor.defaultMarker,
          zIndex: 4,
        infoWindow: InfoWindow.noText,
      ),
    );
    _markers = next;
    if (mounted) setState(() {});
  }

  void _maybeTrimPolyline(LatLng vehiclePos) {
    if (_fullRoute.length < 2) return;
    if (DateTime.now().difference(_lastTrimAt) < _trimInterval) return;
    _lastTrimAt = DateTime.now();

    final res = PolylineTrimUtils.trim(
      full: _fullRoute,
      lastIndex: _trimIndex,
      current: vehiclePos,
      maxLookahead: 55,
      maxSnapMeters: 32,
    );
    if (res == null) return;

    _trimIndex = res.index;
    _completedRoute = res.completed;
    _remainingRoute = res.remaining;
    _rebuildPolylines();
  }

  void _onUserGesture() {
    _pauseFollowUntil = DateTime.now().add(const Duration(seconds: 5));
  }

  void _maybeFollowCamera(LatLng vehiclePos) {
    if (_mapController == null) return;
    if (DateTime.now().isBefore(_pauseFollowUntil)) return;
    if (DateTime.now().difference(_lastCameraAt) < MapUiConfig.cameraFollowInterval) return;
    _lastCameraAt = DateTime.now();

    final z = CameraUtils.clampZoom(
      _currentZoom,
      min: MapUiConfig.followMinZoom,
      max: MapUiConfig.maxZoom,
    );
    try {
      _mapController!.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: vehiclePos, zoom: z, bearing: 0, tilt: 0),
        ),
      );
    } catch (_) {}
  }

  Future<void> recenter() async {
    final pos = _vehiclePos ?? widget.driverLocation;
    if (_mapController == null || pos == null) return;
    _pauseFollowUntil = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: pos, zoom: _currentZoom, bearing: 0, tilt: 0),
        ),
      );
    } catch (_) {}
  }

  Future<void> fitRoute({double padding = 120}) async {
    if (_mapController == null) return;
    final pts = <LatLng>[
      if (_vehiclePos != null) _vehiclePos!,
      widget.pickup,
      widget.drop,
    ];
    if (pts.length < 2) return;
    try {
      final bounds = CameraUtils.boundsFromPoints(pts);
      await _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, padding));
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
              Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
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
  String _routeSig = '';

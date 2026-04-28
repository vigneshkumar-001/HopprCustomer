import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class SharedMap extends StatefulWidget {
  final LatLng initialPosition;
  final LatLng? pickupPosition; // pulsing point
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final Set<Circle> circles;
  final bool myLocationEnabled;
  final bool fitToBounds;
  final double initialZoom;
  final MinMaxZoomPreference minMaxZoomPreference;
  final bool compassEnabled;
  final bool rotateGesturesEnabled;
  final bool tiltGesturesEnabled;
  final Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers;
  final ValueChanged<CameraPosition>? onCameraMove;
  final VoidCallback? onCameraMoveStarted;
  final VoidCallback? onCameraIdle;
  final ValueChanged<LatLng>? onTap;
  final EdgeInsets padding;
  final MapType mapType;

  const SharedMap({
    super.key,
    required this.initialPosition,
    this.pickupPosition,
    this.markers = const <Marker>{},
    this.polylines = const <Polyline>{},
    this.circles = const <Circle>{},
    this.myLocationEnabled = true,
    this.fitToBounds = true,
    this.initialZoom = 14.9,
    this.minMaxZoomPreference = const MinMaxZoomPreference(11.0, 17.0),
    this.compassEnabled = true,
    this.rotateGesturesEnabled = false,
    this.tiltGesturesEnabled = false,
    this.gestureRecognizers = const <Factory<OneSequenceGestureRecognizer>>{},
    this.onCameraMove,
    this.onCameraMoveStarted,
    this.onCameraIdle,
    this.onTap,
    this.padding = EdgeInsets.zero,
    this.mapType = MapType.normal,
  });

  @override
  SharedMapState createState() => SharedMapState(); // 👈 PUBLIC
}

class SharedMapState extends State<SharedMap>
    with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;
  late AnimationController _pulseController;
  bool _cameraInitialized = false;
  String? _mapStyle;
  DateTime _lastFitAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPulseRebuildAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const double _tinyBoundsThresholdMeters = 260.0;
  static const double _tinyBoundsCapZoom = 16.4;
  static const Duration _pulseRebuildMinInterval = Duration(milliseconds: 140);

  double _haversineMeters(LatLng a, LatLng b) {
    const r = 6371000.0; // meters
    final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
    final dLng = (b.longitude - a.longitude) * math.pi / 180.0;
    final lat1 = a.latitude * math.pi / 180.0;
    final lat2 = b.latitude * math.pi / 180.0;

    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.min(1.0, math.sqrt(h)));
  }

  bool _isTinyBounds(LatLngBounds b) {
    final d = _haversineMeters(b.southwest, b.northeast);
    return d.isFinite && d < _tinyBoundsThresholdMeters;
  }

  double _safeZoomForTinyBounds() {
    final maxZ = widget.minMaxZoomPreference.maxZoom ?? 21.0;
    final minZ = widget.minMaxZoomPreference.minZoom ?? 3.0;
    final z = math.min(maxZ, _tinyBoundsCapZoom);
    return math.max(minZ, z);
  }

  @override
  void initState() {
    super.initState();

    _loadMapStyle();

    _pulseController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..addListener(() {
            if (widget.pickupPosition == null) return;
            final now = DateTime.now();
            if (now.difference(_lastPulseRebuildAt) <
                _pulseRebuildMinInterval) {
              return;
            }
            _lastPulseRebuildAt = now;
            if (mounted) setState(() {});
          })
          ..stop();

    if (widget.pickupPosition != null) {
      _pulseController.repeat();
    }
  }

  Future<void> _loadMapStyle() async {
    try {
      final style = await rootBundle.loadString(
        'assets/map_style/map_style_uber_like.json',
      );
      _mapStyle = style;
      if (_mapController != null) {
        _mapController!.setMapStyle(_mapStyle);
      }
    } catch (_) {
      // ignore styling errors
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SharedMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Start/stop pulse ticker to avoid wasting battery when not needed.
    final hadPickup = oldWidget.pickupPosition != null;
    final hasPickup = widget.pickupPosition != null;
    if (hadPickup != hasPickup) {
      if (!hasPickup && _pulseController.isAnimating) {
        _pulseController.stop();
      } else if (hasPickup && !_pulseController.isAnimating) {
        _pulseController.repeat();
      }
    }

    if (!widget.fitToBounds) return;
    if (_mapController == null) return;

    // Refit only when pickup/drop markers change (ignore driver marker churn)
    final oldPickup = _markerPosition(oldWidget.markers, 'pickup');
    final oldDrop = _markerPosition(oldWidget.markers, 'drop');
    final newPickup = _markerPosition(widget.markers, 'pickup');
    final newDrop = _markerPosition(widget.markers, 'drop');

    if (newPickup != null &&
        newDrop != null &&
        (oldPickup == null ||
            oldDrop == null ||
            oldPickup != newPickup ||
            oldDrop != newDrop)) {
      final now = DateTime.now();
      if (now.difference(_lastFitAt) >= const Duration(milliseconds: 600)) {
        _lastFitAt = now;
        fitPointsBounds(<LatLng>[newPickup, newDrop], padding: 150);
      }
    }
  }

  LatLng? _markerPosition(Set<Marker> set, String id) {
    for (final m in set) {
      if (m.markerId.value == id) return m.position;
    }
    return null;
  }

  Future<void> _safeMoveToBounds(LatLngBounds b, {double padding = 130}) async {
    if (_mapController == null) return;

    if (_isTinyBounds(b)) {
      final mid = LatLng(
        (b.northeast.latitude + b.southwest.latitude) / 2,
        (b.northeast.longitude + b.southwest.longitude) / 2,
      );
      try {
        await _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: mid, zoom: _safeZoomForTinyBounds()),
          ),
        );
      } catch (_) {}
      return;
    }
    try {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(b, padding),
      );
    } catch (_) {
      await Future.delayed(const Duration(milliseconds: 300));
      try {
        await _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(b, padding),
        );
      } catch (_) {
        final mid = LatLng(
          (b.northeast.latitude + b.southwest.latitude) / 2,
          (b.northeast.longitude + b.southwest.longitude) / 2,
        );
        _mapController!.moveCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: mid, zoom: 13.8),
          ),
        );
      }
    }
  }

  Future<void> animateTo({
    required LatLng target,
    double? zoom,
    double bearing = 0,
    double tilt = 0,
  }) async {
    if (_mapController == null) return;
    try {
      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: target,
            zoom: zoom ?? widget.initialZoom,
            bearing: bearing,
            tilt: tilt,
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> fitPointsBounds(
    List<LatLng> points, {
    double padding = 130,
  }) async {
    if (_mapController == null) return;
    if (points.length < 2) return;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points.skip(1)) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    await _safeMoveToBounds(bounds, padding: padding);
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;

    if (_mapStyle != null) {
      _mapController!.setMapStyle(_mapStyle);
    }

    if (!_cameraInitialized) {
      _cameraInitialized = true;

      if (widget.fitToBounds && widget.markers.length >= 2) {
        final pickup = _markerPosition(widget.markers, 'pickup');
        final drop = _markerPosition(widget.markers, 'drop');
        if (pickup != null && drop != null) {
          fitPointsBounds(<LatLng>[pickup, drop], padding: 150);
        } else {
          final bounds = _boundsFromMarkers(widget.markers);
          _safeMoveToBounds(bounds, padding: 150);
        }
      } else {
        _mapController!.moveCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: widget.initialPosition,
              zoom: widget.initialZoom,
            ),
          ),
        );
      }
    }
  }

  Future<void> fitPolylineBounds(
    List<LatLng> pts, {
    double padding = 80,
  }) async {
    if (_mapController == null) return;
    if (pts.length < 2) return;

    double minLat = pts.first.latitude;
    double maxLat = pts.first.latitude;
    double minLng = pts.first.longitude;
    double maxLng = pts.first.longitude;

    for (final p in pts) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    await _safeMoveToBounds(bounds, padding: padding);
  }

  LatLngBounds _boundsFromMarkers(Set<Marker> markers) {
    final list = markers.toList();

    double minLat = list.first.position.latitude;
    double maxLat = list.first.position.latitude;
    double minLng = list.first.position.longitude;
    double maxLng = list.first.position.longitude;

    for (final m in list) {
      if (m.position.latitude < minLat) minLat = m.position.latitude;
      if (m.position.latitude > maxLat) maxLat = m.position.latitude;
      if (m.position.longitude < minLng) minLng = m.position.longitude;
      if (m.position.longitude > maxLng) maxLng = m.position.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  Set<Circle> _buildPickupCircles() {
    if (widget.pickupPosition == null) return const <Circle>{};

    final t = _pulseController.value; // 0 → 1
    const double baseRadius = 25;
    final double animRadius = baseRadius + 25 * t;

    return {
      Circle(
        circleId: const CircleId('pickup_inner'),
        center: widget.pickupPosition!,
        radius: baseRadius,
        fillColor: Colors.green.withOpacity(0.25),
        strokeColor: Colors.green.withOpacity(0.7),
        strokeWidth: 2,
      ),
      Circle(
        circleId: const CircleId('pickup_pulse'),
        center: widget.pickupPosition!,
        radius: animRadius,
        fillColor: Colors.green.withOpacity(0.08 * (1 - t)),
        strokeColor: Colors.green.withOpacity(0.6 * (1 - t)),
        strokeWidth: 2,
      ),
    };
  }

  // 🔹 PUBLIC: focus camera on pickup
  Future<void> focusPickup() async {
    if (_mapController == null || widget.pickupPosition == null) return;
    await _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: widget.pickupPosition!,
          zoom: _safeZoomForTinyBounds(),
        ),
      ),
    );
  }

  // 🔹 PUBLIC: fit to all markers (route bounds)
  Future<void> fitRouteBounds() async {
    if (_mapController == null || widget.markers.length < 2) return;
    final bounds = _boundsFromMarkers(widget.markers);
    await _safeMoveToBounds(bounds, padding: 150);
  }

  @override
  Widget build(BuildContext context) {
    final mergedCircles = <Circle>{
      ...widget.circles,
      ..._buildPickupCircles(),
    };

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: widget.initialPosition,
        zoom: widget.initialZoom,
      ),
      onMapCreated: _onMapCreated,
      markers: widget.markers,
      polylines: widget.polylines,
      circles: mergedCircles,
      myLocationEnabled: widget.myLocationEnabled,
      buildingsEnabled: false,
      indoorViewEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      compassEnabled: widget.compassEnabled,
      rotateGesturesEnabled: widget.rotateGesturesEnabled,
      tiltGesturesEnabled: widget.tiltGesturesEnabled,
      mapToolbarEnabled: false,
      trafficEnabled: false,
      minMaxZoomPreference: widget.minMaxZoomPreference,
      gestureRecognizers: widget.gestureRecognizers,
      onCameraMove: widget.onCameraMove,
      onCameraMoveStarted: widget.onCameraMoveStarted,
      onCameraIdle: widget.onCameraIdle,
      onTap: widget.onTap,
      padding: widget.padding,
      mapType: widget.mapType,
    );
  }
}

//
// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
//
// class SharedMap extends StatefulWidget {
//   final LatLng initialPosition;
//   final Set<Marker> markers;
//   final Set<Polyline> polylines;
//   final bool myLocationEnabled;
//   final void Function(GoogleMapController)? onMapCreated;
//
//   /// If true, camera will auto-zoom to fit all markers when they change
//   final bool fitToBounds;
//
//   const SharedMap({
//     super.key,
//     required this.initialPosition,
//     this.markers = const <Marker>{},
//     this.polylines = const <Polyline>{},
//     this.myLocationEnabled = true,
//     this.onMapCreated,
//     this.fitToBounds = true,
//   });
//
//   @override
//   State<SharedMap> createState() => _SharedMapState();
// }
//
// class _SharedMapState extends State<SharedMap>
//     with SingleTickerProviderStateMixin {
//   GoogleMapController? _controller;
//   final Completer<GoogleMapController> _controllerCompleter = Completer();
//   GoogleMapController? _mapController;
//   late AnimationController _pulseController;
//   bool _cameraInitialized = false;
//   String? _mapStyle;
//   @override
//   void initState() {
//     super.initState();
//     // 🔹 Load custom style once
//     _loadMapStyle();
//     // 🔹 Light pulse: slower + smooth
//     _pulseController =
//         AnimationController(vsync: this, duration: const Duration(seconds: 2))
//           ..addListener(() {
//             // Only rebuild circles, but this rebuild is cheap
//             if (mounted) setState(() {});
//           })
//           ..repeat();
//   }
//
//   @override
//   void dispose() {
//     _controller?.dispose();
//     super.dispose();
//   }
//
//   @override
//   void didUpdateWidget(covariant SharedMap oldWidget) {
//     super.didUpdateWidget(oldWidget);
//
//     if (widget.fitToBounds &&
//         _controller != null &&
//         widget.markers.isNotEmpty &&
//         widget.markers != oldWidget.markers) {
//       _animateToBounds();
//     }
//   }
//
//   Future<void> _loadMapStyle() async {
//     try {
//       final style = await rootBundle.loadString(
//         'assets/map_style/map_style1.json',
//       );
//       setState(() {
//         _mapStyle = style;
//       });
//       if (_mapController != null) {
//         _mapController!.setMapStyle(_mapStyle);
//       }
//     } catch (_) {
//       // ignore styling errors
//     }
//   }
//
//   Future<void> _animateToBounds() async {
//     if (_controller == null || widget.markers.isEmpty) return;
//
//     final latitudes = widget.markers.map((m) => m.position.latitude).toList();
//     final longitudes = widget.markers.map((m) => m.position.longitude).toList();
//
//     final southWest = LatLng(
//       latitudes.reduce((a, b) => a < b ? a : b),
//       longitudes.reduce((a, b) => a < b ? a : b),
//     );
//     final northEast = LatLng(
//       latitudes.reduce((a, b) => a > b ? a : b),
//       longitudes.reduce((a, b) => a > b ? a : b),
//     );
//
//     final bounds = LatLngBounds(southwest: southWest, northeast: northEast);
//
//     try {
//       await _controller!.animateCamera(
//         CameraUpdate.newLatLngBounds(bounds, 70),
//       );
//     } catch (_) {
//       // On some devices bounds not ready immediately – small delay works around it
//       await Future.delayed(const Duration(milliseconds: 300));
//       await _controller!.animateCamera(
//         CameraUpdate.newLatLngBounds(bounds, 70),
//       );
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return GoogleMap(
//       initialCameraPosition: CameraPosition(
//         target: widget.initialPosition,
//         zoom: 14,
//       ),
//       myLocationEnabled: widget.myLocationEnabled,
//       myLocationButtonEnabled: false,
//       compassEnabled: false,
//       zoomControlsEnabled: false,
//       markers: widget.markers,
//       polylines: widget.polylines,
//       onMapCreated: (controller) async {
//         _controller = controller;
//         if (!_controllerCompleter.isCompleted) {
//           _controllerCompleter.complete(controller);
//         }
//         widget.onMapCreated?.call(controller);
//
//         // First time: fit to bounds if we have markers
//         if (widget.fitToBounds && widget.markers.isNotEmpty) {
//           await _animateToBounds();
//         }
//       },
//     );
//   }
// }

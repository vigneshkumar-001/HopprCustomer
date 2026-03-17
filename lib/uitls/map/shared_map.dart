import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class SharedMap extends StatefulWidget {
  final LatLng initialPosition;
  final LatLng? pickupPosition; // pulsing point
  final Set<Marker> markers;
  final Set<Polyline> polylines;
  final bool myLocationEnabled;
  final bool fitToBounds;

  const SharedMap({
    super.key,
    required this.initialPosition,
    this.pickupPosition,
    this.markers = const <Marker>{},
    this.polylines = const <Polyline>{},
    this.myLocationEnabled = true,
    this.fitToBounds = true,
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

  @override
  void initState() {
    super.initState();

    _loadMapStyle();

    _pulseController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..addListener(() {
            if (mounted) setState(() {});
          })
          ..repeat();
  }

  Future<void> _loadMapStyle() async {
    try {
      final style = await rootBundle.loadString(
        'assets/map_style/map_style1.json',
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

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;

    if (_mapStyle != null) {
      _mapController!.setMapStyle(_mapStyle);
    }

    if (!_cameraInitialized) {
      _cameraInitialized = true;

      if (widget.fitToBounds && widget.markers.length >= 2) {
        final bounds = _boundsFromMarkers(widget.markers);
        _mapController!.moveCamera(CameraUpdate.newLatLngBounds(bounds, 60));
      } else {
        _mapController!.moveCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: widget.initialPosition, zoom: 15),
          ),
        );
      }
    }
  }
  Future<void> fitPolylineBounds(List<LatLng> pts, {double padding = 80}) async {
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

    await _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, padding),
    );
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
        CameraPosition(target: widget.pickupPosition!, zoom: 17),
      ),
    );
  }

  // 🔹 PUBLIC: fit to all markers (route bounds)
  Future<void> fitRouteBounds() async {
    if (_mapController == null || widget.markers.length < 2) return;
    final bounds = _boundsFromMarkers(widget.markers);
    await _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 60),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: widget.initialPosition,
        zoom: 15,
      ),
      onMapCreated: _onMapCreated,
      markers: widget.markers,
      polylines: widget.polylines,
      circles: _buildPickupCircles(),
      myLocationEnabled: widget.myLocationEnabled,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      compassEnabled: false,
      tiltGesturesEnabled: false,
      mapToolbarEnabled: false,
      trafficEnabled: false,
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

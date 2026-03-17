import 'dart:async';
import 'dart:math' show atan2, cos, pi, sin, sqrt;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class CarMovementAnimator {
  final GoogleMapController mapController;
  final BitmapDescriptor carIcon;

  Marker? _driverMarker;
  LatLng? _lastPosition;

  CarMovementAnimator({
    required this.mapController,
    required this.carIcon,
  });

  /// Haversine distance (in meters)
  double calculateDistance(LatLng from, LatLng to) {
    const R = 6371000; // radius of Earth in meters
    final dLat = _degToRad(to.latitude - from.latitude);
    final dLon = _degToRad(to.longitude - from.longitude);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(from.latitude)) *
            cos(_degToRad(to.latitude)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  /// Bearing between two points (for car rotation)
  double calculateBearing(LatLng from, LatLng to) {
    final dLon = _degToRad(to.longitude - from.longitude);
    final y = sin(dLon) * cos(_degToRad(to.latitude));
    final x = cos(_degToRad(from.latitude)) * sin(_degToRad(to.latitude)) -
        sin(_degToRad(from.latitude)) *
            cos(_degToRad(to.latitude)) *
            cos(dLon);

    final brng = atan2(y, x);
    return (_radToDeg(brng) + 360) % 360;
  }

  /// Animate smooth car movement
  Future<void> animateCar(LatLng newPosition,
      {Duration duration = const Duration(seconds: 2)}) async {
    if (_lastPosition == null) {
      _lastPosition = newPosition;
      _updateMarker(newPosition, 0);
      return;
    }

    final oldPosition = _lastPosition!;
    final bearing = calculateBearing(oldPosition, newPosition);

    final latTween = Tween<double>(
      begin: oldPosition.latitude,
      end: newPosition.latitude,
    );
    final lngTween = Tween<double>(
      begin: oldPosition.longitude,
      end: newPosition.longitude,
    );

    final controller = AnimationController(
      duration: duration,
      vsync: NavigatorState(), // ⚠️ You’ll pass your TickerProvider
    );

    final animation = CurvedAnimation(
      parent: controller,
      curve: Curves.linear,
    );

    controller.addListener(() {
      final lat = latTween.evaluate(animation);
      final lng = lngTween.evaluate(animation);

      _updateMarker(LatLng(lat, lng), bearing);
    });

    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _lastPosition = newPosition;
        controller.dispose();
      }
    });

    controller.forward();
  }

  /// Update marker on map
  void _updateMarker(LatLng position, double bearing) {
    _driverMarker = Marker(
      markerId: const MarkerId("driver_marker"),
      position: position,
      rotation: bearing,
      icon: carIcon,
      flat: true,
      anchor: const Offset(0.5, 0.5),
    );

    // mapController.updateMarker(_driverMarker!);
  }

  /// Polyline between two points
  Polyline getPolyline(String id, List<LatLng> points) {
    return Polyline(
      polylineId: PolylineId(id),
      points: points,
      color: Colors.blue,
      width: 5,
    );
  }

  double _degToRad(double deg) => deg * (pi / 180);
  double _radToDeg(double rad) => rad * (180 / pi);
}

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapAnimator {
  GoogleMapController? _mapController;
  Marker? _driverMarker;
  Set<Marker> markers = {};
  Set<Polyline> polylines = {};
  double zoom = 16.0;
  bool autoFollow = true;

  BitmapDescriptor? carIcon;

  MapAnimator({this.carIcon});

  void attachController(GoogleMapController controller) {
    _mapController = controller;
  }

  void updateDriverMarker(LatLng position, double bearing) {
    final marker = Marker(
      markerId: const MarkerId("driver_marker"),
      position: position,
      rotation: bearing,
      flat: true,
      anchor: const Offset(0.5, 0.5),
      icon: carIcon ?? BitmapDescriptor.defaultMarker,
    );

    markers.removeWhere((m) => m.markerId.value == "driver_marker");
    markers.add(marker);
    _driverMarker = marker;
  }

  Future<void> animateDriver(LatLng from, LatLng to) async {
    if (_mapController == null) return;

    const steps = 50;
    const durationMs = 1200;
    final stepMs = (durationMs / steps).round();
    double currentBearing = _driverMarker?.rotation ?? 0;

    for (int i = 1; i <= steps; i++) {
      await Future.delayed(Duration(milliseconds: stepMs));
      final t = i / steps;
      final lat = _lerp(from.latitude, to.latitude, t);
      final lng = _lerp(from.longitude, to.longitude, t);
      final newPos = LatLng(lat, lng);
      final bearing = _lerpAngle(currentBearing, _getBearing(from, to), t);

      updateDriverMarker(newPos, bearing);

      if (autoFollow && i % 10 == 0) {
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: newPos,
              zoom: zoom,
              bearing: bearing,
              tilt: 45,
            ),
          ),
        );
      }
    }
  }

  void drawPolyline(LatLng from, LatLng to) {
    polylines = {
      Polyline(
        polylineId: const PolylineId("route"),
        points: [from, to],
        width: 4,
        color: Colors.blue,
      ),
    };
  }

  double _lerp(double start, double end, double t) => start + (end - start) * t;

  double _lerpAngle(double start, double end, double t) {
    double diff = end - start;
    while (diff < -180) diff += 360;
    while (diff > 180) diff -= 360;
    return start + diff * t;
  }

  double _getBearing(LatLng start, LatLng end) {
    final lat1 = start.latitude * math.pi / 180;
    final lon1 = start.longitude * math.pi / 180;
    final lat2 = end.latitude * math.pi / 180;
    final lon2 = end.longitude * math.pi / 180;

    final y = math.sin(lon2 - lon1) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(lon2 - lon1);

    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }
}

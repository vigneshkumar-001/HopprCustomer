import 'package:flutter/material.dart';

class MapUiConfig {
  // Polyline
  static const Color activePolylineColor = Colors.black;
  static const Color completedPolylineColor = Color(0xFF9CA3AF); // grey
  static const int polylineWidth = 6;
  static const int polylineOutlineWidth = 10;
  static const Color polylineOutlineColor = Color(0xFFFFFFFF);
  static const int activePolylineZ = 1;
  static const int completedPolylineZ = 0;

  // Camera
  // Active ride screens: never allow zoom <14 or >18.
  static const double initialZoom = 17.0;
  static const double minZoom = 14.0;
  static const double maxZoom = 18.0;
  static const double followMinZoom = 17.0;
  static const Duration cameraFollowInterval = Duration(milliseconds: 900);

  // Marker sizing (logical px / dp)
  // Keep the badge diameter consistent across vehicle types so car/bike
  // never looks "big/small" between screens.
  static const double carMarkerSizeDp = 48;
  static const double bikeMarkerSizeDp = 48;

  static const double pickupDropPinWidthDp = 26;

  // Anchors
  static const double pickupDropAnchorY = 1.0;
  static const double vehicleAnchorY = 0.5;

  // Map padding (sheet)
  static const double defaultBottomPadding = 210;

  // Snap / trim
  // Keep this reasonably tight to avoid "parallel road lock" where the marker
  // sticks to the route even after the driver moved to the next street.
  static const double snapToRouteToleranceMeters = 24.0;

  // =============================================================
  // Vehicle icon bearing offsets
  // =============================================================
  //
  // `google_maps_flutter` marker rotation expects degrees clockwise from NORTH.
  // For correct facing direction, your vehicle PNG should be drawn pointing UP.
  //
  // If your asset points RIGHT (east), use `-90`.
  // If your asset points DOWN (south), use `180`.
  // If your asset points LEFT (west), use `90`.
  static const double carBearingIconOffsetDeg = 0.0;
  static const double bikeBearingIconOffsetDeg = 0.0;

  static double normalizeBearing(double deg) {
    final v = deg % 360.0;
    return (v + 360.0) % 360.0;
  }
}

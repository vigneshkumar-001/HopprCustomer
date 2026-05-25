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
  static const double initialZoom = 16.6;
  static const double minZoom = 12.0;
  static const double maxZoom = 18.0;
  static const double followMinZoom = 15.8;
  static const Duration cameraFollowInterval = Duration(milliseconds: 900);

  // Marker sizing (logical px / dp)
  static const double carMarkerSizeDp = 48;
  static const double bikeMarkerSizeDp = 44;

  static const double pickupDropPinWidthDp = 26;

  // Anchors
  static const double pickupDropAnchorY = 1.0;
  static const double vehicleAnchorY = 0.5;

  // Map padding (sheet)
  static const double defaultBottomPadding = 210;
}


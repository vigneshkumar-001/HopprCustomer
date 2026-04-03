import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapUiDefaults {
  static const double pickupDropMarkerHueGreen = BitmapDescriptor.hueGreen;
  static const double pickupDropMarkerHueRed = BitmapDescriptor.hueRed;

  static const double focusZoom = 17.0;
  static const double minZoom = 11.0;
  static const double maxZoom = 17.0;

  static const int polylineWidth = 3;

  static LatLngBounds boundsFrom2(LatLng a, LatLng b) {
    double minLat = math.min(a.latitude, b.latitude);
    double maxLat = math.max(a.latitude, b.latitude);
    double minLng = math.min(a.longitude, b.longitude);
    double maxLng = math.max(a.longitude, b.longitude);

    const minDelta = 0.009;
    if ((maxLat - minLat) < minDelta) {
      minLat -= minDelta;
      maxLat += minDelta;
    }
    if ((maxLng - minLng) < minDelta) {
      minLng -= minDelta;
      maxLng += minDelta;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }
}

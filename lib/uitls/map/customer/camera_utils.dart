import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

class CameraUtils {
  static double clampZoom(double zoom, {required double min, required double max}) {
    if (!zoom.isFinite) return min;
    return zoom.clamp(min, max).toDouble();
  }

  static LatLngBounds boundsFromPoints(List<LatLng> points) {
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
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }
}


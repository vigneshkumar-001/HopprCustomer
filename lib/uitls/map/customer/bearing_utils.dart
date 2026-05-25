import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

class BearingUtils {
  static double wrap360(double a) => (a % 360 + 360) % 360;

  static double shortestAngleDelta(double from, double to) {
    double diff = wrap360(to) - wrap360(from);
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return diff;
  }

  static double emaAngle(double prevDeg, double targetDeg, double alpha) {
    final d = shortestAngleDelta(prevDeg, targetDeg);
    return wrap360(prevDeg + alpha * d);
  }

  static double computeBearing(LatLng from, LatLng to) {
    final double lat1 = _deg2rad(from.latitude);
    final double lat2 = _deg2rad(to.latitude);
    final double dLon = _deg2rad(to.longitude - from.longitude);

    final double y = math.sin(dLon) * math.cos(lat2);
    final double x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final double brng = math.atan2(y, x);
    return wrap360(brng * 180.0 / math.pi);
  }

  static double _deg2rad(double d) => d * math.pi / 180.0;
}


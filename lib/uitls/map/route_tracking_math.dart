import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Geometry helpers used for customer live ride tracking.
///
/// Notes:
/// - Distances are computed with local projection / haversine where appropriate.
/// - For "snap to polyline", a local equirectangular projection is accurate
///   enough at city scale and avoids heavy spherical math per segment.

double degreesToRadians(double degrees) => degrees * math.pi / 180.0;

double radiansToDegrees(double radians) => radians * 180.0 / math.pi;

double haversineDistanceMeters(LatLng a, LatLng b) {
  const double earthRadius = 6371000.0;
  final dLat = degreesToRadians(b.latitude - a.latitude);
  final dLng = degreesToRadians(b.longitude - a.longitude);
  final lat1 = degreesToRadians(a.latitude);
  final lat2 = degreesToRadians(b.latitude);

  final sinDLat = math.sin(dLat / 2);
  final sinDLng = math.sin(dLng / 2);
  final h =
      sinDLat * sinDLat +
      math.cos(lat1) * math.cos(lat2) * sinDLng * sinDLng;
  final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  return earthRadius * c;
}

/// Bearing in degrees [0, 360).
///
/// Required formula:
/// bearing = atan2(sin(dLng)*cos(lat2), cos(lat1)*sin(lat2)-sin(lat1)*cos(lat2)*cos(dLng))
double bearingBetween(LatLng from, LatLng to) {
  final lat1 = degreesToRadians(from.latitude);
  final lat2 = degreesToRadians(to.latitude);
  final dLng = degreesToRadians(to.longitude - from.longitude);

  final y = math.sin(dLng) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);

  final brng = radiansToDegrees(math.atan2(y, x));
  return (brng + 360.0) % 360.0;
}

double shortestAngleDelta(double fromDeg, double toDeg) {
  double a = (toDeg - fromDeg) % 360.0;
  if (a > 180.0) a -= 360.0;
  if (a < -180.0) a += 360.0;
  return a;
}

double smoothBearing({
  required double currentDeg,
  required double targetDeg,
  required double alpha,
}) {
  final d = shortestAngleDelta(currentDeg, targetDeg);
  return (currentDeg + d * alpha + 360.0) % 360.0;
}

String routeSignature(List<LatLng> pts) {
  if (pts.length < 2) return 'len:${pts.length}';
  final a = pts.first;
  final b = pts.last;
  return 'len:${pts.length}|a:${a.latitude.toStringAsFixed(6)},${a.longitude.toStringAsFixed(6)}|b:${b.latitude.toStringAsFixed(6)},${b.longitude.toStringAsFixed(6)}';
}

LatLng offsetLatLngMeters(LatLng from, double bearingDeg, double distanceMeters) {
  // Spherical earth projection (good enough for small distances).
  const double r = 6371000.0;
  final brng = degreesToRadians(bearingDeg);
  final lat1 = degreesToRadians(from.latitude);
  final lon1 = degreesToRadians(from.longitude);
  final dr = distanceMeters / r;

  final lat2 = math.asin(
    math.sin(lat1) * math.cos(dr) + math.cos(lat1) * math.sin(dr) * math.cos(brng),
  );
  final lon2 = lon1 +
      math.atan2(
        math.sin(brng) * math.sin(dr) * math.cos(lat1),
        math.cos(dr) - math.sin(lat1) * math.sin(lat2),
      );

  return LatLng(radiansToDegrees(lat2), radiansToDegrees(lon2));
}

LatLngBounds boundsFromRoutePoints(
  List<LatLng> routePoints, {
  List<LatLng> extraPoints = const <LatLng>[],
}) {
  final pts = <LatLng>[...routePoints, ...extraPoints];
  if (pts.isEmpty) {
    return LatLngBounds(
      southwest: const LatLng(0, 0),
      northeast: const LatLng(0, 0),
    );
  }

  double minLat = pts.first.latitude;
  double maxLat = pts.first.latitude;
  double minLng = pts.first.longitude;
  double maxLng = pts.first.longitude;

  for (final p in pts.skip(1)) {
    if (p.latitude < minLat) minLat = p.latitude;
    if (p.latitude > maxLat) maxLat = p.latitude;
    if (p.longitude < minLng) minLng = p.longitude;
    if (p.longitude > maxLng) maxLng = p.longitude;
  }

  // Expand slightly so markers/polyline don't touch edges.
  final latSpan = (maxLat - minLat).abs();
  final lngSpan = (maxLng - minLng).abs();
  final padLat = math.max(0.0012, latSpan * 0.12);
  final padLng = math.max(0.0012, lngSpan * 0.12);

  return LatLngBounds(
    southwest: LatLng(minLat - padLat, minLng - padLng),
    northeast: LatLng(maxLat + padLat, maxLng + padLng),
  );
}

class NearestPointOnPolylineResult {
  final LatLng point;
  final int segmentIndex;
  final double t; // [0,1] position on segment
  final double distanceMeters;

  const NearestPointOnPolylineResult({
    required this.point,
    required this.segmentIndex,
    required this.t,
    required this.distanceMeters,
  });
}

/// Returns the nearest point on polyline (over all segments) to [p].
NearestPointOnPolylineResult? nearestPointOnPolyline(
  LatLng p,
  List<LatLng> polyline,
) {
  if (polyline.length < 2) return null;

  NearestPointOnPolylineResult? best;

  for (int i = 0; i < polyline.length - 1; i++) {
    final a = polyline[i];
    final b = polyline[i + 1];
    final res = _nearestPointOnSegmentMeters(p, a, b);
    if (best == null || res.distanceMeters < best.distanceMeters) {
      best = NearestPointOnPolylineResult(
        point: res.point,
        segmentIndex: i,
        t: res.t,
        distanceMeters: res.distanceMeters,
      );
    }
  }

  return best;
}

double distancePointToSegmentMeters(LatLng p, LatLng a, LatLng b) {
  return _nearestPointOnSegmentMeters(p, a, b).distanceMeters;
}

class _NearestOnSeg {
  final LatLng point;
  final double t;
  final double distanceMeters;
  const _NearestOnSeg({
    required this.point,
    required this.t,
    required this.distanceMeters,
  });
}

_NearestOnSeg _nearestPointOnSegmentMeters(LatLng p, LatLng a, LatLng b) {
  // Local projection around segment mid latitude.
  final midLatRad = degreesToRadians((a.latitude + b.latitude) / 2.0);
  const earthRadius = 6371000.0;
  final mx = earthRadius * math.cos(midLatRad);
  final my = earthRadius;

  double toX(double lng) => degreesToRadians(lng) * mx;
  double toY(double lat) => degreesToRadians(lat) * my;

  final ax = toX(a.longitude);
  final ay = toY(a.latitude);
  final bx = toX(b.longitude);
  final by = toY(b.latitude);
  final px = toX(p.longitude);
  final py = toY(p.latitude);

  final abx = bx - ax;
  final aby = by - ay;
  final apx = px - ax;
  final apy = py - ay;

  final abLen2 = abx * abx + aby * aby;
  double t = 0.0;
  if (abLen2 > 0) {
    t = ((apx * abx + apy * aby) / abLen2).clamp(0.0, 1.0);
  }

  final nx = ax + abx * t;
  final ny = ay + aby * t;

  // Convert back to LatLng.
  final nLat = radiansToDegrees(ny / my);
  final nLng = radiansToDegrees(nx / mx);
  final snapped = LatLng(nLat, nLng);

  final dx = px - nx;
  final dy = py - ny;
  final dist = math.sqrt(dx * dx + dy * dy);

  return _NearestOnSeg(point: snapped, t: t, distanceMeters: dist);
}

bool shouldReroute({
  required List<LatLng> activeRoute,
  required LatLng driver,
  required LatLng destination,
  required DateTime now,
  required DateTime lastRouteFetchAt,
  required Duration minInterval,
  double offRouteThresholdMeters = 35.0,
}) {
  if (activeRoute.length < 2) return true;

  final nearest = nearestPointOnPolyline(driver, activeRoute);
  final offRoute =
      (nearest == null) || nearest.distanceMeters > offRouteThresholdMeters;

  if (!offRoute) return false;

  if (now.difference(lastRouteFetchAt) < minInterval) return false;

  // Also avoid rerouting when destination is extremely close; the map will
  // settle naturally even if slightly off-route.
  final dToDest = haversineDistanceMeters(driver, destination);
  if (dToDest < 20) return false;

  return true;
}

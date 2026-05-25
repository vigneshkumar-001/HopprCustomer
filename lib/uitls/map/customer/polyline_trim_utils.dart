import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class PolylineTrimResult {
  final List<LatLng> completed;
  final List<LatLng> remaining;
  final int index;

  PolylineTrimResult({
    required this.completed,
    required this.remaining,
    required this.index,
  });
}

class PolylineTrimUtils {
  static double distanceMeters(LatLng a, LatLng b) => Geolocator.distanceBetween(
        a.latitude,
        a.longitude,
        b.latitude,
        b.longitude,
      );

  static int? nearestIndex({
    required List<LatLng> points,
    required int fromIndex,
    required LatLng current,
    int maxLookahead = 50,
    double maxSnapMeters = 30,
  }) {
    if (points.length < 2) return null;
    final start = fromIndex.clamp(0, points.length - 1);
    final end = (start + maxLookahead).clamp(0, points.length - 1);

    int? bestIdx;
    double bestD = double.infinity;
    for (int i = start; i <= end; i++) {
      final p = points[i];
      final d = distanceMeters(current, p);
      if (d < bestD) {
        bestD = d;
        bestIdx = i;
      }
    }

    if (bestIdx == null) return null;
    if (!bestD.isFinite || bestD > maxSnapMeters) return null;
    return bestIdx;
  }

  static PolylineTrimResult? trim({
    required List<LatLng> full,
    required int lastIndex,
    required LatLng current,
    int maxLookahead = 50,
    double maxSnapMeters = 30,
  }) {
    final idx = nearestIndex(
      points: full,
      fromIndex: lastIndex,
      current: current,
      maxLookahead: maxLookahead,
      maxSnapMeters: maxSnapMeters,
    );
    if (idx == null) return null;
    if (idx <= lastIndex) return null;
    if (idx >= full.length - 1) return null;

    final completed = full.sublist(0, idx + 1);
    final remaining = full.sublist(idx);
    if (completed.length < 2 || remaining.length < 2) return null;

    return PolylineTrimResult(completed: completed, remaining: remaining, index: idx);
  }

  static bool isOffRoute({
    required List<LatLng> route,
    required LatLng current,
    double thresholdMeters = 90,
    int fromIndex = 0,
  }) {
    if (route.length < 2) return false;
    final idx = nearestIndex(
      points: route,
      fromIndex: fromIndex,
      current: current,
      maxLookahead: 80,
      maxSnapMeters: 99999,
    );
    if (idx == null) return false;
    final d = distanceMeters(current, route[idx]);
    return d.isFinite && d > thresholdMeters;
  }
}


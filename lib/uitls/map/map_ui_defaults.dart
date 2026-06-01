import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapUiDefaults {
  static const double pickupDropMarkerHueGreen = BitmapDescriptor.hueGreen;
  static const double pickupDropMarkerHueRed = BitmapDescriptor.hueRed;

  // Pickup/Drop marker sizing (dp). Keep consistent across screens.
  static const double pickupDropPinWidthDp = 26;
  // Make room for 2-line labels (pickup/drop) without feeling cramped.
  static const double pickupDropBubbleWidthDp = 140;
  static const double pickupDropBubbleHeightDp = 50;
  static const double pickupDropFontSizeDp = 12;

  static String _ellipsize(String s, int maxChars) {
    final raw = s.trim();
    if (raw.isEmpty) return raw;
    if (raw.length <= maxChars) return raw;
    if (maxChars <= 3) return raw.substring(0, maxChars);
    return '${raw.substring(0, maxChars - 3)}...';
  }

  static String placeLabel(
    String address, {
    String fallback = 'Pickup',
    int maxChars = 24,
  }) {
    final raw = address.trim();
    if (raw.isEmpty) return fallback;

    // Prefer a 2-line label for map pins when the address has comma segments.
    // This improves readability without increasing font size.
    final parts =
        raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    if (parts.length >= 2) {
      final line1 = _ellipsize(parts[0], 18);
      final line2 = _ellipsize(parts[1], 18);
      // Keep a stable 2-line output; `CompactMarkerIcons.labeledPin` will
      // handle further ellipsis within maxLines.
      return ('$line1\n$line2').trim();
    }

    // Fallback: single-line label.
    final candidate = parts.isNotEmpty ? parts.first : raw;
    return _ellipsize(candidate, maxChars);
  }

  // Active ride screens: never allow zoom <14 or >18.
  static const double focusZoom = 17.0;
  static const double minZoom = 14.0;
  static const double maxZoom = 18.0;

  // Route polyline styling (customer-side): thicker + high-contrast so it
  // never blends into the map style.
  static const int polylineWidth = 6;
  static const int polylineOutlineWidth = 10;
  static const Color polylineColor = Colors.black;
  static const Color polylineOutlineColor = Color(0xFFFFFFFF);

  // Vehicle marker sizing (dp).
  // - Ride/tracking screens use `vehicleBadgeDiameterDp` (circle badge).
  // - Home screen uses `vehicleCarWidthDp`/`vehicleBikeWidthDp` (asset pin)
  //   and should stay smaller to avoid clutter.
  static const double vehicleBadgeDiameterDp = 48;
  static const double vehicleCarWidthDp = 26;
  static const double vehicleBikeWidthDp = 28;

  // Vehicle icon orientation:
  // google_maps_flutter marker rotation expects degrees clockwise from NORTH.
  // Your PNG should be drawn pointing UP for 0°.
  static const double carBearingIconOffsetDeg = 0.0;
  static const double bikeBearingIconOffsetDeg = 0.0;

  static double normalizeBearing(double deg) {
    final v = deg % 360.0;
    return (v + 360.0) % 360.0;
  }

  static Set<Polyline> routePolylines(
    List<LatLng> points, {
    required String id,
    bool outline = true,
  }) {
    if (points.length < 2) return const <Polyline>{};

    final base = Polyline(
      polylineId: PolylineId(id),
      points: points,
      color: polylineColor,
      width: polylineWidth,
      zIndex: 2,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
      jointType: JointType.round,
    );

    if (!outline) return {base};

    final shadow = Polyline(
      polylineId: PolylineId('${id}_outline'),
      points: points,
      color: polylineOutlineColor,
      width: polylineOutlineWidth,
      zIndex: 1,
      startCap: Cap.roundCap,
      endCap: Cap.roundCap,
      jointType: JointType.round,
    );

    return {shadow, base};
  }

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

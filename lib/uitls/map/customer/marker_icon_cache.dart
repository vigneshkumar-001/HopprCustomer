import 'dart:ui' as ui;

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/uitls/map/compact_marker_icons.dart';
import 'package:hopper/uitls/map/customer/map_ui_config.dart';

enum VehicleType { car, bike }

class MarkerIconCache {
  static final Map<String, BitmapDescriptor> _cache = <String, BitmapDescriptor>{};

  static Future<BitmapDescriptor> vehicleIcon(VehicleType type, {double? dpr}) async {
    final resolvedDpr = (dpr ?? ui.window.devicePixelRatio).clamp(1.0, 4.0);
    final sizeDp =
        type == VehicleType.bike ? MapUiConfig.bikeMarkerSizeDp : MapUiConfig.carMarkerSizeDp;
    final asset = type == VehicleType.bike ? AppImages.packageBike : AppImages.carHop;
    final key = 'veh|$asset|$sizeDp|$resolvedDpr';
    final cached = _cache[key];
    if (cached != null) return cached;

    final icon = await CompactMarkerIcons.assetCircleBadge(
      assetPath: asset,
      diameterDp: sizeDp,
      dpr: resolvedDpr,
    );
    _cache[key] = icon;
    return icon;
  }

  static Future<BitmapDescriptor> pickupPin({double? dpr}) async {
    final resolvedDpr = (dpr ?? ui.window.devicePixelRatio).clamp(1.0, 4.0);
    final key = 'pin|pickup|${MapUiConfig.pickupDropPinWidthDp}|$resolvedDpr';
    final cached = _cache[key];
    if (cached != null) return cached;
    final icon = await CompactMarkerIcons.assetPin(
      assetPath: AppImages.pinLocation,
      widthDp: MapUiConfig.pickupDropPinWidthDp,
      dpr: resolvedDpr,
    );
    _cache[key] = icon;
    return icon;
  }

  static Future<BitmapDescriptor> dropPin({double? dpr}) async {
    final resolvedDpr = (dpr ?? ui.window.devicePixelRatio).clamp(1.0, 4.0);
    final key = 'pin|drop|${MapUiConfig.pickupDropPinWidthDp}|$resolvedDpr';
    final cached = _cache[key];
    if (cached != null) return cached;
    final icon = await CompactMarkerIcons.assetPin(
      assetPath: AppImages.rectangleDest,
      widthDp: MapUiConfig.pickupDropPinWidthDp,
      dpr: resolvedDpr,
    );
    _cache[key] = icon;
    return icon;
  }
}


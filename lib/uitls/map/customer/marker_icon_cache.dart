import 'dart:ui' as ui;

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/uitls/map/compact_marker_icons.dart';
import 'package:hopper/uitls/map/customer/map_ui_config.dart';

enum VehicleType { car, bike }

class MarkerIconCache {
  static final Map<String, BitmapDescriptor> _cache =
      <String, BitmapDescriptor>{};

  static Future<BitmapDescriptor> vehicleIcon(
    VehicleType type, {
    double? dpr,
  }) async {
    final resolvedDpr = (dpr ?? ui.window.devicePixelRatio).clamp(1.0, 4.0);
    final sizeDp =
        type == VehicleType.bike
            ? MapUiConfig.bikeMarkerSizeDp
            : MapUiConfig.carMarkerSizeDp;
    final asset =
        type == VehicleType.bike ? AppImages.bikeImage : AppImages.carHop;
    final key = 'veh|contain|$asset|$sizeDp|$resolvedDpr';
    final cached = _cache[key];
    if (cached != null) return cached;

    final icon = await CompactMarkerIcons.assetContained(
      assetPath: asset,
      sizeDp: sizeDp,
      dpr: resolvedDpr,
    );
    _cache[key] = icon;
    return icon;
  }

  // Pickup pin = black, Drop pin = green — same pin.png asset, tinted.
  static const ui.Color _pickupColor = ui.Color(0xFF000000);
  static const ui.Color _dropColor = ui.Color(0xFF15803D);

  static Future<BitmapDescriptor> pickupPin({double? dpr}) async {
    final resolvedDpr = (dpr ?? ui.window.devicePixelRatio).clamp(1.0, 4.0);
    final key =
        'pin|pickup|black|${MapUiConfig.pickupDropPinWidthDp}|$resolvedDpr';
    final cached = _cache[key];
    if (cached != null) return cached;
    final icon = await CompactMarkerIcons.assetPin(
      assetPath: AppImages.pin,
      widthDp: MapUiConfig.pickupDropPinWidthDp,
      tint: _pickupColor,
      dpr: resolvedDpr,
    );
    _cache[key] = icon;
    return icon;
  }

  static Future<BitmapDescriptor> dropPin({double? dpr}) async {
    final resolvedDpr = (dpr ?? ui.window.devicePixelRatio).clamp(1.0, 4.0);
    final key =
        'pin|drop|green|${MapUiConfig.pickupDropPinWidthDp}|$resolvedDpr';
    final cached = _cache[key];
    if (cached != null) return cached;
    final icon = await CompactMarkerIcons.assetPin(
      assetPath: AppImages.pin,
      widthDp: MapUiConfig.pickupDropPinWidthDp,
      tint: _dropColor,
      dpr: resolvedDpr,
    );
    _cache[key] = icon;
    return icon;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/api/repository/api_consents.dart';
import 'package:hopper/uitls/map/map_ui_defaults.dart';

class BookMapController extends GetxController {
  // Map refs
  GoogleMapController? mapController;

  // Reactive map data
  final RxSet<Marker> markers = <Marker>{}.obs;
  final RxSet<Polyline> polylines = <Polyline>{}.obs;

  final RxString address = 'Search...'.obs;

  // Positions
  LatLng? pickupPosition;
  LatLng? destinationPosition;
  LatLng? currentPosition;

  // Map style
  String? mapStyle;

  // Ride toggle (true = normal, false = shared)
  final RxBool isRideOnly = true.obs;

  // Location button: 1st tap focus, 2nd tap fit-bounds.
  bool _locationToggleFit = false;

  // Debounce timers
  Timer? _cameraIdleDebounce;
  Timer? _markerDebounce;

  // Guards
  bool _loadingPolyline = false;
  bool _loadingLocation = false;

  // cache last marker-time to avoid rebuild icon too often
  String _lastMarkerTime = '';

  // ---------- LIFECYCLE ----------
  @override
  void onInit() {
    super.onInit();
    _loadMapStyle();
  }

  @override
  void onClose() {
    _cameraIdleDebounce?.cancel();
    _markerDebounce?.cancel();
    super.onClose();
  }

  // ---------- INIT ----------
  Future<void> initPositions({
    required LatLng pickup,
    required LatLng destination,
    required String pickupLabel,
    required String dropLabel,
  }) async {
    pickupPosition = pickup;
    destinationPosition = destination;

    // draw once
    await drawPolyline();

    // default markers without time (can be updated later)
    await setPickupDropMarkers(
      pickupLabel: pickupLabel.trim().isEmpty ? 'Pickup' : pickupLabel.trim(),
      dropLabel: dropLabel.trim().isEmpty ? 'Drop' : dropLabel.trim(),
      estimatedMin: '',
      pickupAsset: AppImages.circleStart,
      dropAsset: AppImages.rectangleDest,
    );
  }

  Future<void> attachMap(GoogleMapController controller) async {
    mapController = controller;

    // apply style once
    if (mapStyle != null) {
      try {
        await mapController?.setMapStyle(mapStyle);
      } catch (_) {}
    }

    // fit bounds once
    await fitBounds();
  }

  Future<void> _loadMapStyle() async {
    try {
      mapStyle = await rootBundle.loadString('assets/map_style/map_style.json');
    } catch (e) {
      debugPrint('Map style load failed: $e');
    }
  }

  // ---------- CAMERA ----------
  void onUserMapGesture() {
    _locationToggleFit = false;
  }

  Future<void> onLocationButtonTap() async {
    final mc = mapController;
    if (mc == null) return;

    if (_locationToggleFit) {
      _locationToggleFit = false;
      await fitBounds();
      return;
    }

    _locationToggleFit = true;
    await goToCurrentLocation();
  }

  void onCameraIdle() {
    _cameraIdleDebounce?.cancel();
    _cameraIdleDebounce = Timer(const Duration(milliseconds: 350), () async {
      final mc = mapController;
      if (mc == null) return;

      final bounds = await mc.getVisibleRegion();
      final centerLat =
          (bounds.northeast.latitude + bounds.southwest.latitude) / 2;
      final centerLng =
          (bounds.northeast.longitude + bounds.southwest.longitude) / 2;

      final newPos = LatLng(centerLat, centerLng);

      // small move skip reverse geocode
      if (currentPosition != null) {
        final moved = _haversineMeters(currentPosition!, newPos);
        if (moved < 15) return;
      }

      currentPosition = newPos;
      await getAddressFromLatLng(newPos);
    });
  }

  // ---------- LOCATION ----------
  Future<void> goToCurrentLocation() async {
    if (_loadingLocation) return;
    _loadingLocation = true;
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final latLng = LatLng(position.latitude, position.longitude);
      await mapController?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 17));
    } finally {
      _loadingLocation = false;
    }
  }

  Future<void> getAddressFromLatLng(LatLng position) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final value = "${p.street ?? ''}, ${p.locality ?? ''}".trim();
        address.value = value.isEmpty ? "Unknown Location" : value;
      }
    } catch (_) {}
  }

  // ---------- POLYLINE ----------
  Future<void> drawPolyline() async {
    if (_loadingPolyline) return;
    if (pickupPosition == null || destinationPosition == null) return;
    _loadingPolyline = true;

    try {
      final apiKey = ApiConsents.googleMapApiKey;
      final url =
          'https://maps.googleapis.com/maps/api/directions/json?origin=${pickupPosition!.latitude},${pickupPosition!.longitude}&destination=${destinationPosition!.latitude},${destinationPosition!.longitude}&key=$apiKey';

      final response = await http.get(Uri.parse(url));
      final data = json.decode(response.body);

      if (data['status'] == 'OK') {
        final encoded = data['routes'][0]['overview_polyline']['points'];
        final points = _decodePolyline(encoded);

        polylines.assignAll(MapUiDefaults.routePolylines(points, id: 'route'));
      } else {
        AppLogger.log.w("Directions error: ${data['status']}");
      }
    } catch (e) {
      AppLogger.log.w("Polyline error: $e");
    } finally {
      _loadingPolyline = false;
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    final points = <LatLng>[];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  // ---------- MARKERS (HEAVY) ----------
  // Call this when estimatedTime changes (debounced)
  void updateMarkersDebounced({
    required String pickupLabel,
    required String dropLabel,
    required String estimatedMin,
  }) {
    _markerDebounce?.cancel();
    _markerDebounce = Timer(const Duration(milliseconds: 200), () async {
      // avoid rebuilding if same time
      if (_lastMarkerTime == estimatedMin) return;
      _lastMarkerTime = estimatedMin;

      await setPickupDropMarkers(
        pickupLabel: pickupLabel,
        dropLabel: dropLabel,
        estimatedMin: estimatedMin,
        pickupAsset: AppImages.circleStart,
        dropAsset: AppImages.rectangleDest,
      );
    });
  }

  Future<void> setPickupDropMarkers({
    required String pickupLabel,
    required String dropLabel,
    required String estimatedMin,
    required String pickupAsset,
    required String dropAsset,
  }) async {
    if (pickupPosition == null || destinationPosition == null) return;

    final startIcon = await _createCustomMarkerWithLabel(
      timeText: estimatedMin.isNotEmpty ? '$estimatedMin MIN' : null,
      label: MapUiDefaults.placeLabel(pickupLabel, fallback: 'Pickup'),
      assetPath: pickupAsset,
    );

    final destIcon = await _createCustomMarkerWithLabel(
      timeText: null,
      label: MapUiDefaults.placeLabel(dropLabel, fallback: 'Drop'),
      assetPath: dropAsset,
    );

    markers.assignAll({
      Marker(
        markerId: const MarkerId("pickup"),
        icon: startIcon,
        position: pickupPosition!,
        anchor: const Offset(0.5, 1.0),
        infoWindow: InfoWindow.noText,
      ),
      Marker(
        markerId: const MarkerId("destination"),
        icon: destIcon,
        position: destinationPosition!,
        anchor: const Offset(0.5, 1.0),
        infoWindow: InfoWindow.noText,
      ),
    });
  }

  Future<BitmapDescriptor> _createCustomMarkerWithLabel({
    required String label,
    required String assetPath,
    String? timeText,
    double bubbleWidthDp = MapUiDefaults.pickupDropBubbleWidthDp,
    double bubbleHeightDp = MapUiDefaults.pickupDropBubbleHeightDp,
    double pinWidthDp = MapUiDefaults.pickupDropPinWidthDp,
    double fontSizeDp = MapUiDefaults.pickupDropFontSizeDp,
    double? dpr,
  }) async {
    final resolvedDpr = (dpr ?? ui.window.devicePixelRatio).clamp(1.0, 4.0);
    final width = (bubbleWidthDp * resolvedDpr).round().clamp(140, 1400);
    final height = (bubbleHeightDp * resolvedDpr).round().clamp(36, 600);
    final pinW = (pinWidthDp * resolvedDpr).round().clamp(18, 260);
    final pad = (10 * resolvedDpr).round().clamp(8, 90);
    final gap = (4 * resolvedDpr).round().clamp(2, 40);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint();

    final timeBoxWidth = (54 * resolvedDpr).round().clamp(44, 260).toDouble();

    final bool showTime = timeText != null;
    final double labelBoxWidth = showTime
        ? width - timeBoxWidth - (pad * 3)
        : width - (pad * 2);

    // Background
    paint.color = Colors.white;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()
        ..color = const Color(0xFFE5E7EB)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (1.0 * resolvedDpr).clamp(1.0, 3.0),
    );

    // Time Box
    if (showTime) {
      paint.color = Colors.black;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, pad + timeBoxWidth, height.toDouble()),
        paint,
      );

      final timePara = ui.ParagraphBuilder(
        ui.ParagraphStyle(textAlign: TextAlign.center, maxLines: 2),
      )
        ..pushStyle(
          ui.TextStyle(
            color: Colors.white,
            fontSize: (12.5 * resolvedDpr).clamp(12.0, 40.0),
            fontWeight: FontWeight.w700,
          ),
        )
        ..addText(timeText!.replaceAll(" ", "\n"));

      final timeParagraph = timePara.build();
      timeParagraph.layout(ui.ParagraphConstraints(width: timeBoxWidth));

      canvas.drawParagraph(
        timeParagraph,
        Offset(pad.toDouble(), (height - timeParagraph.height) / 2),
      );
    }

    // Label
    final labelPara = ui.ParagraphBuilder(
       ui.ParagraphStyle(
        textAlign: TextAlign.left,
        maxLines: 2,
        ellipsis: '...',
      ),
    )
      ..pushStyle(
        ui.TextStyle(
          color: Colors.black,
          fontSize: (fontSizeDp * resolvedDpr).clamp(12.0, 48.0),
          fontWeight: FontWeight.w800,
        ),
      )
      ..addText(label);

    final labelParagraph = labelPara.build();
    labelParagraph.layout(ui.ParagraphConstraints(width: labelBoxWidth));

    final labelOffsetX = showTime ? (pad + timeBoxWidth + pad) : pad.toDouble();
    canvas.drawParagraph(
      labelParagraph,
      Offset(labelOffsetX, (height - labelParagraph.height) / 2),
    );

    // Marker Icon
    final data = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: pinW,
    );
    final frame = await codec.getNextFrame();
    final markerImage = frame.image;

    final pinH =
        (pinW * (markerImage.height / markerImage.width)).round().clamp(18, 520);
    final totalHeight = height + pinH + gap;
    final imageOffset =
        Offset((width - pinW) / 2, (height + gap).toDouble());
    canvas.drawImageRect(
      markerImage,
      Rect.fromLTWH(
        0,
        0,
        markerImage.width.toDouble(),
        markerImage.height.toDouble(),
      ),
      Rect.fromLTWH(
        imageOffset.dx.toDouble(),
        imageOffset.dy.toDouble(),
        pinW.toDouble(),
        pinH.toDouble(),
      ),
      Paint()..filterQuality = FilterQuality.high,
    );

    final picture = recorder.endRecording();
    final finalImage = await picture.toImage(width, totalHeight);
    final byteData = await finalImage.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
  }

  // ---------- BOUNDS ----------
  Future<void> fitBounds() async {
    if (pickupPosition == null || destinationPosition == null) return;
    final mc = mapController;
    if (mc == null) return;

    double minLat = math.min(pickupPosition!.latitude, destinationPosition!.latitude);
    double maxLat = math.max(pickupPosition!.latitude, destinationPosition!.latitude);
    double minLng = math.min(pickupPosition!.longitude, destinationPosition!.longitude);
    double maxLng = math.max(pickupPosition!.longitude, destinationPosition!.longitude);

    const minDelta = 0.009;
    if ((maxLat - minLat) < minDelta) {
      minLat -= minDelta;
      maxLat += minDelta;
    }
    if ((maxLng - minLng) < minDelta) {
      minLng -= minDelta;
      maxLng += minDelta;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    await mc.animateCamera(CameraUpdate.newLatLngBounds(bounds, 120));
  }

  double _haversineMeters(LatLng from, LatLng to) {
    const double R = 6371000;
    final dLat = _degToRad(to.latitude - from.latitude);
    final dLng = _degToRad(to.longitude - from.longitude);

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
            math.cos(_degToRad(from.latitude)) *
                math.cos(_degToRad(to.latitude)) *
                math.sin(dLng / 2) *
                math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _degToRad(double d) => d * math.pi / 180.0;
}

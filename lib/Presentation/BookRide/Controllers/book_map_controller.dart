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
  }) async {
    pickupPosition = pickup;
    destinationPosition = destination;

    // draw once
    await drawPolyline();

    // default markers without time (can be updated later)
    await setPickupDropMarkers(
      pickupLabel: '',
      dropLabel: '',
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

        polylines.assignAll({
          Polyline(
            polylineId: const PolylineId("route"),
            points: points,
            color: Colors.black,
            width: 3,
          ),
        });
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
      label: pickupLabel,
      assetPath: pickupAsset,
    );

    final destIcon = await _createCustomMarkerWithLabel(
      timeText: null,
      label: dropLabel,
      assetPath: dropAsset,
    );

    markers.assignAll({
      Marker(
        markerId: const MarkerId("pickup"),
        icon: startIcon,
        position: pickupPosition!,
      ),
      Marker(
        markerId: const MarkerId("destination"),
        icon: destIcon,
        position: destinationPosition!,
      ),
    });
  }

  Future<BitmapDescriptor> _createCustomMarkerWithLabel({
    required String label,
    required String assetPath,
    String? timeText,
    double width = 300,
    double height = 100,
    double iconSize = 50,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint();

    const double padding = 10;
    const double timeBoxWidth = 60;

    final bool showTime = timeText != null;
    final double labelBoxWidth =
    showTime ? width - timeBoxWidth - (padding * 3) : width - (padding * 2);
    final double totalHeight = height + iconSize + 10;

    // Background
    paint.color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), paint);

    // Time Box
    if (showTime) {
      paint.color = Colors.black;
      canvas.drawRect(
        Rect.fromLTWH(0, 0, padding + timeBoxWidth, height),
        paint,
      );

      final timePara = ui.ParagraphBuilder(
        ui.ParagraphStyle(textAlign: TextAlign.center, maxLines: 2),
      )
        ..pushStyle(
          ui.TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w400,
          ),
        )
        ..addText(timeText!.replaceAll(" ", "\n"));

      final timeParagraph = timePara.build();
      timeParagraph.layout(const ui.ParagraphConstraints(width: timeBoxWidth));

      canvas.drawParagraph(
        timeParagraph,
        Offset(padding, (height - timeParagraph.height) / 2),
      );
    }

    // Label
    final labelPara = ui.ParagraphBuilder(
      ui.ParagraphStyle(textAlign: TextAlign.center, maxLines: 2),
    )
      ..pushStyle(
        ui.TextStyle(
          color: Colors.black,
          fontSize: 29,
          fontWeight: FontWeight.w600,
        ),
      )
      ..addText(label);

    final labelParagraph = labelPara.build();
    labelParagraph.layout(ui.ParagraphConstraints(width: labelBoxWidth));

    final labelOffsetX = showTime ? padding + timeBoxWidth + padding : padding;
    canvas.drawParagraph(
      labelParagraph,
      Offset(labelOffsetX, (height - labelParagraph.height) / 2),
    );

    // Marker Icon
    final data = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    final markerImage = frame.image;

    final imageOffset = Offset((width - iconSize) / 2, height + 5);
    canvas.drawImageRect(
      markerImage,
      Rect.fromLTWH(
        0,
        0,
        markerImage.width.toDouble(),
        markerImage.height.toDouble(),
      ),
      Rect.fromLTWH(imageOffset.dx, imageOffset.dy, iconSize, iconSize),
      Paint(),
    );

    final picture = recorder.endRecording();
    final finalImage =
    await picture.toImage(width.toInt(), totalHeight.toInt());
    final byteData =
    await finalImage.toByteData(format: ui.ImageByteFormat.png);

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

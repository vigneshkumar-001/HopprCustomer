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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_compass/flutter_compass.dart';

import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Presentation/Authentication/controller/location_gate_controller.dart';
import 'package:hopper/Presentation/OnBoarding/models/popular_address_model.dart';
import 'package:hopper/Presentation/OnBoarding/models/recent_location_model.dart';
import 'package:hopper/api/repository/api_consents.dart';
import 'package:hopper/uitls/websocket/socket_io_client.dart';
import 'package:hopper/uitls/websocket/shared_web_socket.dart';

class HomeMapController extends GetxController {
  final LocationGateController gate = Get.find<LocationGateController>();
  final SocketService socketService = SocketService();
  final RideShareSocketService rideShareSocket = RideShareSocketService();

  GoogleMapController? mapController;

  final RxSet<Marker> markers = <Marker>{}.obs;
  final RxString address = 'Fetching your location...'.obs;

  final RxList<PopularPlace> popularPlaces = <PopularPlace>[].obs;
  final RxList<RecentLocation> recentLocations = <RecentLocation>[].obs;

  String customerId = '';
  LatLng? currentPosition;

  String? mapStyle;

  CameraPosition? _lastCamera;
  Timer? _cameraIdleDebounce;

  final Map<String, String> _geocodeCache = {};
  Timer? _geocodeDebounce;
  LatLng? _lastGeocodedPos;

  bool _loadingLocation = false;

  double _heading = 0.0;
  StreamSubscription<CompassEvent>? _compassSub;
  Timer? _compassThrottle;

  BitmapDescriptor? _carIcon, _bikeIcon;
  final BitmapDescriptor _fallbackIcon = BitmapDescriptor.defaultMarker;

  final Map<String, Marker> _driverMarkers = {};
  final Map<String, String> _driverTypes = {};
  final Map<String, LatLng> _lastPos = {};
  final Map<String, Timer> _moveTimers = {};
  final Map<String, DateTime> _lastSocketProcessedAt = {};
  Timer? _publishDebounce;

  static const int _socketThrottleMs = 250;
  static const int _animStepMs = 80;
  static const double _ignoreMoveMeters = 2.0;

  static const double _reverseGeocodeMinMoveMeters = 15.0;

  @override
  void onInit() {
    super.onInit();
    _preloadMapStyle();
    _startCompassListener();
  }

  @override
  void onClose() {
    _cameraIdleDebounce?.cancel();
    _geocodeDebounce?.cancel();
    _publishDebounce?.cancel();
    _compassThrottle?.cancel();
    _compassSub?.cancel();

    for (final t in _moveTimers.values) {
      t.cancel();
    }
    _moveTimers.clear();

    super.onClose();
  }

  Future<void> start() async {
    await _loadCustomerId();
    _initSocket();
    await _loadDriverIcons();
    await initLocation();
    await loadRecentLocations();
  }

  Future<void> attachMap(GoogleMapController controller) async {
    mapController = controller;

    if (mapStyle != null) {
      try {
        await mapController?.setMapStyle(mapStyle);
      } catch (_) {}
    }

    // ✅ Important for home map: if currentPosition already available, move camera now
    if (currentPosition != null) {
      try {
        await mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(currentPosition!, 15),
        );
      } catch (_) {}
    } else {
      await initLocation();
    }
  }

  void onCameraMove(CameraPosition position) {
    _lastCamera = position;
  }

  void onCameraIdle() {
    _cameraIdleDebounce?.cancel();
    _cameraIdleDebounce = Timer(const Duration(milliseconds: 260), () {
      final cam = _lastCamera;
      if (cam == null) return;

      final newPos = cam.target;

      if (currentPosition != null) {
        final moved = _haversineMeters(currentPosition!, newPos);
        if (moved < _reverseGeocodeMinMoveMeters) return;
      }

      currentPosition = newPos;
      _scheduleReverseGeocode(newPos);
    });
  }

  Future<void> _preloadMapStyle() async {
    try {
      mapStyle = await rootBundle.loadString(
        'assets/map_style/map_style1.json',
      );
    } catch (e) {
      debugPrint('Failed to load map style: $e');
    }
  }

  void _startCompassListener() {
    _compassSub = FlutterCompass.events?.listen((event) {
      if (event.heading == null) return;

      if (_compassThrottle?.isActive == true) return;
      _compassThrottle = Timer(const Duration(milliseconds: 200), () {});
      _heading = event.heading!;
    });
  }

  Future<void> _loadCustomerId() async {
    final prefs = await SharedPreferences.getInstance();
    customerId = prefs.getString('customer_Id') ?? '';

    if (customerId.isEmpty) {
      AppLogger.log.w('⚠️ No customer ID found.');
    } else {
      AppLogger.log.i('✅ customerId = $customerId');
    }
  }

  void _initSocket() {
    if (customerId.isEmpty) return;

    socketService.initSocket(ApiConsents.baseUrl);
    // rideShareSocket.initSocket(ApiConsents.sharedBaseUrl);

    socketService.onConnect(() {
      socketService.registerUser(customerId);
      socketService.onReconnect(() {
        socketService.registerUser(customerId);
      });
    });

    socketService.on('nearby-driver-update', (data) {
      final String driverId = data['driverId'].toString();
      final now = DateTime.now().toUtc();

      final last = _lastSocketProcessedAt[driverId];
      if (last != null &&
          now.difference(last).inMilliseconds < _socketThrottleMs) {
        return;
      }
      _lastSocketProcessedAt[driverId] = now;

      final double lat = (data['latitude'] as num).toDouble();
      final double lng = (data['longitude'] as num).toDouble();

      final String rideType =
          (data['rideType'] ??
                  data['serviceType'] ??
                  data['vehicleType'] ??
                  data['type'] ??
                  'car')
              .toString();

      final dynamic hRaw = data['bearing'] ?? data['heading'];
      final double? serverHeading = (hRaw is num) ? hRaw.toDouble() : null;

      _driverTypes[driverId] = rideType;

      animateDriverTo(
        driverId: driverId,
        to: LatLng(lat, lng),
        serviceType: rideType,
        serverHeading: serverHeading,
      );
    });

    socketService.on('remove-nearby-driver', (data) {
      final String driverId = data['driverId'].toString();

      _moveTimers.remove(driverId)?.cancel();
      _driverMarkers.remove(driverId);
      _driverTypes.remove(driverId);
      _lastPos.remove(driverId);
      _lastSocketProcessedAt.remove(driverId);

      _publishMarkersDebounced();
    });
  }

  Future<bool> _ensureLocationReady() async => gate.isReady.value;

  Future<Position?> _safeGetCurrentPosition() async {
    if (!await _ensureLocationReady()) return null;
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } on LocationServiceDisabledException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> initLocation() async {
    if (_loadingLocation) return;
    _loadingLocation = true;

    try {
      final pos = await _safeGetCurrentPosition();
      if (pos == null) return;

      currentPosition = LatLng(pos.latitude, pos.longitude);

      try {
        await mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: currentPosition!, zoom: 15),
          ),
        );
      } catch (_) {}

      _scheduleReverseGeocode(currentPosition!, immediate: true);
      await fetchPopularPlaces(currentPosition!);
    } finally {
      _loadingLocation = false;
    }
  }

  Future<void> goToCurrentLocation() async {
    final pos = await _safeGetCurrentPosition();
    if (pos == null) return;

    final latLng = LatLng(pos.latitude, pos.longitude);
    currentPosition = latLng;

    try {
      await mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(latLng, 17),
      );
    } catch (_) {}

    _scheduleReverseGeocode(latLng, immediate: true);
  }

  Future<String> getAddressFromLatLng(LatLng position) async {
    final key =
        '${position.latitude.toStringAsFixed(5)},${position.longitude.toStringAsFixed(5)}';

    final cached = _geocodeCache[key];
    if (cached != null) {
      address.value = cached;
      return cached;
    }

    final value = await _reverseGeocode(position);
    _geocodeCache[key] = value;
    address.value = value;
    return value;
  }

  void _scheduleReverseGeocode(LatLng pos, {bool immediate = false}) {
    if (_lastGeocodedPos != null) {
      final moved = _haversineMeters(_lastGeocodedPos!, pos);
      if (moved < _reverseGeocodeMinMoveMeters) return;
    }

    _geocodeDebounce?.cancel();
    final delay = immediate ? Duration.zero : const Duration(milliseconds: 220);

    _geocodeDebounce = Timer(delay, () async {
      _lastGeocodedPos = pos;

      final key =
          '${pos.latitude.toStringAsFixed(5)},${pos.longitude.toStringAsFixed(5)}';

      final cached = _geocodeCache[key];
      if (cached != null) {
        address.value = cached;
        return;
      }

      final value = await _reverseGeocode(pos);
      _geocodeCache[key] = value;
      address.value = value;
    });
  }

  Future<String> _reverseGeocode(LatLng position) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final value = "${p.name ?? ''}, ${p.subLocality ?? ''}".trim();
        return value.isEmpty ? "Unknown Location" : value;
      }
      return "Unknown Location";
    } catch (_) {
      return "Unknown Location";
    }
  }

  Future<void> loadRecentLocations() async {
    final prefs = await SharedPreferences.getInstance();
    final recentList = prefs.getStringList('recent_locations') ?? [];

    final decoded =
        recentList.map((jsonStr) {
          final json = jsonDecode(jsonStr);
          return RecentLocation.fromJson(json);
        }).toList();

    recentLocations.assignAll(decoded);
  }

  Future<void> fetchPopularPlaces(LatLng location) async {
    final apiKey = ApiConsents.googleMapApiKey;
    final url =
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=${location.latitude},${location.longitude}&rankby=distance&type=bus_station&key=$apiKey';

    try {
      final response = await http.get(Uri.parse(url));
      final data = json.decode(response.body);

      if (data['status'] == 'OK') {
        final results = (data['results'] as List);
        final list =
            results.take(2).map((place) {
              final displayName = "${place['name']}, ${place['vicinity']}";
              return PopularPlace(
                name: displayName,
                address: place['vicinity'],
                lat: place['geometry']['location']['lat'],
                lng: place['geometry']['location']['lng'],
              );
            }).toList();

        popularPlaces.assignAll(list);
      }
    } catch (_) {}
  }

  Future<void> _loadDriverIcons() async {
    final dpr = ui.window.devicePixelRatio;

    _carIcon = await _bitmapFromAssetSized(
      AppImages.movingCar,
      widthDp: 22,
      dpr: dpr,
    );
    _bikeIcon = await _bitmapFromAssetSized(
      AppImages.packageBike,
      widthDp: 24,
      dpr: dpr,
    );

    _driverMarkers.updateAll((id, old) {
      final t = _driverTypes[id] ?? 'car';
      return old.copyWith(iconParam: _iconForRideType(t));
    });

    _publishMarkersDebounced();
  }

  Future<BitmapDescriptor> _bitmapFromAssetSized(
    String assetPath, {
    required double widthDp,
    required double dpr,
  }) async {
    final targetWidthPx = (widthDp * dpr).round();

    final byteData = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(
      byteData.buffer.asUint8List(),
      targetWidth: targetWidthPx,
    );
    final frame = await codec.getNextFrame();
    final bytes = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  BitmapDescriptor _iconForRideType(String? raw) {
    final t = (raw ?? '').trim().toLowerCase();
    switch (t) {
      case 'bike':
      case 'two_wheeler':
      case '2w':
      case 'motorbike':
      case 'scooter':
        return _bikeIcon ?? _fallbackIcon;
      default:
        return _carIcon ?? _fallbackIcon;
    }
  }

  void animateDriverTo({
    required String driverId,
    required LatLng to,
    required String serviceType,
    double? serverHeading,
  }) {
    final from = _lastPos[driverId] ?? to;
    final meters = _haversineMeters(from, to);

    if (meters < _ignoreMoveMeters) {
      _updateDriverMarkerPosition(
        driverId,
        to,
        serverHeading ?? _bearingBetween(from, to) ?? _heading,
        serviceType,
      );
      return;
    }

    _moveTimers.remove(driverId)?.cancel();

    final durationMs = meters.clamp(600, 1600).toInt();
    final steps = (durationMs / _animStepMs).clamp(1, 60).round();

    int i = 0;
    final startHeading = _driverMarkers[driverId]?.rotation ?? 0.0;
    final computedBearing = _bearingBetween(from, to);
    final endHeading = serverHeading ?? computedBearing ?? startHeading;

    _moveTimers[driverId] = Timer.periodic(
      const Duration(milliseconds: _animStepMs),
      (timer) {
        i++;
        double t = (i / steps).clamp(0.0, 1.0);
        t = _easeInOutCubic(t);

        final pos = _lerpLatLng(from, to, t);
        final rot = _lerpAngleDeg(startHeading, endHeading, t);

        _updateDriverMarkerPosition(driverId, pos, rot, serviceType);

        if (t >= 1.0) {
          timer.cancel();
          _moveTimers.remove(driverId);
        }
      },
    );
  }

  void _updateDriverMarkerPosition(
    String driverId,
    LatLng pos,
    double rotation,
    String serviceType,
  ) {
    _driverMarkers[driverId] = Marker(
      markerId: MarkerId(driverId),
      position: pos,
      icon: _iconForRideType(serviceType),
      anchor: const Offset(0.5, 0.5),
      flat: true,
      rotation: (rotation + 360) % 360,
    );

    _lastPos[driverId] = pos;
    _publishMarkersDebounced();
  }

  void _publishMarkersDebounced() {
    _publishDebounce?.cancel();
    _publishDebounce = Timer(const Duration(milliseconds: 60), () {
      markers.assignAll(_driverMarkers.values.toSet());
    });
  }

  double _degreesToRadians(double degrees) => degrees * math.pi / 180;

  double _haversineMeters(LatLng from, LatLng to) {
    const double R = 6371000;
    final dLat = _degreesToRadians(to.latitude - from.latitude);
    final dLng = _degreesToRadians(to.longitude - from.longitude);

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(from.latitude)) *
            math.cos(_degreesToRadians(to.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double? _bearingBetween(LatLng from, LatLng to) {
    final lat1 = _degreesToRadians(from.latitude);
    final lon1 = _degreesToRadians(from.longitude);
    final lat2 = _degreesToRadians(to.latitude);
    final lon2 = _degreesToRadians(to.longitude);

    final dLon = lon2 - lon1;
    final y = math.sin(dLon) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  double _easeInOutCubic(double t) =>
      t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3).toDouble() / 2;

  LatLng _lerpLatLng(LatLng a, LatLng b, double t) {
    final lat = a.latitude + (b.latitude - a.latitude) * t;
    final lng = a.longitude + (b.longitude - a.longitude) * t;
    return LatLng(lat, lng);
  }

  double _lerpAngleDeg(double start, double end, double t) {
    double delta = (end - start) % 360;
    if (delta > 180) delta -= 360;
    return (start + delta * t) % 360;
  }
}

// import 'dart:async';
// import 'dart:convert';
// import 'dart:math' as math;
// import 'dart:ui' as ui;
//
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart' show rootBundle;
// import 'package:get/get.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:geocoding/geocoding.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:http/http.dart' as http;
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:flutter_compass/flutter_compass.dart';
//
// import 'package:hopper/Core/Consents/app_logger.dart';
// import 'package:hopper/Core/Utility/app_images.dart';
// import 'package:hopper/Presentation/Authentication/controller/location_gate_controller.dart';
// import 'package:hopper/Presentation/OnBoarding/models/popular_address_model.dart';
// import 'package:hopper/Presentation/OnBoarding/models/recent_location_model.dart';
// import 'package:hopper/api/repository/api_consents.dart';
// import 'package:hopper/uitls/websocket/socket_io_client.dart';
// import 'package:hopper/uitls/websocket/shared_web_socket.dart';
//
// class HomeMapController extends GetxController {
//   // --- external deps
//   final LocationGateController gate = Get.find<LocationGateController>();
//   final SocketService socketService = SocketService();
//   final RideShareSocketService rideShareSocket = RideShareSocketService();
//
//   // --- map controller (set from UI)
//   GoogleMapController? mapController;
//
//   // --- reactive UI states
//   final RxSet<Marker> markers = <Marker>{}.obs;
//   final RxString address = 'Fetching your location...'.obs;
//
//   final RxBool isLocationReady = false.obs;
//
//   // --- data
//   final RxList<PopularPlace> popularPlaces = <PopularPlace>[].obs;
//   final RxList<RecentLocation> recentLocations = <RecentLocation>[].obs;
//
//   String customerId = '';
//   LatLng? currentPosition;
//   LatLng? pickedPosition;
//
//   // --- map style
//   String? mapStyle;
//
//   // --- compass (avoid setState)
//   double _heading = 0.0;
//   StreamSubscription<CompassEvent>? _compassSub;
//   Timer? _compassThrottle;
//
//   // --- camera idle debounce
//   Timer? _cameraIdleDebounce;
//
//   // --- location init guard
//   bool _loadingLocation = false;
//
//   // --- driver icons
//   BitmapDescriptor? _carIcon, _bikeIcon;
//   final BitmapDescriptor _fallbackIcon = BitmapDescriptor.defaultMarker;
//
//   // --- driver state
//   final Map<String, Marker> _driverMarkers = {};
//   final Map<String, String> _driverTypes = {};
//   final Map<String, LatLng> _lastPos = {};
//   final Map<String, Timer> _moveTimers = {};
//   final Map<String, DateTime> _lastSocketProcessedAt = {};
//
//   // tune (uber-like)
//   static const int _socketThrottleMs = 250; // ignore spam
//   static const int _animStepMs = 80; // 12.5 fps
//   static const double _ignoreMoveMeters = 2.0; // ignore micro movement
//   static const double _reverseGeocodeMinMoveMeters = 15.0;
//
//   // -------------------- LIFE CYCLE --------------------
//
//   @override
//   void onInit() {
//     super.onInit();
//     _preloadMapStyle();
//     _startCompassListener();
//   }
//
//   @override
//   void onClose() {
//     _cameraIdleDebounce?.cancel();
//     _compassThrottle?.cancel();
//     _compassSub?.cancel();
//
//     for (final t in _moveTimers.values) {
//       t.cancel();
//     }
//     _moveTimers.clear();
//
//     super.onClose();
//   }
//
//   // Call from HomeScreen after first frame
//   Future<void> start() async {
//     await _loadCustomerId();
//     _initSocket();
//     await _loadDriverIcons();
//     await initLocation();
//     await loadRecentLocations();
//   }
//
//   // -------------------- SETTERS FROM UI --------------------
//
//   Future<void> attachMap(GoogleMapController controller) async {
//     mapController = controller;
//
//     // apply style
//     if (mapStyle != null) {
//       try {
//         await mapController?.setMapStyle(mapStyle);
//       } catch (_) {}
//     }
//
//
//   }
//
//   void onCameraMove(CameraPosition position) {
//     pickedPosition = position.target;
//   }
//
//   void onCameraIdle() {
//     _cameraIdleDebounce?.cancel();
//     _cameraIdleDebounce = Timer(const Duration(milliseconds: 350), () async {
//       final mc = mapController;
//       if (mc == null) return;
//
//       final bounds = await mc.getVisibleRegion();
//       final centerLat =
//           (bounds.northeast.latitude + bounds.southwest.latitude) / 2;
//       final centerLng =
//           (bounds.northeast.longitude + bounds.southwest.longitude) / 2;
//
//       final newPos = LatLng(centerLat, centerLng);
//
//       if (currentPosition != null) {
//         final moved = _haversineMeters(currentPosition!, newPos);
//         if (moved < _reverseGeocodeMinMoveMeters) return;
//       }
//
//       currentPosition = newPos;
//       await getAddressFromLatLng(newPos);
//     });
//   }
//
//   // -------------------- INIT: MAP STYLE --------------------
//
//   Future<void> _preloadMapStyle() async {
//     try {
//       mapStyle = await rootBundle.loadString('assets/map_style/map_style1.json');
//     } catch (e) {
//       debugPrint('Failed to load map style: $e');
//     }
//   }
//
//   // -------------------- INIT: COMPASS --------------------
//
//   void _startCompassListener() {
//     _compassSub = FlutterCompass.events?.listen((event) {
//       if (event.heading == null) return;
//
//       if (_compassThrottle?.isActive == true) return;
//       _compassThrottle = Timer(const Duration(milliseconds: 200), () {});
//
//       _heading = event.heading!;
//     });
//   }
//
//   // -------------------- CUSTOMER ID --------------------
//
//   Future<void> _loadCustomerId() async {
//     final prefs = await SharedPreferences.getInstance();
//     customerId = prefs.getString('customer_Id') ?? '';
//
//     if (customerId.isEmpty) {
//       AppLogger.log.w('⚠️ No customer ID found in shared preferences.');
//     } else {
//       AppLogger.log.i('✅ Loaded customerId = $customerId');
//     }
//   }
//
//   // -------------------- SOCKET --------------------
//
//   void _initSocket() {
//     if (customerId.isEmpty) return;
//
//     socketService.initSocket(
//       'https://hoppr-face-two-dbe557472d7f.herokuapp.com',
//     );
//     rideShareSocket.initSocket(ApiConsents.sharedBaseUrl);
//
//     socketService.onConnect(() {
//       socketService.registerUser(customerId);
//       socketService.onReconnect(() {
//         AppLogger.log.i("🔄 Reconnected");
//         socketService.registerUser(customerId);
//       });
//     });
//
//     socketService.on('registered', (data) {
//       AppLogger.log.i("✅ Registered → $data");
//     });
//
//     socketService.on('nearby-driver-update', (data) {
//       final String driverId = data['driverId'].toString();
//       final now = DateTime.now().toUtc();
//
//       // ✅ throttle
//       final last = _lastSocketProcessedAt[driverId];
//       if (last != null && now.difference(last).inMilliseconds < _socketThrottleMs) {
//         return;
//       }
//       _lastSocketProcessedAt[driverId] = now;
//
//       final double lat = (data['latitude'] as num).toDouble();
//       final double lng = (data['longitude'] as num).toDouble();
//
//       final String rideType =
//       (data['rideType'] ??
//           data['serviceType'] ??
//           data['vehicleType'] ??
//           data['type'] ??
//           'car')
//           .toString();
//
//       final dynamic hRaw = data['bearing'] ?? data['heading'];
//       final double? serverHeading = (hRaw is num) ? hRaw.toDouble() : null;
//
//       _driverTypes[driverId] = rideType;
//
//       animateDriverTo(
//         driverId: driverId,
//         to: LatLng(lat, lng),
//         serviceType: rideType,
//         serverHeading: serverHeading,
//       );
//     });
//
//     socketService.on('remove-nearby-driver', (data) {
//       final String driverId = data['driverId'].toString();
//
//       _moveTimers.remove(driverId)?.cancel();
//       _driverMarkers.remove(driverId);
//       _driverTypes.remove(driverId);
//       _lastPos.remove(driverId);
//       _lastSocketProcessedAt.remove(driverId);
//
//       _publishMarkers();
//     });
//   }
//
//   // -------------------- LOCATION --------------------
//
//   Future<bool> _ensureLocationReady() async => gate.isReady.value;
//
//   Future<Position?> _safeGetCurrentPosition() async {
//     if (!await _ensureLocationReady()) return null;
//     try {
//       return await Geolocator.getCurrentPosition(
//         desiredAccuracy: LocationAccuracy.high,
//       );
//     } on LocationServiceDisabledException {
//       return null;
//     } catch (_) {
//       return null;
//     }
//   }
//
//   Future<void> initLocation() async {
//     if (_loadingLocation) return;
//     _loadingLocation = true;
//
//     try {
//       isLocationReady.value = gate.isReady.value;
//
//       final pos = await _safeGetCurrentPosition();
//       if (pos == null) return;
//
//       currentPosition = LatLng(pos.latitude, pos.longitude);
//
//       await mapController?.animateCamera(
//         CameraUpdate.newCameraPosition(
//           CameraPosition(target: currentPosition!, zoom: 16),
//         ),
//       );
//
//       // ✅ IMPORTANT: set address on first open
//       await getAddressFromLatLng(currentPosition!);
//
//       await fetchPopularPlaces(currentPosition!);
//     } finally {
//       _loadingLocation = false;
//     }
//   }
//
//
//   Future<void> goToCurrentLocation() async {
//     final pos = await _safeGetCurrentPosition();
//     if (pos == null) return;
//
//     final latLng = LatLng(pos.latitude, pos.longitude);
//     await mapController?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 17));
//   }
//
//   Future<String> getAddressFromLatLng(LatLng position) async {
//     try {
//       final placemarks =
//       await placemarkFromCoordinates(position.latitude, position.longitude);
//
//       if (placemarks.isNotEmpty) {
//         final p = placemarks.first;
//         final value = "${p.name ?? ''}, ${p.subLocality ?? ''}".trim();
//         address.value = value.isEmpty ? "Unknown Location" : value;
//         return address.value;
//       }
//       address.value = "Unknown Location";
//       return address.value;
//     } catch (_) {
//       address.value = "Unknown Location";
//       return address.value;
//     }
//   }
//
//   Future<void> loadRecentLocations() async {
//     final prefs = await SharedPreferences.getInstance();
//     final recentList = prefs.getStringList('recent_locations') ?? [];
//
//     final decoded = recentList.map((jsonStr) {
//       final json = jsonDecode(jsonStr);
//       return RecentLocation.fromJson(json);
//     }).toList();
//
//     recentLocations.assignAll(decoded);
//   }
//
//   Future<void> fetchPopularPlaces(LatLng location) async {
//     final apiKey = ApiConsents.googleMapApiKey;
//     final url =
//         'https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=${location.latitude},${location.longitude}&rankby=distance&type=bus_station&key=$apiKey';
//
//     try {
//       final response = await http.get(Uri.parse(url));
//       final data = json.decode(response.body);
//
//       if (data['status'] == 'OK') {
//         final results = (data['results'] as List);
//         final list = results.take(2).map((place) {
//           final displayName = "${place['name']}, ${place['vicinity']}";
//           return PopularPlace(
//             name: displayName,
//             address: place['vicinity'],
//             lat: place['geometry']['location']['lat'],
//             lng: place['geometry']['location']['lng'],
//           );
//         }).toList();
//
//         popularPlaces.assignAll(list);
//       }
//     } catch (_) {}
//   }
//
//   // -------------------- ICONS --------------------
//
//   Future<BitmapDescriptor> _bitmapFromAssetSized(
//       String assetPath, {
//         required double widthDp,
//       }) async {
//     final dpr = Get.context != null
//         ? MediaQuery.devicePixelRatioOf(Get.context!)
//         : ui.window.devicePixelRatio;
//
//     final targetWidthPx = (widthDp * dpr).round();
//
//     final byteData = await rootBundle.load(assetPath);
//     final codec = await ui.instantiateImageCodec(
//       byteData.buffer.asUint8List(),
//       targetWidth: targetWidthPx,
//     );
//     final frame = await codec.getNextFrame();
//     final bytes = await frame.image.toByteData(format: ui.ImageByteFormat.png);
//     return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
//   }
//
//   Future<void> _loadDriverIcons() async {
//     _carIcon = await _bitmapFromAssetSized(AppImages.movingCar, widthDp: 26);
//     _bikeIcon = await _bitmapFromAssetSized(AppImages.packageBike, widthDp: 30);
//
//     // refresh icons if markers already exist
//     _driverMarkers.updateAll((id, old) {
//       final t = _driverTypes[id] ?? 'car';
//       return old.copyWith(iconParam: _iconForRideType(t));
//     });
//
//     _publishMarkers();
//   }
//
//   BitmapDescriptor _iconForRideType(String? raw) {
//     final t = (raw ?? '').trim().toLowerCase();
//     switch (t) {
//       case 'bike':
//       case 'two_wheeler':
//       case '2w':
//       case 'motorbike':
//       case 'scooter':
//         return _bikeIcon ?? _fallbackIcon;
//       default:
//         return _carIcon ?? _fallbackIcon;
//     }
//   }
//
//   // -------------------- DRIVER ANIMATION --------------------
//
//   void animateDriverTo({
//     required String driverId,
//     required LatLng to,
//     required String serviceType,
//     double? serverHeading,
//   }) {
//     final from = _lastPos[driverId] ?? to;
//     final meters = _haversineMeters(from, to);
//
//     if (meters < _ignoreMoveMeters) {
//       _updateDriverMarkerPosition(
//         driverId,
//         to,
//         serverHeading ?? _bearingBetween(from, to) ?? _heading,
//         serviceType,
//       );
//       return;
//     }
//
//     _moveTimers.remove(driverId)?.cancel();
//
//     final durationMs = meters.clamp(600, 1600).toInt();
//     final steps = (durationMs / _animStepMs).clamp(1, 60).round();
//
//     int i = 0;
//     final startHeading = _driverMarkers[driverId]?.rotation ?? 0.0;
//     final computedBearing = _bearingBetween(from, to);
//     final endHeading = serverHeading ?? computedBearing ?? startHeading;
//
//     _moveTimers[driverId] = Timer.periodic(
//       const Duration(milliseconds: _animStepMs),
//           (timer) {
//         i++;
//         double t = (i / steps).clamp(0.0, 1.0);
//         t = _easeInOutCubic(t);
//
//         final pos = _lerpLatLng(from, to, t);
//         final rot = _lerpAngleDeg(startHeading, endHeading, t);
//
//         _updateDriverMarkerPosition(driverId, pos, rot, serviceType);
//
//         if (t >= 1.0) {
//           timer.cancel();
//           _moveTimers.remove(driverId);
//         }
//       },
//     );
//   }
//
//   void _updateDriverMarkerPosition(
//       String driverId,
//       LatLng pos,
//       double rotation,
//       String serviceType,
//       ) {
//     _driverMarkers[driverId] = Marker(
//       markerId: MarkerId(driverId),
//       position: pos,
//       icon: _iconForRideType(serviceType),
//       anchor: const Offset(0.5, 0.5),
//       flat: true,
//       rotation: (rotation + 360) % 360,
//     );
//
//     _lastPos[driverId] = pos;
//     _publishMarkers();
//   }
//
//   void _publishMarkers() {
//     markers.assignAll(_driverMarkers.values.toSet());
//   }
//
//   // -------------------- MATH HELPERS --------------------
//
//   double _degreesToRadians(double degrees) => degrees * math.pi / 180;
//
//   double _haversineMeters(LatLng from, LatLng to) {
//     const double R = 6371000;
//     final dLat = _degreesToRadians(to.latitude - from.latitude);
//     final dLng = _degreesToRadians(to.longitude - from.longitude);
//
//     final a =
//         math.sin(dLat / 2) * math.sin(dLat / 2) +
//             math.cos(_degreesToRadians(from.latitude)) *
//                 math.cos(_degreesToRadians(to.latitude)) *
//                 math.sin(dLng / 2) *
//                 math.sin(dLng / 2);
//
//     final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
//     return R * c;
//   }
//
//   double? _bearingBetween(LatLng from, LatLng to) {
//     final lat1 = _degreesToRadians(from.latitude);
//     final lon1 = _degreesToRadians(from.longitude);
//     final lat2 = _degreesToRadians(to.latitude);
//     final lon2 = _degreesToRadians(to.longitude);
//
//     final dLon = lon2 - lon1;
//     final y = math.sin(dLon) * math.cos(lat2);
//     final x =
//         math.cos(lat1) * math.sin(lat2) -
//             math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
//
//     return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
//   }
//
//   double _easeInOutCubic(double t) =>
//       t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3).toDouble() / 2;
//
//   LatLng _lerpLatLng(LatLng a, LatLng b, double t) {
//     final lat = a.latitude + (b.latitude - a.latitude) * t;
//     final lng = a.longitude + (b.longitude - a.longitude) * t;
//     return LatLng(lat, lng);
//   }
//
//   double _lerpAngleDeg(double start, double end, double t) {
//     double delta = (end - start) % 360;
//     if (delta > 180) delta -= 360;
//     return (start + delta * t) % 360;
//   }
// }


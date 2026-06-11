import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

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
import 'package:hopper/uitls/map/compact_marker_icons.dart';
import 'package:hopper/uitls/map/map_ui_defaults.dart';
import 'package:hopper/uitls/map/route_tracking_math.dart';
import 'package:hopper/uitls/websocket/socket_io_client.dart';
import 'package:hopper/uitls/websocket/shared_web_socket.dart';

class HomeMapController extends GetxController with WidgetsBindingObserver {
  // This custom pulse updates GoogleMap `circles`, which triggers frequent
  // platform-view redraws on Android and can cause jank / `lockHardwareCanvas`
  // spam on some devices. Enabled by request; emission is throttled inside
  // `_refreshMyLocationPulseCircles()` to minimize churn.
  static const bool _enableCustomLocationPulse = true;

  final LocationGateController gate = Get.find<LocationGateController>();
  final SocketService socketService = SocketService();
  final RideShareSocketService rideShareSocket = RideShareSocketService();

  GoogleMapController? mapController;

  final RxSet<Marker> markers = <Marker>{}.obs;
  final RxSet<Circle> circles = <Circle>{}.obs;
  final RxInt markersRevision = 0.obs;
  final RxString address = 'Fetching your location...'.obs;

  final RxList<PopularPlace> popularPlaces = <PopularPlace>[].obs;
  final RxList<RecentLocation> recentLocations = <RecentLocation>[].obs;

  String customerId = '';
  final Rxn<LatLng> _currentPosition = Rxn<LatLng>();
  LatLng? get currentPosition => _currentPosition.value;
  set currentPosition(LatLng? pos) {
    _currentPosition.value = pos;
    _persistLastLocationDebounced(pos);
  }

  String? mapStyle;

  CameraPosition? _lastCamera;
  bool _suppressNextIdle = false;

  LatLng? get cameraTarget => _lastCamera?.target;

  final Map<String, String> _geocodeCache = {};
  Timer? _geocodeDebounce;
  LatLng? _lastGeocodedPos;

  bool _loadingLocation = false;
  bool _started = false;
  bool _restoredFromPrefs = false;

  static const double _homeInitZoom = 17.2;

  double _heading = 0.0;
  StreamSubscription<CompassEvent>? _compassSub;
  Timer? _compassThrottle;
  Worker? _gateReadyWorker;
  StreamSubscription<Position>? _positionSub;
  final Rxn<LatLng> _devicePosition = Rxn<LatLng>();
  DateTime? _devicePositionAt;
  Timer? _persistDebounce;
  Timer? _pulseTimer;
  DateTime _lastCameraMoveAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Overlay pulse (Flutter layer) uses this controller-provided screen offset.
  // This avoids frequent platform-view updates (GoogleMap circles), which can
  // feel laggy on Android.
  final Rxn<Offset> pulseOffset = Rxn<Offset>();

  Timer? _pulseOffsetDebounce;
  LatLng? _lastPulseLatLng;
  DateTime _lastPulseOffsetAt = DateTime.fromMillisecondsSinceEpoch(0);

  static const int _pulseTickMs = 900; // recompute screen coordinate

  LatLng? get devicePosition => _devicePosition.value;

  BitmapDescriptor? _carIcon, _bikeIcon;
  final BitmapDescriptor _fallbackIcon = BitmapDescriptor.defaultMarker;

  final Map<String, Marker> _driverMarkers = {};
  final Map<String, String> _driverTypes = {};
  final Map<String, LatLng> _lastPos = {};
  final Map<String, Timer> _moveTimers = {};
  final Map<String, DateTime> _lastSocketProcessedAt = {};
  Timer? _publishDebounce;
  Timer? _staleDriverGcTimer;

  static const int _socketThrottleMs = 250;
  // Smoother nearby-driver animation (Uber/Ola-like).
  // Keep this relatively high-FPS; markers are lightweight and count is small.
  static const int _animStepMs = 25; // ~40 fps

  // Debounce micro updates: ignore <5m moves to avoid jitter + churn.
  static const double _ignoreMoveMeters = 5.0;
  static const double _overlapDetectMeters = 6.0;
  static const double _overlapSpreadMeters = 4.5;

  static const double _reverseGeocodeMinMoveMeters = 15.0;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _preloadMapStyle();
    _startCompassListener();
    _restoreLastLocationFromPrefs();

    // If HomeMapController.start() runs before location permission is granted,
    // initLocation() will early-return. This ensures we fetch & center as soon as
    // the gate becomes ready, avoiding a blank/0,0 map on first open.
    _gateReadyWorker = ever<bool>(gate.isReady, (ready) {
      if (!ready) {
        _stopPositionStream();
        _stopMyLocationPulse();
        return;
      }

      _startPositionStream();
      _startMyLocationPulse();
      // If we previously restored a stale last-known map location (from prefs)
      // before permission was granted, we must still recenter to live GPS once
      // the gate becomes ready.
      if (currentPosition == null || _restoredFromPrefs) {
        initLocation();
      }
    });
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _geocodeDebounce?.cancel();
    _publishDebounce?.cancel();
    _staleDriverGcTimer?.cancel();
    _compassThrottle?.cancel();
    _compassSub?.cancel();
    _gateReadyWorker?.dispose();
    _stopPositionStream();
    _persistDebounce?.cancel();
    _pulseTimer?.cancel();
    _pulseOffsetDebounce?.cancel();

    for (final t in _moveTimers.values) {
      t.cancel();
    }
    _moveTimers.clear();

    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Avoid burning CPU / platform-view updates while backgrounded.
    if (state == AppLifecycleState.resumed) {
      if (gate.isReady.value) _startMyLocationPulse();
    } else {
      _stopMyLocationPulse();
    }
  }

  void _startMyLocationPulse() {
    if (!_enableCustomLocationPulse) {
      _stopMyLocationPulse();
      return;
    }
    if (!gate.isReady.value) return;
    _pulseTimer?.cancel();
    // Keep the pulse light; frequent platform-view updates can cause jank/hangs
    // on some Android devices (and spam `lockHardwareCanvas` in logcat).
    _pulseTimer = Timer.periodic(
      const Duration(milliseconds: _pulseTickMs),
      (_) => _refreshMyLocationPulseCircles(),
    );
    _refreshMyLocationPulseCircles();
  }

  void _stopMyLocationPulse() {
    _pulseTimer?.cancel();
    _pulseTimer = null;
    _pulseOffsetDebounce?.cancel();
    _pulseOffsetDebounce = null;
    if (circles.isNotEmpty) circles.clear();
    pulseOffset.value = null;
  }

  void _refreshMyLocationPulseCircles() {
    // Only show when permission is granted (myLocationEnabled is on).
    if (!gate.isReady.value) {
      if (circles.isNotEmpty) circles.clear();
      pulseOffset.value = null;
      return;
    }

    // Prefer live device stream (matches blue dot), fallback to last known.
    final now = DateTime.now();
    final hasFreshDevicePos =
        devicePosition != null &&
        _devicePositionAt != null &&
        now.difference(_devicePositionAt!).inSeconds <= 10;

    // If we're showing a restored-from-prefs map position, avoid rendering the
    // pulsing ring until we have a fresh live GPS point. Otherwise the ring
    // "jumps" when live GPS arrives.
    if (_restoredFromPrefs && !hasFreshDevicePos) {
      if (circles.isNotEmpty) circles.clear();
      return;
    }

    final LatLng? center = hasFreshDevicePos ? devicePosition : currentPosition;
    if (center == null) {
      if (circles.isNotEmpty) circles.clear();
      pulseOffset.value = null;
      return;
    }

    // We no longer drive a pulsing ring via GoogleMap circles (platform view),
    // because it feels laggy. Keep circles empty and compute the on-screen
    // coordinate so a Flutter overlay can animate smoothly.
    if (circles.isNotEmpty) circles.clear();
    final mc = mapController;
    if (mc == null) return;

    // While the user is actively panning/zooming the map, skip platform calls.
    if (now.difference(_lastCameraMoveAt).inMilliseconds < 900) return;

    final moved =
        _lastPulseLatLng == null ? double.infinity : _haversineMeters(_lastPulseLatLng!, center);
    if (moved < 1.5 && now.difference(_lastPulseOffsetAt).inMilliseconds < 900) {
      return;
    }

    // Throttle coordinate lookups (async platform call).
    _pulseOffsetDebounce?.cancel();
    _pulseOffsetDebounce = Timer(const Duration(milliseconds: 120), () async {
      final mc2 = mapController;
      if (mc2 == null) return;
      if (!gate.isReady.value) return;
      try {
        final sc = await mc2.getScreenCoordinate(center);
        pulseOffset.value = Offset(sc.x.toDouble(), sc.y.toDouble());
        _lastPulseLatLng = center;
        _lastPulseOffsetAt = DateTime.now();
      } catch (_) {}
    });
  }

  void _startPositionStream() {
    if (_positionSub != null) return;

    try {
      const settings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      );

      _positionSub = Geolocator.getPositionStream(
        locationSettings: settings,
      ).listen((pos) {
        _devicePosition.value = LatLng(pos.latitude, pos.longitude);
        _devicePositionAt = DateTime.now();
        if (_enableCustomLocationPulse) _refreshMyLocationPulseCircles();
      });
    } catch (_) {
      // ignore stream errors; app should still work with getCurrentPosition()
    }
  }

  void _stopPositionStream() {
    _positionSub?.cancel();
    _positionSub = null;
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;

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

    if (_enableCustomLocationPulse) {
      _refreshMyLocationPulseCircles();
    }

    // ✅ Important for home map: if currentPosition already available, move camera now
    if (currentPosition != null) {
      try {
        _lastCamera = CameraPosition(
          target: currentPosition!,
          zoom: _homeInitZoom,
        );
        await mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(currentPosition!, _homeInitZoom),
        );
      } catch (_) {}
    } else {
      await initLocation();
    }
  }

  void onCameraMove(CameraPosition position) {
    _lastCamera = position;
    _lastCameraMoveAt = DateTime.now();
  }

  ScreenCoordinate _pinTipScreenCoordinate({
    required Size mapSize,
    required double pinAlignY,
    required double pinWidgetHeightPx,
  }) {
    final centerX = (mapSize.width / 2).round();

    // Align computes top-left based on (parent - child) size.
    // Pin tip is at the bottom of the pin widget.
    final childTopY =
        ((pinAlignY + 1) / 2) * (mapSize.height - pinWidgetHeightPx);
    final pinTipY = childTopY + pinWidgetHeightPx;
    final pinY = pinTipY.round().clamp(0, mapSize.height.round());

    return ScreenCoordinate(x: centerX, y: pinY);
  }

  Future<String?> onCameraIdle({
    bool immediateGeocode = false,
    bool suppressible = true,
  }) async {
    if (suppressible && _suppressNextIdle) {
      _suppressNextIdle = false;
      return null;
    }

    final cam = _lastCamera;
    if (cam == null) return null;

    final newPos = cam.target;

    if (currentPosition != null) {
      final moved = _haversineMeters(currentPosition!, newPos);
      if (moved < _reverseGeocodeMinMoveMeters) {
        return address.value;
      }
    }

    currentPosition = newPos;

    if (immediateGeocode) {
      return await _geocodeNow(newPos);
    }

    _scheduleReverseGeocode(newPos);
    return null;
  }

  /// Home screen uses a "floating pin" that is not at screen center (because of
  /// the bottom sheet). This maps camera movement to the actual LatLng under
  /// the pin tip, so the pin location matches the blue GPS dot when centered.
  Future<String?> onCameraIdlePinned({
    required Size mapSize,
    required double pinAlignY,
    required double pinWidgetHeightPx,
    bool immediateGeocode = false,
    bool suppressible = true,
  }) async {
    if (suppressible && _suppressNextIdle) {
      _suppressNextIdle = false;
      return null;
    }

    final controller = mapController;
    if (controller == null) return null;

    LatLng newPos;
    try {
      final sc = _pinTipScreenCoordinate(
        mapSize: mapSize,
        pinAlignY: pinAlignY,
        pinWidgetHeightPx: pinWidgetHeightPx,
      );
      newPos = await controller.getLatLng(sc);
    } catch (_) {
      // Fallback to center target if getLatLng fails.
      final cam = _lastCamera;
      if (cam == null) return null;
      newPos = cam.target;
    }

    if (currentPosition != null) {
      final moved = _haversineMeters(currentPosition!, newPos);
      if (moved < _reverseGeocodeMinMoveMeters) {
        return address.value;
      }
    }

    currentPosition = newPos;

    if (immediateGeocode) {
      return await _geocodeNow(newPos);
    }

    _scheduleReverseGeocode(newPos);
    return null;
  }

  Future<String?> onCameraIdleAt({
    required ScreenCoordinate pinTip,
    bool immediateGeocode = false,
    bool suppressible = true,
  }) async {
    if (suppressible && _suppressNextIdle) {
      _suppressNextIdle = false;
      return null;
    }

    final controller = mapController;
    if (controller == null) return null;

    LatLng newPos;
    try {
      newPos = await controller.getLatLng(pinTip);
    } catch (_) {
      final cam = _lastCamera;
      if (cam == null) return null;
      newPos = cam.target;
    }

    if (currentPosition != null) {
      final moved = _haversineMeters(currentPosition!, newPos);
      if (moved < _reverseGeocodeMinMoveMeters) {
        return address.value;
      }
    }

    currentPosition = newPos;

    if (immediateGeocode) {
      return await _geocodeNow(newPos);
    }

    _scheduleReverseGeocode(newPos);
    return null;
  }

  /// Move the camera so that [currentPosition] sits exactly under the pin tip.
  /// This is pixel-accurate and avoids "pin vs blue dot" mismatch.
  Future<void> alignCameraToPinnedUnderPin({
    required Size mapSize,
    required double pinAlignY,
    required double pinWidgetHeightPx,
  }) async {
    final pos = currentPosition;
    final controller = mapController;
    if (pos == null || controller == null) return;

    try {
      final scPin = _pinTipScreenCoordinate(
        mapSize: mapSize,
        pinAlignY: pinAlignY,
        pinWidgetHeightPx: pinWidgetHeightPx,
      );

      final scBefore = await controller.getScreenCoordinate(pos);
      var dx = (scPin.x - scBefore.x).toDouble();
      var dy = (scPin.y - scBefore.y).toDouble();
      if (dx.abs() + dy.abs() < 2.0) return;

      // First attempt.
      _suppressNextIdle = true;
      await controller.animateCamera(CameraUpdate.scrollBy(dx, dy));

      final scAfter1 = await controller.getScreenCoordinate(pos);
      final dxRemain1 = (scPin.x - scAfter1.x).toDouble();
      final dyRemain1 = (scPin.y - scAfter1.y).toDouble();
      if (dxRemain1.abs() + dyRemain1.abs() < 2.0) return;

      // If scrollBy units/sign differ, estimate how much the feature moved vs
      // requested scroll, then apply a corrected second scroll.
      final movedX = (scAfter1.x - scBefore.x).toDouble();
      final movedY = (scAfter1.y - scBefore.y).toDouble();

      final kx = dx.abs() > 0.5 ? (movedX / dx) : 0.0;
      final ky = dy.abs() > 0.5 ? (movedY / dy) : 0.0;

      final dx2 =
          (kx.abs() < 0.05)
              ? dxRemain1
              : (dxRemain1 / kx).clamp(-1200.0, 1200.0);
      final dy2 =
          (ky.abs() < 0.05)
              ? dyRemain1
              : (dyRemain1 / ky).clamp(-1200.0, 1200.0);

      if (dx2.abs() + dy2.abs() < 1.0) return;
      _suppressNextIdle = true;
      await controller.animateCamera(CameraUpdate.scrollBy(dx2, dy2));
    } catch (_) {}
  }

  Future<void> alignCameraToPinTip({required ScreenCoordinate pinTip}) async {
    final pos = currentPosition;
    final controller = mapController;
    if (pos == null || controller == null) return;

    try {
      final scBefore = await controller.getScreenCoordinate(pos);
      var dx = (pinTip.x - scBefore.x).toDouble();
      var dy = (pinTip.y - scBefore.y).toDouble();
      if (dx.abs() + dy.abs() < 2.0) return;

      // First attempt.
      _suppressNextIdle = true;
      await controller.animateCamera(CameraUpdate.scrollBy(dx, dy));

      final scAfter1 = await controller.getScreenCoordinate(pos);
      final dxRemain1 = (pinTip.x - scAfter1.x).toDouble();
      final dyRemain1 = (pinTip.y - scAfter1.y).toDouble();
      if (dxRemain1.abs() + dyRemain1.abs() < 2.0) return;

      // Estimate the effective scroll factor (handles sign / DPR issues).
      final movedX = (scAfter1.x - scBefore.x).toDouble();
      final movedY = (scAfter1.y - scBefore.y).toDouble();

      final kx = dx.abs() > 0.5 ? (movedX / dx) : 0.0;
      final ky = dy.abs() > 0.5 ? (movedY / dy) : 0.0;

      final dx2 =
          (kx.abs() < 0.05)
              ? dxRemain1
              : (dxRemain1 / kx).clamp(-1200.0, 1200.0);
      final dy2 =
          (ky.abs() < 0.05)
              ? dyRemain1
              : (dyRemain1 / ky).clamp(-1200.0, 1200.0);

      if (dx2.abs() + dy2.abs() < 1.0) return;
      _suppressNextIdle = true;
      await controller.animateCamera(CameraUpdate.scrollBy(dx2, dy2));
    } catch (_) {}
  }

  /// Recenter the camera so that [latLng] appears exactly under [desiredPoint]
  /// on the screen. Uses `getLatLng()` iterations to avoid `scrollBy`
  /// direction/scale differences between platforms.
  Future<void> placeLatLngUnderScreenPoint({
    required LatLng latLng,
    required ScreenCoordinate desiredPoint,
    required ScreenCoordinate centerPoint,
  }) async {
    final controller = mapController;
    if (controller == null) return;

    try {
      for (var i = 0; i < 3; i++) {
        final underPin = await controller.getLatLng(desiredPoint);
        final centerLatLng = await controller.getLatLng(centerPoint);

        if (_haversineMeters(latLng, underPin) < 2.5) return;

        final dLat = latLng.latitude - underPin.latitude;
        final dLng = latLng.longitude - underPin.longitude;

        final newTarget = LatLng(
          centerLatLng.latitude + dLat,
          centerLatLng.longitude + dLng,
        );

        _suppressNextIdle = true;
        await controller.animateCamera(CameraUpdate.newLatLng(newTarget));
      }
    } catch (_) {}
  }

  Future<void> _preloadMapStyle() async {
    try {
      mapStyle = await rootBundle.loadString(
        'assets/map_style.json',
      );
      try {
        if (mapController != null && mapStyle != null) {
          await mapController?.setMapStyle(mapStyle);
        }
      } catch (_) {}
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

    // Shared-ride socket: connect from Home itself (not only after booking confirm)
    // so the shared flow feels instant.
    rideShareSocket.initSocket(ApiConsents.sharedBaseUrl);
    rideShareSocket.registerUser(customerId);

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

    // Shared-ride backend nearby updates (show on the same home map too).
    rideShareSocket.on('nearby-driver-update', (data) {
      final String driverId = 'shared_${(data['driverId'] ?? '').toString()}';
      if (driverId == 'shared_') return;

      final now = DateTime.now().toUtc();
      final last = _lastSocketProcessedAt[driverId];
      if (last != null &&
          now.difference(last).inMilliseconds < _socketThrottleMs) {
        return;
      }
      _lastSocketProcessedAt[driverId] = now;

      final latRaw = data['latitude'];
      final lngRaw = data['longitude'];
      if (latRaw is! num || lngRaw is! num) return;
      final double lat = latRaw.toDouble();
      final double lng = lngRaw.toDouble();

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

    rideShareSocket.on('remove-nearby-driver', (data) {
      final raw = (data['driverId'] ?? '').toString();
      if (raw.trim().isEmpty) return;
      final driverId = 'shared_$raw';

      _moveTimers.remove(driverId)?.cancel();
      _driverMarkers.remove(driverId);
      _driverTypes.remove(driverId);
      _lastPos.remove(driverId);
      _lastSocketProcessedAt.remove(driverId);

      _publishMarkersDebounced();
    });

    // Safety net: expire markers whose driver has gone silent (missed removal).
    _startStaleDriverGc();
  }

  Future<bool> _ensureLocationReady() async => gate.isReady.value;

  Future<Position?> _safeGetCurrentPosition() async {
    if (!await _ensureLocationReady()) return null;
    try {
      // Quick path first (much faster on cold GPS).
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return last;

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
    } on LocationServiceDisabledException {
      return null;
    } on TimeoutException {
      // Try last known again on timeout.
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  Future<void> initLocation() async {
    if (_loadingLocation) return;
    _loadingLocation = true;

    try {
      // If we already have a recent live GPS value, use it immediately.
      final now = DateTime.now();
      if (devicePosition != null &&
          _devicePositionAt != null &&
          now.difference(_devicePositionAt!).inSeconds <= 12) {
        currentPosition = devicePosition;
      }

      final pos = await _safeGetCurrentPosition();
      if (pos == null) return;

      currentPosition = LatLng(pos.latitude, pos.longitude);
      _restoredFromPrefs = false;
      _lastCamera = CameraPosition(
        target: currentPosition!,
        zoom: _homeInitZoom,
      );

      try {
        await mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: currentPosition!, zoom: _homeInitZoom),
          ),
        );
      } catch (_) {}

      await _geocodeNow(currentPosition!);
      await fetchPopularPlaces(currentPosition!);
    } finally {
      _loadingLocation = false;
    }
  }

  Future<void> goToCurrentLocation() async {
    // Prefer the live stream value (matches the blue dot better), fallback to
    // one-shot location.
    late final LatLng latLng;
    final now = DateTime.now();
    if (devicePosition != null &&
        _devicePositionAt != null &&
        now.difference(_devicePositionAt!).inSeconds <= 8) {
      latLng = devicePosition!;
    } else {
      final pos = await _safeGetCurrentPosition();
      if (pos == null) return;
      latLng = LatLng(pos.latitude, pos.longitude);
      _devicePosition.value = latLng;
      _devicePositionAt = now;
    }

    currentPosition = latLng;
    _restoredFromPrefs = false;
    _lastCamera = CameraPosition(target: latLng, zoom: 17.5);

    try {
      // Prevent home onCameraIdle from overwriting [currentPosition] while we're
      // doing a programmatic "go to GPS" camera move.
      _suppressNextIdle = true;
      await mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(latLng, 17.5),
      );
    } catch (_) {}

    await _geocodeNow(latLng);
  }

  void _persistLastLocationDebounced(LatLng? pos) {
    if (pos == null) return;
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 900), () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('home_last_lat', pos.latitude);
        await prefs.setDouble('home_last_lng', pos.longitude);
        await prefs.setString('home_last_address', address.value);
      } catch (_) {}
    });
  }

  void _restoreLastLocationFromPrefs() {
    Future<void>(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final lat = prefs.getDouble('home_last_lat');
        final lng = prefs.getDouble('home_last_lng');
        final addr = prefs.getString('home_last_address');

        if (lat != null && lng != null && currentPosition == null) {
          currentPosition = LatLng(lat, lng);
          _restoredFromPrefs = true;
          _lastCamera = CameraPosition(target: currentPosition!, zoom: 15);
        }
        if (addr != null && addr.trim().isNotEmpty) {
          address.value = addr;
        }
      } catch (_) {}
    });
  }

  Future<String> getAddressFromLatLng(LatLng position) async {
    final key =
        '${position.latitude.toStringAsFixed(5)},${position.longitude.toStringAsFixed(5)}';

    final cached = _geocodeCache[key];
    if (cached != null) {
      address.value = cached;
      return cached;
    }

    return await _geocodeNow(position);
  }

  Future<void> centerCameraOnPinnedPosition() async {
    final pos = currentPosition;
    final controller = mapController;
    if (pos == null || controller == null) return;

    _suppressNextIdle = true;
    try {
      await controller.animateCamera(CameraUpdate.newLatLng(pos));
    } catch (_) {}
  }

  Future<void> offsetCameraToKeepPinnedUnderPin({
    required Size mapSize,
    required double pinAlignY,
    double pinTipYOffsetPx = 28,
  }) async {
    final pos = currentPosition;
    final controller = mapController;
    if (pos == null || controller == null) return;

    // Compute the screen point symmetric to the pin around center,
    // then move camera so the pinned location stays under the shifted pin.
    final centerX = (mapSize.width / 2).round();
    final centerY = (mapSize.height / 2).round();

    final rawPinY = (((pinAlignY + 1) / 2) * mapSize.height) + pinTipYOffsetPx;
    final pinY = rawPinY.round().clamp(0, mapSize.height.round());
    final belowY = (2 * centerY - pinY).clamp(0, mapSize.height.round());

    try {
      final target = await controller.getLatLng(
        ScreenCoordinate(x: centerX, y: belowY),
      );
      _suppressNextIdle = true;
      await controller.animateCamera(CameraUpdate.newLatLng(target));
    } catch (_) {}
  }

  Future<String> _geocodeNow(LatLng pos) async {
    _geocodeDebounce?.cancel();

    if (_lastGeocodedPos != null) {
      final moved = _haversineMeters(_lastGeocodedPos!, pos);
      if (moved < _reverseGeocodeMinMoveMeters) {
        return address.value;
      }
    }

    _lastGeocodedPos = pos;

    final key =
        '${pos.latitude.toStringAsFixed(5)},${pos.longitude.toStringAsFixed(5)}';
    final cached = _geocodeCache[key];
    if (cached != null) {
      address.value = cached;
      return cached;
    }

    final value = await _reverseGeocode(pos);
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
        final street =
            [
              (p.subThoroughfare ?? '').trim(),
              (p.thoroughfare ?? '').trim(),
            ].where((e) => e.isNotEmpty).join(' ').trim();

        final primary = street.isNotEmpty ? street : (p.name ?? '').trim();

        final parts =
            <String>[
              primary,
              (p.subLocality ?? '').trim(),
              (p.locality ?? '').trim(),
            ].where((e) => e.isNotEmpty).toList();

        final value = parts.join(', ');
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
    // Rank by prominence within a reasonable radius -> genuinely "nearby +
    // popular" destinations (malls, transit hubs, landmarks, hospitals…),
    // not just the closest bus stop. We then categorise, drop noise, dedupe
    // and keep a diverse set of 4.
    final url =
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
        '?location=${location.latitude},${location.longitude}'
        '&rankby=prominence&radius=12000&type=point_of_interest&key=$apiKey';

    try {
      final response = await http.get(Uri.parse(url));
      final data = json.decode(response.body);

      if (data['status'] == 'OK') {
        final results = (data['results'] as List);
        final seenName = <String>{};
        final seenCategory = <String>{};
        final list = <PopularPlace>[];

        // First pass: prefer category variety (one per category) so the
        // 4 shown feel diverse and useful.
        for (final pass in [true, false]) {
          for (final place in results) {
            if (list.length >= 4) break;
            final types =
                (place['types'] as List?)?.cast<String>() ?? const <String>[];
            final category = _popularCategoryFromTypes(types);
            if (category == null) continue; // noise -> skip
            final name = (place['name'] ?? '').toString().trim();
            if (name.isEmpty) continue;
            final nameKey = name.toLowerCase();
            if (seenName.contains(nameKey)) continue;
            // Pass 1 enforces one-per-category for variety; pass 2 fills up.
            if (pass && seenCategory.contains(category)) continue;

            seenName.add(nameKey);
            seenCategory.add(category);
            list.add(
              PopularPlace(
                name: name,
                address: (place['vicinity'] ?? '').toString(),
                lat: place['geometry']['location']['lat'],
                lng: place['geometry']['location']['lng'],
                category: category,
              ),
            );
          }
          if (list.length >= 4) break;
        }

        popularPlaces.assignAll(list);
      }
    } catch (_) {}
  }

  /// Maps Google place `types` to one of our category keys. Returns null for
  /// low-value noise (ATMs, parking, fuel…) so it's filtered out.
  String? _popularCategoryFromTypes(List<String> types) {
    const noise = {
      'atm',
      'parking',
      'gas_station',
      'bus_stop',
      'convenience_store',
      'car_repair',
      'car_dealer',
      'storage',
      'moving_company',
      'finance',
      'accounting',
      'laundry',
      'real_estate_agency',
    };
    if (types.any(noise.contains)) return null;

    bool has(String t) => types.contains(t);
    if (has('airport')) return 'airport';
    if (has('train_station') ||
        has('subway_station') ||
        has('light_rail_station')) {
      return 'train';
    }
    if (has('bus_station') || has('transit_station')) return 'bus';
    if (has('shopping_mall') || has('department_store')) return 'mall';
    if (has('hospital') || has('pharmacy') || has('doctor')) return 'hospital';
    if (has('university') || has('school')) return 'school';
    if (has('stadium')) return 'stadium';
    if (has('park')) return 'park';
    if (has('lodging')) return 'hotel';
    if (has('tourist_attraction') ||
        has('museum') ||
        has('art_gallery') ||
        has('zoo')) {
      return 'attraction';
    }
    if (has('restaurant') || has('cafe')) return 'food';
    if (has('place_of_worship') ||
        has('church') ||
        has('mosque') ||
        has('hindu_temple')) {
      return 'worship';
    }
    if (has('point_of_interest') || has('establishment')) return 'place';
    return null;
  }

  Future<void> _loadDriverIcons() async {
    _carIcon = await CompactMarkerIcons.assetPin(
      assetPath: AppImages.movingCar,
      widthDp: MapUiDefaults.vehicleCarWidthDp,
    );
    _bikeIcon = await CompactMarkerIcons.assetPin(
      assetPath: AppImages.packageBike,
      widthDp: MapUiDefaults.vehicleBikeWidthDp,
    );

    _driverMarkers.updateAll((id, old) {
      final t = _driverTypes[id] ?? 'car';
      return old.copyWith(iconParam: _iconForRideType(t));
    });

    _publishMarkersDebounced();
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
      markers.assignAll(_buildPublishedDriverMarkers());
      markersRevision.value++;
    });
  }

  // ---------------- stale-driver GC (safety net) ----------------
  // A nearby-driver car marker must never get "stuck" if a `remove-nearby-driver`
  // event is missed (e.g. during a socket reconnect / network blip). Every 15s we
  // drop any driver we haven't heard from in >90s. 90s is comfortably above the
  // live-driver heartbeat (~25s), so a genuinely live driver is never GC'd — only
  // ones that have actually gone away. On reconnect the backend also re-sends a
  // fresh nearby snapshot which reconciles the set; this GC just guarantees the
  // cleanup happens even when that snapshot is delayed or missed.
  static const Duration _staleDriverGcInterval = Duration(seconds: 15);
  static const Duration _staleDriverTtl = Duration(seconds: 90);

  void _startStaleDriverGc() {
    _staleDriverGcTimer?.cancel();
    _staleDriverGcTimer = Timer.periodic(
      _staleDriverGcInterval,
      (_) => _sweepStaleDrivers(),
    );
  }

  void _sweepStaleDrivers() {
    if (_driverMarkers.isEmpty) return;

    // _lastSocketProcessedAt is stored in UTC (see the nearby-driver handlers).
    final now = DateTime.now().toUtc();
    // Collect first, then remove, so we don't mutate _driverMarkers while iterating.
    final stale = <String>[];
    for (final driverId in _driverMarkers.keys) {
      final last = _lastSocketProcessedAt[driverId];
      if (last != null && now.difference(last) > _staleDriverTtl) {
        stale.add(driverId);
      }
    }
    if (stale.isEmpty) return;

    for (final driverId in stale) {
      // Mirror the `remove-nearby-driver` handler exactly.
      _moveTimers.remove(driverId)?.cancel();
      _driverMarkers.remove(driverId);
      _driverTypes.remove(driverId);
      _lastPos.remove(driverId);
      _lastSocketProcessedAt.remove(driverId);
    }
    _publishMarkersDebounced();
  }

  Set<Marker> _buildPublishedDriverMarkers() {
    final entries =
        _driverMarkers.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));

    final groups = <List<MapEntry<String, Marker>>>[];
    for (final entry in entries) {
      bool added = false;
      for (final group in groups) {
        final anchor = group.first.value.position;
        if (_haversineMeters(anchor, entry.value.position) <= _overlapDetectMeters) {
          group.add(entry);
          added = true;
          break;
        }
      }
      if (!added) groups.add(<MapEntry<String, Marker>>[entry]);
    }

    final published = <Marker>{};
    for (final group in groups) {
      if (group.length == 1) {
        published.add(group.first.value);
        continue;
      }

      final center = _groupCenter(group.map((e) => e.value.position).toList());
      for (int i = 0; i < group.length; i++) {
        final entry = group[i];
        final spreadBearing = (360.0 / group.length) * i;
        final adjustedPos = offsetLatLngMeters(
          center,
          spreadBearing,
          _overlapSpreadMeters,
        );
        published.add(
          entry.value.copyWith(
            positionParam: adjustedPos,
            zIndexParam: 10.0 + i,
          ),
        );
      }
    }
    return published;
  }

  LatLng _groupCenter(List<LatLng> points) {
    double lat = 0;
    double lng = 0;
    for (final point in points) {
      lat += point.latitude;
      lng += point.longitude;
    }
    return LatLng(lat / points.length, lng / points.length);
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

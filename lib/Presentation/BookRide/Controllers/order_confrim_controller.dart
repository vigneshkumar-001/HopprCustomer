import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:hopper/api/repository/api_consents.dart';
import 'package:hopper/Presentation/BookRide/Controllers/driver_search_controller.dart';
import 'package:hopper/uitls/map/direction_helper.dart';
import 'package:hopper/uitls/websocket/socket_io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hopper/uitls/map/map_ui_defaults.dart';
import 'package:hopper/uitls/map/compact_marker_icons.dart';

class DriverPose {
  final LatLng latLng;
  final DateTime t;
  final double? bearing;
  DriverPose(this.latLng, {DateTime? t, this.bearing})
    : t = t ?? DateTime.now();
}

class OrderConfirmController extends GetxController
    with GetSingleTickerProviderStateMixin {
  // ---------- inputs ----------
  late final String bookingId;
  late final String pickupAddress;
  late final String destinationAddress;
  late final String carType;

  late final double? baseFare;
  late final double? serviceFare;
  late final double? distanceFare;
  late final double? pickupFare;
  late final double? bookingFee;
  late final double? timeFare;
  String? resumeDriverId;
  bool _iconsReady = false;

  void init({
    required String bookingId,
    required String pickupAddress,
    required String destinationAddress,
    required String carType,
    double? pickupLat,
    double? pickupLng,
    double? dropLat,
    double? dropLng,
    double? baseFare,
    double? serviceFare,
    double? distanceFare,
    double? pickupFare,
    double? bookingFee,
    double? timeFare,
    String? resumeDriverId,
    String? initialDriverName,
    String? initialDriverProfilePic,
    String? initialCarDetails,
    double? initialAmount,
  }) {
    this.bookingId = bookingId;
    this.pickupAddress = pickupAddress;
    this.destinationAddress = destinationAddress;
    this.carType = carType;

    this.baseFare = baseFare;
    this.serviceFare = serviceFare;
    this.distanceFare = distanceFare;
    this.pickupFare = pickupFare;
    this.bookingFee = bookingFee;
    this.timeFare = timeFare;
    this.resumeDriverId = resumeDriverId;
    if ((initialDriverName ?? '').trim().isNotEmpty) {
      driverName.value = initialDriverName!.trim();
    }
    if ((initialDriverProfilePic ?? '').trim().isNotEmpty) {
      profilePic.value = initialDriverProfilePic!.trim();
    }
    if ((initialCarDetails ?? '').trim().isNotEmpty) {
      carDetails.value = initialCarDetails!.trim();
    }
    if (initialAmount != null && initialAmount > 0) {
      amount.value = initialAmount;
    }

    // Ensure pickup point is available immediately for "Finding a driver" UI,
    // even before socket returns `customerLocation`.
    if (pickupLat != null &&
        pickupLng != null &&
        dropLat != null &&
        dropLng != null) {
      customerLatLng = LatLng(pickupLat, pickupLng);
      customerToLatLng = LatLng(dropLat, dropLng);
      _syncPickupMarkerForSearch(force: true);
    }
  }

  // ---------- deps ----------
  final socketService = SocketService();
  final DriverSearchController driverSearchController =
      Get.isRegistered<DriverSearchController>()
          ? Get.find<DriverSearchController>()
          : Get.put(DriverSearchController());
  late final DirectionsHelper _dir;

  // ---------- map ----------
  GoogleMapController? mapController;
  String? mapStyle;
  double currentZoomLevel = 14.9; // matched to driver-side live map zoom
  static const double _minAutoFollowZoom = 15.8;
  BuildContext? _screenCtx;
  Timer? _searchTimer;
  final RxBool focusDriverOnNextTap = false.obs;

  static const double _mapBearingNorth = 0.0;
  static const double _mapTilt = 0.0;

  // Auto camera control (Ola style)
  DateTime _lastCameraMoveAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _cameraInterval = const Duration(milliseconds: 900);
  DateTime _pauseAutoFollowUntil = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _userGesturePause = const Duration(seconds: 6);
  bool _hasFittedAtLeastOnce = false;
  bool _autoFitBoundsEnabled = true;
  bool _didFitDriverAndPickup = false;
  static const double _focusDriverZoom = 16.6;
  DateTime _lastAutoFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _autoFrameInterval = const Duration(milliseconds: 1400);

  // ---------- UI / state ----------
  final RxBool isExpanded = false.obs;

  final RxBool isDriverConfirmed = false.obs;
  final RxBool driverStartedRide = false.obs;
  final RxBool destinationReached = false.obs;
  final RxBool isTripCancelled = false.obs;

  final RxBool isWaitingForDriver = true.obs;
  final RxBool noDriverFound = false.obs;

  final RxString cancelReason = "".obs;

  final RxString plateNumber = "".obs;
  final RxString profilePic = "".obs;
  final RxString carExteriorPhotos = "".obs;
  final RxString driverName = "".obs;
  final RxString carDetails = "".obs;
  final RxString customerPhone = "".obs;
  final RxString cartypeFromServer = "".obs;
  final RxString otp = "".obs;
  final RxDouble amount = 0.0.obs;

  final RxBool driverArrived = false.obs;
  final RxBool nearDestination = false.obs;
  final RxString etaChipText = ''.obs;
  final RxInt etaMinutes = 0.obs;
  final RxInt pickupDurationMin = 0.obs;
  final RxInt dropDurationMin = 0.obs;
  final RxInt tripDurationMin = 0.obs;
  final RxDouble pickupDistanceMeters = 0.0.obs;
  final RxDouble dropDistanceMeters = 0.0.obs;
  final RxString latestRideStatus = 'DRIVER_ACCEPTED'.obs;
  // ---------- markers / polylines ----------
  final RxSet<Marker> markers = <Marker>{}.obs;
  final RxSet<Polyline> polylines = <Polyline>{}.obs;
  final RxSet<Circle> circles = <Circle>{}.obs;

  BitmapDescriptor? carIcon;
  BitmapDescriptor? bikeIcon;

  // Pickup/drop image icons
  // Pickup/drop compact image pins (like home map).
  BitmapDescriptor? pickupPinIcon;
  BitmapDescriptor? dropPinIcon;
  BitmapDescriptor? pickupWaitingLabelIcon;

  String _pickupMarkerVariant = 'dot';
  bool _locationToggleFit = false;

  LatLng? currentPosition;
  LatLng? customerLatLng; // pickup
  LatLng? customerToLatLng; // drop

  // Throttle driver marker updates to avoid rebuilding GoogleMap every frame.
  // `_updateDriverMarker` is called on every animation tick (up to ~60fps).
  // Rebuilding the platform view that often causes jank/white-map flashes.
  static const Duration _driverMarkerMinInterval = Duration(milliseconds: 120);
  DateTime _lastDriverMarkerAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _driverMarkerFlushTimer;
  LatLng? _pendingDriverMarkerPos;
  double? _pendingDriverMarkerBearing;

  bool _isRideStartedStatus(String status) {
    final s = status.trim().toUpperCase();
    return s == 'STARTED' || s == 'RIDE_STARTED' || s == 'TRIP_STARTED';
  }

  // =================================================================
  //                  SMOOTH DRIVER ENGINE
  // =================================================================
  final Duration _playbackDelay = const Duration(milliseconds: 600);
  final List<DriverPose> _poseQueue = <DriverPose>[];
  late final AnimationController _moveCtrl;

  bool _isAnimatingSegment = false;

  LatLng? _lastReceivedPos;
  LatLng? _displayPos;

  final int _maxQueue = 10;
  final Duration _maxStale = const Duration(seconds: 20); // little relaxed
  final Duration _minSeg = const Duration(milliseconds: 450);
  final Duration _maxSeg = const Duration(milliseconds: 1200);

  LatLng? _emaPos;
  final double _emaAlphaSlow = 0.12;
  final double _emaAlphaFast = 0.30;

  double _lastBearing = 0.0;
  final double _bearingEmaAlpha = 0.20;
  final double _maxTurnDegPerSec = 220.0;

  final Curve _ease = Curves.easeInOutCubic;
  VoidCallback? _activeTick;

  // Hard filter to stop "teleport jump"
  final double _hardJumpMeters =
      120.0; // if server point jumps > 120m => ignore
  final double _minMoveMeters = 1.2; // ignore micro jitter

  // =================================================================
  //                        POLYLINE CONTROL
  // =================================================================
  DateTime _lastPolylineAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _polylineInterval = const Duration(seconds: 25);

  bool _isDrawingPolyline = false;
  String? _activePolyId;

  bool _seededPickupMarker = false;
  bool _seededDropMarker = false;
  Timer? _pulseTimer;
  DateTime _pulseStartAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void onInit() {
    super.onInit();
    _moveCtrl = AnimationController(vsync: this);
    _dir = DirectionsHelper(apiKey: ApiConsents.googleMapApiKey);
    _loadMapStyle();
    _boot();
  }

  Future<void> _boot() async {
    await _ensureSocketReady();
    await _loadCustomMarkers();
    _iconsReady = true;
    _syncPickupMarkerForSearch(force: true);
    _startPulseAnimation();
    _setupSocketListeners();
    if ((resumeDriverId ?? '').trim().isNotEmpty) {
      socketService.joinBooking(
        bookingId: bookingId,
        driverId: resumeDriverId!.trim(),
      );
    }
    await _initLocation();
  }

  Future<void> _ensureSocketReady() async {
    try {
      socketService.initSocket(ApiConsents.baseUrl);
      final prefs = await SharedPreferences.getInstance();
      final customerId = (prefs.getString('customer_Id') ?? '').trim();
      if (customerId.isEmpty) return;
      if (socketService.connected) {
        socketService.registerUser(customerId);
      } else {
        socketService.onConnect(() {
          socketService.registerUser(customerId);
        });
      }
    } catch (e) {
      AppLogger.log.e('Socket bootstrap failed in ride screen: ');
    }
  }

  Future<void> _loadMapStyle() async {
    try {
      mapStyle = await rootBundle.loadString(
        'assets/map_style/map_style_ride_clean.json',
      );
    } catch (_) {}
  }

  @override
  void onClose() {
    _searchTimer?.cancel();
    _pulseTimer?.cancel();
    _driverMarkerFlushTimer?.cancel();
    if (_activeTick != null) _moveCtrl.removeListener(_activeTick!);
    _moveCtrl.dispose();
    super.onClose();
  }

  // ---------- map callbacks ----------
  void onMapCreated(GoogleMapController controller /*String styleJson*/) {
    mapController = controller;
    if (mapStyle != null) {
      try {
        mapController?.setMapStyle(mapStyle);
      } catch (_) {}
    }

    // Initial move
    if (currentPosition != null) {
      mapController?.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: currentPosition!,
            zoom: currentZoomLevel,
            bearing: _mapBearingNorth,
            tilt: _mapTilt,
          ),
        ),
      );
    }

    // Ola-like: show pickup/drop once available
    _maybeFitInitialRoute();
    _focusPickupForWaiting();
  }

  void onCameraMove(CameraPosition pos) {
    currentZoomLevel = pos.zoom.clamp(11.0, 17.0).toDouble();
  }

  // Call from UI when user touches map
  void onUserMapGesture() {
    _pauseAutoFollowUntil = DateTime.now().add(_userGesturePause);
    _autoFitBoundsEnabled = false;
  }

  void bindContext(BuildContext ctx) {
    _screenCtx = ctx;
  }

  Future<void> goToCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final latLng = LatLng(position.latitude, position.longitude);
      currentPosition = latLng;
      _pauseAutoFollowUntil = DateTime.fromMillisecondsSinceEpoch(0);

      mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: latLng,
            zoom: currentZoomLevel,
            bearing: _mapBearingNorth,
            tilt: _mapTilt,
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> zoomIn() async => _zoomBy(0.8);

  Future<void> zoomOut() async => _zoomBy(-0.8);

  Future<void> _zoomBy(double delta) async {
    if (mapController == null) return;
    final next = (currentZoomLevel + delta).clamp(11.0, 17.0).toDouble();
    _pauseAutoFollowUntil = DateTime.now().add(const Duration(seconds: 2));
    _autoFitBoundsEnabled = false;
    try {
      await mapController!.animateCamera(CameraUpdate.zoomTo(next));
    } catch (_) {}
  }

  Future<void> onLocateActionTap() async {
    // UX: 1st tap -> focus the moving driver, 2nd tap -> fit bounds (driver↔pickup/drop)
    if (!focusDriverOnNextTap.value) {
      await focusDriverLocation();
      focusDriverOnNextTap.value = true;
      return;
    }

    fitActiveRouteBounds();
    focusDriverOnNextTap.value = false;
  }

  Future<void> focusDriverLocation() async {
    final target = _emaPos ?? _displayPos ?? currentPosition;
    if (target == null) {
      await goToCurrentLocation();
      return;
    }

    _pauseAutoFollowUntil = DateTime.fromMillisecondsSinceEpoch(0);
    _autoFitBoundsEnabled = false;
    try {
      await mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: target,
            zoom: math
                .max(currentZoomLevel, _focusDriverZoom)
                .clamp(_minAutoFollowZoom, 17.0),
            bearing: _mapBearingNorth,
            tilt: _mapTilt,
          ),
        ),
      );
    } catch (_) {}
  }

  void fitActiveRouteBounds() {
    _pauseAutoFollowUntil = DateTime.now().add(const Duration(seconds: 4));

    final driverPos = _emaPos ?? _displayPos;
    final target = driverStartedRide.value ? customerToLatLng : customerLatLng;

    if (driverPos != null && target != null) {
      _fitBounds(points: [driverPos, target], padding: 130);
      return;
    }

    if (customerLatLng != null && customerToLatLng != null) {
      _fitBounds(points: [customerLatLng!, customerToLatLng!], padding: 150);
      return;
    }

    if (driverPos != null) {
      mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: driverPos,
            zoom: currentZoomLevel,
            bearing: _mapBearingNorth,
            tilt: _mapTilt,
          ),
        ),
      );
      return;
    }

    goToCurrentLocation();
  }

  // ---------- icons ----------
  Future<void> _loadCustomMarkers() async {
    final dpr = ui.window.devicePixelRatio;

    try {
      carIcon = await _bitmapFromAssetSized(
        AppImages.carHop,
        widthDp: 28,
        dpr: dpr,
        circleBadge: true,
      );
    } catch (_) {
      carIcon = BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueAzure,
      );
    }

    try {
      bikeIcon = await _bitmapFromAssetSized(
        AppImages.packageBike,
        widthDp: 28,
        dpr: dpr,
        circleBadge: true,
      );
    } catch (_) {
      bikeIcon = BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueOrange,
      );
    }

    // Compact pickup/drop pins (assets).
    try {
      pickupPinIcon = await CompactMarkerIcons.assetPin(
        assetPath: AppImages.pinLocation,
        widthDp: 26,
        dpr: dpr,
      );
    } catch (_) {
      pickupPinIcon = null;
    }
    try {
      dropPinIcon = await CompactMarkerIcons.assetPin(
        assetPath: AppImages.rectangleDest,
        widthDp: 22,
        dpr: dpr,
      );
    } catch (_) {
      dropPinIcon = null;
    }
    try {
      pickupWaitingLabelIcon = await CompactMarkerIcons.labeledPin(
        label: 'Your pickup spot',
        assetPath: AppImages.pinLocation,
        bubbleWidthDp: 126,
        bubbleHeightDp: 38,
        pinWidthDp: 26,
        fontSizeDp: 11.5,
        dpr: dpr,
      );
    } catch (_) {
      pickupWaitingLabelIcon = pickupPinIcon;
    }
  }

  void _syncPickupMarkerForSearch({required bool force}) {
    if (!_iconsReady) return;
    if (customerLatLng == null) return;

    // Only applies before ride start; after start we show destination marker.
    if (driverStartedRide.value) return;

    _seedStaticMarkers(forceRecreate: force);
  }

  Future<BitmapDescriptor> _bitmapFromAssetSized(
    String assetPath, {
    required double widthDp,
    required double dpr,
    bool circleBadge = false,
  }) async {
    final targetPx = (widthDp * dpr).round();
    final sourceWidth = circleBadge ? (targetPx * 0.56).round() : targetPx;
    final byteData = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(
      byteData.buffer.asUint8List(),
      targetWidth: sourceWidth,
    );
    final frame = await codec.getNextFrame();

    if (!circleBadge) {
      final bytes = await frame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(targetPx.toDouble(), targetPx.toDouble());
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = targetPx / 2;

    canvas.drawCircle(center, radius * 0.88, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      radius * 0.88,
      Paint()
        ..color = const Color(0xFFE5E7EB)
        ..style = PaintingStyle.stroke
        ..strokeWidth = targetPx * 0.06,
    );

    final imageRect = Rect.fromCenter(
      center: center,
      width: frame.image.width.toDouble(),
      height: frame.image.height.toDouble(),
    );
    canvas.drawImageRect(
      frame.image,
      Rect.fromLTWH(
        0,
        0,
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      ),
      imageRect,
      Paint()..filterQuality = FilterQuality.high,
    );

    final composed = await recorder.endRecording().toImage(targetPx, targetPx);
    final bytes = await composed.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  BitmapDescriptor _iconForVehicleType(String? type) {
    final t = (type ?? '').toLowerCase();
    switch (t) {
      case 'bike':
      case 'two_wheeler':
      case '2w':
      case 'motorbike':
      case 'scooter':
        return bikeIcon ?? BitmapDescriptor.defaultMarker;
      default:
        return carIcon ?? BitmapDescriptor.defaultMarker;
    }
  }

  // ---------- location ----------
  Future<void> _initLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition();
      currentPosition = LatLng(position.latitude, position.longitude);
      AppLogger.log.i("ðŸ“ customer currentPosition: $currentPosition");
    } catch (_) {}
  }

  // ---------- driver search timer ----------
  void startDriverSearchTimer() {
    _searchTimer?.cancel();

    isDriverConfirmed.value = false;
    driverStartedRide.value = false;
    driverArrived.value = false;
    nearDestination.value = false;
    destinationReached.value = false;
    isTripCancelled.value = false;
    isWaitingForDriver.value = true;
    noDriverFound.value = false;
    latestRideStatus.value = 'SEARCHING';
    etaChipText.value = '';
    etaMinutes.value = 0;
    _autoFitBoundsEnabled = true;

    _syncPickupMarkerForSearch(force: true);
    _focusPickupForWaiting();
    _locationToggleFit = false;

    _searchTimer = Timer(const Duration(seconds: 60), () async {
      if (isClosed) return;
      if (isDriverConfirmed.value) return;
      if (_screenCtx == null) return;

      final hasDriver = await driverSearchController.noDriverFound(
        context: _screenCtx!,
        bookingId: bookingId,
        status: true,
      );

      if (isClosed) return;
      isWaitingForDriver.value = false;
      noDriverFound.value = !hasDriver;
    });
  }

  Future<void> onLocationButtonTap() async {
    if (mapController == null) return;

    // Toggle between focus (driver/current/pickup) and fit bounds (pickup+drop).
    if (_locationToggleFit) {
      _locationToggleFit = false;
      if (customerLatLng != null && customerToLatLng != null) {
        try {
          final bounds = MapUiDefaults.boundsFrom2(
            customerLatLng!,
            customerToLatLng!,
          );
          await mapController!.animateCamera(
            CameraUpdate.newLatLngBounds(bounds, 120),
          );
          return;
        } catch (_) {}
      }
    } else {
      _locationToggleFit = true;
      final target = _emaPos ?? _displayPos;
      if (target == null) {
        // No driver yet: zoom to current device location (or internal fallback).
        await goToCurrentLocation();
        return;
      }
      try {
        _pauseAutoFollowUntil = DateTime.fromMillisecondsSinceEpoch(0);
        await mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: target,
              zoom: math.max(currentZoomLevel, MapUiDefaults.focusZoom),
              bearing: _mapBearingNorth,
              tilt: _mapTilt,
            ),
          ),
        );
      } catch (_) {}
    }
  }

  void _focusPickupForWaiting() {
    if (mapController == null) return;
    if (customerLatLng == null) return;
    if (!isWaitingForDriver.value) return;
    if (isDriverConfirmed.value || driverStartedRide.value) return;

    try {
      mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: customerLatLng!,
            zoom: math.max(currentZoomLevel, MapUiDefaults.focusZoom),
            bearing: _mapBearingNorth,
            tilt: _mapTilt,
          ),
        ),
      );
    } catch (_) {}
  }

  // =================================================================
  //                         SOCKETS
  // =================================================================
  void _setupSocketListeners() {
    socketService.onConnect(() {
      AppLogger.log.i("Socket connected on booking screen");
    });

    socketService.on('joined-booking', (data) async {
      final vehicle = data['vehicle'] ?? {};
      final String driverId = (data['driverId'] ?? '').toString();
      final String driverFullName = (data['driverName'] ?? '').toString();
      final String customerPhoneStr = (data['customerPhone'] ?? '').toString();
      final double rating =
          double.tryParse((data['driverRating'] ?? '0').toString()) ?? 0.0;
      final String color = (vehicle['color'] ?? '').toString();
      final String brand = (vehicle['brand'] ?? '').toString();
      final String vehicleType =
          (vehicle['type'] ??
                  vehicle['serviceType'] ??
                  vehicle['carType'] ??
                  '')
              .toString();

      final bool driverAccepted = data['driver_accept_status'] == true;

      final driverLoc = data['driverLocation'] ?? {};
      final driverLat = _toDouble(driverLoc['latitude']);
      final driverLng = _toDouble(driverLoc['longitude']);

      final bool hasDriver =
          driverAccepted ||
          driverId.trim().isNotEmpty ||
          (driverLat != null && driverLng != null);

      final String plate = (vehicle['plateNumber'] ?? '').toString();
      final String profile = _firstImageUrl(
        data['profilePic'] ?? vehicle['profilePic'],
      );
      final photos = _firstImageUrl(
        data['carExteriorPhotos'] ?? vehicle['carExteriorPhotos'],
      );

      final customerLoc = data['customerLocation'] ?? {};
      final amt =
          (data['amount'] is num) ? (data['amount'] as num).toDouble() : 0.0;

      final fromLat = _toDouble(customerLoc['fromLatitude']);
      final fromLng = _toDouble(customerLoc['fromLongitude']);
      final toLat = _toDouble(customerLoc['toLatitude']);
      final toLng = _toDouble(customerLoc['toLongitude']);
      if (fromLat == null ||
          fromLng == null ||
          toLat == null ||
          toLng == null) {
        AppLogger.log.e("Invalid customerLocation payload: $customerLoc");
        return;
      }
      customerLatLng = LatLng(fromLat, fromLng);
      customerToLatLng = LatLng(toLat, toLng);

      plateNumber.value = plate;
      driverName.value = '$driverFullName ⭐️ $rating';
      carDetails.value = '$color - $brand';
      isDriverConfirmed.value = hasDriver;
      customerPhone.value = customerPhoneStr;
      cartypeFromServer.value = vehicleType;
      amount.value = amt;
      profilePic.value = profile;
      carExteriorPhotos.value = photos;

      // Ensure we are tracking the right booking/driver for this ride.
      final eventBookingId = (data['bookingId'] ?? '').toString().trim();
      final joinBookingId = eventBookingId.isNotEmpty ? eventBookingId : '';
      if (joinBookingId.isNotEmpty && driverId.trim().isNotEmpty) {
        socketService.joinBooking(
          bookingId: joinBookingId,
          driverId: driverId.trim(),
        );
      }

      _seedStaticMarkers(forceRecreate: true);

      if (driverLat != null && driverLng != null) {
        final initialDriverPos = LatLng(driverLat, driverLng);
        _displayPos = initialDriverPos;
        _emaPos = initialDriverPos;
        _lastReceivedPos = initialDriverPos;
        _lastBearing = 0.0;
        _updateDriverMarker(initialDriverPos, _lastBearing);
      }

      _refreshPulseCircles();

      final latestStatus =
          (data['latestStatus'] ?? data['status'] ?? '')
              .toString()
              .toUpperCase();
      _updateRideMetrics(data);
      latestRideStatus.value =
          latestStatus.isEmpty ? 'SEARCHING' : latestStatus;
      final joinedRideStarted = _isRideStartedStatus(latestStatus);
      final hasAssignedDriver =
          driverAccepted ||
          joinedRideStarted ||
          driverId.trim().isNotEmpty ||
          (driverLat != null && driverLng != null);

      if (hasAssignedDriver) {
        _searchTimer?.cancel();
        isWaitingForDriver.value = false;
        noDriverFound.value = false;
        isDriverConfirmed.value = true;
      } else if (!noDriverFound.value) {
        isWaitingForDriver.value = true;
        isDriverConfirmed.value = false;
      }

      if (joinedRideStarted) {
        driverStartedRide.value = true;
        _seedStaticMarkers(forceRecreate: false);
      }

      // Enforce correct marker visibility even if server status is noisy.
      _seedStaticMarkers(forceRecreate: false);

      if (driverLat != null && driverLng != null) {
        if (driverStartedRide.value && customerToLatLng != null) {
          await _drawPolyline(
            origin: LatLng(driverLat, driverLng),
            destination: customerToLatLng!,
            polyId: 'driver_to_drop',
            force: true,
          );
        } else if (!driverStartedRide.value && customerLatLng != null) {
          await _drawPolyline(
            origin: LatLng(driverLat, driverLng),
            destination: customerLatLng!,
            polyId: 'driver_to_pickup',
            force: true,
          );
        }
      }

      if (driverStartedRide.value) {
        _fitPickupAndDrop(force: true);
      } else {
        _fitDriverAndPickupOnce();
      }

      if (driverId.trim().isNotEmpty) {
        socketService.emit('track-driver', {'driverId': driverId.trim()});
      }
    });

    socketService.on('driver-location', (data) {
      if (isClosed) return;

      final lat = _toDouble(data['latitude']);
      final lng = _toDouble(data['longitude']);
      if (lat == null || lng == null) {
        AppLogger.log.e("Invalid driver-location payload: $data");
        return;
      }
      final newPos = LatLng(lat, lng);

      final rawTs = _parseServerTime(data['timestamp']);
      final age = DateTime.now().difference(rawTs);
      if (age > _maxStale) return;

      final srvBearing = _toDouble(data['bearing']);
      final liveRideType =
          (data['rideType'] ?? data['vehicleType'] ?? '').toString();
      if (liveRideType.trim().isNotEmpty) {
        cartypeFromServer.value = liveRideType;
      }
      final latestStatus =
          (data['latestStatus'] ?? '').toString().toUpperCase();
      _updateRideMetrics(data);
      final derivedRideStarted = _isRideStartedStatus(latestStatus);

      if (derivedRideStarted && !driverStartedRide.value) {
        driverStartedRide.value = true;
        _seedStaticMarkers(forceRecreate: false);
        _refreshPulseCircles();
        if (customerToLatLng != null) {
          _drawPolyline(
            origin: newPos,
            destination: customerToLatLng!,
            polyId: 'driver_to_drop',
            force: true,
          );
        }
      }
      // Jump filter (teleport)
      if (_lastReceivedPos != null) {
        final distJump = Geolocator.distanceBetween(
          _lastReceivedPos!.latitude,
          _lastReceivedPos!.longitude,
          newPos.latitude,
          newPos.longitude,
        );
        if (distJump < _minMoveMeters) return;
        if (distJump > _hardJumpMeters) return;
      }
      _lastReceivedPos = newPos;

      // first point -> show immediately
      if (_displayPos == null) {
        _displayPos = newPos;
        _emaPos = newPos;
        _lastBearing = srvBearing ?? 0.0;
        _updateDriverMarker(newPos, _lastBearing);

        // Ola like: while waiting, show driver + pickup together
        _fitDriverAndPickupOnce();

        // polyline driver->pickup once
        if (!driverStartedRide.value && customerLatLng != null) {
          _drawPolyline(
            origin: newPos,
            destination: customerLatLng!,
            polyId: "driver_to_pickup",
            force: true,
          );
        }
        return;
      }

      // enqueue for smooth motion
      final shiftedTs = rawTs.add(_playbackDelay);
      _poseQueue.add(DriverPose(newPos, t: shiftedTs, bearing: srvBearing));
      if (_poseQueue.length > _maxQueue) {
        _poseQueue.removeRange(0, _poseQueue.length - _maxQueue);
      }

      // polyline update rarely
      if (!driverStartedRide.value &&
          customerLatLng != null &&
          _shouldUpdatePolyline("driver_to_pickup")) {
        _drawPolyline(
          origin: newPos,
          destination: customerLatLng!,
          polyId: "driver_to_pickup",
        );
      }

      if (driverStartedRide.value &&
          customerToLatLng != null &&
          _shouldUpdatePolyline("driver_to_drop")) {
        _drawPolyline(
          origin: newPos,
          destination: customerToLatLng!,
          polyId: "driver_to_drop",
        );
      }

      _pumpMotion();
    });

    socketService.on('driver-arrived', (data) {
      if (isClosed) return;
      if (data != null && data['status'] == true) {
        driverArrived.value = true;
        etaChipText.value = 'Driver arrived';
      }
    });

    socketService.on('otp-generated', (data) {
      if (isClosed) return;
      final code = (data['otpCode'] ?? '').toString().trim();
      if (code.isEmpty) return;

      otp.value = code;

      // Fallback: OTP only comes after booking is confirmed.
      if (!isDriverConfirmed.value) {
        isDriverConfirmed.value = true;
      }
      if (isWaitingForDriver.value) {
        isWaitingForDriver.value = false;
      }
    });

    socketService.on('ride-started', (data) async {
      if (isClosed) return;

      final bool status = data['status'] == true;
      driverStartedRide.value = status;
      if (status) {
        driverArrived.value = true;
        latestRideStatus.value = 'STARTED';
        _updateRideMetrics(data);
      }

      _seedStaticMarkers(forceRecreate: false);
      _refreshPulseCircles();

      // redraw pickup->drop immediately (once)
      if (status && customerToLatLng != null) {
        final polyOrigin =
            _emaPos ?? _displayPos ?? customerLatLng ?? customerToLatLng!;
        await _drawPolyline(
          origin: polyOrigin,
          destination: customerToLatLng!,
          polyId: "driver_to_drop",
          force: true,
        );

        // Ola like: fit pickup+drop after ride started (skip if user manually
        // took over the camera via focus/zoom/drag).
        if (_autoFitBoundsEnabled) {
          _fitPickupAndDrop(force: true);
        }
      }
    });

    socketService.on('driver-reached-destination', (data) {
      if (isClosed) return;
      if (data != null && data['status'] == true) {
        destinationReached.value = true;
        nearDestination.value = true;
        etaChipText.value = 'Arrived at destination';
        latestRideStatus.value = 'COMPLETED';
      }
    });

    socketService.on('customer-cancelled', (data) {
      if (isClosed) return;
      if (data != null && data['status'] == true) {
        isTripCancelled.value = true;
        cancelReason.value =
            (data['message'] ?? data['reason'] ?? "Trip cancelled").toString();
      }
    });

    socketService.on('driver-cancelled', (data) {
      if (isClosed) return;
      if (data != null && data['status'] == true) {
        isTripCancelled.value = true;
        cancelReason.value =
            (data['message'] ?? data['reason'] ?? "Trip cancelled").toString();
      }
    });
  }

  DateTime _parseServerTime(dynamic ts) {
    try {
      if (ts == null) return DateTime.now();
      if (ts is int) {
        if (ts < 2000000000) {
          return DateTime.fromMillisecondsSinceEpoch(ts * 1000);
        }
        return DateTime.fromMillisecondsSinceEpoch(ts);
      }
      if (ts is String) {
        final parsed = DateTime.tryParse(ts);
        if (parsed != null) return parsed.toLocal();
      }
      return DateTime.now();
    } catch (_) {
      return DateTime.now();
    }
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  String _firstImageUrl(dynamic value) {
    if (value is List && value.isNotEmpty) {
      return (value.first ?? '').toString().trim();
    }
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return '';
    final normalized = raw
        .replaceAll('[', '')
        .replaceAll(']', '')
        .replaceAll('"', '');
    for (final part in normalized.split(',')) {
      final url = part.trim();
      if (url.isNotEmpty) return url;
    }
    return normalized;
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  String _formatEtaDuration(int mins) {
    final safeMins = mins <= 0 ? 1 : mins;
    if (safeMins >= 60) {
      final hrs = safeMins ~/ 60;
      final rem = safeMins % 60;
      return rem == 0 ? '$hrs hr' : '$hrs hr $rem min';
    }
    return '$safeMins min';
  }

  String _formatDistanceKm(double meters) {
    final km = meters <= 0 ? 0.0 : meters / 1000;
    return km >= 10
        ? '${km.toStringAsFixed(0)} km'
        : '${km.toStringAsFixed(1)} km';
  }

  void _updateRideMetrics(dynamic data) {
    pickupDurationMin.value = _toInt(data['pickupDurationInMin']);
    dropDurationMin.value = _toInt(data['dropDurationInMin']);
    tripDurationMin.value = _toInt(data['tripDurationInMin']);
    pickupDistanceMeters.value =
        _toDouble(data['pickupDistanceInMeters']) ?? 0.0;
    dropDistanceMeters.value = _toDouble(data['dropDistanceInMeters']) ?? 0.0;
    final incomingStatus =
        (data['latestStatus'] ?? data['status'] ?? '').toString().toUpperCase();
    if (incomingStatus.isNotEmpty) {
      latestRideStatus.value = incomingStatus;
    }
    if (!driverStartedRide.value) {
      final mins = pickupDurationMin.value;
      final meters = pickupDistanceMeters.value;
      final isArriving = driverArrived.value || meters <= 120 || mins <= 1;
      etaMinutes.value = mins;
      etaChipText.value =
          isArriving
              ? 'Arriving at pickup | ' + _formatDistanceKm(meters)
              : _formatEtaDuration(mins) +
                  ' away | ' +
                  _formatDistanceKm(meters);
      nearDestination.value = false;
      return;
    }
    final mins =
        dropDurationMin.value > 0
            ? dropDurationMin.value
            : tripDurationMin.value;
    final meters = dropDistanceMeters.value;
    nearDestination.value =
        meters > 0 && meters <= 400 || (mins > 0 && mins <= 2);
    etaMinutes.value = mins;
    if (destinationReached.value) {
      etaChipText.value = 'Arrived at destination';
    } else if (nearDestination.value) {
      etaChipText.value = 'Near destination | ' + _formatDistanceKm(meters);
    } else {
      etaChipText.value =
          _formatEtaDuration(mins) + ' to drop | ' + _formatDistanceKm(meters);
    }
  }

  int get timelineIndex {
    if (destinationReached.value) return 5;
    if (nearDestination.value) return 4;
    if (driverStartedRide.value) return 3;
    if (driverArrived.value) return 2;
    if (isDriverConfirmed.value) return 1;
    return 0;
  }

  void _updateEtaChipFallbackFromPositions() {
    if (!isDriverConfirmed.value) return;
    if (etaChipText.value.isNotEmpty) return;

    final hasMetrics =
        pickupDurationMin.value > 0 ||
        dropDurationMin.value > 0 ||
        tripDurationMin.value > 0 ||
        pickupDistanceMeters.value > 0.0 ||
        dropDistanceMeters.value > 0.0;
    if (hasMetrics) return;

    final driverPos = _emaPos ?? _displayPos;
    final target = driverStartedRide.value ? customerToLatLng : customerLatLng;
    if (driverPos == null || target == null) return;

    final meters = Geolocator.distanceBetween(
      driverPos.latitude,
      driverPos.longitude,
      target.latitude,
      target.longitude,
    );
    if (meters <= 0) return;

    final int mins = ((meters / (7.2 * 60.0)).ceil()).clamp(1, 999).toInt();
    final dist = _formatDistanceKm(meters);

    if (destinationReached.value) {
      etaChipText.value = 'Arrived at destination';
      return;
    }

    if (!driverStartedRide.value) {
      final arriving = driverArrived.value || meters <= 120 || mins <= 1;
      etaChipText.value =
          arriving
              ? 'Arriving at pickup | $dist'
              : '${_formatEtaDuration(mins)} away | $dist';
      nearDestination.value = false;
      return;
    }

    final near = meters <= 400 || mins <= 2;
    nearDestination.value = near;
    etaChipText.value =
        near
            ? 'Near destination | $dist'
            : '${_formatEtaDuration(mins)} to drop | $dist';
  }

  void _seedStaticMarkers({required bool forceRecreate}) {
    final set = Set<Marker>.from(markers);

    if (forceRecreate) {
      set.removeWhere(
        (m) =>
            m.markerId.value == 'pickup_marker' ||
            m.markerId.value == 'drop_marker',
      );
      _seededPickupMarker = false;
      _seededDropMarker = false;
    }

    // Before ride starts: show ONLY pickup marker (hide destination).
    if (!driverStartedRide.value) {
      if (set.any((m) => m.markerId.value == 'drop_marker')) {
        set.removeWhere((m) => m.markerId.value == 'drop_marker');
        _seededDropMarker = false;
      }
    }

    if (!driverStartedRide.value && customerLatLng != null) {
      // Waiting screen: show a compact pin with a small label above.
      final useWaitingLabel =
          isWaitingForDriver.value && !isDriverConfirmed.value;
      final variant = useWaitingLabel ? 'wait_label' : 'pin';
      final shouldReplace =
          forceRecreate ||
          !_seededPickupMarker ||
          _pickupMarkerVariant != variant;

      if (shouldReplace) {
        set.removeWhere((m) => m.markerId.value == 'pickup_marker');
        set.add(
          Marker(
            markerId: const MarkerId('pickup_marker'),
            position: customerLatLng!,
            infoWindow: InfoWindow.noText,
            icon:
                (useWaitingLabel ? pickupWaitingLabelIcon : pickupPinIcon) ??
                BitmapDescriptor.defaultMarkerWithHue(
                  MapUiDefaults.pickupDropMarkerHueGreen,
                ),
            anchor: const Offset(0.5, 1.0),
            flat: true,
            zIndexInt: 10,
          ),
        );
        _seededPickupMarker = true;
        _pickupMarkerVariant = variant;
      }
    }

    // After ride starts: show ONLY destination marker (hide pickup).
    if (driverStartedRide.value) {
      if (set.any((m) => m.markerId.value == 'pickup_marker')) {
        set.removeWhere((m) => m.markerId.value == 'pickup_marker');
        _seededPickupMarker = false;
      }
    }

    if (driverStartedRide.value &&
        customerToLatLng != null &&
        !_seededDropMarker) {
      set.add(
        Marker(
          markerId: const MarkerId('drop_marker'),
          position: customerToLatLng!,
          infoWindow: InfoWindow.noText,
          icon:
              dropPinIcon ??
              BitmapDescriptor.defaultMarkerWithHue(
                MapUiDefaults.pickupDropMarkerHueRed,
              ),
          anchor: const Offset(0.5, 1.0),
          flat: true,
        ),
      );
      _seededDropMarker = true;
    }

    markers
      ..clear()
      ..addAll(set);

    _refreshPulseCircles();
  }

  // =================================================================
  //                      MOTION
  // =================================================================
  void _pumpMotion() {
    if (_isAnimatingSegment) return;
    if (_poseQueue.isEmpty) return;
    if (_displayPos == null) return;

    final from = _displayPos!;
    final toPose = _poseQueue.removeAt(0);
    final to = toPose.latLng;

    final dist = Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
    if (dist < _minMoveMeters) return;

    int dur = (500 + (dist * 20)).toInt();
    dur = dur.clamp(_minSeg.inMilliseconds, _maxSeg.inMilliseconds);
    final segDur = Duration(milliseconds: dur);

    final targetBearing = toPose.bearing ?? _getBearing(from, to);
    final startBearing = _lastBearing;
    final bearingDelta = _shortestAngleDelta(startBearing, targetBearing);

    _isAnimatingSegment = true;

    _moveCtrl
      ..stop()
      ..reset()
      ..duration = segDur;

    if (_activeTick != null) _moveCtrl.removeListener(_activeTick!);
    _activeTick = () => _onTick(from, to, startBearing, bearingDelta);
    _moveCtrl.addListener(_activeTick!);

    _moveCtrl.forward().whenComplete(() {
      _displayPos = to;
      _lastBearing = _wrap360(startBearing + bearingDelta);
      _updateDriverMarker(_emaPos ?? to, _lastBearing);

      _isAnimatingSegment = false;
      if (_poseQueue.isNotEmpty) _pumpMotion();
    });
  }

  void _onTick(
    LatLng from,
    LatLng to,
    double startBearing,
    double bearingDelta,
  ) {
    final t = _ease.transform(_moveCtrl.value);

    final rawPos = LatLng(
      _lerp(from.latitude, to.latitude, t),
      _lerp(from.longitude, to.longitude, t),
    );

    final rawDist = Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
    final segSeconds = (_moveCtrl.duration?.inMilliseconds ?? 1) / 1000.0;
    final speedMps = (segSeconds > 0) ? (rawDist / segSeconds) : 0.0;
    final emaAlpha = (speedMps > 8.0) ? _emaAlphaFast : _emaAlphaSlow;

    _emaPos =
        (_emaPos == null) ? rawPos : _emaLatLng(_emaPos!, rawPos, emaAlpha);

    final targetB = _wrap360(startBearing + bearingDelta * t);
    final emaB = _emaAngle(_lastBearing, targetB, _bearingEmaAlpha);

    _lastBearing = _clampTurnRate(
      _lastBearing,
      emaB,
      1 / 60.0,
      _maxTurnDegPerSec,
    );

    _updateDriverMarker(_emaPos!, _lastBearing);

    // Ola-like camera update (NOT every tick + NOT over zoom)
    _autoCameraUpdate();
  }

  void _updateDriverMarker(LatLng position, double bearing) {
    final now = DateTime.now();
    final since = now.difference(_lastDriverMarkerAt);
    if (since < _driverMarkerMinInterval) {
      _pendingDriverMarkerPos = position;
      _pendingDriverMarkerBearing = bearing;
      _driverMarkerFlushTimer?.cancel();
      _driverMarkerFlushTimer = Timer(_driverMarkerMinInterval - since, () {
        if (isClosed) return;
        final pos = _pendingDriverMarkerPos;
        if (pos == null) return;
        final b = _pendingDriverMarkerBearing ?? _lastBearing;
        _pendingDriverMarkerPos = null;
        _pendingDriverMarkerBearing = null;
        _applyDriverMarkerNow(pos, b);
      });
      return;
    }

    _applyDriverMarkerNow(position, bearing);
  }

  void _applyDriverMarkerNow(LatLng position, double bearing) {
    _lastDriverMarkerAt = DateTime.now();
    final newMarker = Marker(
      markerId: const MarkerId("driver_marker"),
      position: position,
      rotation: bearing,
      icon: _iconForVehicleType(cartypeFromServer.value),
      anchor: const Offset(0.5, 0.72),
      flat: true,
    );

    markers.removeWhere((m) => m.markerId.value == "driver_marker");
    markers.add(newMarker);
    markers.refresh();

    _refreshPulseCircles();
  }

  // =================================================================
  //                           CAMERA (OLA STYLE)
  // =================================================================

  void _autoCameraUpdate() {
    if (mapController == null) return;
    if (_emaPos == null) return;

    // pause if user recently dragged/zoomed
    if (DateTime.now().isBefore(_pauseAutoFollowUntil)) return;

    final now = DateTime.now();
    if (now.difference(_lastCameraMoveAt) < _cameraInterval) return;
    _lastCameraMoveAt = now;

    // If server doesn't send ride metrics, compute a fallback ETA+distance so the top chip still shows.
    _updateEtaChipFallbackFromPositions();

    final lockedZoom =
        (currentZoomLevel < _minAutoFollowZoom)
            ? _minAutoFollowZoom
            : currentZoomLevel;

    // 1) Pre-ride: follow driver with pickup awareness, without fit-bounds jitter.
    if (!driverStartedRide.value && customerLatLng != null) {
      final mid = LatLng(
        (_emaPos!.latitude + customerLatLng!.latitude) / 2,
        (_emaPos!.longitude + customerLatLng!.longitude) / 2,
      );
      // Keep zoom stable so roads + vehicle icon remain clear (avoid zooming out).
      final z = lockedZoom.clamp(_minAutoFollowZoom, 17.0);
      try {
        mapController!.moveCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: mid,
              zoom: z,
              bearing: _mapBearingNorth,
              tilt: _mapTilt,
            ),
          ),
        );
      } catch (_) {}
      return;
    }

    // 2) Ride started: smoothly follow live driver.
    if (driverStartedRide.value) {
      final z = lockedZoom.clamp(_minAutoFollowZoom, 17.0);
      try {
        mapController!.moveCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: _emaPos!,
              zoom: z,
              bearing: _mapBearingNorth,
              tilt: _mapTilt,
            ),
          ),
        );
      } catch (_) {}
      return;
    }

    // 3) fallback: follow driver with a safe zoom clamp
    final z = lockedZoom.clamp(_minAutoFollowZoom, 17.0);
    try {
      mapController!.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _emaPos!,
            zoom: z,
            bearing: _mapBearingNorth,
            tilt: _mapTilt,
          ),
        ),
      );
    } catch (_) {}
  }

  void _maybeFitInitialRoute() {
    if (_hasFittedAtLeastOnce) return;
    if (mapController == null) return;

    if (customerLatLng != null && customerToLatLng != null) {
      _autoFramePoints(
        points: [customerLatLng!, customerToLatLng!],
        allowZoomOut: false,
      );
      _hasFittedAtLeastOnce = true;
      return;
    }

    if (currentPosition != null) {
      try {
        mapController!.moveCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: currentPosition!,
              zoom: currentZoomLevel,
              bearing: _mapBearingNorth,
              tilt: _mapTilt,
            ),
          ),
        );
      } catch (_) {}
    }
  }

  void _fitDriverAndPickupOnce() {
    if (mapController == null) return;
    if (_emaPos == null || customerLatLng == null) return;
    if (!_autoFitBoundsEnabled) return;
    if (_didFitDriverAndPickup) return;
    _didFitDriverAndPickup = true;

    // only once right after first driver point
    _autoFramePoints(points: [_emaPos!, customerLatLng!], allowZoomOut: false);
  }

  void _fitPickupAndDrop({required bool force}) {
    if (mapController == null) return;
    if (customerLatLng == null || customerToLatLng == null) return;
    if (!force && DateTime.now().isBefore(_pauseAutoFollowUntil)) return;
    if (!_autoFitBoundsEnabled) return;

    _autoFramePoints(
      points: [customerLatLng!, customerToLatLng!],
      allowZoomOut: false,
    );
  }

  double _zoomForDiagMeters(double meters) {
    if (!meters.isFinite) return currentZoomLevel;
    if (meters <= 300) return 16.8;
    if (meters <= 700) return 16.2;
    if (meters <= 1500) return 15.6;
    if (meters <= 3000) return 15.0;
    if (meters <= 6000) return 14.5;
    return 13.9;
  }

  void _autoFramePoints({
    required List<LatLng> points,
    required bool allowZoomOut,
  }) {
    final controller = mapController;
    if (controller == null) return;
    if (points.length < 2) return;

    if (DateTime.now().isBefore(_pauseAutoFollowUntil)) return;

    final now = DateTime.now();
    if (now.difference(_lastAutoFrameAt) < _autoFrameInterval) return;
    _lastAutoFrameAt = now;

    final b = _boundsFrom(points);
    final diag = Geolocator.distanceBetween(
      b.southwest.latitude,
      b.southwest.longitude,
      b.northeast.latitude,
      b.northeast.longitude,
    );

    final mid = LatLng(
      (b.northeast.latitude + b.southwest.latitude) / 2,
      (b.northeast.longitude + b.southwest.longitude) / 2,
    );

    final desired = _zoomForDiagMeters(diag).clamp(11.0, 17.0);
    final z = allowZoomOut ? desired : math.max(currentZoomLevel, desired);

    try {
      controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: mid,
            zoom: z,
            bearing: _mapBearingNorth,
            tilt: _mapTilt,
          ),
        ),
      );
    } catch (_) {}
  }

  void _fitBounds({
    required List<LatLng> points,
    required double padding,
    bool allowZoomOut = true,
  }) {
    if (mapController == null) return;
    if (points.length < 2) return;

    final b = _boundsFrom(points);
    final diag = Geolocator.distanceBetween(
      b.southwest.latitude,
      b.southwest.longitude,
      b.northeast.latitude,
      b.northeast.longitude,
    );

    // Auto-fit should not zoom way out (looks unprofessional in production).
    // Users can still press the fit button to see the full route.
    if (!allowZoomOut && diag.isFinite && diag > 3500) {
      final mid = LatLng(
        (b.northeast.latitude + b.southwest.latitude) / 2,
        (b.northeast.longitude + b.southwest.longitude) / 2,
      );
      final z = math
          .max(currentZoomLevel, _minAutoFollowZoom)
          .clamp(11.0, 17.0);
      try {
        mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: mid,
              zoom: z,
              bearing: _mapBearingNorth,
              tilt: _mapTilt,
            ),
          ),
        );
      } catch (_) {}
      return;
    }

    if (diag.isFinite && diag < 260) {
      final mid = LatLng(
        (b.northeast.latitude + b.southwest.latitude) / 2,
        (b.northeast.longitude + b.southwest.longitude) / 2,
      );
      final z = math
          .max(currentZoomLevel, _minAutoFollowZoom)
          .clamp(11.0, 17.0);
      try {
        mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: mid,
              zoom: z,
              bearing: _mapBearingNorth,
              tilt: _mapTilt,
            ),
          ),
        );
      } catch (_) {}
      return;
    }
    try {
      mapController!.animateCamera(CameraUpdate.newLatLngBounds(b, padding));
    } catch (_) {
      // sometimes bounds fails before map laid out; fallback safe move
      final mid = LatLng(
        (b.northeast.latitude + b.southwest.latitude) / 2,
        (b.northeast.longitude + b.southwest.longitude) / 2,
      );
      mapController!.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: mid,
            zoom: 13.8,
            bearing: _mapBearingNorth,
            tilt: _mapTilt,
          ),
        ),
      );
    }
  }

  LatLngBounds _boundsFrom(List<LatLng> pts) {
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

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  // =================================================================
  //                           POLYLINES
  // =================================================================
  bool _shouldUpdatePolyline(String polyId) {
    final now = DateTime.now();
    final canByTime = now.difference(_lastPolylineAt) >= _polylineInterval;
    if (!canByTime) return false;

    _lastPolylineAt = now;
    _activePolyId = polyId;
    return true;
  }

  Future<void> _drawPolyline({
    required LatLng origin,
    required LatLng destination,
    required String polyId,
    bool force = false,
  }) async {
    if (!force && _isDrawingPolyline) return;
    _isDrawingPolyline = true;

    try {
      final route = await _dir.getRouteInfo(
        origin: origin,
        destination: destination,
        mode: "driving",
        alternatives: false,
        traffic: true,
      );

      final pts = _simplifyPolyline(route.points);
      if (pts.length < 2) return;

      polylines.assignAll({
        Polyline(
          polylineId: PolylineId('${polyId}_outline'),
          points: pts,
          color: const Color(0xFFE5E7EB),
          width: 5,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
        Polyline(
          polylineId: PolylineId(polyId),
          points: pts,
          color: Colors.black,
          width: MapUiDefaults.polylineWidth,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      });
      _activePolyId = polyId;
    } catch (e) {
      AppLogger.log.e("Polyline error: $e");
    } finally {
      _isDrawingPolyline = false;
    }
  }

  // =================================================================
  //                         MATH
  // =================================================================
  double _lerp(double a, double b, double t) => a + (b - a) * t;

  double _getBearing(LatLng start, LatLng end) {
    final lat1 = start.latitude * math.pi / 180;
    final lon1 = start.longitude * math.pi / 180;
    final lat2 = end.latitude * math.pi / 180;
    final lon2 = end.longitude * math.pi / 180;

    final dLon = lon2 - lon1;
    final y = math.sin(dLon) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final bearing = math.atan2(y, x);
    return (bearing * 180 / math.pi + 360) % 360;
  }

  double _wrap360(double a) {
    a %= 360.0;
    if (a < 0) a += 360.0;
    return a;
  }

  double _shortestAngleDelta(double from, double to) {
    double diff = _wrap360(to) - _wrap360(from);
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return diff;
  }

  double _signedDelta(double from, double to) {
    double diff = _wrap360(to) - _wrap360(from);
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return diff;
  }

  double _emaAngle(double prevDeg, double targetDeg, double alpha) {
    final d = _signedDelta(prevDeg, targetDeg);
    return _wrap360(prevDeg + alpha * d);
  }

  LatLng _emaLatLng(LatLng prev, LatLng next, double alpha) {
    return LatLng(
      prev.latitude + (next.latitude - prev.latitude) * alpha,
      prev.longitude + (next.longitude - prev.longitude) * alpha,
    );
  }

  double _clampTurnRate(
    double current,
    double target,
    double dtSec,
    double maxDegPerSec,
  ) {
    final d = _signedDelta(current, target);
    final maxDelta = maxDegPerSec * dtSec;
    final clamped = d.clamp(-maxDelta, maxDelta);
    return _wrap360(current + clamped);
  }

  // =================================================================
  //                         EXPOSED
  // =================================================================

  List<LatLng> _simplifyPolyline(List<LatLng> points) {
    if (points.length <= 2) return points;

    const minStepMeters = 6.0;
    const maxPoints = 220;

    final simplified = <LatLng>[points.first];

    for (int i = 1; i < points.length - 1; i++) {
      final last = simplified.last;
      final next = points[i];
      final dist = Geolocator.distanceBetween(
        last.latitude,
        last.longitude,
        next.latitude,
        next.longitude,
      );

      if (dist >= minStepMeters) {
        simplified.add(next);
      }
    }

    if (simplified.last != points.last) {
      simplified.add(points.last);
    }

    if (simplified.length <= maxPoints) {
      return simplified;
    }

    final reduced = <LatLng>[];
    final step = (simplified.length / maxPoints).ceil();
    for (int i = 0; i < simplified.length; i += step) {
      reduced.add(simplified[i]);
    }
    if (reduced.last != simplified.last) {
      reduced.add(simplified.last);
    }

    return reduced;
  }

  void _startPulseAnimation() {
    _pulseTimer?.cancel();
    _pulseStartAt = DateTime.now();
    // Smooth pulse without over-updating the map.
    _pulseTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      _refreshPulseCircles();
    });
  }

  void _refreshPulseCircles() {
    final items = <Circle>{};
    final searching = !isDriverConfirmed.value && !driverStartedRide.value;
    final activeTarget =
        searching
            ? customerLatLng
            : (driverStartedRide.value ? customerToLatLng : customerLatLng);
    // Only one pulse at a time:
    // - Before pickup: pulse pickup
    // - After pickup: pulse destination
    // Destination marker can still show; just don't animate it.

    if (activeTarget == null) {
      circles.clear();
      return;
    }

    final now = DateTime.now();
    final elapsedMs = now.difference(_pulseStartAt).inMilliseconds;
    const periodMs = 1400;
    final phase = ((elapsedMs % periodMs) / periodMs).clamp(0.0, 1.0);

    void addPulse(String id, LatLng center, Color baseColor) {
      const baseRadius = 18.0;
      const pulseRadius = 40.0;
      final radius = baseRadius + (pulseRadius * phase);
      final alpha = (0.18 * (1.0 - phase)).clamp(0.0, 0.18);

      items.add(
        Circle(
          circleId: CircleId('${id}_inner'),
          center: center,
          radius: 16,
          fillColor: baseColor.withOpacity(0.14),
          strokeColor: baseColor.withOpacity(0.18),
          strokeWidth: 1,
        ),
      );
      items.add(
        Circle(
          circleId: CircleId('${id}_pulse'),
          center: center,
          radius: radius,
          fillColor: baseColor.withOpacity(alpha),
          strokeColor: baseColor.withOpacity((alpha + 0.08).clamp(0.0, 1.0)),
          strokeWidth: 1,
        ),
      );
    }

    addPulse('active_target', activeTarget, Colors.black);

    circles.assignAll(items);
  }

  void toggleFareDetails() => isExpanded.value = !isExpanded.value;
}

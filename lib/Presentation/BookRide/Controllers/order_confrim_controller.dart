import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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
import 'package:hopper/uitls/map/driver_motion_engine.dart';
import 'package:hopper/uitls/map/route_tracking_math.dart';
import 'package:hopper/uitls/websocket/socket_io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hopper/uitls/map/map_ui_defaults.dart';
import 'package:hopper/uitls/map/compact_marker_icons.dart';

class _RouteRequest {
  final LatLng origin;
  final LatLng destination;
  final String polyId;
  final bool force;
  final String? cacheKey;

  const _RouteRequest({
    required this.origin,
    required this.destination,
    required this.polyId,
    required this.force,
    required this.cacheKey,
  });
}

class OrderConfirmController extends GetxController
    with GetSingleTickerProviderStateMixin, WidgetsBindingObserver {
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
    String? initialStatus,
    bool? initialRideStarted,
    bool? initialDestinationReached,
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

    if ((initialStatus ?? '').trim().isNotEmpty) {
      latestRideStatus.value = initialStatus!.trim();
    }

    final statusUpper = latestRideStatus.value.trim().toUpperCase();
    final started =
        initialRideStarted == true ||
        _isRideStartedStatus(statusUpper) ||
        statusUpper.contains('IN_PROGRESS');
    final reached =
        initialDestinationReached == true ||
        statusUpper.contains('DESTINATION_REACHED') ||
        statusUpper.contains('COMPLETED');

    if (reached) destinationReached.value = true;
    if (started) driverStartedRide.value = true;

    final confirmed = (resumeDriverId ?? '').trim().isNotEmpty;
    if (confirmed) isDriverConfirmed.value = true;

    isWaitingForDriver.value =
        !isDriverConfirmed.value &&
        !driverStartedRide.value &&
        !destinationReached.value &&
        !isTripCancelled.value;

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
  // Active ride tracking zoom.
  double currentZoomLevel = 17.0;
  static const double _minAutoFollowZoom = 17.0;
  BuildContext? _screenCtx;
  Timer? _searchTimer;
  final RxBool focusDriverOnNextTap = false.obs;

  static const double _mapTilt = 30.0;

  // Auto camera control (Ola style)
  DateTime _lastCameraMoveAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _cameraInterval = const Duration(milliseconds: 900);
  DateTime _pauseAutoFollowUntil = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _userGesturePause = const Duration(seconds: 6);
  bool _hasFittedAtLeastOnce = false;
  bool _autoFitBoundsEnabled = true;
  bool _didFitDriverAndPickup = false;
  bool _didFitDriverAndDrop = false;
  static const double _focusDriverZoom = 17.6;
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
  final RxString driverPhone = "".obs;
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

  /// Exposed raw driver position for reusable map widgets.
  final Rxn<LatLng> driverLocation = Rxn<LatLng>();

  /// Exposed active route points (decoded + simplified).
  final RxList<LatLng> activeRoutePoints = <LatLng>[].obs;

  /// When true, this controller will not move the camera automatically.
  /// Used when screens render the map via a reusable component that owns
  /// camera follow behavior.
  bool externalCameraControl = false;

  BitmapDescriptor? carIcon;
  BitmapDescriptor? bikeIcon;

  // Pickup/drop image icons
  // Pickup/drop compact image pins (like home map).
  BitmapDescriptor? pickupPinIcon;
  BitmapDescriptor? dropPinIcon;
  BitmapDescriptor? pickupWaitingLabelIcon;
  BitmapDescriptor? pickupLabelIcon;
  BitmapDescriptor? dropLabelIcon;

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
    return _isDropPhaseStatus(status);
  }

  bool _isDropPhaseStatus(String status) {
    final s = status.trim().toUpperCase();
    return s == 'STARTED' ||
        s == 'RIDE_STARTED' ||
        s == 'TRIP_STARTED' ||
        s == 'PICKED_UP' ||
        s == 'ON_TRIP' ||
        s == 'IN_PROGRESS' ||
        s == 'RIDE_IN_PROGRESS' ||
        s == 'TRIP_IN_PROGRESS';
  }

  bool _isCompletedStatus(String status) {
    final s = status.trim().toUpperCase();
    return s == 'COMPLETED' ||
        s == 'RIDE_COMPLETED' ||
        s == 'TRIP_COMPLETED' ||
        s == 'DESTINATION_REACHED' ||
        s == 'DRIVER_REACHED_DESTINATION';
  }

  // =================================================================
  //                  SMOOTH DRIVER ENGINE
  // =================================================================
  late final DriverMotionEngine _driverMotion;
  LatLng? _displayPos;
  LatLng? _emaPos;
  double _lastBearing = 0.0;
  DateTime _lastAcceptedDriverLocationTs = DateTime.fromMillisecondsSinceEpoch(
    0,
  );

  // =================================================================
  //                        POLYLINE CONTROL
  // =================================================================
  // Route API call throttle. Keep separate from polyline rebuild cadence so we
  // can reroute faster when off-route without spamming the API.
  DateTime _lastRouteFetchAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastRouteKey = '';
  String _activeRouteSig = '';
  String? _routeInFlightKey;
  _RouteRequest? _pendingRouteRequest;

  // Small in-memory route cache to avoid repeated decode/fetch work.
  // Key: phase|originLat|originLng|destLat|destLng (rounded to 5 decimals).
  // Value: simplified LatLng points.
  final Map<String, List<LatLng>> _routeCache = <String, List<LatLng>>{};
  static const int _routeCacheMaxEntries = 10;

  bool _isDrawingPolyline = false;

  bool _seededPickupMarker = false;
  bool _seededDropMarker = false;
  Timer? _pulseTimer;
  DateTime _pulseStartAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _driverMotion = DriverMotionEngine(
      vsync: this,
      onUpdate: (pos, bearing) {
        _emaPos = pos;
        _displayPos = pos;
        _lastBearing = bearing;
        _updateDriverMarker(pos, bearing);
      },
      onFrameSideEffects: (pos) {
        _autoCameraUpdate();
      },
      // Debounce raw GPS packets (ignore <5m moves).
      minMoveMeters: 5.0,
    );
    _dir = DirectionsHelper(apiKey: ApiConsents.googleMapApiKey);
    _loadMapStyle();
    _boot();
  }

  Future<void> _boot() async {
    await _ensureSocketReady();
    await _loadCustomMarkers();
    _iconsReady = true;
    _seedStaticMarkers(forceRecreate: true);
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
      mapStyle = await rootBundle.loadString('assets/map_style.json');
    } catch (_) {}
  }

  @override
  void onClose() {
    _searchTimer?.cancel();
    _pulseTimer?.cancel();
    _driverMarkerFlushTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _driverMotion.dispose();
    _clearActiveRoute();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Don't keep pulsing the map while backgrounded.
    if (state == AppLifecycleState.resumed) {
      _startPulseAnimation();
    } else {
      _pulseTimer?.cancel();
      _pulseTimer = null;
      if (circles.isNotEmpty) circles.clear();
    }
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
      mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: currentPosition!,
            zoom: currentZoomLevel,
            bearing: _lastBearing,
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
            bearing: _lastBearing,
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
            bearing: _lastBearing,
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
    final routePts = activeRoutePoints.toList(growable: false);

    if (routePts.length >= 2) {
      final extras = <LatLng>[
        if (driverPos != null) driverPos,
        if (customerLatLng != null) customerLatLng!,
        if (customerToLatLng != null) customerToLatLng!,
      ];
      try {
        final bounds = boundsFromRoutePoints(routePts, extraPoints: extras);
        mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 170));
      } catch (_) {
        _fitBounds(
          points: [
            if (driverPos != null) driverPos,
            if (target != null) target,
          ],
          padding: 170,
        );
      }
      return;
    }

    if (driverPos != null && target != null) {
      _fitBounds(points: [driverPos, target], padding: 170);
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
            bearing: _lastBearing,
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
      carIcon = await CompactMarkerIcons.assetContained(
        assetPath: AppImages.carHop,
        sizeDp: MapUiDefaults.vehicleBadgeDiameterDp,
        dpr: dpr,
      );
    } catch (_) {
      carIcon = BitmapDescriptor.defaultMarkerWithHue(
        BitmapDescriptor.hueAzure,
      );
    }

    try {
      bikeIcon = await CompactMarkerIcons.assetContained(
        assetPath: AppImages.bikeImage,
        sizeDp: MapUiDefaults.vehicleBadgeDiameterDp,
        dpr: dpr,
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
        widthDp: MapUiDefaults.pickupDropPinWidthDp,
        dpr: dpr,
      );
    } catch (_) {
      pickupPinIcon = null;
    }
    try {
      dropPinIcon = await CompactMarkerIcons.assetPin(
        assetPath: AppImages.rectangleDest,
        widthDp: MapUiDefaults.pickupDropPinWidthDp,
        dpr: dpr,
      );
    } catch (_) {
      dropPinIcon = null;
    }
    try {
      pickupWaitingLabelIcon = await CompactMarkerIcons.labeledPin(
        label: MapUiDefaults.placeLabel(pickupAddress, fallback: 'Pickup'),
        assetPath: AppImages.pinLocation,
        bubbleWidthDp: MapUiDefaults.pickupDropBubbleWidthDp,
        bubbleHeightDp: MapUiDefaults.pickupDropBubbleHeightDp,
        pinWidthDp: MapUiDefaults.pickupDropPinWidthDp,
        fontSizeDp: MapUiDefaults.pickupDropFontSizeDp,
        textAlign: TextAlign.left,
        dpr: dpr,
      );
    } catch (_) {
      pickupWaitingLabelIcon = pickupPinIcon;
    }
    try {
      pickupLabelIcon = await CompactMarkerIcons.labeledPin(
        label: MapUiDefaults.placeLabel(pickupAddress, fallback: 'Pickup'),
        assetPath: AppImages.pinLocation,
        bubbleWidthDp: MapUiDefaults.pickupDropBubbleWidthDp,
        bubbleHeightDp: MapUiDefaults.pickupDropBubbleHeightDp,
        pinWidthDp: MapUiDefaults.pickupDropPinWidthDp,
        fontSizeDp: MapUiDefaults.pickupDropFontSizeDp,
        textAlign: TextAlign.left,
        dpr: dpr,
      );
    } catch (_) {
      pickupLabelIcon = pickupPinIcon;
    }
    try {
      dropLabelIcon = await CompactMarkerIcons.labeledPin(
        label: MapUiDefaults.placeLabel(destinationAddress, fallback: 'Drop'),
        assetPath: AppImages.rectangleDest,
        bubbleWidthDp: MapUiDefaults.pickupDropBubbleWidthDp,
        bubbleHeightDp: MapUiDefaults.pickupDropBubbleHeightDp,
        pinWidthDp: MapUiDefaults.pickupDropPinWidthDp,
        fontSizeDp: MapUiDefaults.pickupDropFontSizeDp,
        textAlign: TextAlign.left,
        dpr: dpr,
      );
    } catch (_) {
      dropLabelIcon = dropPinIcon;
    }
  }

  void _syncPickupMarkerForSearch({required bool force}) {
    if (!_iconsReady) return;
    if (customerLatLng == null) return;

    // Only applies before ride start; after start we show destination marker.
    if (driverStartedRide.value) return;

    _seedStaticMarkers(forceRecreate: force);
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
    focusDriverOnNextTap.value = false;
    _didFitDriverAndPickup = false;
    _didFitDriverAndDrop = false;

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
            CameraUpdate.newLatLngBounds(bounds, 80),
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
              bearing: _lastBearing,
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
            bearing: _lastBearing,
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
      final payload = _normalizeSocketPayload(data);
      if (payload.isEmpty) return;

      final vehicle =
          payload['vehicle'] is Map ? payload['vehicle'] as Map : {};
      final String driverId = (payload['driverId'] ?? '').toString();
      final String driverFullName = (payload['driverName'] ?? '').toString();
      final String driverPhoneStr = (payload['driverPhone'] ?? '').toString();
      final String customerPhoneStr =
          (payload['customerPhone'] ?? '').toString();
      final double rating =
          double.tryParse((payload['driverRating'] ?? '0').toString()) ?? 0.0;
      final String color = (vehicle['color'] ?? '').toString();
      final String brand = (vehicle['brand'] ?? '').toString();
      final String vehicleType =
          (vehicle['type'] ??
                  vehicle['serviceType'] ??
                  payload['serviceType'] ??
                  vehicle['carType'] ??
                  '')
              .toString();

      final bool driverAccepted =
          payload['driver_accept_status'] == true ||
          payload['orderConfirmationStatus'] == true;

      final driverLoc = payload['driverLocation'] ?? {};
      final driverLat = _toDouble(driverLoc['latitude']);
      final driverLng = _toDouble(driverLoc['longitude']);

      final bool hasDriver =
          driverAccepted ||
          driverId.trim().isNotEmpty ||
          (driverLat != null && driverLng != null);

      final String plate = (vehicle['plateNumber'] ?? '').toString();
      final String profile = _firstImageUrl(
        payload['profilePic'] ?? vehicle['profilePic'],
      );
      final photos = _firstImageUrl(
        payload['carExteriorPhotos'] ?? vehicle['carExteriorPhotos'],
      );

      final customerLoc = payload['customerLocation'] ?? {};
      final amt =
          (payload['amount'] is num)
              ? (payload['amount'] as num).toDouble()
              : 0.0;

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
      driverPhone.value = driverPhoneStr;
      customerPhone.value = customerPhoneStr;
      cartypeFromServer.value = vehicleType;
      amount.value = amt;
      profilePic.value = profile;
      carExteriorPhotos.value = photos;

      // Ensure we are tracking the right booking/driver for this ride.
      final eventBookingId = (payload['bookingId'] ?? '').toString().trim();
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
        driverLocation.value = initialDriverPos;
        _displayPos = initialDriverPos;
        _emaPos = initialDriverPos;
        _lastBearing = 0.0;
        _driverMotion.reset(initialDriverPos, bearing: 0.0);
        _updateDriverMarker(initialDriverPos, 0.0);
      }

      _refreshPulseCircles();

      final latestStatus =
          (payload['latestStatus'] ?? payload['status'] ?? '')
              .toString()
              .toUpperCase();
      _updateRideMetrics(payload);
      latestRideStatus.value =
          latestStatus.isEmpty ? 'SEARCHING' : latestStatus;
      final joinedRideStarted = _isDropPhaseStatus(latestStatus);
      final joinedRideCompleted = _isCompletedStatus(latestStatus);
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
        _didFitDriverAndDrop = false;
        _seedStaticMarkers(forceRecreate: false);
      }
      if (joinedRideCompleted) {
        driverStartedRide.value = true;
        destinationReached.value = true;
        nearDestination.value = true;
        _clearActiveRoute();
      }

      // Enforce correct marker visibility even if server status is noisy.
      _seedStaticMarkers(forceRecreate: false);

      if (driverLat != null && driverLng != null) {
        final initialDriverPos = LatLng(driverLat, driverLng);
        _updatePolylinesForStatus(
          latestRideStatus.value,
          driverPos: initialDriverPos,
          force: true,
        );
      }

      if (driverStartedRide.value) {
        _fitDriverAndDrop(force: true);
      } else {
        _fitDriverAndPickupOnce();
      }

      if (driverId.trim().isNotEmpty) {
        socketService.emit('track-driver', {'driverId': driverId.trim()});
      }
    });

    socketService.on('driver-location', (data) {
      if (isClosed) return;

      final lat = _toDouble(data['latitude'] ?? data['lat']);
      final lng = _toDouble(data['longitude'] ?? data['lng']);
      if (lat == null || lng == null) {
        AppLogger.log.e("Invalid driver-location payload: $data");
        return;
      }
      final rawTs = _parseServerTime(data['timestamp']);
      if (!_isFreshTrackingTimestamp(rawTs)) {
        if (kDebugMode) {
          AppLogger.log.w(
            'Ignoring stale ride driver-location ts=$rawTs lat=$lat lng=$lng',
          );
        }
        return;
      }
      if (rawTs.isBefore(_lastAcceptedDriverLocationTs)) {
        return;
      }
      _lastAcceptedDriverLocationTs = rawTs;

      final newPos = LatLng(lat, lng);
      driverLocation.value = newPos;

      final srvBearing = _toDouble(data['bearing']);
      final liveRideType =
          (data['rideType'] ?? data['vehicleType'] ?? '').toString();
      if (liveRideType.trim().isNotEmpty) {
        cartypeFromServer.value = liveRideType;
      }
      final latestStatus =
          (data['latestStatus'] ?? '').toString().toUpperCase();
      _updateRideMetrics(data);
      final derivedRideStarted = _isDropPhaseStatus(latestStatus);
      final derivedRideCompleted = _isCompletedStatus(latestStatus);
      final effectiveStatus =
          latestStatus.trim().isNotEmpty
              ? latestStatus
              : latestRideStatus.value;

      if (derivedRideStarted && !driverStartedRide.value) {
        driverStartedRide.value = true;
        _didFitDriverAndDrop = false;
        _seedStaticMarkers(forceRecreate: false);
        _refreshPulseCircles();
        _updatePolylinesForStatus(
          effectiveStatus,
          driverPos: newPos,
          force: true,
        );
      }
      if (derivedRideCompleted) {
        if (!driverStartedRide.value) {
          driverStartedRide.value = true;
        }
        destinationReached.value = true;
        nearDestination.value = true;
        etaChipText.value = 'Arrived at destination';
        _seedStaticMarkers(forceRecreate: false);
        _refreshPulseCircles();
        _clearActiveRoute();
      }
      // first point -> show immediately
      if (_displayPos == null) {
        _displayPos = newPos;
        _emaPos = newPos;
        _lastBearing = srvBearing ?? 0.0;
        _driverMotion.reset(newPos, bearing: _lastBearing);

        // Ola like: while waiting, show driver + pickup together
        _fitDriverAndPickupOnce();

        // polyline driver->pickup once
        _updatePolylinesForStatus(
          effectiveStatus,
          driverPos: newPos,
          force: true,
        );
        return;
      }

      // enqueue for smooth motion (shared helper)
      _driverMotion.ingest(newPos, serverTs: rawTs, bearing: srvBearing);

      // Keep polylines in sync with phase + driver motion (throttled/cached).
      _updatePolylinesForStatus(effectiveStatus, driverPos: newPos);

      // Motion ticks are handled inside DriverMotionEngine.
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
        final polyOrigin = _emaPos ?? _displayPos;
        if (polyOrigin != null) {
          _maybeRerouteFromDriver(polyOrigin, force: true);
        }

        // Ola like: fit driver+drop after ride started (skip if user manually
        // took over the camera via focus/zoom/drag).
        if (_autoFitBoundsEnabled) {
          _fitDriverAndDrop(force: true);
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
        _clearActiveRoute();
      }
    });

    socketService.on('customer-cancelled', (data) {
      if (isClosed) return;
      if (data != null && data['status'] == true) {
        isTripCancelled.value = true;
        cancelReason.value =
            (data['message'] ?? data['reason'] ?? "Trip cancelled").toString();
        _clearActiveRoute();
      }
    });

    socketService.on('driver-cancelled', (data) {
      if (isClosed) return;
      if (data != null && data['status'] == true) {
        isTripCancelled.value = true;
        cancelReason.value =
            (data['message'] ?? data['reason'] ?? "Trip cancelled").toString();
        _clearActiveRoute();
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

  bool _isFreshTrackingTimestamp(
    DateTime ts, {
    Duration maxAge = const Duration(seconds: 20),
    Duration maxFutureSkew = const Duration(seconds: 12),
  }) {
    final now = DateTime.now();
    if (ts.isAfter(now.add(maxFutureSkew))) return false;
    if (now.difference(ts) > maxAge) return false;
    return true;
  }

  Map<String, dynamic> _normalizeSocketPayload(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    if (raw is List && raw.isNotEmpty) {
      return _normalizeSocketPayload(raw.first);
    }
    return <String, dynamic>{};
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
      final variant = useWaitingLabel ? 'wait_label' : 'label';
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
                (useWaitingLabel ? pickupWaitingLabelIcon : pickupLabelIcon) ??
                pickupPinIcon ??
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

    final shouldShowDrop = driverStartedRide.value && customerToLatLng != null;
    if (!shouldShowDrop) {
      if (set.any((m) => m.markerId.value == 'drop_marker')) {
        set.removeWhere((m) => m.markerId.value == 'drop_marker');
        _seededDropMarker = false;
      }
    } else {
      final shouldReplaceDrop =
          forceRecreate ||
          !_seededDropMarker ||
          !set.any((m) => m.markerId.value == 'drop_marker');
      if (shouldReplaceDrop) {
        set.removeWhere((m) => m.markerId.value == 'drop_marker');
        set.add(
          Marker(
            markerId: const MarkerId('drop_marker'),
            position: customerToLatLng!,
            infoWindow: InfoWindow.noText,
            icon:
                dropLabelIcon ??
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
    }

    markers
      ..clear()
      ..addAll(set);

    _refreshPulseCircles();
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
    final t = cartypeFromServer.value.trim().toLowerCase();
    final isCar =
        t.contains('car') ||
        t.contains('sedan') ||
        t.contains('suv') ||
        t.contains('van');
    final adjustedBearing = MapUiDefaults.normalizeBearing(
      bearing +
          (isCar
              ? MapUiDefaults.carBearingIconOffsetDeg
              : MapUiDefaults.bikeBearingIconOffsetDeg),
    );
    final newMarker = Marker(
      markerId: const MarkerId("driver_marker"),
      position: position,
      rotation: adjustedBearing,
      icon: _iconForVehicleType(cartypeFromServer.value),
      anchor: const Offset(0.5, 0.72),
      flat: true,
      infoWindow: InfoWindow(
        title:
            driverName.value.trim().isNotEmpty
                ? driverName.value.trim()
                : 'Driver',
        snippet:
            carDetails.value.trim().isNotEmpty ? carDetails.value.trim() : null,
      ),
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
    if (externalCameraControl) return;
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
        mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: mid,
              zoom: z,
              bearing: _lastBearing,
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
        mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: _emaPos!,
              zoom: z,
              bearing: _lastBearing,
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
      mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _emaPos!,
            zoom: z,
            bearing: _lastBearing,
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
        mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: currentPosition!,
              zoom: currentZoomLevel,
              bearing: _lastBearing,
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

  void _fitDriverAndDrop({required bool force}) {
    if (mapController == null) return;
    if (customerToLatLng == null) return;
    if (!force && DateTime.now().isBefore(_pauseAutoFollowUntil)) return;
    if (!_autoFitBoundsEnabled) return;
    if (!force && _didFitDriverAndDrop) return;

    final driverPos = _emaPos ?? _displayPos;
    if (driverPos == null) return;
    _didFitDriverAndDrop = true;

    _autoFramePoints(
      points: [driverPos, customerToLatLng!],
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
            bearing: _lastBearing,
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
              bearing: _lastBearing,
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
              bearing: _lastBearing,
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
      mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: mid,
            zoom: 13.8,
            bearing: _lastBearing,
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
  String _routeKey({required bool toDrop, required LatLng destination}) {
    return '${toDrop ? 'toDrop' : 'toPickup'}|dest:${destination.latitude.toStringAsFixed(5)},${destination.longitude.toStringAsFixed(5)}';
  }

  String _routeCacheKey({
    required bool toDrop,
    required LatLng origin,
    required LatLng destination,
  }) {
    final phase = toDrop ? 'toDrop' : 'toPickup';
    return '$phase|'
        '${origin.latitude.toStringAsFixed(5)}|${origin.longitude.toStringAsFixed(5)}|'
        '${destination.latitude.toStringAsFixed(5)}|${destination.longitude.toStringAsFixed(5)}';
  }

  void _cachePut(String key, List<LatLng> points) {
    if (_routeCache.containsKey(key)) {
      _routeCache.remove(key);
    }
    _routeCache[key] = points;
    while (_routeCache.length > _routeCacheMaxEntries) {
      _routeCache.remove(_routeCache.keys.first);
    }
  }

  String _routeSig(List<LatLng> pts) {
    if (pts.length < 2) return 'len:${pts.length}';
    final idxs =
        <int>{
            0,
            pts.length - 1,
            (pts.length * 1 ~/ 4),
            (pts.length * 2 ~/ 4),
            (pts.length * 3 ~/ 4),
          }.toList()
          ..sort();

    final sb = StringBuffer('len:${pts.length}');
    for (final i in idxs) {
      final p = pts[i.clamp(0, pts.length - 1)];
      sb.write('|');
      sb.write(
        '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}',
      );
    }
    return sb.toString();
  }

  LatLng? _activeDestination() {
    // Two-phase routing:
    // - Before pickup: driver -> pickup
    // - After pickup:  driver -> drop
    if (driverStartedRide.value) return customerToLatLng;
    return customerLatLng;
  }

  void _maybeRerouteFromDriver(LatLng driverPos, {bool force = false}) {
    if (isTripCancelled.value || destinationReached.value) return;
    final dest = _activeDestination();
    if (dest == null) return;

    final now = DateTime.now();
    final key = _routeKey(toDrop: driverStartedRide.value, destination: dest);
    final cacheKey = _routeCacheKey(
      toDrop: driverStartedRide.value,
      origin: driverPos,
      destination: dest,
    );

    if (force || key != _lastRouteKey) {
      // IMPORTANT (production UX): don't clear the current polyline immediately.
      // Clearing here causes visible "blink" (route disappears) while Directions
      // API fetch is in-flight, and if the fetch fails the map becomes blank.
      //
      // Also: keep `_lastRouteKey` consistent. Previously `_clearActiveRoute()` was
      // resetting `_lastRouteKey` which caused repeated reroute fetches and
      // visible flicker on every location tick.
      _clearActiveRoute(clearVisuals: false, clearKey: false);
      _lastRouteKey = key;
      _drawPolyline(
        origin: driverPos,
        destination: dest,
        polyId: driverStartedRide.value ? 'driver_to_drop' : 'driver_to_pickup',
        force: true,
        cacheKey: cacheKey,
      );
      _lastRouteFetchAt = now;
      return;
    }

    if (!shouldReroute(
      activeRoute: activeRoutePoints,
      driver: driverPos,
      destination: dest,
      now: now,
      lastRouteFetchAt: _lastRouteFetchAt,
      minInterval: const Duration(seconds: 30),
      offRouteThresholdMeters: 100.0,
    )) {
      return;
    }

    _lastRouteFetchAt = now;
    _drawPolyline(
      origin: driverPos,
      destination: dest,
      polyId: driverStartedRide.value ? 'driver_to_drop' : 'driver_to_pickup',
      force: true,
      cacheKey: cacheKey,
    );
  }

  void _updatePolylinesForStatus(
    String orderStatus, {
    LatLng? driverPos,
    bool force = false,
  }) {
    final s = orderStatus.trim().toLowerCase();

    // Phase 2 (ride in progress)
    if (s == 'picked_up' ||
        s == 'on_trip' ||
        s == 'in_progress' ||
        s == 'started' ||
        s == 'ride_started' ||
        s == 'trip_started') {
      if (driverPos != null) {
        _maybeRerouteFromDriver(driverPos, force: force);
      }
      return;
    }

    // Completed / cancelled
    if (s == 'completed' || s == 'cancelled' || s == 'canceled') {
      _clearActiveRoute(clearVisuals: true, clearKey: true);
      return;
    }

    // Phase 1 (driver approaching pickup)
    if (s == 'driver_assigned' ||
        s == 'accepted' ||
        s == 'driver_approaching' ||
        s == 'approaching' ||
        s == 'arriving' ||
        s == 'assigned') {
      final pickup = customerLatLng;
      if (driverPos != null && pickup != null) {
        _maybeRerouteFromDriver(driverPos, force: force);
      }
    }
  }

  void _clearActiveRoute({bool clearVisuals = true, bool clearKey = true}) {
    if (clearVisuals) {
      activeRoutePoints.clear();
      polylines.clear();
    }
    if (clearKey) _lastRouteKey = '';
    _lastRouteFetchAt = DateTime.fromMillisecondsSinceEpoch(0);
    // Keep the last signature when visuals are kept, so the new route will only
    // apply if it is actually different (prevents rapid redraw flicker).
    if (clearVisuals) _activeRouteSig = '';
    _routeInFlightKey = null;
  }

  Future<void> _drawPolyline({
    required LatLng origin,
    required LatLng destination,
    required String polyId,
    bool force = false,
    String? cacheKey,
  }) async {
    // Never run multiple Directions calls in parallel. If we need a newer route
    // (phase switch / off-route), queue the latest request and run it right
    // after the current fetch finishes.
    if (_isDrawingPolyline) {
      _pendingRouteRequest = _RouteRequest(
        origin: origin,
        destination: destination,
        polyId: polyId,
        force: force,
        cacheKey: cacheKey,
      );
      return;
    }
    _isDrawingPolyline = true;

    try {
      final resolvedCacheKey =
          cacheKey ??
          _routeCacheKey(
            toDrop: polyId == 'driver_to_drop',
            origin: origin,
            destination: destination,
          );

      // Prevent duplicate same-origin/same-destination requests while one is in-flight.
      if (_routeInFlightKey == resolvedCacheKey) return;

      final cached = _routeCache[resolvedCacheKey];
      if (cached != null && cached.length >= 2) {
        if (kDebugMode) {
          AppLogger.log.i(
            '🧭 route cache hit: $resolvedCacheKey (${cached.length} pts)',
          );
        }
        final sig = _routeSig(cached);
        if (sig != _activeRouteSig) {
          _activeRouteSig = sig;
          activeRoutePoints.assignAll(cached);
          polylines.assignAll(MapUiDefaults.routePolylines(cached, id: polyId));
        }
        return;
      }

      _routeInFlightKey = resolvedCacheKey;
      if (kDebugMode) {
        AppLogger.log.i(
          '🧭 route fetch: $resolvedCacheKey (origin=${origin.latitude.toStringAsFixed(5)},${origin.longitude.toStringAsFixed(5)} dest=${destination.latitude.toStringAsFixed(5)},${destination.longitude.toStringAsFixed(5)})',
        );
      }
      final route = await _dir.getRouteInfo(
        origin: origin,
        destination: destination,
        mode: "driving",
        alternatives: false,
        traffic: true,
      );

      final pts = _simplifyPolyline(route.points);
      if (pts.length < 2) return;

      _cachePut(resolvedCacheKey, pts);

      final sig = _routeSig(pts);
      if (sig != _activeRouteSig) {
        _activeRouteSig = sig;
        activeRoutePoints.assignAll(pts);
        polylines.assignAll(MapUiDefaults.routePolylines(pts, id: polyId));
        if (kDebugMode) {
          AppLogger.log.i('🧭 route applied: ${pts.length} pts ($polyId)');
        }
      }
    } catch (e) {
      AppLogger.log.e("Polyline error: $e");
      // Production-safe fallback: if Directions fails and we don't have a route
      // yet, draw a straight line so the UI never looks "broken/blank".
      if (activeRoutePoints.isEmpty) {
        final pts = <LatLng>[origin, destination];
        _activeRouteSig = _routeSig(pts);
        activeRoutePoints.assignAll(pts);
        polylines.assignAll(MapUiDefaults.routePolylines(pts, id: polyId));
      }
    } finally {
      _routeInFlightKey = null;
      _isDrawingPolyline = false;

      final pending = _pendingRouteRequest;
      _pendingRouteRequest = null;
      if (pending != null) {
        // Run latest queued request.
        unawaited(
          _drawPolyline(
            origin: pending.origin,
            destination: pending.destination,
            polyId: pending.polyId,
            force: true,
            cacheKey: pending.cacheKey,
          ),
        );
      }
    }
  }

  // =================================================================
  //                         MATH
  // =================================================================

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
    _pulseTimer = Timer.periodic(const Duration(milliseconds: 320), (_) {
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

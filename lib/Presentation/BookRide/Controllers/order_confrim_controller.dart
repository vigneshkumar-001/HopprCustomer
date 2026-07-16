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
import 'package:hopper/api/dataSource/apiDataSource.dart';
import 'package:hopper/Presentation/BookRide/Controllers/driver_search_controller.dart';
import 'package:hopper/uitls/map/direction_helper.dart';
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
  static const double _minAutoFollowZoom = 16.35;
  BuildContext? _screenCtx;
  Timer? _searchTimer;
  final RxBool focusDriverOnNextTap = false.obs;

  static const double _mapTilt = 28.0;

  // Auto camera control (Ola style)
  DateTime _lastCameraMoveAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _cameraInterval = const Duration(milliseconds: 900);
  DateTime _pauseAutoFollowUntil = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _userGesturePause = const Duration(seconds: 6);
  bool _hasFittedAtLeastOnce = false;
  bool _autoFitBoundsEnabled = true;
  bool _didFitDriverAndPickup = false;
  bool _didFitDriverAndDrop = false;
  static const double _focusDriverZoom = 16.9;
  DateTime _lastAutoFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _autoFrameInterval = const Duration(milliseconds: 1400);
  static const Duration _routeTrimInterval = Duration(milliseconds: 90);
  int _lastTrimSegIndex = -1;

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
  // Customer "Didn't get it? / Resend" support. Client cooldown + busy flag
  // mirror the server's 30s / 5-attempt policy so the button can't be spammed.
  final ApiDataSource _otpApi = ApiDataSource();
  final RxBool otpResending = false.obs;
  final RxInt otpResendCooldown = 0.obs;
  Timer? _otpCooldownTimer;
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

  /// Server emit time (serverEmittedAt/serverTime/...) for the latest accepted
  /// [driverLocation]. Passed to the map widget so its playback jitter-buffer is
  /// timed off the server clock instead of client packet-arrival time.
  final Rxn<DateTime> driverLocationServerTs = Rxn<DateTime>();

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
  static const Duration _driverMarkerMinInterval = Duration(milliseconds: 70);
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

  // --------------------------------------------------------------------------
  // Monotonic phase/state machine: ACCEPTED(1) -> ARRIVED(2) -> STARTED(3) ->
  // COMPLETED(4). Phase only ever ADVANCES. Applied independently of the
  // position-ordering gate because a snapshot can carry a FORWARD status with an
  // OLD timestamp (booking-954881): the pickup->drop switch must not be lost to
  // a stale-by-time position drop, and a late ACCEPTED/ARRIVED must never rewind
  // us back to the pickup route.
  // --------------------------------------------------------------------------
  int _maxPhaseRank = 0;

  int _phaseRankForStatus(String status) {
    final s = status.trim().toUpperCase();
    if (_isCompletedStatus(s)) return 4;
    if (_isDropPhaseStatus(s)) return 3;
    if (s == 'ARRIVED' ||
        s == 'DRIVER_ARRIVED' ||
        s == 'REACHED' ||
        s == 'DRIVER_REACHED' ||
        s == 'ARRIVED_AT_PICKUP') {
      return 2;
    }
    if (s == 'ACCEPTED' ||
        s == 'CONFIRMED' ||
        s == 'ASSIGNED' ||
        s == 'DRIVER_ASSIGNED' ||
        s == 'DRIVER_ACCEPTED' ||
        s == 'ARRIVING' ||
        s == 'ON_THE_WAY' ||
        s == 'EN_ROUTE') {
      return 1;
    }
    return 0; // unknown -> leave phase untouched
  }

  /// Apply a status update under the monotonic phase rule. Safe to call for
  /// EVERY packet (including stale-by-time snapshots) and for the dedicated
  /// status socket events. Forward transitions run exactly once; regressions and
  /// same-rank repeats are ignored.
  void _applyMonotonicPhase(String latestStatus, {required LatLng driverPos}) {
    // Sync from any other path that may have advanced the phase (joined-booking,
    // ride-started event, resume) so those states can't be rewound here either.
    if (driverStartedRide.value && _maxPhaseRank < 3) _maxPhaseRank = 3;

    final rank = _phaseRankForStatus(latestStatus);
    if (rank == 0) return; // unknown status
    if (rank < _maxPhaseRank) {
      if (kDebugMode) {
        AppLogger.log.d(
          'phase regression ignored status=$latestStatus '
          'rank=$rank max=$_maxPhaseRank',
        );
      }
      return;
    }
    if (rank == _maxPhaseRank) return; // no phase change
    _maxPhaseRank = rank;

    final effectiveStatus =
        latestStatus.trim().isNotEmpty ? latestStatus : latestRideStatus.value;

    // STARTED / drop phase: switch to toDrop exactly once. The map view resets
    // its forward-only trim index when the new (drop) route is applied.
    if (rank >= 3 && !driverStartedRide.value) {
      driverStartedRide.value = true;
      _didFitDriverAndDrop = false;
      _seedStaticMarkers(forceRecreate: false);
      _refreshPulseCircles();
      _updatePolylinesForStatus(
        effectiveStatus,
        driverPos: driverPos,
        force: true,
      );
    }

    // COMPLETED: arrived at destination, clear the active route.
    if (rank >= 4) {
      if (!driverStartedRide.value) driverStartedRide.value = true;
      destinationReached.value = true;
      nearDestination.value = true;
      etaChipText.value = 'Arrived at destination';
      _seedStaticMarkers(forceRecreate: false);
      _refreshPulseCircles();
      _clearActiveRoute();
    }
  }

  // =================================================================
  //                  SMOOTH DRIVER ENGINE
  // =================================================================
  // Latest accepted driver pose (raw packet pose). The VISIBLE marker + follow
  // camera are animated solely by CustomerRideMapView's TrackingPlaybackEngine;
  // these fields only feed controller-side helpers (route-fetch origin, framing,
  // legacy markers). There is intentionally NO second animation engine here.
  LatLng? _displayPos;
  LatLng? _emaPos;
  double _lastBearing = 0.0;
  DateTime _lastAcceptedDriverLocationTs = DateTime.fromMillisecondsSinceEpoch(
    0,
    isUtc: true,
  );
  LatLng? _lastAcceptedDriverLocationPos;
  int _lastAcceptedDriverSeq = -1;
  // [LIVETRACK] debug: throttle for the raw-received trace (grep "LIVETRACK").
  DateTime? _lastLiveTrackRecvLogAt;
  DateTime _receiveMetricsWindowStartedAt = DateTime.now().toUtc();
  int _receiveCountWindow = 0;
  int _lastGapMs = 0;
  int _duplicateDroppedCount = 0;
  int _staleDroppedCount = 0;
  DateTime _lastAcceptedUpdateLocationAt = DateTime.fromMillisecondsSinceEpoch(
    0,
  );
  String? _lastAcceptedUpdateLocationBookingId;
  static const Duration _heartbeatLowPriorityWindow = Duration(seconds: 4);

  // Tiered live-tracking freshness (AC#1). Measured from the last ACCEPTED
  // driver fix (server/device time), not wall-clock receive time. Lets the UI
  // distinguish live / reconnecting / signal-lost instead of silently showing a
  // frozen car. The motion engine already glides (dead-reckon) for the first
  // few seconds; these flags drive the chip once the gap is clearly too long.
  Timer? _freshnessTimer;
  static const Duration _trackingStaleAfter = Duration(seconds: 8);
  static const Duration _trackingHardStaleAfter = Duration(seconds: 10);
  final RxBool driverSignalStale = false.obs; // >8s -> "Reconnectingâ€¦"
  final RxBool driverSignalLost = false.obs; // >10s -> "Driver signal lost"
  // Wall-clock time of the last VALID tracking packet for this booking â€” any
  // packet carrying coordinates, INCLUDING stationary same-point snapshots. The
  // watchdog measures CONTACT from here, not marker movement: a driver stopped
  // at a signal still emits, so identical snapshots must not read as "lost".
  DateTime _lastTrackingContactAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Single source of truth for the live-tracking socket events this controller
  // owns. Used both to clear-before-(re)subscribe in _setupSocketListeners and
  // to tear them down in onClose, so the two lists can never drift apart.
  static const List<String> _trackedSocketEvents = <String>[
    'joined-booking',
    'driver-location',
    'driver-heartbeat',
    'driver-arrived',
    'otp-generated',
    'ride-started',
    'driver-reached-destination',
    'customer-cancelled',
    'driver-cancelled',
    'active_ride_sync_required',
    // Instant active-booking cleanup signals (backend emits after final payment).
    'payment_success',
    'ride_completed',
    'active_booking_cleared',
  ];

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
    // NOTE: the controller-side DriverMotionEngine was removed. It never drove
    // the visible marker (its onUpdate only stored scalars; onFrameSideEffects
    // was a no-op) yet ran an AnimationController + dead-reckon timer per packet.
    // The single source of truth for marker animation is now CustomerRideMapView's
    // TrackingPlaybackEngine. Controller pose fields are updated directly from the
    // accepted packet in _handleDriverTrackingUpdate.
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
    _startFreshnessWatchdog();
    socketService.retainOnlyBookingContext(bookingId);
    // ALWAYS join the booking room so the customer receives live driver-location
    // broadcasts â€” the backend joins the room by bookingId alone, no driverId
    // needed. Previously this was gated on `resumeDriverId`, so on a fresh ride
    // (driver just accepted, resumeDriverId empty) the socket never joined the
    // room: the car showed from the initial snapshot but never moved, because no
    // live `driver-location` packets arrived. Stored in the socket's room map so
    // it auto-rejoins on every reconnect too.
    if (bookingId.trim().isNotEmpty) {
      socketService.joinBookingRoom(bookingId: bookingId);
    }
    // Fallback source of truth: if the live socket OTP event was missed (socket
    // down on a flaky network / app cold-started), seed the PIN from the
    // active-booking record so the customer can always read it.
    unawaited(_seedOtpFromActiveBooking());
    await _initLocation();
  }

  /// Seed the start-trip OTP from the persistent active-booking record (HTTP),
  /// so a missed `otp-generated` socket event never leaves the customer without
  /// the PIN. Only fills when we don't already have one.
  Future<void> _seedOtpFromActiveBooking() async {
    try {
      final res = await _otpApi.getActiveBooking();
      res.fold((_) {}, (active) {
        final code = (active.data?.otpCode ?? '').toString().trim();
        final bid = (active.data?.bookingId ?? '').toString().trim();
        final verified = active.data?.otpVerified == true;
        if (code.isNotEmpty &&
            !verified &&
            (bid.isEmpty || bid == bookingId) &&
            otp.value.isEmpty) {
          otp.value = code;
        }
      });
    } catch (_) {}
  }

  /// Customer-initiated "Didn't get it? / Resend" â€” calls the resend API and
  /// starts a client cooldown. Server enforces the real 30s/5-attempt policy.
  Future<void> resendRideOtp() async {
    if (otpResending.value || otpResendCooldown.value > 0) return;
    if (bookingId.trim().isEmpty) return;
    otpResending.value = true;
    _startOtpCooldown(
      30,
    ); // immediate client cooldown; server is source of truth
    try {
      final res = await _otpApi.resendRideOtp(bookingId);
      res.fold(
        (fail) => Get.snackbar('OTP', fail.message),
        (data) => Get.snackbar(
          'OTP',
          (data['message'] ?? 'OTP resent to your device').toString(),
        ),
      );
    } catch (_) {
      // network error â€” client cooldown already running; user can retry after it
    } finally {
      otpResending.value = false;
    }
  }

  void _startOtpCooldown(int seconds) {
    _otpCooldownTimer?.cancel();
    otpResendCooldown.value = seconds;
    _otpCooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (otpResendCooldown.value <= 1) {
        otpResendCooldown.value = 0;
        t.cancel();
      } else {
        otpResendCooldown.value -= 1;
      }
    });
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
    _disposed = true;
    _searchTimer?.cancel();
    _pulseTimer?.cancel();
    _driverMarkerFlushTimer?.cancel();
    _freshnessTimer?.cancel();
    _otpCooldownTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    try {
      socketService.leaveBooking(bookingId);
      // Remove every listener this controller registered (not just four) so a
      // back-to-back ride starts with a clean single listener per event.
      for (final event in _trackedSocketEvents) {
        socketService.off(event);
      }
    } catch (_) {}
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
    // UX: 1st tap -> focus the moving driver, 2nd tap -> fit bounds (driverâ†”pickup/drop)
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
        assetPath: AppImages.pin,
        tint: const Color(0xFF000000),
        widthDp: MapUiDefaults.pickupDropPinWidthDp,
        dpr: dpr,
      );
    } catch (_) {
      pickupPinIcon = null;
    }
    try {
      dropPinIcon = await CompactMarkerIcons.assetPin(
        assetPath: AppImages.pin,
        tint: const Color(0xFF15803D),
        widthDp: MapUiDefaults.pickupDropPinWidthDp,
        dpr: dpr,
      );
    } catch (_) {
      dropPinIcon = null;
    }
    try {
      pickupWaitingLabelIcon = await CompactMarkerIcons.labeledPin(
        label: MapUiDefaults.placeLabel(pickupAddress, fallback: 'Pickup'),
        assetPath: AppImages.pin,
        tint: const Color(0xFF000000),
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
        assetPath: AppImages.pin,
        tint: const Color(0xFF000000),
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
        assetPath: AppImages.pin,
        tint: const Color(0xFF15803D),
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
      AppLogger.log.i("Ã°Å¸â€œÂ customer currentPosition: $currentPosition");
    } catch (_) {}
  }

  // ---------- driver search timer ----------
  void startDriverSearchTimer() {
    _searchTimer?.cancel();

    isDriverConfirmed.value = false;
    driverStartedRide.value = false;
    _maxPhaseRank = 0; // reset phase machine for a fresh / back-to-back ride
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
  // H6: reconnect recovery. The backend (Phase 2) emits 'active_ride_sync_required'
  // after it validates our session on reconnect. We then RE-PULL the authoritative
  // ride state over HTTP (status + latest driver location) instead of trusting the
  // local cache, and make sure the booking room is rejoined. Deduped (no parallel /
  // rapid-fire calls on a flaky network) and timeout-bounded so it can never hang.
  bool _recovering = false;
  bool _disposed = false;
  DateTime _lastRecoverAt = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _recoverActiveRide({String reason = 'reconnect'}) async {
    if (_disposed || _recovering) return;
    final now = DateTime.now();
    if (now.difference(_lastRecoverAt) < const Duration(seconds: 3)) return;
    _recovering = true;
    _lastRecoverAt = now;
    try {
      // Booking room auto-rejoins via the socket room map, but force it so live
      // driver-location resumes even if the cached payload was dropped.
      if (bookingId.trim().isNotEmpty) {
        socketService.joinBookingRoom(bookingId: bookingId, force: true);
      }
      final res = await _otpApi.getActiveBooking().timeout(
        const Duration(seconds: 10),
      );
      if (_disposed) return;
      res.fold((_) {}, (active) {
        if (active.hasActiveBooking != true || active.data == null) return;
        final d = active.data!;
        if (d.bookingId.isNotEmpty &&
            bookingId.isNotEmpty &&
            d.bookingId != bookingId) {
          return; // a different ride owns this controller; ignore
        }
        // Restore canonical status from the backend (source of truth).
        final status = d.status.trim().toUpperCase();
        if (status.isNotEmpty) latestRideStatus.value = status;
        if (d.cancelled) isTripCancelled.value = true;
        // Seed the latest driver location WITHOUT fighting the live smooth stream:
        // only when no fresh driver-location packet arrived in the last 6s.
        final loc = d.driverLocation;
        if (loc != null) {
          final pos = LatLng(loc.latitude, loc.longitude);
          final hasLiveStream =
              _lastAcceptedDriverLocationPos != null &&
              DateTime.now().difference(_lastAcceptedDriverLocationTs) <
                  const Duration(seconds: 6);
          if (!hasLiveStream) {
            driverLocation.value = pos;
            _displayPos = pos;
            _emaPos = pos;
            _updateDriverMarker(pos, 0.0);
          }
        }
        AppLogger.log.i('Active-ride recovery ($reason): status=$status');
      });
    } catch (_) {
      // Keep the last marker; never clear the ride just because recovery failed.
    } finally {
      _recovering = false;
    }
  }

  /// Backend signalled this booking is paid/finished. Reflect the terminal state
  /// (mirrors driver-reached-destination) and re-pull authoritative state so the
  /// screen leaves tracking via its normal completion flow. Ignores events for a
  /// DIFFERENT booking (shared co-passenger safety) so we never end the wrong ride.
  void _handlePaymentTerminalEvent(dynamic data, String event) {
    if (isClosed || _disposed) return;
    final payload = _normalizeSocketPayload(data);
    final evtBookingId = (payload['bookingId'] ?? '').toString().trim();
    if (evtBookingId.isNotEmpty &&
        bookingId.isNotEmpty &&
        evtBookingId != bookingId) {
      return; // another passenger's leg â€” leave this ride untouched
    }
    latestRideStatus.value = 'COMPLETED';
    destinationReached.value = true;
    _clearActiveRoute();
    AppLogger.log.i('[$event] terminal -> re-verifying active booking');
    _recoverActiveRide(reason: event);
  }

  void _setupSocketListeners() {
    // Idempotent re-bind (req-6: exactly one listener per event). A controller
    // can re-register on reconnect, app-resume, hot reload, or a back-to-back
    // ride that re-uses the singleton socket. Without clearing first, each
    // re-bind STACKS another handler on the same event, so a single
    // driver-location packet is processed N times -> marker churn + duplicate
    // status transitions. Clear our events before (re)subscribing.
    for (final event in _trackedSocketEvents) {
      socketService.off(event);
    }

    socketService.onConnect(() {
      AppLogger.log.i("Socket connected on booking screen");
    });

    // H6: backend asks us to resync after it validated our session on reconnect.
    socketService.on(
      'active_ride_sync_required',
      (_) => _recoverActiveRide(reason: 'sync-required'),
    );

    // Final payment (online or cash) reached -> reflect terminal state so the
    // screen shows its completion UI, then re-verify over HTTP (never trust the
    // socket alone). Guarded by bookingId so a SHARED co-passenger's payment can
    // never end THIS customer's ride.
    socketService.on('payment_success', (data) {
      _handlePaymentTerminalEvent(data, 'payment_success');
    });
    socketService.on('ride_completed', (data) {
      _handlePaymentTerminalEvent(data, 'ride_completed');
    });
    socketService.on('active_booking_cleared', (data) {
      _handlePaymentTerminalEvent(data, 'active_booking_cleared');
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
      driverName.value = '$driverFullName â­ï¸ $rating';
      carDetails.value = '$color - $brand';
      isDriverConfirmed.value = hasDriver;
      driverPhone.value = driverPhoneStr;
      customerPhone.value = customerPhoneStr;
      cartypeFromServer.value = vehicleType;
      amount.value = amt;
      profilePic.value = profile;
      carExteriorPhotos.value = photos;

      // Keep this screen on the booking room only.
      //
      // `CustomerRideMapView` renders from the booking-room `driver-location`
      // stream. Re-subscribing to `track-driver` here produced an extra
      // `tracked-driver-location` feed for the same driver, which added socket
      // noise and made debugging the live movement much harder.
      final eventBookingId = (payload['bookingId'] ?? '').toString().trim();
      final joinBookingId = eventBookingId.isNotEmpty ? eventBookingId : '';
      if (joinBookingId.isNotEmpty) {
        socketService.retainOnlyBookingContext(joinBookingId);
        socketService.joinBookingRoom(bookingId: joinBookingId, force: true);
      }

      _seedStaticMarkers(forceRecreate: true);

      final hasLiveDriverStream =
          _lastAcceptedDriverLocationPos != null &&
          _lastAcceptedDriverLocationTs.isAfter(
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          );
      if (driverLat != null && driverLng != null && !hasLiveDriverStream) {
        final initialDriverPos = LatLng(driverLat, driverLng);
        driverLocation.value = initialDriverPos;
        _displayPos = initialDriverPos;
        _emaPos = initialDriverPos;
        _lastBearing = 0.0;
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

      if (driverLat != null && driverLng != null && !hasLiveDriverStream) {
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
    });

    socketService.on(
      'driver-location',
      (data) => _handleDriverTrackingUpdate(data, source: 'driver-location'),
    );
    socketService.on(
      'driver-heartbeat',
      (data) => _handleDriverTrackingUpdate(data, source: 'driver-heartbeat'),
    );

    socketService.on('driver-arrived', (data) {
      if (isClosed) return;
      // Robust parse (matches the `ride-started` fix): the server may send
      // `status` as a bool / number / string, and the presence of `arrivedAt`
      // or an "arrived" message is itself a definitive arrival signal. The old
      // strict `data['status'] == true` silently missed those, so the arrival
      // UI never appeared even though the event arrived.
      bool arrived = false;
      if (data is Map) {
        final raw = data['status'];
        final s = (raw ?? '').toString().trim().toLowerCase();
        final msg = (data['message'] ?? '').toString().toLowerCase();
        arrived =
            raw == true ||
            raw == 1 ||
            s == 'true' ||
            s == '1' ||
            s.contains('arriv') ||
            data['arrivedAt'] != null ||
            msg.contains('arriv');
      } else {
        final s = (data ?? '').toString().trim().toLowerCase();
        arrived = s == 'true' || s == '1' || s.contains('arriv');
      }
      // Ignore a late ARRIVED once the ride has STARTED (monotonic phase rule):
      // it must not rewrite the chip back to "Driver arrived".
      if (arrived && !driverStartedRide.value) {
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

      // Robust status parse: the server may send a bool, a number, or a string
      // ("true"/"1"/"STARTED"). A strict `== true` missed those and left the map
      // stuck on the pickup phase (pickup marker + driver->pickup line).
      final dynamic rawStatus = (data is Map) ? data['status'] : data;
      final String statusStr =
          (rawStatus ?? '').toString().trim().toLowerCase();
      final bool status =
          rawStatus == true ||
          rawStatus == 1 ||
          statusStr == 'true' ||
          statusStr == '1' ||
          statusStr.contains('start');
      // Set-true-only: never let a malformed/late ride-started event (status
      // parsed false) rewind us out of the drop phase (monotonic phase rule).
      if (status) {
        driverStartedRide.value = true;
        if (_maxPhaseRank < 3) _maxPhaseRank = 3;
        driverArrived.value = true;
        latestRideStatus.value = 'STARTED';
        _updateRideMetrics(data);
      }

      _seedStaticMarkers(forceRecreate: false);
      _refreshPulseCircles();

      // redraw driver->drop immediately (once). Anchor the drop route at the
      // FRESHEST RAW driver fix, not the smoothed engine position.
      //
      // BUG (booking-474342): the drop route was being fetched from `_emaPos`
      // (the controller's smoothed motion-engine output). That smoothed value
      // can lag â€” or freeze â€” several fixes behind the real position, so at
      // ride-start it still held the pickup/accept-time location (~the spot the
      // driver accepted from). The result: a driver->drop polyline drawn from a
      // stale point hundreds of metres off the driver's true position, which
      // then made the car fall outside the snap-to-route tolerance for ~30s
      // (constant "trim paused" + raw-GPS jitter / shake / backward drift) until
      // the next live packet re-routed from the real position.
      //
      // `_lastAcceptedDriverLocationPos` is the last accepted *raw* GPS fix and
      // is always at least as fresh as `_emaPos`; prefer it, then the exposed
      // raw `driverLocation.value`, and only fall back to the smoothed pose.
      if (status && customerToLatLng != null) {
        final polyOrigin =
            _lastAcceptedDriverLocationPos ??
            driverLocation.value ??
            _emaPos ??
            _displayPos;
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
      if (data != null && _isCancelPayload(data)) {
        isTripCancelled.value = true;
        cancelReason.value =
            (data['message'] ?? data['reason'] ?? "Trip cancelled").toString();
        _clearActiveRoute();
      }
    });

    socketService.on('driver-cancelled', (data) {
      if (isClosed) return;
      if (data != null && _isCancelPayload(data)) {
        isTripCancelled.value = true;
        cancelReason.value =
            (data['message'] ?? data['reason'] ?? "Trip cancelled").toString();
        _clearActiveRoute();
      }
    });
  }

  // Lenient cancellation-payload check (mirrors the already-hardened shared-
  // ride version in shared_screens.dart) â€” the strict `status == true` check
  // silently dropped the event if the backend ever sent status as a string
  // ("CANCELLED"), omitted it, or used a different field.
  bool _isCancelPayload(dynamic data) {
    final st = data['status'];
    final statusStr = (st ?? '').toString().toUpperCase();
    return st == true ||
        statusStr == 'CANCELLED' ||
        statusStr == 'DRIVER_CANCELLED' ||
        data['clearActiveRide'] == true ||
        st == null;
  }

  DateTime _parseServerTime(dynamic ts) {
    try {
      if (ts == null) return DateTime.now().toUtc();
      if (ts is int) {
        if (ts < 2000000000) {
          return DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true);
        }
        return DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true);
      }
      if (ts is String) {
        final parsed = DateTime.tryParse(ts);
        if (parsed != null) return parsed.toUtc();
      }
      return DateTime.now().toUtc();
    } catch (_) {
      return DateTime.now().toUtc();
    }
  }

  DateTime _normalizeTrackingTimestampUtc(
    DateTime ts, {
    required bool simulated,
    Duration maxFutureSkew = const Duration(seconds: 12),
  }) {
    final nowUtc = DateTime.now().toUtc();
    if (ts.isAfter(nowUtc.add(maxFutureSkew))) {
      return nowUtc;
    }
    return ts;
  }

  bool _isSameTrackingPoint(LatLng a, LatLng b, {double epsilonMeters = 0.6}) {
    return Geolocator.distanceBetween(
          a.latitude,
          a.longitude,
          b.latitude,
          b.longitude,
        ) <=
        epsilonMeters;
  }

  bool _shouldAcceptTrackingPacket({
    required DateTime receivedTsUtc,
    required LatLng position,
    required bool simulated,
    required String source,
    int? seq,
  }) {
    final lastAcceptedTsUtc = _lastAcceptedDriverLocationTs;
    final lastAcceptedPos = _lastAcceptedDriverLocationPos;
    String decision = 'accepted';

    // Future-timestamp guard. A driver device with a skewed clock can send a fix
    // dated far in the future. Accepting it makes `_lastAcceptedDriverLocationTs`
    // jump ahead, after which EVERY subsequent real fix reads as `older_than_last`
    // and is rejected forever â€” the marker freezes and never recovers. Drop a
    // clearly-future packet so it can never become the baseline. (Simulated
    // packets are trusted; their timestamps are generated locally.)
    if (!simulated) {
      final futureSkew = receivedTsUtc.difference(DateTime.now().toUtc());
      if (futureSkew > const Duration(minutes: 2)) {
        decision = 'future_ts';
        _staleDroppedCount += 1;
        _logReceiveMetricsIfNeeded();
        if (kDebugMode) {
          AppLogger.log.w(
            'ride tracking decision source=$source receivedTsUtc=$receivedTsUtc '
            'futureSkewMs=${futureSkew.inMilliseconds} staleDecision=$decision '
            'markerUpdated=false',
          );
        }
        return false;
      }
    }

    if (seq != null && seq > 0 && _lastAcceptedDriverSeq > 0) {
      if (seq <= _lastAcceptedDriverSeq) {
        // Seq-space reset detector (defense-in-depth). The driver app emits from
        // two isolates with independent seq counters (foreground socket vs the
        // background location service). On a foreground->background handoff â€”
        // the driver opening Google Maps â€” the counter can restart lower, so a
        // genuinely fresh fix looks "older" by seq. If the wall-clock timestamp
        // is clearly newer than the last accepted fix, trust time over seq:
        // accept and let the caller re-baseline _lastAcceptedDriverSeq to this
        // new (lower) value. Keeps the marker live through navigation even if a
        // driver build without the monotonic-seq fix is in the field.
        final bool seqResetWithNewerTime =
            seq < _lastAcceptedDriverSeq &&
            receivedTsUtc.isAfter(
              lastAcceptedTsUtc.add(const Duration(seconds: 2)),
            );
        if (!seqResetWithNewerTime) {
          decision =
              seq == _lastAcceptedDriverSeq ? 'duplicate_seq' : 'older_seq';
          if (seq == _lastAcceptedDriverSeq) {
            _duplicateDroppedCount += 1;
          } else {
            _staleDroppedCount += 1;
          }
          _logReceiveMetricsIfNeeded();
          if (kDebugMode) {
            AppLogger.log.d(
              'ride tracking decision source=$source receivedTsUtc=$receivedTsUtc '
              'lastAcceptedTsUtc=$lastAcceptedTsUtc staleDecision=$decision '
              'markerUpdated=false',
            );
          }
          return false;
        }
        // Fall through: treat as a seq reset. The duplicate-point and
        // older-than-last timestamp guards below still protect against
        // teleports and true regressions.
      }
    }

    if (lastAcceptedPos != null) {
      final samePoint = _isSameTrackingPoint(lastAcceptedPos, position);
      if (samePoint) {
        decision = 'duplicate_same_point';
        _duplicateDroppedCount += 1;
        _logReceiveMetricsIfNeeded();
        if (kDebugMode) {
          AppLogger.log.d(
            'ride tracking decision source=$source receivedTsUtc=$receivedTsUtc '
            'lastAcceptedTsUtc=$lastAcceptedTsUtc staleDecision=$decision '
            'markerUpdated=false',
          );
        }
        return false;
      }

      if (receivedTsUtc.isBefore(lastAcceptedTsUtc)) {
        decision = 'older_than_last';
        _staleDroppedCount += 1;
        _logReceiveMetricsIfNeeded();
        if (kDebugMode) {
          AppLogger.log.d(
            'ride tracking decision source=$source receivedTsUtc=$receivedTsUtc '
            'lastAcceptedTsUtc=$lastAcceptedTsUtc staleDecision=$decision '
            'markerUpdated=false',
          );
        }
        return false;
      }
    } else if (!simulated) {
      final age = DateTime.now().toUtc().difference(receivedTsUtc);
      if (age > const Duration(minutes: 2)) {
        decision = 'too_old_initial';
        _staleDroppedCount += 1;
        _logReceiveMetricsIfNeeded();
        if (kDebugMode) {
          AppLogger.log.d(
            'ride tracking decision source=$source receivedTsUtc=$receivedTsUtc '
            'lastAcceptedTsUtc=$lastAcceptedTsUtc staleDecision=$decision '
            'markerUpdated=false',
          );
        }
        return false;
      }
    }

    if (kDebugMode) {
      AppLogger.log.d(
        'ride tracking decision source=$source receivedTsUtc=$receivedTsUtc '
        'lastAcceptedTsUtc=$lastAcceptedTsUtc staleDecision=$decision '
        'markerUpdated=true',
      );
    }
    return true;
  }

  void _noteAcceptedTrackingPacket(DateTime receivedTsUtc) {
    if (_lastAcceptedDriverLocationTs.millisecondsSinceEpoch > 0) {
      _lastGapMs = receivedTsUtc
          .difference(_lastAcceptedDriverLocationTs)
          .inMilliseconds
          .clamp(0, 1 << 30);
    }
    _receiveCountWindow += 1;
    _logReceiveMetricsIfNeeded();
  }

  /// Tiered freshness watchdog (AC#1). Runs at 1 Hz and flips two observables
  /// from the gap since the last ACCEPTED driver fix:
  ///   gap >= 8s  -> driverSignalStale  (UI: dim marker + "Reconnectingâ€¦")
  ///   gap >= 10s -> driverSignalLost   (UI: "Driver signal lost")
  /// 0-8s is left to the motion engine, which keeps the marker gliding /
  /// dead-reckoning so short gaps never surface as a frozen car.
  void _startFreshnessWatchdog() {
    _freshnessTimer?.cancel();
    _freshnessTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isClosed) return;
      final lastContact = _lastTrackingContactAt;
      if (lastContact.millisecondsSinceEpoch <= 0) return; // no contact yet
      final gap = DateTime.now().difference(lastContact);
      final bool stale = gap >= _trackingStaleAfter;
      final bool lost = gap >= _trackingHardStaleAfter;
      if (driverSignalStale.value != stale) driverSignalStale.value = stale;
      if (driverSignalLost.value != lost) driverSignalLost.value = lost;
    });
  }

  void _logReceiveMetricsIfNeeded() {
    if (!kDebugMode) return;
    final now = DateTime.now().toUtc();
    if (now.difference(_receiveMetricsWindowStartedAt) <
        const Duration(minutes: 1)) {
      return;
    }
    AppLogger.log.d(
      'ride tracking metrics receive_rate=$_receiveCountWindow/min '
      'last_gap_ms=$_lastGapMs duplicate_dropped=$_duplicateDroppedCount '
      'stale_dropped=$_staleDroppedCount',
    );
    _receiveMetricsWindowStartedAt = now;
    _receiveCountWindow = 0;
  }

  bool _isWrongBookingTrackingPacket(Map<String, dynamic> payload) {
    final packetBookingId =
        (payload['bookingId'] ?? payload['bookingID'] ?? '').toString().trim();
    return packetBookingId.isNotEmpty && packetBookingId != bookingId.trim();
  }

  String _effectiveTrackingSource(
    Map<String, dynamic> payload, {
    required String fallbackSource,
  }) {
    final raw =
        (payload['source'] ?? payload['event'] ?? fallbackSource)
            .toString()
            .trim()
            .toLowerCase();
    if (raw == 'driver-heartbeat' || raw == 'heartbeat') {
      return 'driver-heartbeat';
    }
    if (raw == 'updatelocation' ||
        raw == 'update_location' ||
        raw == 'driver-location' ||
        raw == 'location') {
      return 'updateLocation';
    }
    return fallbackSource;
  }

  bool _isLowPriorityHeartbeatSource(String source) {
    return source == 'driver-heartbeat';
  }

  void _markAcceptedTrackingSource(
    String source, {
    required Map<String, dynamic> payload,
  }) {
    if (source == 'updateLocation') {
      _lastAcceptedUpdateLocationAt = DateTime.now();
      _lastAcceptedUpdateLocationBookingId =
          (payload['bookingId'] ?? payload['bookingID'] ?? '')
              .toString()
              .trim();
    }
  }

  void _handleDriverTrackingUpdate(dynamic data, {required String source}) {
    if (isClosed) return;

    final payload = _normalizeSocketPayload(data);
    if (payload.isEmpty) return;
    if (_isWrongBookingTrackingPacket(payload)) {
      if (kDebugMode) {
        AppLogger.log.w(
          'Ignoring wrong-booking $source packet '
          'screenBooking=$bookingId packetBooking=${payload['bookingId']}',
        );
      }
      return;
    }

    final lat = _toDouble(payload['latitude'] ?? payload['lat']);
    final lng = _toDouble(payload['longitude'] ?? payload['lng']);
    if (lat == null || lng == null) {
      AppLogger.log.e("Invalid $source payload: $payload");
      return;
    }
    // Valid packet for our booking = live contact. Stamp + recover the chip now
    // (even for stationary same-point snapshots) so a stopped-but-connected
    // driver never surfaces as stale/lost.
    _lastTrackingContactAt = DateTime.now();
    if (driverSignalStale.value) driverSignalStale.value = false;
    if (driverSignalLost.value) driverSignalLost.value = false;

    final isSimulated =
        payload['simulated'] == true ||
        (payload['source'] ?? '').toString().trim().toLowerCase() ==
            'ride-simulator';

    final rawTs = _normalizeTrackingTimestampUtc(
      _parseServerTime(
        payload['timestamp'] ??
            payload['serverTime'] ??
            payload['serverReceivedAt'] ??
            payload['serverEmittedAt'] ??
            payload['deviceTimestamp'] ??
            payload['ts'] ??
            payload['time'],
      ),
      simulated: isSimulated,
    );
    final rawSeq =
        payload['seq'] ?? payload['sequence'] ?? payload['locationSeq'];
    final seq =
        rawSeq is num
            ? rawSeq.toInt()
            : int.tryParse((rawSeq ?? '').toString().trim());
    final newPos = LatLng(lat, lng);
    final effectiveSource = _effectiveTrackingSource(
      payload,
      fallbackSource: source,
    );
    final isHeartbeatSource = _isLowPriorityHeartbeatSource(effectiveSource);
    final packetBookingId =
        (payload['bookingId'] ?? payload['bookingID'] ?? '').toString().trim();
    final isActiveBookingPacket = packetBookingId.isNotEmpty;
    if (isHeartbeatSource && isActiveBookingPacket) {
      _updateRideMetrics(payload, packetPos: newPos);
      if (kDebugMode) {
        AppLogger.log.d(
          'Ignoring active-booking heartbeat '
          'bookingId=${packetBookingId.isEmpty ? "" : "***${packetBookingId.substring(packetBookingId.length > 4 ? packetBookingId.length - 4 : 0)}"} '
          'hasAcceptedUpdate=${_lastAcceptedUpdateLocationBookingId == packetBookingId}',
        );
      }
      return;
    }
    if (isHeartbeatSource &&
        _lastAcceptedUpdateLocationAt.millisecondsSinceEpoch > 0 &&
        DateTime.now().difference(_lastAcceptedUpdateLocationAt) <
            _heartbeatLowPriorityWindow) {
      _updateRideMetrics(payload, packetPos: newPos);
      if (kDebugMode) {
        AppLogger.log.d(
          'Ignoring low-priority heartbeat '
          'lastUpdateAgeMs=${DateTime.now().difference(_lastAcceptedUpdateLocationAt).inMilliseconds}',
        );
      }
      return;
    }

    // ---- Monotonic phase/state machine (independent of position ordering) ----
    // Apply status BEFORE the position gates below: a STARTED snapshot can carry
    // an old timestamp that the ordering gate would otherwise drop, losing the
    // pickup->drop switch; and a late ACCEPTED/ARRIVED must not rewind the mode.
    final String latestStatusEarly =
        (payload['latestStatus'] ?? payload['status'] ?? '')
            .toString()
            .toUpperCase();
    if (latestStatusEarly.trim().isNotEmpty) {
      _applyMonotonicPhase(latestStatusEarly, driverPos: newPos);
    }

    final samePointAsLast =
        _lastAcceptedDriverLocationPos != null &&
        _isSameTrackingPoint(_lastAcceptedDriverLocationPos!, newPos);
    final olderThanLast = rawTs.isBefore(_lastAcceptedDriverLocationTs);
    if (samePointAsLast && !olderThanLast) {
      _duplicateDroppedCount += 1;
      _logReceiveMetricsIfNeeded();
      _updateRideMetrics(payload, packetPos: newPos);
      final liveRideType =
          (payload['rideType'] ??
                  payload['vehicleType'] ??
                  payload['serviceType'] ??
                  '')
              .toString();
      if (liveRideType.trim().isNotEmpty) {
        cartypeFromServer.value = liveRideType;
      }
      // Phase/status already handled by _applyMonotonicPhase above. This is a
      // positional duplicate (snapshot / stationary) -> do NOT animate the
      // marker or rebuild the polyline/trim (task 3).
      return;
    }
    if (!_shouldAcceptTrackingPacket(
      receivedTsUtc: rawTs,
      position: newPos,
      simulated: isSimulated,
      source: effectiveSource,
      seq: seq,
    )) {
      if (kDebugMode) {
        AppLogger.log.w(
          'Ignoring stale ride $effectiveSource ts=$rawTs lat=$lat lng=$lng',
        );
      }
      return;
    }
    // (Restructured live-tracking pipeline) The consistency-drop, backward
    // micro-jitter, and force-accept-after-N gates that used to sit here have
    // been removed. Each of them froze the marker (sometimes for seconds) and
    // then released into a catch-up jump â€” the "appears then freezes & jumps"
    // symptom. CustomerRideMapView's single TrackingPlaybackEngine now owns ALL
    // jitter / stationary / teleport handling and glides smoothly between fixes,
    // so every ordered, non-duplicate fix is accepted and forwarded to it.
    _noteAcceptedTrackingPacket(rawTs);

    // (Restructured pipeline) The server-truth-speed "stationary hold" that used
    // to live here â€” holding the marker for up to 25m whenever the driver
    // reported speed < 0.7 m/s â€” has been removed. It was the main "freeze then
    // jump" source: a driver creeping in traffic reports low speed yet keeps
    // moving, so the marker froze for many metres and then leapt to catch up.
    // The playback engine's own stationary-jitter guard (implied speed +
    // small-move filter) keeps the marker rock-solid at a genuine stop without
    // freezing slow real movement.
    _lastAcceptedDriverLocationTs = rawTs;
    if (seq != null && seq > 0) {
      _lastAcceptedDriverSeq = seq;
    }
    // [track-gap] DIAGNOSTIC (hop 4/4: server â†’ customer). Fires only when the
    // customer resumes ACCEPTING real location packets after an anomalous
    // silence (>3s) â€” i.e. the exact moment the marker un-freezes and jumps
    // ahead. Correlate by timestamp with the driver/server [track-gap] logs:
    //   â€¢ driver-emit gap too  -> driver stopped sending (device/FGS/handoff).
    //   â€¢ server-inbound gap    -> network driverâ†’server dropped.
    //   â€¢ server-emit gap only  -> server suppressed/throttled its own forward.
    //   â€¢ only this one fires    -> network serverâ†’customer (or seq-gate drops).
    if (_lastAcceptedUpdateLocationAt.millisecondsSinceEpoch > 0) {
      final recvGapMs =
          DateTime.now()
              .difference(_lastAcceptedUpdateLocationAt)
              .inMilliseconds;
      if (recvGapMs > 3000) {
        AppLogger.log.w(
          '[track-gap] hop=customer-recv gap_ms=$recvGapMs seq=${seq ?? "na"} '
          'source=$effectiveSource booking=$bookingId',
        );
      }
    }
    _markAcceptedTrackingSource(effectiveSource, payload: payload);
    // [LIVETRACK] RAW input trace: the accepted driver fix BEFORE any snapping /
    // rendering. `moveM` = distance from the previous accepted fix; if this shows
    // big back-and-forth here, the back-stepping is already in the driver/server
    // feed; if recv is monotonic but the rendered `[LIVETRACK] draw` goes backward,
    // it's the client snap/engine. grep LIVETRACK.
    if (kDebugMode) {
      final prevAccepted = _lastAcceptedDriverLocationPos;
      final moveM =
          prevAccepted == null
              ? 0.0
              : Geolocator.distanceBetween(
                prevAccepted.latitude,
                prevAccepted.longitude,
                newPos.latitude,
                newPos.longitude,
              );
      final nowMs = DateTime.now();
      if (_lastLiveTrackRecvLogAt == null ||
          nowMs.difference(_lastLiveTrackRecvLogAt!) >=
              const Duration(milliseconds: 700)) {
        _lastLiveTrackRecvLogAt = nowMs;
        AppLogger.log.w(
          '[LIVETRACK] recv mode=${driverStartedRide.value ? "drop" : "pickup"} '
          'raw=${newPos.latitude.toStringAsFixed(6)},${newPos.longitude.toStringAsFixed(6)} '
          'moveM=${moveM.toStringAsFixed(1)} seq=${seq ?? "na"} '
          'spd=${(_toDouble(payload['speed']) ?? 0).toStringAsFixed(1)} '
          'src=$effectiveSource',
        );
      }
    }
    _lastAcceptedDriverLocationPos = newPos;
    driverLocation.value = newPos;
    // Surface the server emit time alongside the position so the map widget's
    // playback buffer is spaced by the server clock, not packet-arrival time.
    driverLocationServerTs.value = rawTs;

    final srvBearing = _toDouble(
      payload['bearing'] ?? payload['heading'] ?? payload['rotation'],
    );
    final liveRideType =
        (payload['rideType'] ??
                payload['vehicleType'] ??
                payload['serviceType'] ??
                '')
            .toString();
    if (liveRideType.trim().isNotEmpty) {
      cartypeFromServer.value = liveRideType;
    }
    final latestStatus =
        (payload['latestStatus'] ?? payload['status'] ?? '')
            .toString()
            .toUpperCase();
    _updateRideMetrics(payload, packetPos: newPos);
    // Phase transitions are owned by _applyMonotonicPhase (run at the top of
    // this handler). These locals only decide the position-driven route re-fetch
    // below â€” they no longer drive the mode switch.
    final derivedRideStarted = _isDropPhaseStatus(latestStatus);
    final derivedRideCompleted = _isCompletedStatus(latestStatus);
    final effectiveStatus =
        latestStatus.trim().isNotEmpty ? latestStatus : latestRideStatus.value;

    if (_displayPos == null) {
      _displayPos = newPos;
      _emaPos = newPos;
      _lastBearing = srvBearing ?? 0.0;
      _fitDriverAndPickupOnce();
      _updatePolylinesForStatus(
        effectiveStatus,
        driverPos: newPos,
        force: true,
      );
      return;
    }

    final displayDeltaMeters = Geolocator.distanceBetween(
      _displayPos!.latitude,
      _displayPos!.longitude,
      newPos.latitude,
      newPos.longitude,
    );

    // Keep the controller pose fields in sync with the latest accepted packet.
    // (The visible marker is animated by CustomerRideMapView's playback engine;
    // these feed only route-fetch origin / framing helpers, so the raw accepted
    // pose â€” fresher than any interpolation â€” is exactly what they want.)
    _displayPos = newPos;
    _emaPos = newPos;
    if (srvBearing != null) _lastBearing = srvBearing;

    // Re-fetch only on a meaningful move (was 2.5m). At 2.5m nearly every
    // packet re-fetched the route from a slightly different (jittery) origin,
    // which replaced `activeRoutePoints` and reset the widget's forward-only
    // trim index -> the line kept snapping back to full length and wobbling
    // between road snaps. Phase changes still force an immediate refresh below.
    final shouldRefreshRoute =
        activeRoutePoints.isEmpty ||
        derivedRideStarted ||
        derivedRideCompleted ||
        displayDeltaMeters > 20.0;
    if (shouldRefreshRoute) {
      _updatePolylinesForStatus(effectiveStatus, driverPos: newPos);
    }
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

  void _updateRideMetrics(dynamic data, {LatLng? packetPos}) {
    pickupDurationMin.value = _toInt(data['pickupDurationInMin']);
    dropDurationMin.value = _toInt(data['dropDurationInMin']);
    tripDurationMin.value = _toInt(data['tripDurationInMin']);
    final incomingStatus =
        (data['latestStatus'] ?? data['status'] ?? '').toString().toUpperCase();
    if (incomingStatus.isNotEmpty) {
      latestRideStatus.value = incomingStatus;
    }
    final rideStartedLike =
        driverStartedRide.value || _isDropPhaseStatus(incomingStatus);
    final anchorPos = _displayPos ?? _emaPos ?? driverLocation.value;
    final travelMoveMeters =
        packetPos == null || anchorPos == null
            ? 0.0
            : Geolocator.distanceBetween(
              anchorPos.latitude,
              anchorPos.longitude,
              packetPos.latitude,
              packetPos.longitude,
            );

    var nextPickupMeters = _toDouble(data['pickupDistanceInMeters']) ?? 0.0;
    var nextDropMeters = _toDouble(data['dropDistanceInMeters']) ?? 0.0;

    if (rideStartedLike) {
      nextPickupMeters = 0.0;
      if (dropDistanceMeters.value > 0 &&
          nextDropMeters > dropDistanceMeters.value + 220.0 &&
          travelMoveMeters < 45.0) {
        nextDropMeters = dropDistanceMeters.value;
      }
    } else {
      nextDropMeters = 0.0;
      if (pickupDistanceMeters.value > 0 &&
          nextPickupMeters > pickupDistanceMeters.value + 180.0 &&
          travelMoveMeters < 35.0) {
        nextPickupMeters = pickupDistanceMeters.value;
      }
    }

    pickupDistanceMeters.value = nextPickupMeters;
    dropDistanceMeters.value = nextDropMeters;

    if (!rideStartedLike) {
      final mins = pickupDurationMin.value;
      final meters = pickupDistanceMeters.value;
      // App-side arrival check (fires first; the `driver-arrived` socket event
      // is the fallback). When the live pickup distance shows the driver is
      // essentially at the pickup, mark arrived. `meters > 0` excludes the
      // no-data default so we never flip arrived prematurely.
      if (!driverArrived.value && meters > 0 && meters <= 30) {
        driverArrived.value = true;
      }
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

    _trimActiveRouteVisual(position);
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
      final mid = _cameraFollowTarget(
        driverPos: _emaPos!,
        anchorPos: customerLatLng!,
      );
      // Keep zoom stable so roads + vehicle icon remain clear (avoid zooming out).
      final z = lockedZoom.clamp(_minAutoFollowZoom, 16.75);
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
      final z = lockedZoom.clamp(_minAutoFollowZoom, 16.75);
      final target = _cameraFollowTarget(
        driverPos: _emaPos!,
        anchorPos: customerToLatLng,
      );
      try {
        mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: target,
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
    final z = lockedZoom.clamp(_minAutoFollowZoom, 16.75);
    final target = _cameraFollowTarget(driverPos: _emaPos!);
    try {
      mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: target,
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
    // Origin is rounded to 4 dp (~11m) instead of 5 dp (~1m): a driver creeping
    // 1-2m no longer produces a new cache key (and a fresh Directions call) on
    // every packet. Destination stays at 5 dp since it is fixed per phase.
    return '$phase|'
        '${origin.latitude.toStringAsFixed(4)}|${origin.longitude.toStringAsFixed(4)}|'
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
      minInterval:
          driverStartedRide.value
              ? const Duration(seconds: 10)
              : const Duration(seconds: 16),
      offRouteThresholdMeters: driverStartedRide.value ? 24.0 : 30.0,
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
    if (driverPos == null) return;
    final s = orderStatus.trim().toLowerCase();

    // Completed / cancelled -> clear the route.
    if (destinationReached.value ||
        isTripCancelled.value ||
        s == 'completed' ||
        s == 'cancelled' ||
        s == 'canceled') {
      _clearActiveRoute(clearVisuals: true, clearKey: true);
      return;
    }

    // The route phase is decided by the authoritative `driverStartedRide` flag
    // (set by the `ride-started` event / a drop-phase status), NOT by the
    // per-packet status string. The server keeps sending `status: ACCEPTED` in
    // driver-location packets even AFTER the ride starts â€” relying on that
    // string previously left the drop route unfetched (no driver->drop line).
    // `_maybeRerouteFromDriver` reads `_activeDestination()` (pickup before
    // start, drop after), so we just always reroute and let it pick the leg.
    _maybeRerouteFromDriver(driverPos, force: force);
  }

  String _currentPolylineId() {
    return driverStartedRide.value ? 'driver_to_drop' : 'driver_to_pickup';
  }

  // Intentionally a no-op now.
  //
  // Visual route trimming is owned by CustomerRideMapView, which trims a DISPLAY
  // copy of the route without mutating `activeRoutePoints`. Trimming the source
  // list here every ~90ms rewrote the route the widget receives, forcing it to
  // re-sync and snap the marker on every frame -> the car appeared to "jump" and
  // the line flashed "partial". Keeping the full fetched route lets the widget
  // trim it smoothly. `activeRoutePoints` now changes only on a real reroute.
  // ignore: avoid_unused_constructor_parameters
  void _trimActiveRouteVisual(LatLng driverPos) {}

  LatLng _cameraFollowTarget({required LatLng driverPos, LatLng? anchorPos}) {
    final bearing = _lastBearing;
    double backtrackMeters = driverStartedRide.value ? 55.0 : 36.0;

    if (anchorPos != null) {
      final gap = Geolocator.distanceBetween(
        driverPos.latitude,
        driverPos.longitude,
        anchorPos.latitude,
        anchorPos.longitude,
      );
      if (gap < 120.0) {
        backtrackMeters = 18.0;
      } else if (gap < 260.0) {
        backtrackMeters = 28.0;
      }
    }

    final headingRad = (bearing + 180.0) * math.pi / 180.0;
    const metersPerDegreeLat = 111320.0;
    final metersPerDegreeLng =
        metersPerDegreeLat * math.cos(driverPos.latitude * math.pi / 180.0);

    final latOffset =
        (math.cos(headingRad) * backtrackMeters) / metersPerDegreeLat;
    final lngOffset =
        metersPerDegreeLng.abs() < 1
            ? 0.0
            : (math.sin(headingRad) * backtrackMeters) / metersPerDegreeLng;

    return LatLng(
      driverPos.latitude + latOffset,
      driverPos.longitude + lngOffset,
    );
  }

  void _clearActiveRoute({bool clearVisuals = true, bool clearKey = true}) {
    if (clearVisuals) {
      activeRoutePoints.clear();
      polylines.clear();
    }
    _lastTrimSegIndex = -1;
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
            'ðŸ§­ route cache hit: $resolvedCacheKey (${cached.length} pts)',
          );
        }
        final sig = _routeSig(cached);
        if (sig != _activeRouteSig) {
          _activeRouteSig = sig;
          _lastTrimSegIndex = -1;
          activeRoutePoints.assignAll(cached);
          polylines.assignAll(MapUiDefaults.routePolylines(cached, id: polyId));
          final livePos = _displayPos ?? _emaPos ?? driverLocation.value;
          if (livePos != null) {
            _trimActiveRouteVisual(livePos);
          }
        }
        return;
      }

      _routeInFlightKey = resolvedCacheKey;
      if (kDebugMode) {
        AppLogger.log.i(
          'ðŸ§­ route fetch: $resolvedCacheKey (origin=${origin.latitude.toStringAsFixed(5)},${origin.longitude.toStringAsFixed(5)} dest=${destination.latitude.toStringAsFixed(5)},${destination.longitude.toStringAsFixed(5)})',
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
        _lastTrimSegIndex = -1;
        activeRoutePoints.assignAll(pts);
        polylines.assignAll(MapUiDefaults.routePolylines(pts, id: polyId));
        final livePos = _displayPos ?? _emaPos ?? driverLocation.value;
        if (livePos != null) {
          _trimActiveRouteVisual(livePos);
        }
        if (kDebugMode) {
          AppLogger.log.i('ðŸ§­ route applied: ${pts.length} pts ($polyId)');
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
        final livePos = _displayPos ?? _emaPos ?? driverLocation.value;
        if (livePos != null) {
          _trimActiveRouteVisual(livePos);
        }
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

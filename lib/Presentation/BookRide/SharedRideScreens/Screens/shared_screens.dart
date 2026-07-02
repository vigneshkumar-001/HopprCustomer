import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:hopper/Core/Utility/app_buttons.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Core/Utility/phone_launcher.dart';
import 'package:hopper/Core/Utility/app_toasts.dart';
import 'package:hopper/Presentation/Authentication/widgets/textFields.dart';
import 'package:hopper/Presentation/BookRide/Controllers/driver_search_controller.dart';
import 'package:hopper/Presentation/BookRide/Screens/order_confirm_screen.dart'
    show SafetySheet;
import 'package:hopper/Presentation/BookRide/SharedRideScreens/Controller/share_ride_controller.dart';
import 'package:hopper/Presentation/BookRide/SharedRideScreens/Screens/shared_chat_screens.dart';
import 'package:hopper/Presentation/OnBoarding/Screens/home_screens.dart';

import 'package:hopper/Presentation/OnBoarding/Screens/payment_screen.dart';
import 'package:hopper/api/repository/api_consents.dart';
import 'package:hopper/Presentation/BookRide/Models/shared_my_state.dart';
import 'package:hopper/api/dataSource/shared_api_datasource.dart';
import 'package:hopper/uitls/netWorkHandling/network_handling_screen.dart';
import 'package:hopper/uitls/websocket/shared_web_socket.dart';
import 'package:hopper/uitls/map/customer/customer_ride_map_view.dart';
import 'package:hopper/uitls/map/customer/marker_icon_cache.dart' as icon_cache;
import 'package:hopper/Presentation/BookRide/SharedRideScreens/Widgets/shared_trip_status_card.dart';
import 'package:share_plus/share_plus.dart';
import 'package:hopper/Presentation/CustomerSupport/screens/customer_support_list_screen.dart';

import 'package:http/http.dart' as http;

class SharedScreens extends StatefulWidget {
  final String pickupAddress;
  final String destinationAddress;
  final double? baseFare;
  final double? serviceFare;
  final double? distanceFare;
  final double? pickupFare;
  final double? bookingFee;
  final double? timeFare;
  final String carType;

  final LatLng initialPosition; // where camera starts
  final LatLng pickupPosition; // initial pickup
  final LatLng dropPosition; // initial drop

  /// When resuming an active booking, pass initial ride state so SharedScreens
  /// doesn't fallback to pickup/waiting UI.
  final String? initialStatus;
  final bool initialRideStarted;
  final bool initialDestinationReached;
  final String? resumeDriverId;
  final LatLng? initialDriverPosition;

  /// Optional initial route (decoded polyline from previous page)
  final List<LatLng> routePoints;

  /// Seat number(s) this customer booked, shown as a "Your seat" card on the
  /// live tracking screen. Empty on a resumed ride where seats aren't known.
  final List<int> selectedSeats;

  final VoidCallback? onCancel;

  const SharedScreens({
    super.key,
    this.baseFare,
    this.serviceFare,
    this.distanceFare,
    this.pickupFare,
    this.bookingFee,
    this.timeFare,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.initialPosition,
    required this.pickupPosition,
    required this.dropPosition,
    this.initialStatus,
    this.initialRideStarted = false,
    this.initialDestinationReached = false,
    this.resumeDriverId,
    this.initialDriverPosition,
    this.routePoints = const [],
    this.selectedSeats = const [],
    this.onCancel,
    required this.carType,
  });

  @override
  State<SharedScreens> createState() => _SharedScreensState();
}

class _SharedScreensState extends State<SharedScreens>
    with SingleTickerProviderStateMixin {
  Timer? _searchingElapsedTimer;
  Timer? _noDriverFoundTimer;
  // PERF: throttle the heavy route-trim + ETA/distance setState (which rebuilds the
  // whole bottom sheet) to at most once per _trimMinInterval, instead of on every
  // driver-location packet (1–3/s). The map interpolates the car marker between the
  // positions it receives, so movement stays smooth while the sheet stops thrashing.
  Timer? _trimThrottleTimer;
  DateTime _lastTrimAt = DateTime.fromMillisecondsSinceEpoch(0);
  LatLng? _pendingTrimPos;
  static const Duration _trimMinInterval = Duration(milliseconds: 800);
  int _searchingElapsedSeconds = 0;
  ValueNotifier<int>? _searchingElapsedSecondsVN;

  ValueNotifier<int> get _elapsedSecondsNotifier =>
      _searchingElapsedSecondsVN ??= ValueNotifier<int>(
        _searchingElapsedSeconds,
      );

  final TextEditingController _startController = TextEditingController();
  final TextEditingController _destController = TextEditingController();

  // ---------- MAP CONTROL ----------
  final GlobalKey<CustomerRideMapViewState> _mapKey =
      GlobalKey<CustomerRideMapViewState>();

  // Map-first sheet: collapsed by default so most of the map/route is visible.
  // Three snap states (collapsed / half / full) + programmatic auto-expand to
  // "half" exactly once when the driver arrives or an OTP is needed (only while
  // the user is still collapsed, so it never fights a manual drag).
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  bool _didAutoExpandArrival = false;
  bool _didAutoExpandOtp = false;

  // Just-saved pickup instruction (immediate UX); falls back to the DB-sourced
  // value carried in `_myState.pickupInstruction` until the next save.
  String? _pickupInstructionLocal;

  // Single map control with two toggling actions. true => next tap fits the
  // whole route (shows the fit icon); false => next tap recenters on the driver
  // (shows the locate icon). The icon flips after each tap.
  bool _mapShowFit = true;

  // ---------- RIDE STATE ----------
  bool isWaitingForDriver = true;
  bool noDriverFound = false;
  bool isTripCancelled = false;
  String _waitingServerMessage = '';
  // STRICT seat dispatch: when the backend skips every car because the chosen seat
  // is taken in all of them, it emits booking-update {SEAT_NOT_AVAILABLE}. We show
  // this message in the terminal state and offer "Choose another seat" (back to the
  // seat picker) — never auto-fallback to a different seat.
  String _seatUnavailableMessage = '';

  final RideShareSocketService rideShareSocket = RideShareSocketService();
  final DriverSearchController driverSearchController =
      Get.isRegistered<DriverSearchController>()
          ? Get.find<DriverSearchController>()
          : Get.put(DriverSearchController());
  final ShareRideController shareRideController =
      Get.isRegistered<ShareRideController>()
          ? Get.find<ShareRideController>()
          : Get.put(ShareRideController());

  String ProfilePic = '';
  String driverName = '';
  String carDetails = '';
  String otp = '';
  String plateNumber = '';
  String CUSTOMERPHONE = '';
  double Amount = 0.0;
  String _driverPhone = '';
  String _bookingId = '';
  String CarExteriorPhotos = '';
  bool isExpanded = false;

  // Customer's seat(s). Prefer the backend value (joined-booking payload, which
  // works on resume); fall back to the seats threaded from booking.
  List<int> _mySeatsFromServer = [];
  List<int> get _effectiveSeats =>
      _mySeatsFromServer.isNotEmpty ? _mySeatsFromServer : widget.selectedSeats;

  bool isDriverConfirmed = false;
  bool driverStartedRide = false;
  bool destinationReached = false;
  bool _driverArrived = false;
  bool _nearDestination = false;
  String cancelReason = "";
  DateTime _lastMetricsAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _metricsInterval = const Duration(milliseconds: 1200);
  bool _didExitToHome = false;
  // Guards the one-time navigation to PaymentScreen. Payment opens ONLY on the
  // per-booking 'ride-completed' event (the driver's manual Complete swipe), never
  // on GPS arrival — so a shared drop can't bounce every rider to payment at once.
  bool _didGoToPayment = false;

  // ---------- POSITIONS ----------
  LatLng? _customerPickupLatLng;
  LatLng? _customerDropLatLng;
  LatLng? _driverLatLng; // last known driver position
  DateTime _lastAcceptedDriverLocationTsUtc =
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  LatLng? _lastAcceptedDriverLocationPos;

  // ---------- ROUTE / POLYLINE STATE ----------
  /// Current active route (either driver→pickup OR pickup→drop)
  List<LatLng> _activeRoute = <LatLng>[];
  double? _routeTotalMeters;
  int? _routeTotalSeconds;
  double? _routeRemainingMeters;
  int? _routeRemainingSeconds;
  String _etaChipText = '';
  String _distanceChipText = '';

  // Phase B: privacy-safe per-customer shared-ride state (from `shared_my_state`
  // socket event + GET recovery). Drives the Uber-style "X pickups before you".
  SharedMyState? _myState;

  Future<void> _fetchMySharedState() async {
    final bId = _effectiveBookingId();
    if (bId.isEmpty) return;
    final state = await SharedApiDatasource().getMySharedState(bId);
    if (!mounted || state == null) return;
    setState(() {
      _myState = state;
      // Persist the DB-sourced pickup instruction locally so it survives active-
      // booking RESUME and the live `shared_my_state` socket updates (which don't
      // carry it) — otherwise the entered "Directions to reach" disappears.
      if (state.pickupInstruction.trim().isNotEmpty) {
        _pickupInstructionLocal = state.pickupInstruction;
      }
    });
    // RESUME/RECONNECT recovery: if the backend says MY booking was CANCELLED
    // (driver cancelled while the app was backgrounded / socket missed), leave the
    // ride screen instead of restoring a stuck trip.
    if (state.myStatus == 'CANCELLED') {
      _exitCancelled('Your trip has been cancelled by the driver.');
      return;
    }
    // ...or already completed (driver dropped me while the app was dead) → payment.
    _maybeGoToPaymentFromMyState(state);
    // Route the map to the driver's actual next stop (resume/reconnect).
    _refreshSharedRouteForState();
  }

  /// Single exit path for a cancelled ride (socket event OR resume recovery).
  /// Idempotent via [_didExitToHome]; blocks any payment nav; shows the reason
  /// briefly, then returns home exactly once.
  void _exitCancelled(String reason) {
    if (!mounted || _didExitToHome) return;
    _didExitToHome = true; // nav lock — dedupe duplicate cancel events
    _didGoToPayment = true; // hard-block payment nav after a cancel
    setState(() {
      isTripCancelled = true;
      cancelReason = reason;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      Get.offAll(() => const HomeScreens());
    });
  }

  /// Handle a driver/customer cancellation socket event. The event NAME is
  /// definitive, so we accept it whether `status` is `true`, a "CANCELLED" string,
  /// `clearActiveRide` is set, or status is absent — but ONLY for MY bookingId.
  void _handleRideCancelledEvent(dynamic data, String source) {
    if (data is! Map) return;
    final evtBookingId = (data['bookingId'] ?? '').toString();
    final myBookingId = _effectiveBookingId();
    // bookingId guard: ignore a cancellation meant for a different booking.
    if (evtBookingId.isNotEmpty &&
        myBookingId.isNotEmpty &&
        evtBookingId != myBookingId) {
      return;
    }
    final st = data['status'];
    final statusStr = (st ?? '').toString().toUpperCase();
    final isCancel = st == true ||
        statusStr == 'CANCELLED' ||
        statusStr == 'DRIVER_CANCELLED' ||
        data['clearActiveRide'] == true ||
        st == null; // event fired without a status field is still a cancellation
    if (!isCancel) return;
    AppLogger.log.i('$source booking=$evtBookingId');
    _exitCancelled(
      (data['message'] ?? data['reason'] ?? 'Your trip has been cancelled.')
          .toString(),
    );
  }

  /// Backend status is the source of truth for completion. Opens payment when MY
  /// booking is completed — via the reliable booking-doc flag (`myBookingCompleted`,
  /// from the my-state HTTP API) or the aggregate's DROPPED status (live socket).
  /// Used on resume/reconnect AND as a backup if the per-booking 'ride-completed'
  /// event is missed. NEVER GPS-based, and strictly scoped to MY bookingId.
  /// True when a new shared_my_state differs in a UI-meaningful field, so we only
  /// rebuild the sheet on real changes (not on every backend re-emit). Covers every
  /// field the status/seat/payment UI reads.
  bool _sharedStateChanged(SharedMyState? a, SharedMyState? b) {
    if (a == null || b == null) return true;
    return a.myStatus != b.myStatus ||
        a.driverCurrentAction != b.driverCurrentAction ||
        a.amINextPickup != b.amINextPickup ||
        a.amINextDrop != b.amINextDrop ||
        a.stopsBeforeMe != b.stopsBeforeMe ||
        a.myBookingCompleted != b.myBookingCompleted ||
        a.etaToMyPickupMinutes != b.etaToMyPickupMinutes ||
        a.etaToMyDropMinutes != b.etaToMyDropMinutes ||
        a.pickupInstruction != b.pickupInstruction ||
        a.paymentMode != b.paymentMode ||
        a.customerBookingId != b.customerBookingId ||
        a.statusTitle != b.statusTitle ||
        a.statusMessage != b.statusMessage ||
        a.activeStopLat != b.activeStopLat ||
        a.activeStopLng != b.activeStopLng ||
        a.activeStopType != b.activeStopType ||
        a.activeStopIsMine != b.activeStopIsMine ||
        a.mySeatNumbers.join(',') != b.mySeatNumbers.join(',');
  }

  void _maybeGoToPaymentFromMyState(SharedMyState? state) {
    if (state == null) return;
    final bool completed =
        state.myBookingCompleted || state.myStatus == 'DROPPED';
    if (!completed) return;
    final String myBookingId = _effectiveBookingId();
    if (myBookingId.isEmpty) return;
    // Not my booking → ignore (defensive; my-state is already scoped to me).
    if (state.customerBookingId.isNotEmpty &&
        state.customerBookingId != myBookingId) {
      return;
    }
    if (!mounted || _didGoToPayment) return;
    _didGoToPayment = true;
    if (mounted) {
      setState(() {
        destinationReached = true;
        _nearDestination = false;
      });
    }
    AppLogger.log.i(
        "my-state completed (backend) -> payment: ${state.customerBookingId}");
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      Get.offAll(() => PaymentScreen(bookingId: myBookingId, amount: Amount));
    });
  }

  void _goToPaymentOnce({
    required String bookingId,
    required num amount,
    required String source,
  }) {
    if (!mounted || _didGoToPayment) return;
    _didGoToPayment = true;
    setState(() {
      destinationReached = true;
      _nearDestination = false;
    });
    AppLogger.log.i("$source -> payment: bookingId=$bookingId amount=$amount");
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      Get.offAll(() => PaymentScreen(
            bookingId: bookingId,
            amount: amount.toDouble(),
          ));
    });
  }

  /// Are we routing driver → pickup (before ride-started)?
  bool _isRoutingToPickup = false;

  /// Are we routing pickup → drop (after ride-started)?
  bool _isRoutingToDrop = false;

  bool _isFetchingRoute = false;

  // Off-route handling: require consecutive misses + throttle reroute to avoid
  // polyline flicker from one noisy GPS sample.
  int _offRouteConsecutive = 0;
  static const int _offRouteConfirmCount = 3;
  static const Duration _minRerouteInterval = Duration(seconds: 12);
  DateTime _lastRerouteAt = DateTime.fromMillisecondsSinceEpoch(0);

  // ---------- SMOOTH MOTION STATE ----------
  DateTime _lastDriverLocationLogAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Camera follow is handled by [CustomerRideMapView].

  // Normalize an image field that may be a List, a "[url1,url2]" string, or a
  // plain URL → the first usable URL (mirrors single ride's order_confirm helper).
  String _firstImageUrl(dynamic value) {
    if (value is List && value.isNotEmpty) {
      return (value.first ?? '').toString().trim();
    }
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return '';
    final normalized =
        raw.replaceAll('[', '').replaceAll(']', '').replaceAll('"', '');
    for (final part in normalized.split(',')) {
      final url = part.trim();
      if (url.isNotEmpty) return url;
    }
    return normalized;
  }

  String _effectiveBookingId() {
    final fromSocket = _bookingId.trim();
    if (fromSocket.isNotEmpty) return fromSocket;
    final fromController =
        (shareRideController.sharedBooking.value?.bookingId ?? '')
            .toString()
            .trim();
    return fromController;
  }

  Future<String?> _handleCancelRide(String selectedReason) async {
    final bookingId = _effectiveBookingId();
    if (bookingId.isEmpty) {
      AppToasts.showError(context, 'Booking id missing. Please try again.');
      return 'Booking id missing';
    }

    final res = await driverSearchController.cancelRide(
      bookingId: bookingId,
      selectedReason: selectedReason,
      context: context,
    );

    if (!mounted) return res;

    final ok = (res ?? '').trim().isEmpty;
    if (!ok) return res;

    setState(() {
      isTripCancelled = true;
      cancelReason = selectedReason;
    });

    // give a short confirmation, then go home
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return res;
    if (_didExitToHome) return res;
    _didExitToHome = true;
    Get.offAll(() => const HomeScreens());
    return '';
  }

  int get _timelineIndex {
    if (destinationReached) return 5;
    if (_nearDestination) return 4;
    if (driverStartedRide) return 3;
    if (_driverArrived) return 2;
    if (isDriverConfirmed) return 1;
    return 0;
  }

  // ---------- WAITING TIMER ----------
  void startDriverSearch() {
    isWaitingForDriver = true;
    noDriverFound = false;
    _searchingElapsedTimer?.cancel();
    _noDriverFoundTimer?.cancel();
    _searchingElapsedSeconds = 0;
    _elapsedSecondsNotifier.value = 0;
    _searchingElapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (!isWaitingForDriver || isDriverConfirmed) return;
      _searchingElapsedSeconds += 1;
      _elapsedSecondsNotifier.value = _searchingElapsedSeconds;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!isWaitingForDriver || isDriverConfirmed || driverStartedRide) return;
      final mapState = _mapKey.currentState;
      final pickup = _customerPickupLatLng ?? widget.pickupPosition;
      mapState?.fitRoute(padding: 150);
      updatePickup(pickup);
    });

    _restartNoDriverFoundTimer();
  }

  /// (Re)start the 60s "no driver found" fallback. Called when searching begins
  /// AND each time the backend REDISPATCHES (DRIVER_REJECTED via `booking-update`)
  /// — a redispatch means a fresh driver is now deciding, so we extend the window
  /// instead of prematurely declaring "no driver".
  void _restartNoDriverFoundTimer() {
    _noDriverFoundTimer?.cancel();
    _noDriverFoundTimer = Timer(const Duration(seconds: 60), () async {
      if (!mounted) return;
      if (isDriverConfirmed) return;

      final bookingId =
          _bookingId.trim().isNotEmpty
              ? _bookingId.trim()
              : (shareRideController.sharedBooking.value?.bookingId ?? '')
                  .toString()
                  .trim();

      if (bookingId.isEmpty) {
        setState(() {
          isWaitingForDriver = false;
          noDriverFound = true;
        });
        return;
      }

      bool hasDriver = false;
      try {
        hasDriver = await driverSearchController
            .noDriverFound(context: context, bookingId: bookingId, status: true)
            .timeout(const Duration(seconds: 12), onTimeout: () => false);
      } catch (_) {
        hasDriver = false;
      }

      if (!mounted) return;
      setState(() {
        isWaitingForDriver = false;
        noDriverFound = !hasDriver;
      });
    });
  }

  /// ALTERNATE_SEATS_AVAILABLE confirmation popup. The backend found rides but
  /// the chosen seat is taken in all of them; other seats are free. Only after
  /// the customer confirms do we update the booking's seats and re-dispatch —
  /// never a silent reassignment. On "No thanks" the booking closes safely via
  /// the same no-driver flow the search timeout uses.
  bool _alternateSeatsDialogShowing = false;

  void _showAlternateSeatsDialog(List<int> altSeats, String message) {
    if (!mounted || _alternateSeatsDialogShowing) return;
    if (isDriverConfirmed || isTripCancelled) return;
    _alternateSeatsDialogShowing = true;

    // Keep the searching UI paused (not failed) while the customer decides.
    setState(() {
      isWaitingForDriver = false;
      noDriverFound = false;
    });

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Seat not available',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _onAlternateSeatsRejected();
            },
            child: const Text('No, cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _onAlternateSeatsConfirmed(altSeats);
            },
            child: Text(
              'Continue with seat${altSeats.length == 1 ? '' : 's'} ${altSeats.join(', ')}',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    ).whenComplete(() => _alternateSeatsDialogShowing = false);
  }

  Future<void> _onAlternateSeatsConfirmed(List<int> altSeats) async {
    if (!mounted) return;
    if (shareRideController.isLoading.value) return;
    final bookingId = _bookingId.trim().isNotEmpty
        ? _bookingId.trim()
        : (shareRideController.sharedBooking.value?.bookingId ?? '')
            .toString()
            .trim();
    if (bookingId.isEmpty) {
      setState(() {
        isWaitingForDriver = false;
        noDriverFound = true;
      });
      return;
    }

    setState(() {
      isWaitingForDriver = true;
      noDriverFound = false;
      _waitingServerMessage = 'Confirming seats…';
    });

    final confirmed = await shareRideController.confirmAlternateSeats(
      bookingId: bookingId,
      seats: altSeats,
      context: context,
    );
    if (!mounted) return;

    if (!confirmed) {
      setState(() {
        isWaitingForDriver = false;
        noDriverFound = true;
      });
      return;
    }

    // Seats updated server-side — start a fresh dispatch cycle (same path as the
    // "Try Again" button), which resets declined-driver exclusions on the backend.
    final pickup = _customerPickupLatLng ?? widget.pickupPosition;
    final drop = _customerDropLatLng ?? widget.dropPosition;
    final result = await shareRideController.sendSharedDriverRequest(
      carType: widget.carType,
      pickupLatitude: pickup.latitude,
      pickupLongitude: pickup.longitude,
      dropLatitude: drop.latitude,
      dropLongitude: drop.longitude,
      bookingId: bookingId,
      context: context,
    );
    if (!mounted) return;

    if (result == 'success') {
      setState(() => _waitingServerMessage = 'Finding your driver…');
      startDriverSearch();
    } else {
      setState(() {
        isWaitingForDriver = false;
        noDriverFound = true;
      });
    }
  }

  Future<void> _onAlternateSeatsRejected() async {
    if (!mounted) return;
    final bookingId = _bookingId.trim().isNotEmpty
        ? _bookingId.trim()
        : (shareRideController.sharedBooking.value?.bookingId ?? '')
            .toString()
            .trim();

    // Close the booking safely server-side (same call the 60s search timeout
    // uses), then show the no-driver state so the customer can go home.
    if (bookingId.isNotEmpty) {
      try {
        await driverSearchController
            .noDriverFound(context: context, bookingId: bookingId, status: true)
            .timeout(const Duration(seconds: 12), onTimeout: () => false);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      isWaitingForDriver = false;
      noDriverFound = true;
      _seatUnavailableMessage = '';
    });
  }

  @override
  void initState() {
    super.initState();

    _bootstrapFromInitialRideState();

    _setupSocketListeners();

    // Phase B: pull the privacy-safe shared state on open (socket fills live after).
    _fetchMySharedState();

    _startController.text = widget.pickupAddress;
    _destController.text = widget.destinationAddress;

    // Start waiting timer only for fresh bookings (no driver yet).
    if (isWaitingForDriver && !isDriverConfirmed && !driverStartedRide) {
      startDriverSearch();
    }
  }

  /// Auto-expand the sheet to the "half" state. No-op if the sheet is already at
  /// or past half, so it never overrides a manual drag — only lifts a collapsed
  /// sheet when there's something the rider must see (arrival / OTP).
  void _autoExpandSheetToHalf() {
    void run() {
      if (!mounted || !_sheetController.isAttached) return;
      const target = 0.52;
      if (_sheetController.size >= target - 0.03) return;
      _sheetController.animateTo(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }

    // If the event also flipped isDriverConfirmed, the confirmed sheet (and its
    // controller) attaches on the next frame — defer so animateTo has a target.
    if (_sheetController.isAttached) {
      run();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => run());
    }
  }

  @override
  void dispose() {
    _searchingElapsedTimer?.cancel();
    _noDriverFoundTimer?.cancel();
    _trimThrottleTimer?.cancel();
    _searchingElapsedSecondsVN?.dispose();
    _sheetController.dispose();
    // CRITICAL FIX: remove every socket listener registered in
    // _setupSocketListeners(). The socket is a process-wide singleton, so
    // without this the disposed State stays retained via the captured closures
    // and stale callbacks fire setState/Navigator after dispose (and the chat
    // screen's listeners on the same singleton collide with these). Mirrors the
    // single-ride screen's teardown.
    for (final event in const [
      'connect',
      'shared_my_state',
      'joined-booking',
      'otp-generated',
      'ride-started',
      'driver-reached-destination',
      'ride-completed',
      'driver-arrived',
      'customer-cancelled',
      'driver-cancelled',
      'booking-update',
      'driver-location',
      'pickup_instruction_updated',
    ]) {
      rideShareSocket.off(event);
    }
    super.dispose();
  }

  // ---------- ASSET → BITMAP (resize) ----------
  // ignore: unused_element
  Future<void> _loadMarkerIcons() async {
    // Deprecated: map rendering is owned by CustomerRideMapView.
    _initRouteAndMarkers();
    if (mounted) setState(() {});
  }

  /*
    try {
      _pickupWaitingLabelIcon = await CompactMarkerIcons.labeledPin(
        label: MapUiDefaults.placeLabel(
          widget.pickupAddress,
          fallback: 'Pickup',
        ),
        assetPath: AppImages.pin,
        tint: const Color(0xFF000000),
        bubbleWidthDp: MapUiDefaults.pickupDropBubbleWidthDp,
        bubbleHeightDp: MapUiDefaults.pickupDropBubbleHeightDp,
        pinWidthDp: MapUiDefaults.pickupDropPinWidthDp,
        fontSizeDp: MapUiDefaults.pickupDropFontSizeDp,
        textAlign: TextAlign.left,
      );
    } catch (_) {
      _pickupWaitingLabelIcon = _pickupIcon;
    }
    try {
      _pickupLabelIcon = await CompactMarkerIcons.labeledPin(
        label: MapUiDefaults.placeLabel(
          widget.pickupAddress,
          fallback: 'Pickup',
        ),
        assetPath: AppImages.pin,
        tint: const Color(0xFF000000),
        bubbleWidthDp: MapUiDefaults.pickupDropBubbleWidthDp,
        bubbleHeightDp: MapUiDefaults.pickupDropBubbleHeightDp,
        pinWidthDp: MapUiDefaults.pickupDropPinWidthDp,
        fontSizeDp: MapUiDefaults.pickupDropFontSizeDp,
        textAlign: TextAlign.left,
      );
    } catch (_) {
      _pickupLabelIcon = _pickupIcon;
    }
    try {
      _dropLabelIcon = await CompactMarkerIcons.labeledPin(
        label: MapUiDefaults.placeLabel(
          widget.destinationAddress,
          fallback: 'Drop',
        ),
        assetPath: AppImages.pin,
        tint: const Color(0xFF15803D),
        bubbleWidthDp: MapUiDefaults.pickupDropBubbleWidthDp,
        bubbleHeightDp: MapUiDefaults.pickupDropBubbleHeightDp,
        pinWidthDp: MapUiDefaults.pickupDropPinWidthDp,
        fontSizeDp: MapUiDefaults.pickupDropFontSizeDp,
        textAlign: TextAlign.left,
      );
    } catch (_) {
      _dropLabelIcon = _dropIcon;
    }

    final t = widget.carType.toLowerCase();
    final driverAsset =
        (t.contains('bike') || t.contains('package'))
            ? AppImages.packageBike
            : AppImages.carHop;
    try {
      _driverIcon = await CompactMarkerIcons.assetContained(
        assetPath: driverAsset,
        sizeDp: MapUiDefaults.vehicleBadgeDiameterDp,
      );
    } catch (_) {
      _driverIcon = null;
    }

    _initRouteAndMarkers();
    if (!mounted) return;
    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mapState = _mapKey.currentState;
      if (mapState == null) return;
      if (_driverLatLng != null) {
        _updateDriverMarker(_driverLatLng!);
      }
      if (driverStartedRide) {
        // Resumed ride: show pickup→drop route immediately.
        _setRoutePickupToDrop();
      } else if (isDriverConfirmed && _driverLatLng != null) {
        // Driver assigned but ride not started yet.
        _setRouteDriverToPickup();
      }
      mapState.animateTo(
        target:
            _driverLatLng ??
            (driverStartedRide ? widget.dropPosition : widget.pickupPosition),
        zoom: MapUiDefaults.focusZoom,
      );
    });
  }

  */

  bool _statusSuggestsRideStarted(String? status) {
    final s = (status ?? '').trim().toUpperCase();
    if (s.isEmpty) return false;
    return s.contains('RIDE_IN_PROGRESS') ||
        s.contains('TRIP_IN_PROGRESS') ||
        s.contains('IN_PROGRESS') ||
        s.contains('RIDE_STARTED');
  }

  bool _statusSuggestsDestinationReached(String? status) {
    final s = (status ?? '').trim().toUpperCase();
    if (s.isEmpty) return false;
    return s.contains('DESTINATION_REACHED') ||
        s.contains('COMPLETED') ||
        s.contains('ENDED') ||
        s.contains('FINISHED');
  }

  void _bootstrapFromInitialRideState() {
    final bool hasInitialDriver =
        (widget.resumeDriverId ?? '').toString().trim().isNotEmpty ||
        widget.initialDriverPosition != null;

    final bool started =
        widget.initialRideStarted ||
        _statusSuggestsRideStarted(widget.initialStatus);
    final bool reached =
        widget.initialDestinationReached ||
        _statusSuggestsDestinationReached(widget.initialStatus);

    if (widget.initialDriverPosition != null) {
      _driverLatLng = widget.initialDriverPosition;
    }

    if (hasInitialDriver || started || reached) {
      isDriverConfirmed = hasInitialDriver;
      isWaitingForDriver = false;
      noDriverFound = false;
    }

    if (reached) destinationReached = true;
    if (started || reached) {
      driverStartedRide = true;
      _driverArrived = true;
      _nearDestination = false;
    }
  }

  // ---------- INITIAL ROUTE ----------
  void _initRouteAndMarkers() {
    _activeRoute = widget.routePoints;
    _customerPickupLatLng = widget.pickupPosition;
    _customerDropLatLng = widget.dropPosition;
  }

  // ---------- LOCATION HELPERS ----------
  void updatePickup(LatLng pos) {
    _customerPickupLatLng = pos;
    if (mounted) setState(() {});
  }

  void updateDrop(LatLng pos) {
    _customerDropLatLng = pos;
    if (mounted) setState(() {});
  }

  void updateRoute(List<LatLng> points) {
    _activeRoute = points;
    if (mounted) setState(() {});
  }

  void _updateDriverMarker(LatLng pos) {
    _driverLatLng = pos;
    if (mounted) setState(() {});
  }

  Future<void> _onLocationFabTap() async {
    await _mapKey.currentState?.recenter();
  }

  // ---------- ROUTE MANAGEMENT ----------

  /// Replace active route and polyline, and fit bounds once.
  void _setActiveRoute(List<LatLng> points) {
    if (!mounted || points.isEmpty) return;
    setState(() {
      _activeRoute = points;
      _routeRemainingMeters = _computeRouteMeters(points);
      _routeRemainingSeconds = _estimateRemainingSeconds(
        meters: _routeRemainingMeters,
        totalMeters: _routeTotalMeters,
        totalSeconds: _routeTotalSeconds,
      );
      final etaCore = _formatEta(_routeRemainingSeconds);
      final distCore = _formatDistance(_routeRemainingMeters);
      final near =
          (_routeRemainingMeters != null && _routeRemainingMeters! <= 400) ||
          (_routeRemainingSeconds != null && _routeRemainingSeconds! <= 120);
      _nearDestination = driverStartedRide && near;
      if (driverStartedRide) {
        _etaChipText =
            _nearDestination
                ? 'Near destination'
                : (etaCore.isEmpty ? '' : '$etaCore to drop');
      } else {
        _etaChipText =
            _driverArrived
                ? 'Arriving at pickup'
                : (etaCore.isEmpty ? '' : '$etaCore away');
      }
      _distanceChipText = distCore;
    });
  }

  /// Call Google Directions API and decode polyline.
  Future<List<LatLng>> _requestRoute(LatLng from, LatLng to) async {
    if (_isFetchingRoute) {
      // Avoid spamming Directions API; return current route if any
      return _activeRoute;
    }

    _isFetchingRoute = true;
    try {
      final String apiKey = ApiConsents.googleMapApiKey;

      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/directions/json',
        <String, String>{
          'origin': '${from.latitude},${from.longitude}',
          'destination': '${to.latitude},${to.longitude}',
          'mode': 'driving',
          'alternatives': 'false',
          'key': apiKey,
        },
      );

      final http.Response res = await http
          .get(uri)
          .timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) {
        AppLogger.log.w('Directions HTTP error: ${res.statusCode}');
        return const <LatLng>[];
      }

      final Map<String, dynamic> data =
          json.decode(res.body) as Map<String, dynamic>;

      final String status = data['status']?.toString() ?? 'UNKNOWN';
      if (status != 'OK') {
        AppLogger.log.w('Directions status: $status');
        return const <LatLng>[];
      }

      final List routes = data['routes'] as List;
      if (routes.isEmpty) return const <LatLng>[];

      final Map<String, dynamic> route0 =
          (routes[0] as Map).cast<String, dynamic>();

      try {
        final List legs = (route0['legs'] as List?) ?? const [];
        if (legs.isNotEmpty) {
          final Map<String, dynamic> leg0 =
              (legs[0] as Map).cast<String, dynamic>();
          final int? meters =
              (leg0['distance'] is Map)
                  ? (leg0['distance']['value'] as num?)?.toInt()
                  : null;
          final int? seconds =
              (leg0['duration'] is Map)
                  ? (leg0['duration']['value'] as num?)?.toInt()
                  : null;
          if (meters != null && meters > 0)
            _routeTotalMeters = meters.toDouble();
          if (seconds != null && seconds > 0) _routeTotalSeconds = seconds;
        }
      } catch (_) {
        // ignore parsing errors; will fallback to heuristic ETA
      }

      final String encoded =
          (route0['overview_polyline'] as Map)['points'] as String;
      final List<LatLng> points = _decodePolyline(encoded);
      return points;
    } catch (e, st) {
      AppLogger.log.e('Directions error: $e\n$st');
      return const <LatLng>[];
    } finally {
      _isFetchingRoute = false;
    }
  }

  Future<void> _setRouteDriverToPickup() async {
    if (_driverLatLng == null || _customerPickupLatLng == null) return;
    _isRoutingToPickup = true;
    _isRoutingToDrop = false;

    final pts = await _requestRoute(_driverLatLng!, _customerPickupLatLng!);
    if (pts.isNotEmpty) _setActiveRoute(pts);
  }

  Future<void> _setRoutePickupToDrop() async {
    if (_customerDropLatLng == null) return;
    _isRoutingToPickup = false;
    _isRoutingToDrop = true;

    final from = _driverLatLng ?? _customerPickupLatLng;
    if (from == null) return;
    final pts = await _requestRoute(from, _customerDropLatLng!);
    if (pts.isNotEmpty) _setActiveRoute(pts);
  }

  /// Update remaining meters/ETA based on driver's progress along the route.
  /// Note: map polyline trimming is handled by `CustomerRideMapView` so we do
  /// NOT mutate `_activeRoute` here (mutating causes flicker / missing polylines).
  /// Leading + trailing throttle around [_trimRouteForDriver] so its sheet-wide
  /// setState fires at most once per [_trimMinInterval]. The latest driver position
  /// is always kept in [_pendingTrimPos]; the car marker stays smooth because the
  /// map interpolates between the positions it receives.
  void _throttledTrimRoute(LatLng driverPos) {
    _pendingTrimPos = driverPos;
    final now = DateTime.now();
    final sinceLast = now.difference(_lastTrimAt);
    if (sinceLast >= _trimMinInterval) {
      _lastTrimAt = now;
      _trimThrottleTimer?.cancel();
      _trimThrottleTimer = null;
      _trimRouteForDriver(driverPos);
      return;
    }
    if (_trimThrottleTimer != null) return; // trailing run already scheduled
    _trimThrottleTimer = Timer(_trimMinInterval - sinceLast, () {
      _trimThrottleTimer = null;
      if (!mounted) return;
      _lastTrimAt = DateTime.now();
      final p = _pendingTrimPos;
      if (p != null && _activeRoute.isNotEmpty) _trimRouteForDriver(p);
    });
  }

  void _trimRouteForDriver(LatLng driverPos) {
    if (_activeRoute.length < 2) return;

    int closestIndex = 0;
    double closestDist = double.infinity;

    for (int i = 0; i < _activeRoute.length; i++) {
      final d = _distanceMeters(_activeRoute[i], driverPos);
      if (d < closestDist) {
        closestDist = d;
        closestIndex = i;
      }
    }

    if (closestIndex > 0 && closestIndex < _activeRoute.length) {
      final remaining = _activeRoute.sublist(closestIndex);
      setState(() {
        _routeRemainingMeters = _computeRouteMeters(remaining);
        _routeRemainingSeconds = _estimateRemainingSeconds(
          meters: _routeRemainingMeters,
          totalMeters: _routeTotalMeters,
          totalSeconds: _routeTotalSeconds,
        );
        final etaCore = _formatEta(_routeRemainingSeconds);
        final distCore = _formatDistance(_routeRemainingMeters);
        final near =
            (_routeRemainingMeters != null && _routeRemainingMeters! <= 400) ||
            (_routeRemainingSeconds != null && _routeRemainingSeconds! <= 120);
        _nearDestination = driverStartedRide && near;
        if (driverStartedRide) {
          _etaChipText =
              _nearDestination
                  ? 'Near destination'
                  : (etaCore.isEmpty ? '' : '$etaCore to drop');
        } else {
          _etaChipText =
              _driverArrived
                  ? 'Arriving at pickup'
                  : (etaCore.isEmpty ? '' : '$etaCore away');
        }
        _distanceChipText = distCore;
      });
    }
  }

  double _computeRouteMeters(List<LatLng> pts) {
    if (pts.length < 2) return 0;
    double sum = 0;
    for (int i = 0; i < pts.length - 1; i++) {
      sum += _distanceMeters(pts[i], pts[i + 1]);
    }
    return sum;
  }

  int? _estimateRemainingSeconds({
    required double? meters,
    required double? totalMeters,
    required int? totalSeconds,
  }) {
    if (meters == null) return null;
    if (totalMeters != null &&
        totalMeters > 1 &&
        totalSeconds != null &&
        totalSeconds > 0) {
      final ratio = (meters / totalMeters).clamp(0.0, 1.0);
      return (totalSeconds * ratio).round();
    }

    const double metersPerSecond = 7.2; // ~26 km/h
    return (meters / metersPerSecond).round();
  }

  /// Bottom-sheet editor for the pickup instruction ("Directions to reach").
  /// Saves to the backend (source of truth); on success updates local state so
  /// the card reflects it immediately. Clear/Remove sends an empty instruction.
  void _openPickupInstructionSheet() {
    final bookingId = _effectiveBookingId();
    if (bookingId.isEmpty) {
      AppToasts.showError(context, 'Booking not ready yet. Try again.');
      return;
    }
    final existing =
        (_pickupInstructionLocal ?? (_myState?.pickupInstruction ?? '')).trim();
    final controller = TextEditingController(text: existing);
    bool saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheet) {
            Future<void> submit({required bool clear}) async {
              final text = clear ? '' : controller.text.trim();
              setSheet(() => saving = true);
              final ok = await SharedApiDatasource().updatePickupInstruction(
                bookingId: bookingId,
                instruction: text,
              );
              if (!mounted) return;
              if (ok) {
                setState(() => _pickupInstructionLocal = text);
                Navigator.of(sheetCtx).pop();
              } else {
                setSheet(() => saving = false);
                AppToasts.showError(context, 'Could not save. Try again.');
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                top: 18,
                bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 18,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Directions to reach',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Help your driver reach you faster',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    maxLength: 160,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'e.g. Waiting near the main gate, blue shirt',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      if (existing.isNotEmpty)
                        TextButton(
                          onPressed: saving ? null : () => submit(clear: true),
                          child: const Text(
                            'Remove',
                            style: TextStyle(color: Color(0xFFD93025)),
                          ),
                        ),
                      const Spacer(),
                      ElevatedButton(
                        onPressed: saving ? null : () => submit(clear: false),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF006FD0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: saving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Save',
                                style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Fixed bottom app bar (Call + Message), pinned at the very bottom of the
  /// screen and always visible while the draggable sheet scrolls. Only rendered
  /// once a driver is assigned (call/chat targets exist).
  Widget _buildFixedDriverActionBar() {
    if (!isDriverConfirmed) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              // Call — small rounded brand button.
              GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  _callDriverFromBar();
                },
                child: Container(
                  height: 50,
                  width: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFF000000),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.call_rounded,
                      color: Colors.white, size: 24),
                ),
              ),
              const SizedBox(width: 12),
              // Message — wider rounded outlined button.
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    _messageDriverFromBar();
                  },
                  child: Container(
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.containerColor1,
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: Colors.black.withOpacity(0.06)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.chat_bubble_outline_rounded,
                            size: 20, color: Color(0xFF1A1A1A)),
                        const SizedBox(width: 8),
                        CustomTextFields.textWithStylesSmall(
                          'Message your driver',
                          colors: AppColors.commonBlack,
                          fontWeight: FontWeight.w600,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// SOS → open the same Safety sheet the single-ride screen uses (emergency
  /// call + trusted contacts + share live trip). Reuses the shared SafetySheet.
  void _openSafetySheet() {
    final bookingId = _effectiveBookingId();
    final trackUrl =
        'https://hoppr-admin-e7bebfb9fb05.herokuapp.com/ride-tracker/$bookingId';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafetySheet(trackUrl: trackUrl, driverName: driverName),
    );
  }

  /// Dial the driver (used by the bottom action bar). Same logic that used to
  /// live in the under-driver-card call button.
  Future<void> _callDriverFromBar() async {
    HapticFeedback.mediumImpact();
    try {
      final rawNumber = _driverPhone.trim();
      if (rawNumber.isEmpty) {
        AppToasts.showError(context, 'Number Not set ');
        return;
      }
      final hasPlus = rawNumber.startsWith('+');
      final digitsOnly = rawNumber.replaceAll(RegExp(r'[^0-9]'), '');
      final normalized = hasPlus ? '+$digitsOnly' : digitsOnly;
      if (normalized.isEmpty) {
        AppToasts.showError(context, 'Invalid number');
        return;
      }
      final ok = await launchPhoneDialer(normalized);
      if (!ok) AppToasts.showError(context, 'Could not open dialer');
    } catch (e) {
      AppToasts.showError(context, 'Failed to start call');
    }
  }

  /// Open the driver chat (used by the bottom action bar).
  void _messageDriverFromBar() {
    HapticFeedback.mediumImpact();
    final chatBookingId = _effectiveBookingId();
    if (chatBookingId.isEmpty) {
      AppToasts.showError(context, 'Booking id missing. Please try again.');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SharedChatScreens(bookingId: chatBookingId),
      ),
    );
  }

  /// Full-screen Hero preview of the driver's photo. Safe no-op when the photo
  /// URL is empty; reuses the same ProfilePic source as the avatar.
  void _openDriverPhotoPreview() {
    final url = ProfilePic.trim();
    if (url.isEmpty) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, __, ___) => _DriverPhotoPreview(imageUrl: url),
      ),
    );
  }

  String _formatEta(int? seconds) {
    if (seconds == null || seconds <= 0) return '';
    final mins = (seconds / 60).ceil();
    if (mins < 60) return '$mins min';
    final h = mins ~/ 60;
    final m = mins % 60;
    return '${h}h ${m}m';
  }

  String _formatDistance(double? meters) {
    if (meters == null || meters <= 0) return '';
    if (meters < 1000) return '${meters.round()} m';
    final km = meters / 1000.0;
    return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';
  }

  /// MAP overlay for a WAITING rider when the driver is serving ANOTHER rider
  /// first — so the driver dot moving "away" never confuses them. Hidden once the
  /// driver is coming to THIS rider (amINextPickup), arrived, onboard, or for a
  /// single ride (no shared state). Privacy-safe: counts + generic action only,
  /// never the other rider's location / identity.
  /// Map route styling for this rider: grey dashed while the driver is serving
  /// ANOTHER rider first, solid brand-blue ("your route") once the driver is
  /// headed to me. Privacy-safe — driven only by the generic driverCurrentAction.
  SharedRouteStyle _sharedRouteStyle() {
    // The main route is always MY own leg now (blue). The grey "serving another
    // rider" leg is drawn as a SEPARATE polyline (otherRoute).
    return SharedRouteStyle.mine;
  }

  /// The location the driver is heading to next, as a map point (or null).
  LatLng? get _activeStopLatLng {
    final ms = _myState;
    if (ms == null || !ms.hasActiveStop) return null;
    return LatLng(ms.activeStopLat!, ms.activeStopLng!);
  }

  /// The generic "another rider" stop marker to show on the map — only when the
  /// driver's current target is NOT mine. Privacy-safe (location + type only).
  LatLng? get _otherStopForMap {
    final ms = _myState;
    if (ms == null || !ms.activeStopIsOther) return null;
    return _activeStopLatLng;
  }

  // Re-route the map to where the driver is ACTUALLY heading next (stops[0])
  // rather than always MY pickup/drop. When the driver detours to another
  // rider's stop, the polyline follows the real leg (styled grey by
  // _sharedRouteStyle) and the other-rider marker is shown. Only re-requests
  // Directions when the TARGET stop changes (driver movement is handled by the
  // existing route-trim), so no API spam.
  // Grey "serving another rider" leg (driver → the other rider's stop). The main
  // _activeRoute is then MY own leg (other stop → my pickup/drop), drawn blue.
  List<LatLng> _otherLegRoute = const <LatLng>[];
  String _lastSharedRouteKey = '';
  Future<void> _refreshSharedRouteForState() async {
    final active = _activeStopLatLng;
    if (active == null) return; // old backend / no data → keep phase route
    final ms = _myState!;
    final key = '${ms.activeStopLat},${ms.activeStopLng},${ms.activeStopIsMine}';
    if (key == _lastSharedRouteKey) return;
    final from = _driverLatLng ?? _customerPickupLatLng;
    if (from == null) return;
    _lastSharedRouteKey = key;

    if (ms.activeStopIsOther) {
      // Two legs: grey driver→other stop, then blue other stop→MY next stop.
      final leg1 = await _requestRoute(from, active);
      if (mounted) setState(() => _otherLegRoute = leg1);
      final myTarget = ms.isOnboard ? _customerDropLatLng : _customerPickupLatLng;
      if (myTarget != null) {
        final leg2 = await _requestRoute(active, myTarget);
        if (leg2.isNotEmpty) _setActiveRoute(leg2);
      }
    } else {
      // Driver is coming to ME → single blue leg driver→my stop.
      if (_otherLegRoute.isNotEmpty && mounted) {
        setState(() => _otherLegRoute = const <LatLng>[]);
      }
      final pts = await _requestRoute(from, active);
      if (pts.isNotEmpty) _setActiveRoute(pts);
    }
  }

  /// One Cancel/Support/Share action cell: icon on top, label below.
  Widget _actionCell({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.mediumImpact(); // nice tap feedback
        onTap();
      },
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionDivider() => SizedBox(
        height: 34,
        child: VerticalDivider(
          width: 1,
          thickness: 1,
          color: Colors.black.withOpacity(0.08),
        ),
      );

  /// One fare-breakdown line: label left, currency + value right. Uniform rows.
  Widget _fareRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
            ),
            Image.asset(AppImages.nBlackCurrency, height: 12),
            const SizedBox(width: 3),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF14213A),
              ),
            ),
          ],
        ),
      );

  /// Right-side status for MY pickup row in the stops card (privacy-safe).
  String _pickupStopTrailing() {
    if (destinationReached) return 'Done';
    if (driverStartedRide) return 'Picked up';
    final ms = _myState;
    if (ms != null && ms.amINextPickup) {
      final e = ms.etaToMyPickupMinutes;
      return e != null ? '~$e min' : 'Arriving';
    }
    return 'In queue';
  }

  Color _pickupStopTrailingColor() {
    if (destinationReached || driverStartedRide) return const Color(0xFF15803D);
    return const Color(0xFF111418);
  }

  /// Right-side ETA for MY drop row in the stops card.
  String _dropStopTrailing() {
    if (destinationReached) return 'Reached';
    final e = _myState?.etaToMyDropMinutes;
    return e != null ? '~$e min' : 'En route';
  }

  Widget _buildDriverBusyMapBanner() {
    final ms = _myState;
    if (ms == null) return const SizedBox.shrink();
    if (destinationReached) return const SizedBox.shrink();
    // Show ONLY when the driver is serving another rider (and I'm not the next
    // stop). This now works for an ONBOARD rider too (Customer 2), so an
    // already-picked customer sees WHY the car is detouring — not just a bare count.
    if (ms.amINextPickup || ms.amINextDrop || ms.isDropped) {
      return const SizedBox.shrink();
    }

    String title;
    if (ms.driverCurrentAction == 'PICKING_OTHER_RIDER') {
      title = 'Driver is picking up another rider first';
    } else if (ms.driverCurrentAction == 'DROPPING_OTHER_RIDER') {
      title = 'Driver is dropping another rider first';
    } else if (ms.stopsBeforeMe > 0) {
      final s = ms.stopsBeforeMe;
      title = '$s stop${s == 1 ? '' : 's'} before you';
    } else {
      return const SizedBox.shrink();
    }
    // ETA to MY next stop: my drop if I'm already onboard, else my pickup.
    final eta = ms.isOnboard ? ms.etaToMyDropMinutes : ms.etaToMyPickupMinutes;
    final legWord = ms.isOnboard ? 'drop' : 'pickup';
    final sub = eta != null
        ? "You're next after · ~$eta min to your $legWord"
        : "You're next after — hang tight";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: const Color(0xFF111418).withOpacity(0.92),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.20),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.directions_car_filled_rounded,
              size: 18,
              color: Color(0xFF111418),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFB7BBC2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Live "Direction to reach" status card. Reuses the already-computed ETA
  /// (_etaChipText) and distance (_distanceChipText) — phase-aware: before
  /// pickup it shows the driver reaching the customer, after pickup it shows the
  /// trip to the drop. No extra Directions calls; it only reflects current state.
  Widget _buildReachStatusCard() {
    String title;
    IconData icon;
    String badge; // short uppercase stage tag for instant scannability
    // Phase B: privacy-safe shared context overrides the generic message + ETA
    // for the pickup-pending and onboard phases (sequence-aware "X before you").
    final ms = _myState;
    String? sharedDetail;
    if (destinationReached) {
      icon = Icons.flag_rounded;
      title = 'You have reached your destination';
      badge = 'COMPLETED';
    } else if (driverStartedRide) {
      icon = Icons.navigation_rounded;
      badge = _nearDestination ? 'ALMOST THERE' : 'ON TRIP';
      if (ms != null) {
        title = ms.titleText;
        sharedDetail = ms.detailText;
      } else {
        title = _nearDestination
            ? 'Almost at your destination'
            : 'On the way to your destination';
      }
    } else if (_driverArrived && (ms == null || ms.amINextPickup)) {
      // "Arrived" ONLY for the rider the driver is actually at (I'm next pickup),
      // or for a single ride (ms == null). In a shared ride the driver can only be
      // at ONE pickup — co-riders must NOT all show "arrived"; they fall through to
      // their privacy-safe sequence message below ("1 pickup before you", etc.).
      icon = Icons.local_taxi_rounded;
      title = 'Driver has arrived at pickup';
      badge = 'ARRIVED';
    } else {
      icon = Icons.directions_car_filled_rounded;
      // Shared ride: lead with the sequence context so each rider knows whether
      // the driver is coming to THEM or to another rider first.
      if (ms != null) {
        badge = ms.amINextPickup ? 'YOU ARE NEXT' : 'IN QUEUE';
        title = ms.titleText;
        sharedDetail = ms.detailText;
      } else {
        badge = 'PICKUP';
        title = 'Driver is reaching you';
      }
    }

    final detail = (sharedDetail != null && sharedDetail.trim().isNotEmpty)
        ? sharedDetail
        : [_etaChipText, _distanceChipText]
            .where((s) => s.trim().isNotEmpty)
            .join('  ·  ');

    // "Action needed" stages get a slightly stronger accent so OTP/arrival pops.
    final bool emphasise = _driverArrived && !driverStartedRide;

    // Uber-style morph: cross-fade the content + ease the height whenever the
    // stage changes (PICKUP → ARRIVED → ON TRIP → COMPLETED). One screen, no
    // rebuild, theme colors unchanged — only the card content animates.
    final String stageKey =
        '$badge|$title|$detail|${_effectiveSeats.join(',')}';
    return AnimatedSize(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 340),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeIn,
        // Slide-up + fade so a status change (e.g. "You are next" →
        // "Driver is picking up another rider first") visibly animates in.
        transitionBuilder: (child, anim) {
          final slide = Tween<Offset>(
            begin: const Offset(0, 0.10),
            end: Offset.zero,
          ).animate(anim);
          return FadeTransition(
            opacity: anim,
            child: SlideTransition(position: slide, child: child),
          );
        },
        layoutBuilder: (currentChild, previousChildren) => Stack(
          alignment: Alignment.topCenter,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        ),
        child: SharedTripStatusCard(
          key: ValueKey<String>(stageKey),
          overline: badge,
          title: title,
          detail: detail,
          icon: icon,
          seats: _effectiveSeats,
          emphasise: emphasise,
        ),
      ),
    );
  }

  // Shared-ride progress + stop timeline now live in the reusable
  // SharedTripStatusCard / SharedStopTimeline widgets
  // (Widgets/shared_trip_status_card.dart), so the sheet leads with a single
  // clean status card instead of two stacked cards.

  void _updateLiveMetrics(LatLng driverPos) {
    final now = DateTime.now();
    if (now.difference(_lastMetricsAt) < _metricsInterval) return;
    _lastMetricsAt = now;

    if (destinationReached) {
      if (_etaChipText == 'Arrived at destination' &&
          _distanceChipText.isEmpty) {
        return;
      }
      setState(() {
        _etaChipText = 'Arrived at destination';
        _distanceChipText = '';
        _nearDestination = false;
      });
      return;
    }

    final LatLng? target =
        driverStartedRide ? _customerDropLatLng : _customerPickupLatLng;
    if (target == null) return;

    final double meters =
        (_routeRemainingMeters != null &&
                _routeRemainingMeters! > 1 &&
                _activeRoute.length >= 2)
            ? _routeRemainingMeters!
            : _distanceMeters(driverPos, target);

    final int seconds = ((meters / 7.2).round()).clamp(1, 24 * 60 * 60).toInt();
    final etaCore = _formatEta(seconds);
    final distCore = _formatDistance(meters);

    final bool near = meters > 0 && meters <= 400 || seconds <= 120;
    final String etaText;
    if (driverStartedRide) {
      _nearDestination = near;
      etaText =
          near
              ? 'Near destination'
              : (etaCore.isEmpty ? '' : '$etaCore to drop');
    } else {
      final arriving = meters > 0 && meters <= 120 || seconds <= 60;
      etaText =
          (_driverArrived || arriving)
              ? 'Arriving at pickup'
              : (etaCore.isEmpty ? '' : '$etaCore away');
    }

    if (etaText.isEmpty) return;
    if (_etaChipText == etaText && _distanceChipText == distCore) return;

    setState(() {
      if (!driverStartedRide &&
          (meters > 0 && meters <= 120 || seconds <= 60)) {
        _driverArrived = true;
      }
      _etaChipText = etaText;
      _distanceChipText = distCore;
    });
  }

  Future<void> _showEtaDistanceSheet() async {
    final eta = _etaChipText;
    final dist = _distanceChipText;
    if (eta.isEmpty && dist.isEmpty) return;

    final title =
        _isRoutingToDrop || driverStartedRide ? 'To destination' : 'To pickup';

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _metricTile(
                        icon: Icons.schedule_rounded,
                        label: 'ETA',
                        value: eta.isEmpty ? '--' : eta,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _metricTile(
                        icon: Icons.route_rounded,
                        label: 'Distance',
                        value: dist.isEmpty ? '--' : dist,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      side: const BorderSide(color: Colors.black12),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      'Close',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _metricTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Container(
            height: 36,
            width: 36,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: Colors.black87),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _otpHighlightCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ride OTP',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  otp,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Share this OTP when the driver reaches pickup.',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: otp));
              if (!mounted) return;
              AppToasts.showSuccess(context, 'OTP copied');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.copy_rounded, size: 16, color: Colors.black),
                  SizedBox(width: 6),
                  Text('Copy', style: TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Check if driver is too far away from current route (off-route).
  bool _isOffRoute(LatLng driverPos, {double thresholdMeters = 60}) {
    if (_activeRoute.isEmpty) return false;

    double minDist = double.infinity;
    for (final p in _activeRoute) {
      final d = _distanceMeters(p, driverPos);
      if (d < minDist) minDist = d;
    }
    return minDist > thresholdMeters;
  }

  // ---------- SOCKET LISTENERS ----------
  void _setupSocketListeners() {
    // Socket should already be connected from Home for a smooth shared flow.
    // Fallback: connect here only if needed (e.g., deep-link into this screen).
    if (!rideShareSocket.connected) {
      rideShareSocket.initSocket(ApiConsents.sharedBaseUrl);
    }

    rideShareSocket.on('connect', (_) {
      if (!mounted) return;
      AppLogger.log.i("✅ Shared socket connected on shared screen");
      // Recover the latest privacy-safe shared state on (re)connect.
      _fetchMySharedState();
    });

    // Phase B: per-customer privacy-safe shared state (live). Updates the
    // "X pickups before you / you are next / stops before your drop" message.
    rideShareSocket.on('shared_my_state', (data) {
      if (!mounted || data is! Map) return;
      try {
        final newState = SharedMyState.fromJson(Map<String, dynamic>.from(data));
        // PERF dedupe: the backend re-emits my-state on every sync (incl. driver
        // location ticks). Only rebuild the sheet when a UI-meaningful field
        // actually changed; otherwise refresh the reference without a rebuild. The
        // payment-completion backup still runs every time (its fields are compared).
        if (!_sharedStateChanged(_myState, newState)) {
          _myState = newState;
          _maybeGoToPaymentFromMyState(newState);
          return;
        }
        setState(() => _myState = newState);
        _maybeGoToPaymentFromMyState(newState);
        // Re-route the map to the driver's actual next stop when it changed.
        _refreshSharedRouteForState();
      } catch (_) {}
    });

    // BUG 3 — dispatch feedback (REUSES the existing backend `booking-update`
    // event). On a driver DECLINE the backend emits DRIVER_REJECTED and instantly
    // redispatches to the next eligible driver (emitBookingRequest), so the
    // customer must STAY searching ("Finding another driver"), NOT go home. When
    // truly no driver remains it emits NO_DRIVERS_AVAILABLE → show the no-driver
    // state. Ignored once a driver is confirmed.
    rideShareSocket.on('booking-update', (data) {
      if (!mounted || data is! Map) return;
      if (isDriverConfirmed || isTripCancelled) return;
      final status = (data['status'] ?? '').toString().toUpperCase();
      if (status == 'DRIVER_REJECTED' || status == 'SEARCHING_NEXT_DRIVER') {
        setState(() {
          isWaitingForDriver = true;
          noDriverFound = false;
          _waitingServerMessage = 'Finding another driver…';
        });
        // A fresh driver is now deciding → extend the no-driver window.
        _restartNoDriverFoundTimer();
      } else if (status == 'ALTERNATE_SEATS_AVAILABLE') {
        // Chosen seat taken in every eligible car, but OTHER seats are free.
        // Backend never reassigns silently — ask the customer to confirm the
        // alternate seat(s); on confirm we update the booking and re-dispatch.
        _noDriverFoundTimer?.cancel();
        final altSeats = (data['availableSeats'] is List)
            ? (data['availableSeats'] as List)
                .map((s) => int.tryParse(s.toString()) ?? -1)
                .where((s) => s >= 2)
                .toList()
            : <int>[];
        final message = (data['message'] ?? '').toString().trim().isNotEmpty
            ? data['message'].toString()
            : 'Your selected seat is not available. Are you okay to continue with the available seats?';
        if (altSeats.isEmpty) {
          // Defensive: no usable alternates in the payload -> same as strict
          // seat-unavailable ("choose another seat").
          setState(() {
            isWaitingForDriver = false;
            noDriverFound = true;
            _seatUnavailableMessage = message;
          });
        } else {
          _showAlternateSeatsDialog(altSeats, message);
        }
      } else if (status == 'SEAT_NOT_AVAILABLE') {
        // STRICT: chosen seat taken in every eligible car. Stop searching and ask
        // the rider to pick another seat (no automatic fallback).
        _noDriverFoundTimer?.cancel();
        setState(() {
          isWaitingForDriver = false;
          noDriverFound = true;
          _seatUnavailableMessage =
              (data['message'] ?? '').toString().trim().isNotEmpty
                  ? data['message'].toString()
                  : 'Sorry, your selected seat is not currently available. Please choose another seat.';
        });
      } else if (status == 'NO_DRIVERS_AVAILABLE' ||
          status == 'NO_DRIVER_AVAILABLE') {
        _noDriverFoundTimer?.cancel();
        setState(() {
          isWaitingForDriver = false;
          noDriverFound = true;
          _seatUnavailableMessage = '';
        });
      }
    });

    // Live pickup-instruction updates — kept in _pickupInstructionLocal so they
    // persist independently of the shared_my_state payload (which omits it).
    rideShareSocket.on('pickup_instruction_updated', (data) {
      if (!mounted || data is! Map) return;
      final bId = (data['bookingId'] ?? '').toString();
      if (bId.isNotEmpty && bId != _effectiveBookingId()) return;
      setState(() =>
          _pickupInstructionLocal = (data['pickupInstruction'] ?? '').toString());
    });

    // When booking is joined and driver accepted
    rideShareSocket.on('joined-booking', (data) async {
      if (!mounted || data == null) return;
      AppLogger.log.i("🚕 joined-booking: $data");

      final wasWaitingForDriver = isWaitingForDriver;
      final wasNoDriverFound = noDriverFound;
      final wasTimerActive = _searchingElapsedTimer?.isActive ?? false;

      // Server sometimes sends `[ { ... } ]` instead of `{ ... }`.
      final dynamic payload =
          (data is List && data.isNotEmpty) ? data.first : data;
      if (payload is! Map) return;

      final Map vehicle =
          (payload['vehicle'] is Map)
              ? (payload['vehicle'] as Map)
              : const <String, dynamic>{};

      // Customer's seat(s) from the backend — resume-safe source for the
      // "Your seat" card.
      final seatsRaw = payload['seats'];
      if (seatsRaw is List) {
        final parsed = seatsRaw
            .map((e) => int.tryParse(e.toString()))
            .whereType<int>()
            .toList();
        if (parsed.isNotEmpty) _mySeatsFromServer = parsed;
      }

      final String driverId = (payload['driverId'] ?? '').toString();
      final String driverFullName = (payload['driverName'] ?? '').toString();
      final double rating =
          double.tryParse(payload['driverRating']?.toString() ?? '') ?? 0.0;
      final String customerPhone = (payload['customerPhone'] ?? '').toString();
      final String color = (vehicle['color'] ?? '').toString();
      final String brand = (vehicle['brand'] ?? '').toString();
      final String model = (vehicle['model'] ?? '').toString();
      final String plate = (vehicle['plateNumber'] ?? '').toString();
      // Use _firstImageUrl (same as single ride) — these fields can arrive as an
      // ARRAY or a "[url]" string; a plain .toString() produced an invalid URL
      // ("[https://…]") so CachedNetworkImage showed a broken-image icon.
      final String profilePic =
          _firstImageUrl(payload['profilePic'] ?? vehicle['profilePic']);
      final double amount =
          (payload['amount'] is num)
              ? (payload['amount'] as num).toDouble()
              : 0.0;
      final String carExteriorPhotos = _firstImageUrl(
        payload['carExteriorPhotos'] ?? vehicle['carExteriorPhotos'],
      );

      final String driverPhone = (payload['driverPhone'] ?? '').toString();
      final String bookingId = (payload['bookingId'] ?? '').toString();
      final String serverMsg = (payload['message'] ?? '').toString();

      final bool driverAccepted = payload['driver_accept_status'] == true;
      final String serverStatus =
          (payload['status'] ?? payload['bookingStatus'] ?? '').toString();
      final bool serverRideStarted =
          payload['rideStarted'] == true ||
          payload['ride_started'] == true ||
          _statusSuggestsRideStarted(serverStatus);
      final bool serverDestinationReached =
          payload['destinationReached'] == true ||
          payload['destination_reached'] == true ||
          _statusSuggestsDestinationReached(serverStatus);

      // customer pickup/drop
      final customerLoc = payload['customerLocation'];
      if (customerLoc is Map) {
        final fromLat =
            (customerLoc['fromLatitude'] as num?)?.toDouble() ?? 0.0;
        final fromLng =
            (customerLoc['fromLongitude'] as num?)?.toDouble() ?? 0.0;
        final toLat = (customerLoc['toLatitude'] as num?)?.toDouble() ?? 0.0;
        final toLng = (customerLoc['toLongitude'] as num?)?.toDouble() ?? 0.0;

        updatePickup(LatLng(fromLat, fromLng));
        updateDrop(LatLng(toLat, toLng));
      }

      // driver location if sent in joined-booking
      final driverLoc = payload['driverLocation'];
      final hasLiveDriverStream =
          _lastAcceptedDriverLocationPos != null &&
          _lastAcceptedDriverLocationTsUtc.isAfter(
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          );
      if (driverLoc is Map && !hasLiveDriverStream) {
        final dLat = (driverLoc['latitude'] as num?)?.toDouble();
        final dLng = (driverLoc['longitude'] as num?)?.toDouble();
        if (dLat != null && dLng != null) {
          _driverLatLng = LatLng(dLat, dLng);
          _updateDriverMarker(_driverLatLng!);
          _updateLiveMetrics(_driverLatLng!);
        }
      }

      final hasDriver =
          driverAccepted || driverId.trim().isNotEmpty || _driverLatLng != null;

      setState(() {
        _waitingServerMessage = serverMsg;
        isDriverConfirmed = hasDriver;
        isWaitingForDriver = !hasDriver;
        noDriverFound = false;
        // M1: the GPS-derived 'destinationReached' flag NEVER flips the COMPLETED
        // text in a shared ride (co-riders share the drop). It only means "almost
        // there"; real completion comes from ride-completed / my-state DROPPED.
        if (serverRideStarted || serverDestinationReached) {
          driverStartedRide = true;
          _driverArrived = true;
          _nearDestination = serverDestinationReached;
        }
        driverName =
            rating > 0
                ? '$driverFullName  ⭐ ${rating.toStringAsFixed(2)}'
                : driverFullName;
        CUSTOMERPHONE = customerPhone;
        carDetails = <String>[
          color,
          brand,
          model,
        ].where((x) => x.trim().isNotEmpty).join(' · ');

        Amount = amount;
        plateNumber = plate;
        CarExteriorPhotos = carExteriorPhotos;
        ProfilePic = profilePic;
        _driverPhone = driverPhone;
        _bookingId = bookingId;
      });

      // If server confirms booking but driver not accepted yet, ensure waiting timers/UI are active.
      if (!hasDriver) {
        if (!wasTimerActive || wasNoDriverFound || !wasWaitingForDriver) {
          startDriverSearch();
        }
      } else {
        _searchingElapsedTimer?.cancel();
        _noDriverFoundTimer?.cancel();
      }

      // Re-apply pickup marker so the "waiting" label icon is removed once a driver is assigned.
      if (_customerPickupLatLng != null) {
        updatePickup(_customerPickupLatLng!);
      }

      // draw DRIVER → PICKUP when accepted
      if (hasDriver && _driverLatLng != null) {
        _mapKey.currentState?.fitRoute(padding: 120);

        if (driverStartedRide) {
          final drop = _customerDropLatLng ?? widget.dropPosition;
          updateDrop(drop);
          await _setRoutePickupToDrop();
        } else if (_customerPickupLatLng != null) {
          await _setRouteDriverToPickup();
        }
      }

    });

    // OTP generated
    rideShareSocket.on('otp-generated', (data) {
      if (!mounted) return;
      if (data is! Map) return; // guard against unexpected payload shapes
      final otpGenerated = (data['otpCode'] ?? '').toString().trim();
      if (otpGenerated.isEmpty) return;
      setState(() {
        otp = otpGenerated;
        // OTP only comes after booking is confirmed; ensure UI switches from waiting state.
        isDriverConfirmed = true;
        isWaitingForDriver = false;
      });
      if (!_didAutoExpandOtp) {
        _didAutoExpandOtp = true;
        _autoExpandSheetToHalf(); // surface the OTP without hiding the map
      }
      if (_customerPickupLatLng != null) {
        updatePickup(_customerPickupLatLng!);
      }
      AppLogger.log.i("otp-generated: $data");
    });

    // Ride started (OTP success)
    rideShareSocket.on('ride-started', (data) async {
      if (data is! Map) return; // guard against unexpected payload shapes
      final bool status = data['status'] == true;
      AppLogger.log.i("ride-started: $data");

      if (!mounted) return;
      setState(() {
        driverStartedRide = status;
        if (status) {
          _driverArrived = true;
          _nearDestination = false;
        }
      });

      if (status) {
        // Now route from PICKUP → DROP
        final drop = _customerDropLatLng ?? widget.dropPosition;
        updateDrop(drop);
        await _setRoutePickupToDrop();
        final driverPos = _driverLatLng;
        if (driverPos != null) _updateLiveMetrics(driverPos);
      }
    });

    // GPS proximity only: the driver's CAR reached the drop area (backend fires
    // this at <50m). It ONLY updates the UI to "you've reached your destination" —
    // it does NOT open payment. Critical for shared rides: 3 riders sharing one
    // drop sit in booking rooms whose drop is the same point, so this event reaches
    // ALL of them; navigating here would open payment for everyone at once.
    rideShareSocket.on('driver-reached-destination', (data) {
      if (data is! Map) return; // guard against unexpected payload shapes
      final status = data['status'];
      if (status == true) {
        if (!mounted) return;
        setState(() {
          // M1: do NOT flip to "you have reached your destination" on a GPS
          // proximity event — at a shared drop this fires for co-riders who are
          // NOT dropped yet. Show "Almost there" instead; the COMPLETED text +
          // payment come ONLY from the per-booking 'ride-completed' / my-state
          // DROPPED (backend-confirmed for THIS bookingId).
          _nearDestination = true;
        });
        final drop = _customerDropLatLng ?? widget.dropPosition;
        updateDrop(drop);
        final p = _driverLatLng;
        if (p != null) _updateLiveMetrics(p);
        AppLogger.log.i("driver_reached_area (almost-there UI only): $data");
      }
    });

    // PAYMENT opens ONLY here. The backend emits 'ride-completed' to THIS booking's
    // room exclusively from completeRide() — i.e. when the driver MANUALLY swipes
    // "Complete stop" for THIS passenger. Per-booking + backend-confirmed, so each
    // rider pays only when their OWN drop is finished; pending co-riders keep
    // waiting instead of all jumping to payment at a shared drop.
    rideShareSocket.on('ride-completed', (data) {
      if (data is! Map) return;
      final String myBookingId = _effectiveBookingId();
      final String evtBookingId = (data['bookingId'] ?? '').toString();
      // The event is already room-scoped to this booking; this id check is a
      // belt-and-braces guard so a stray broadcast can never pay the wrong rider.
      if (evtBookingId.isNotEmpty &&
          myBookingId.isNotEmpty &&
          evtBookingId != myBookingId) {
        return;
      }
      final num evtAmount =
          data['tripAmount'] is num ? data['tripAmount'] as num : Amount;
      _goToPaymentOnce(
        bookingId: myBookingId,
        amount: evtAmount,
        source: "ride-completed (manual swipe)",
      );
    });

    rideShareSocket.on('driver-arrived', (data) {
      AppLogger.log.i("driver-arrived: $data");
      if (!mounted) return;
      setState(() {
        _driverArrived = true;
      });
      if (!_didAutoExpandArrival) {
        _didAutoExpandArrival = true;
        _autoExpandSheetToHalf(); // lift the sheet so the rider sees "arrived"
      }
      final p = _driverLatLng;
      if (p != null) _updateLiveMetrics(p);
    });

    rideShareSocket.on('customer-cancelled',
        (data) => _handleRideCancelledEvent(data, 'customer-cancelled'));

    rideShareSocket.on('driver-cancelled',
        (data) => _handleRideCancelledEvent(data, 'driver-cancelled'));

    // SMOOTH driver-location updates
    rideShareSocket.onAck('driver-location', (data, ack) async {
      if (ack != null) {
        ack({"status": true, "message": "Driver location $ack"});
      }

      // Defensive: onAck normalizes payloads to a Map, but guard against any
      // unexpected delivery shape so a stray List/primitive can't crash the
      // ride isolate with a "String is not a subtype of int of 'index'" error.
      if (data is! Map) return;

      final double lat =
          (data['latitude'] as num?)?.toDouble() ??
          widget.pickupPosition.latitude;
      final double lng =
          (data['longitude'] as num?)?.toDouble() ??
          widget.pickupPosition.longitude;

      final isSimulated =
          data['simulated'] == true ||
          (data['source'] ?? '').toString().trim().toLowerCase() ==
              'ride-simulator';
      DateTime ts = _normalizeTrackingTimestampUtc(
        _parseServerTime(data['timestamp']),
        simulated: isSimulated,
      );
      final newPos = LatLng(lat, lng);
      if (!_shouldAcceptTrackingPacket(
        receivedTsUtc: ts,
        position: newPos,
        simulated: isSimulated,
      )) {
        if (kDebugMode) {
          AppLogger.log.w(
            'Ignoring stale shared-ride driver-location ts=$ts lat=$lat lng=$lng',
          );
        }
        return;
      }
      _lastAcceptedDriverLocationTsUtc = ts;
      _lastAcceptedDriverLocationPos = newPos;
      final now0 = DateTime.now().toUtc();
      // If server clock is skewed too far into the future, treat it as "now"
      // to avoid the animation waiting/stalling.
      if (ts.isAfter(now0.add(const Duration(seconds: 12)))) {
        ts = now0;
      }
      _driverLatLng = newPos;

      // Trim route according to driver progress (throttled — see _throttledTrimRoute).
      if (_activeRoute.isNotEmpty) {
        _throttledTrimRoute(newPos);

        // OFF-ROUTE DETECTION (production-safe):
        // - Require consecutive misses (GPS noise protection)
        // - Throttle route API calls (prevents polyline flicker / blinking)
        final offRoute = _isOffRoute(newPos);
        if (!offRoute) {
          _offRouteConsecutive = 0;
        } else {
          _offRouteConsecutive++;
          final nowR = DateTime.now();
          final canReroute =
              _offRouteConsecutive >= _offRouteConfirmCount &&
              nowR.difference(_lastRerouteAt) >= _minRerouteInterval;
          if (canReroute) {
            _offRouteConsecutive = 0;
            _lastRerouteAt = nowR;
            AppLogger.log.w("🚨 Driver is off route, recalculating...");
            if (_isRoutingToDrop && _customerDropLatLng != null) {
              _requestRoute(newPos, _customerDropLatLng!).then(_setActiveRoute);
            } else if (_isRoutingToPickup && _customerPickupLatLng != null) {
              _requestRoute(
                newPos,
                _customerPickupLatLng!,
              ).then(_setActiveRoute);
            }
          }
        }
      }

      if (kDebugMode) {
        final now = DateTime.now();
        if (now.difference(_lastDriverLocationLogAt) >
            const Duration(seconds: 3)) {
          _lastDriverLocationLogAt = now;
          AppLogger.log.i("driver-location: $data");
        }
      }
    });
  }

  DateTime _parseServerTime(dynamic ts) {
    try {
      if (ts == null) return DateTime.now().toUtc();
      if (ts is int) {
        // Some backends send seconds (10-digit). Some send milliseconds.
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
  }) {
    final lastAcceptedTsUtc = _lastAcceptedDriverLocationTsUtc;
    final lastAcceptedPos = _lastAcceptedDriverLocationPos;
    String decision = 'accepted';

    if (lastAcceptedPos != null) {
      final samePoint = _isSameTrackingPoint(lastAcceptedPos, position);
      if (samePoint) {
        decision = 'duplicate_same_point';
        if (kDebugMode) {
          AppLogger.log.d(
            'shared tracking decision receivedTsUtc=$receivedTsUtc '
            'lastAcceptedTsUtc=$lastAcceptedTsUtc staleDecision=$decision markerUpdated=false',
          );
        }
        return false;
      }
      if (receivedTsUtc.isBefore(lastAcceptedTsUtc)) {
        decision = 'older_than_last';
        if (kDebugMode) {
          AppLogger.log.d(
            'shared tracking decision receivedTsUtc=$receivedTsUtc '
            'lastAcceptedTsUtc=$lastAcceptedTsUtc staleDecision=$decision markerUpdated=false',
          );
        }
        return false;
      }
    } else if (!simulated) {
      final age = DateTime.now().toUtc().difference(receivedTsUtc);
      if (age > const Duration(minutes: 2)) {
        decision = 'too_old_initial';
        if (kDebugMode) {
          AppLogger.log.d(
            'shared tracking decision receivedTsUtc=$receivedTsUtc '
            'lastAcceptedTsUtc=$lastAcceptedTsUtc staleDecision=$decision markerUpdated=false',
          );
        }
        return false;
      }
    }

    if (kDebugMode) {
      AppLogger.log.d(
        'shared tracking decision receivedTsUtc=$receivedTsUtc '
        'lastAcceptedTsUtc=$lastAcceptedTsUtc staleDecision=$decision markerUpdated=true',
      );
    }
    return true;
  }

  double _distanceMeters(LatLng a, LatLng b) {
    const double R = 6371000.0;
    final double dLat = _deg2rad(b.latitude - a.latitude);
    final double dLng = _deg2rad(b.longitude - a.longitude);
    final double la1 = _deg2rad(a.latitude);
    final double la2 = _deg2rad(b.latitude);

    final double h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(la1) * math.cos(la2) * math.sin(dLng / 2) * math.sin(dLng / 2);
    final double c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return R * c;
  }

  double _deg2rad(double d) => d * math.pi / 180.0;

  /// Decode Google encoded polyline to points
  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> points = <LatLng>[];
    int index = 0;
    int lat = 0, lng = 0;

    while (index < encoded.length) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final int dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final int dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  // ignore: unused_element
  Widget _rideTypePill({required bool shared}) {
    final icon = shared ? Icons.group_rounded : Icons.person_rounded;
    final label = shared ? 'Shared ride' : 'Solo ride';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.black87),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  // Kept (currently unrendered) so the 6-step stepper can be re-enabled easily.
  // ignore: unused_element
  Widget _rideStatusTimeline() {
    const steps = [
      'Driver accepted',
      'Reaching pickup',
      'Arrived',
      'Ride started',
      'Near destination',
      'Completed',
    ];
    final activeIndex = _timelineIndex;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ride status',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(steps.length, (index) {
                final completed = index < activeIndex;
                final active = index == activeIndex;
                final color =
                    completed || active
                        ? Colors.black
                        : const Color(0xFFD0D5DD);
                return Row(
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                completed || active
                                    ? Colors.black
                                    : Colors.white,
                            border: Border.all(color: color, width: 2),
                          ),
                          child:
                              completed
                                  ? const Icon(
                                    Icons.check,
                                    size: 10,
                                    color: Colors.white,
                                  )
                                  : active
                                  ? const Center(
                                    child: SizedBox(
                                      width: 6,
                                      height: 6,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  )
                                  : null,
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: 82,
                          child: Text(
                            steps[index],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight:
                                  active ? FontWeight.w700 : FontWeight.w500,
                              color:
                                  completed || active
                                      ? Colors.black
                                      : const Color(0xFF98A2B3),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (index != steps.length - 1)
                      Container(
                        width: 34,
                        height: 2,
                        margin: const EdgeInsets.only(bottom: 24),
                        color:
                            index < activeIndex
                                ? Colors.black
                                : const Color(0xFFE4E7EC),
                      ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NoInternetOverlay(
      child: WillPopScope(
        onWillPop: () async => false,
        child: Scaffold(
          backgroundColor: Colors.white,
          body: Stack(
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomerRideMapView(
                    key: _mapKey,
                    // Full screen behind the sheet. Map auto day/night (dark
                    // after 7pm) — no forced dark.
                    vehicleType:
                        widget.carType.toLowerCase().contains('bike')
                            ? icon_cache.VehicleType.bike
                            : icon_cache.VehicleType.car,
                    driverLocation: _driverLatLng,
                    routePoints: List<LatLng>.from(_activeRoute),
                    pickup: _customerPickupLatLng ?? widget.pickupPosition,
                    drop: _customerDropLatLng ?? widget.dropPosition,
                    mode:
                        driverStartedRide
                            ? RideMapMode.toDrop
                            : RideMapMode.toPickup,
                    etaText: isDriverConfirmed ? _etaChipText : '',
                    distanceText: isDriverConfirmed ? _distanceChipText : '',
                    statusText:
                        driverStartedRide
                            ? 'Ride in progress'
                            : 'Driver reaching pickup',
                    // Keep the route/car above the collapsed sheet peek (0.55).
                    mapPadding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).size.height * 0.55,
                    ),
                    // Blue solid = "your route"; grey dashed while the driver is
                    // serving another rider (matches the on-map legend).
                    sharedRouteStyle: _sharedRouteStyle(),
                    // Generic "another rider" stop the driver is heading to
                    // (privacy-safe: location + type only, never identity).
                    otherStop: _otherStopForMap,
                    otherStopIsPickup:
                        (_myState?.activeStopType ?? '') == 'pickup',
                    // Grey dashed leg driver → that other-rider stop.
                    otherRoute: _otherLegRoute,
                  ),
                ),
              ),

              // SHARED-RIDE CLARITY: when the driver is serving ANOTHER rider
              // first, the driver dot moving "away" confuses a waiting rider who's
              // watching the MAP (not the sheet). This map banner explains it —
              // privacy-safe (counts + generic action only, never the other rider).
              Positioned(
                top: 10,
                left: 12,
                right: 12,
                child: SafeArea(
                  bottom: false,
                  child: _buildDriverBusyMapBanner(),
                ),
              ),

              // Single map control, two toggling actions (Uber/Ola style):
              // tap fits the whole route, then the icon flips to "recenter"; tap
              // again recenters on the driver, icon flips back to "fit".
              Positioned(
                top: 350,
                right: 10,
                child: SafeArea(
                  child: GestureDetector(
                    onTap: () {
                      // Manual only: tap = full-route view (stays), tap again =
                      // focus the driver at zoom 16. No auto-toggling.
                      if (_mapShowFit) {
                        _mapKey.currentState?.fitRoute(padding: 120);
                      } else {
                        _onLocationFabTap();
                      }
                      if (mounted) setState(() => _mapShowFit = !_mapShowFit);
                    },
                    child: Container(
                      height: 42,
                      width: 42,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 8,
                            offset: Offset(0, 3),
                          ),
                        ],
                        border:
                            Border.all(color: Colors.black.withOpacity(0.05)),
                      ),
                      child: Icon(
                        _mapShowFit ? Icons.crop_free : Icons.gps_fixed,
                        size: 22,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
              ),

              // ETA/distance is rendered by CustomerRideMapView (reusable card).

              // (Location FAB is unified above; no duplicate button in confirmed state.)

              // EMERGENCY (SOS) — same white icon-button style as the locate
              // button below it. These two are the only map controls.
              Positioned(
                top: 302,
                right: 10,
                child: SafeArea(
                  child: GestureDetector(
                    onTap: _openSafetySheet,
                    child: Container(
                      height: 42,
                      width: 42,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 8,
                            offset: Offset(0, 3),
                          ),
                        ],
                        border:
                            Border.all(color: Colors.black.withOpacity(0.05)),
                      ),
                      child: Icon(
                        Icons.sos_rounded,
                        size: 22,
                        color: AppColors.emergencyColor,
                      ),
                    ),
                  ),
                ),
              ),

              // Map legend — explains the two route styles (your route vs
              // serving another rider). Only when another rider's stop is in the
              // queue, so the grey/blue distinction is actually on screen.
              if (isDriverConfirmed &&
                  !isTripCancelled &&
                  (_myState?.privacySafeStops.length ?? 0) > 1)
                const Positioned(
                  left: 12,
                  top: 300,
                  child: SafeArea(child: SharedRouteLegend()),
                ),

              // DRAGGABLE SHEET
              DraggableScrollableSheet(
                // ONE sheet for the whole journey (Uber-style): no `key`, so it is
                // NEVER recreated when waiting→confirmed flips — the content morphs
                // in place instead (no rebuild, no "new screen" flash). The
                // controller is ALWAYS attached, so there is only ever ONE live
                // attachment; the old double-attach crash came from the ValueKey
                // rebuilding the sheet with two controllers at the same instant.
                controller: _sheetController,
                // One size config for both phases. We don't switch initialChildSize
                // on confirm (that needs a recreate) — the sheet just stays where
                // the rider left it while the content cross-fades.
                // Minimum peek is 0.55 of the screen; drag up to expand to full.
                initialChildSize: 0.50,
                minChildSize: 0.45,
                maxChildSize: 0.92,
                snap: true,
                snapSizes: const <double>[0.55, 0.75, 0.92],
                builder: (context, scrollController) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(26),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          offset: Offset(0, -4),
                          blurRadius: 18,
                        ),
                      ],
                    ),
                    child: ListView(
                      controller: scrollController,
                      physics: const BouncingScrollPhysics(),
                      children: [
                        Center(
                          child: Container(
                            margin: const EdgeInsets.only(top: 4),
                            width: 44,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Phase B polish: compact privacy-safe shared summary —
                        // visible when the sheet is collapsed.
                        if (_myState != null &&
                            isDriverConfirmed &&
                            !isTripCancelled &&
                            _myState!.collapsedResolved.trim().isNotEmpty) ...[
                          Row(
                            children: [
                              const Icon(Icons.groups_rounded,
                                  size: 18, color: Color(0xFF111418)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _myState!.collapsedResolved,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF111418),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],

                        if (!isDriverConfirmed && isWaitingForDriver) ...[
                          waitingForDriverUI(),
                        ] else if (!isDriverConfirmed && noDriverFound) ...[
                          noDriverFoundUI(),
                        ] else ...[
                          // Strong live trip summary FIRST, at the top of the sheet.
                          if (!isTripCancelled) ...[
                            _buildReachStatusCard(),
                            const SizedBox(height: 14),
                          ],
                          // (Seat + shared-route progress are rendered BELOW the
                          // driver card so the collapsed sheet leads with the
                          // status card + driver detail.)
                          if (isTripCancelled)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 36,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 84,
                                    height: 84,
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.cancel_rounded,
                                      color: Colors.red.shade400,
                                      size: 48,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  const Text(
                                    'Ride cancelled',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.commonBlack,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    cancelReason.trim().isEmpty
                                        ? "Your driver had to cancel this ride. You haven't been charged for the trip."
                                        : cancelReason,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      height: 1.4,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 28),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Taking you back home…',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 12),
                          // (Removed) 6-step ride-status timeline — the live
                          // summary card at the top now carries the ride stage.
                          // OTP black card — before ride starts (urgent pre-ride
                          // action), above the driver card. Hidden after start; a
                          // blue OTP chip then shows in the Total Fare card.
                          // OTP card morphs in/out (no pop): eases open before the
                          // ride starts, then smoothly collapses away once started.
                          AnimatedSize(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.topCenter,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 280),
                              switchInCurve: Curves.easeOut,
                              switchOutCurve: Curves.easeIn,
                              transitionBuilder: (child, anim) =>
                                  FadeTransition(opacity: anim, child: child),
                              child: (otp.isNotEmpty &&
                                      !driverStartedRide &&
                                      !destinationReached)
                                  ? Padding(
                                      key: const ValueKey('otp-card'),
                                      padding: const EdgeInsets.only(bottom: 16),
                                      child: _otpHighlightCard(),
                                    )
                                  : const SizedBox.shrink(
                                      key: ValueKey('otp-none'),
                                    ),
                            ),
                          ),
                          // DRIVER CARD — bordered. Photo left; name, rating and
                          // plate stacked vertically; car image on the right.
                          Builder(
                            builder: (_) {
                              final rawName = driverName.trim();
                              final starIdx = rawName.indexOf('⭐');
                              final nameOnly = (starIdx >= 0
                                      ? rawName.substring(0, starIdx)
                                      : rawName)
                                  .trim();
                              final ratingOnly = starIdx >= 0
                                  ? rawName.substring(starIdx + 1).trim()
                                  : '';
                              return Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: Colors.black.withOpacity(0.12)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    // Driver photo + rating badge (tap → Hero).
                                    SizedBox(
                                      width: 52,
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        alignment: Alignment.bottomCenter,
                                        children: [
                                          GestureDetector(
                                            onTap: ProfilePic.trim().isEmpty
                                                ? null
                                                : _openDriverPhotoPreview,
                                            child: Container(
                                              height: 52,
                                              width: 52,
                                              clipBehavior: Clip.antiAlias,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color:
                                                    AppColors.containerColor1,
                                                border: Border.all(
                                                  color: const Color(0xFF111418)
                                                      .withOpacity(0.25),
                                                  width: 2,
                                                ),
                                              ),
                                              child: (ProfilePic.isNotEmpty)
                                                  ? Hero(
                                                      tag: 'driver-photo-hero',
                                                      child: CachedNetworkImage(
                                                        imageUrl: ProfilePic,
                                                        fit: BoxFit.cover,
                                                        memCacheWidth: 160,
                                                        placeholder:
                                                            (context, url) =>
                                                                const Center(
                                                          child: SizedBox(
                                                            height: 16,
                                                            width: 16,
                                                            child:
                                                                CircularProgressIndicator(
                                                                    strokeWidth:
                                                                        2),
                                                          ),
                                                        ),
                                                        errorWidget: (context,
                                                                url, error) =>
                                                            const Icon(
                                                                Icons.person,
                                                                size: 26),
                                                      ),
                                                    )
                                                  : const Icon(Icons.person,
                                                      size: 26),
                                            ),
                                          ),
                                          if (ratingOnly.isNotEmpty)
                                            Positioned(
                                              bottom: -7,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color:
                                                      const Color(0xFF111418),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                      color: Colors.white,
                                                      width: 1.5),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      ratingOnly,
                                                      style: const TextStyle(
                                                        fontSize: 10.5,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 2),
                                                    const Icon(
                                                        Icons.star_rounded,
                                                        size: 10,
                                                        color: Colors.white),
                                                  ],
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Name → rating → plate, each on its own line.
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            nameOnly.isEmpty
                                                ? 'Your driver'
                                                : nameOnly,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF1A1A1A),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          // Number plate.
                                          Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 9, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF1F3F5),
                                              borderRadius:
                                                  BorderRadius.circular(7),
                                              border: Border.all(
                                                  color: Colors.black
                                                      .withOpacity(0.08)),
                                            ),
                                            child: Text(
                                              plateNumber.isEmpty
                                                  ? '—'
                                                  : plateNumber,
                                              style: const TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 1.0,
                                                color: Color(0xFF1A1A1A),
                                              ),
                                            ),
                                          ),
                                          if (carDetails.trim().isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              carDetails,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: AppColors.carTypeColor,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    // Car exterior photo (right).
                                    if (CarExteriorPhotos.isNotEmpty)
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: CachedNetworkImage(
                                          fit: BoxFit.cover,
                                          height: 66,
                                          width: 86,
                                          memCacheWidth: 260,
                                          imageUrl: CarExteriorPhotos,
                                          placeholder: (context, url) =>
                                              const Center(
                                            child: SizedBox(
                                              height: 16,
                                              width: 16,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2),
                                            ),
                                          ),
                                          errorWidget: (context, url, error) =>
                                              Container(
                                            height: 66,
                                            width: 86,
                                            alignment: Alignment.center,
                                            color: Colors.grey.shade200,
                                            child: Icon(Icons.directions_car,
                                                color: Colors.grey.shade500,
                                                size: 26),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                // Shared-ride tag + your seat, INSIDE the card.
                                if (!isTripCancelled) ...[
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(9),
                                    border: Border.all(
                                        color: Colors.black.withOpacity(0.14)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.groups_rounded,
                                          size: 15, color: Color(0xFF14213A)),
                                      SizedBox(width: 6),
                                      Text(
                                        'Shared ride',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF14213A),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_effectiveSeats.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(9),
                                      border: Border.all(
                                          color: Colors.black.withOpacity(0.14)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.person_outline_rounded,
                                            size: 15, color: Color(0xFF14213A)),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Seat ${_effectiveSeats.join(', ')}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF14213A),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                // Payment type pill — real paymentMode from the
                                // booking (Cash / Online / Wallet), once it's set.
                                if ((_myState?.paymentLabel ?? '').isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF5F5F7),
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _myState!.paymentLabel == 'Cash'
                                              ? Icons.payments_outlined
                                              : _myState!.paymentLabel ==
                                                      'Wallet'
                                                  ? Icons
                                                      .account_balance_wallet_outlined
                                                  : Icons.credit_card_rounded,
                                          size: 15,
                                          color: const Color(0xFF1A1A1A),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          _myState!.paymentLabel,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF1A1A1A),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                                  ),
                                ],
                              ],
                            ),
                          );
                            },
                          ),
                          const SizedBox(height: 14),
                          // Shared-route progress + stop timeline are now part of
                          // the status card at the top of the sheet.

                          // FARE BOX
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.commonWhite,
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 8,
                                  offset: Offset(0, 4),
                                ),
                              ],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 20),
                              child: Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          children: [
                                            CustomTextFields.textWithImage(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                              colors: AppColors.commonBlack,
                                              text: 'Total Fare',
                                              rightImagePath:
                                                  AppImages.nBlackCurrency,
                                              rightImagePathText: ' $Amount',
                                            ),
                                            const SizedBox(width: 8),
                                            // Real payment type (DB-sourced via
                                            // my-state): Cash / Online / Wallet.
                                            if ((_myState?.paymentLabel ?? '')
                                                .isNotEmpty)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 9,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF5F5F7),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      _myState!.paymentLabel ==
                                                              'Cash'
                                                          ? Icons
                                                              .payments_outlined
                                                          : _myState!
                                                                      .paymentLabel ==
                                                                  'Wallet'
                                                              ? Icons
                                                                  .account_balance_wallet_outlined
                                                              : Icons
                                                                  .credit_card_rounded,
                                                      size: 14,
                                                      color: const Color(
                                                          0xFF1A1A1A),
                                                    ),
                                                    const SizedBox(width: 5),
                                                    Text(
                                                      _myState!.paymentLabel,
                                                      style: const TextStyle(
                                                        fontSize: 11.5,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color:
                                                            Color(0xFF1A1A1A),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            const Spacer(),
                                            InkWell(
                                              onTap: () {
                                                HapticFeedback.selectionClick();
                                                setState(() =>
                                                    isExpanded = !isExpanded);
                                              },
                                              child: AnimatedRotation(
                                                turns: isExpanded ? 0.5 : 0,
                                                duration: const Duration(
                                                    milliseconds: 300),
                                                child: Image.asset(
                                                    AppImages.dropDown,
                                                    height: 18),
                                              ),
                                            ),
                                          ],
                                        ),
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: InkWell(
                                            onTap: () {
                                              HapticFeedback.selectionClick();
                                              setState(() =>
                                                  isExpanded = !isExpanded);
                                            },
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 4),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  CustomTextFields
                                                      .textWithStylesSmall(
                                                    'View Details',
                                                    colors: AppColors
                                                        .changeButtonColor,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  Icon(
                                                    Icons.chevron_right_rounded,
                                                    size: 18,
                                                    color: AppColors
                                                        .changeButtonColor,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        AnimatedSwitcher(
                                          duration: const Duration(
                                            milliseconds: 300,
                                          ),
                                          switchInCurve: Curves.easeInOut,
                                          switchOutCurve: Curves.easeInOut,
                                          transitionBuilder: (
                                            child,
                                            animation,
                                          ) {
                                            return SizeTransition(
                                              sizeFactor: animation,
                                              axisAlignment: -1,
                                              child: FadeTransition(
                                                opacity: animation,
                                                child: child,
                                              ),
                                            );
                                          },
                                          child:
                                              isExpanded
                                                  ? Column(
                                                    key: const ValueKey(
                                                      "expanded",
                                                    ),
                                                    children: [
                                                      const SizedBox(
                                                        height: 10,
                                                      ),
                                                      Container(
                                                        margin:
                                                            const EdgeInsets.only(
                                                              top: 10,
                                                            ),
                                                        padding:
                                                            const EdgeInsets.all(
                                                              10,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          border: Border.all(
                                                            color: AppColors
                                                                .commonBlack
                                                                .withOpacity(
                                                                  0.1,
                                                                ),
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                        ),
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            const Text(
                                                              "Fare Breakdown",
                                                              style: TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              height: 5,
                                                            ),
                                                            _fareRow(
                                                                'Base Fare',
                                                                (widget.baseFare ??
                                                                        0)
                                                                    .toString()),
                                                            _fareRow(
                                                                'Distance Fare',
                                                                (widget.distanceFare ??
                                                                        0)
                                                                    .toString()),
                                                            _fareRow(
                                                                'Pickup Fare',
                                                                (widget.pickupFare ??
                                                                        0)
                                                                    .toString()),
                                                            _fareRow(
                                                                'Booking Fee',
                                                                (widget.bookingFee ??
                                                                        0)
                                                                    .toString()),
                                                            _fareRow(
                                                                'Time Fare',
                                                                (widget.timeFare ??
                                                                        0)
                                                                    .toString()),
                                                            const SizedBox(
                                                              height: 10,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(
                                                        height: 10,
                                                      ),
                                                    ],
                                                  )
                                                  : const SizedBox.shrink(
                                                    key: ValueKey("collapsed"),
                                                  ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // DIRECTIONS CARD — only useful BEFORE pickup is done
                          // (driver coming / arrived). Hidden once the ride starts.
                          if (isDriverConfirmed &&
                              !driverStartedRide &&
                              !destinationReached) ...[
                            Builder(
                              builder: (_) {
                                final instr = (_pickupInstructionLocal ??
                                        (_myState?.pickupInstruction ?? ''))
                                    .trim();
                                final hasInstr = instr.isNotEmpty;
                                return GestureDetector(
                                  onTap: _openPickupInstructionSheet,
                                  child: Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: AppColors.containerColor1,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: Colors.black.withOpacity(0.05)),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(15),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(Icons.explore_outlined,
                                                  size: 18,
                                                  color: Color(0xFF374151)),
                                              const SizedBox(width: 8),
                                              CustomTextFields.textWithStyles600(
                                                'Directions to reach',
                                                fontSize: 14,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          CustomTextFields.textWithStylesSmall(
                                            'Help your driver reach you faster',
                                            fontSize: 12,
                                          ),
                                          if (hasInstr) ...[
                                            const SizedBox(height: 8),
                                            Text(
                                              instr,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w500,
                                                color: Color(0xFF1A1A1A),
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 8),
                                          CustomTextFields.textWithStylesSmall(
                                            hasInstr
                                                ? 'Edit Direction'
                                                : 'Add Direction',
                                            fontSize: 12,
                                            colors: AppColors.resendBlue,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 20),
                          ],

                          // PICKUP & DROP READONLY FIELDS + ACTIONS
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 8,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                // Clean stops card (privacy-safe: MY pickup + MY
                                // drop only, with status/ETA on the right).
                                SharedStopsCard(
                                  pickupAddress: _startController.text,
                                  dropAddress: _destController.text,
                                  pickupTrailing: _pickupStopTrailing(),
                                  pickupTrailingColor:
                                      _pickupStopTrailingColor(),
                                  dropTrailing: _dropStopTrailing(),
                                ),
                                const Divider(
                                  height: 0,
                                  color: AppColors.containerColor,
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Obx(() {
                                          final isCancelling =
                                              driverSearchController
                                                  .isCancelLoading
                                                  .value;
                                          final canCancel = !isCancelling &&
                                              !driverStartedRide &&
                                              !destinationReached;
                                          return _actionCell(
                                            icon: Icons.cancel_outlined,
                                            label: isCancelling
                                                ? 'Cancelling...'
                                                : 'Cancel Ride',
                                            color: canCancel
                                                ? AppColors.cancelRideColor
                                                : AppColors.cancelRideColor
                                                    .withOpacity(0.55),
                                            onTap: () {
                                              if (!canCancel) {
                                                if (driverStartedRide) {
                                                  AppToasts.showInfoGlobal(
                                                    "Ride is in progress. Cancellation is not available now.",
                                                    title: 'Info',
                                                  );
                                                  return;
                                                }
                                                AppToasts.showInfoGlobal(
                                                  'Please wait a moment',
                                                  title: 'Info',
                                                );
                                                return;
                                              }
                                              AppButtons
                                                  .showCancelRideBottomSheet(
                                                context,
                                                onConfirmCancel: (
                                                  String selectedReason,
                                                ) {
                                                  return _handleCancelRide(
                                                    selectedReason,
                                                  );
                                                },
                                              );
                                            },
                                          );
                                        }),
                                      ),
                                      _actionDivider(),
                                      Expanded(
                                        child: _actionCell(
                                          icon: Icons.support,
                                          label: 'Support',
                                          color: const Color(0xFF14213A),
                                          onTap: () {
                                            final String bookingId =
                                                shareRideController
                                                        .sharedBooking
                                                        .value
                                                        ?.bookingId ??
                                                    '';
                                            Get.to(
                                              () => CustomerSupportListScreen(
                                                bookingId: bookingId,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      _actionDivider(),
                                      Expanded(
                                        child: _actionCell(
                                          icon: Icons.ios_share,
                                          label: 'Share Ride',
                                          color: const Color(0xFF14213A),
                                          onTap: () {
                                            final String bookingId =
                                                shareRideController
                                                        .sharedBooking
                                                        .value
                                                        ?.bookingId ??
                                                    '';
                                            final url =
                                                "https://hoppr-admin-e7bebfb9fb05.herokuapp.com/ride-tracker/$bookingId";
                                            Share.share(url);
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                        // Bottom padding so the fixed Call/Message bar never
                        // hides the last sheet content (Cancel/Support/Share).
                        const SizedBox(height: 104),
                      ],
                    ),
                  );
                },
              ),

              // FIXED BOTTOM BAR — Call + Message, always visible above the
              // draggable sheet (drawn last in the Stack so it sits on top).
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildFixedDriverActionBar(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget waitingForDriverUI() {
    return ValueListenableBuilder<int>(
      valueListenable: _elapsedSecondsNotifier,
      builder: (context, t, _) {
        final step1Done = t >= 5;
        final step2Done = t >= 12;
        final step3Done = t >= 22;

        Widget buildStep({
          required String title,
          required bool isDone,
          required bool isActive,
        }) {
          final icon =
              isDone
                  ? Icons.check_circle
                  : (isActive
                      ? Icons.radio_button_checked
                      : Icons.circle_outlined);
          final color =
              isDone
                  ? Colors.green.shade600
                  : (isActive ? Colors.black : Colors.grey.shade500);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      color: isActive ? Colors.black : Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final dots = '.' * (1 + (t % 3));
        final serverMsg = _waitingServerMessage.trim();
        final subtitle =
            serverMsg.isNotEmpty ? serverMsg : 'Searching nearby drivers$dots';

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.black,
                          Colors.black.withOpacity(0.92),
                          Colors.black.withOpacity(0.86),
                        ],
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              height: 56,
                              width: 56,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.10),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.18),
                                ),
                              ),
                            ),
                            Container(
                              height: 44,
                              width: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.15),
                              ),
                              child: const Stack(
                                alignment: Alignment.center,
                                children: [
                                  CupertinoActivityIndicator(radius: 12),
                                  Icon(
                                    Icons.local_taxi_outlined,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Finding a driver',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.82),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: LinearProgressIndicator(
                                  minHeight: 6,
                                  backgroundColor: Colors.white.withOpacity(
                                    0.18,
                                  ),
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    size: 16,
                                    color: Colors.white.withOpacity(0.80),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Arrival time shows after a driver accepts',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.80),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Image.asset(AppImages.confirmCar, height: 150, width: 220),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.black.withOpacity(0.08),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 16,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "What's happening",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 6),
                        buildStep(
                          title: 'Requesting nearby drivers',
                          isDone: step1Done,
                          isActive: !step1Done,
                        ),
                        buildStep(
                          title: 'Finding the best price',
                          isDone: step2Done,
                          isActive: step1Done && !step2Done,
                        ),
                        buildStep(
                          title: 'Confirming your driver',
                          isDone: step3Done,
                          isActive: step2Done && !step3Done,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  CustomTextFields.plainTextField(
                    readOnly: true,
                    Style: TextStyle(
                      fontSize: 12,
                      color: AppColors.commonBlack.withOpacity(0.6),
                      overflow: TextOverflow.ellipsis,
                    ),
                    controller: _startController,
                    containerColor: AppColors.commonWhite,
                    leadingImage: AppImages.circleStart,
                    title: 'Search for an address or landmark',
                    hintStyle: const TextStyle(fontSize: 11),
                    imgHeight: 17,
                  ),
                  const Divider(height: 0, color: AppColors.containerColor),
                  CustomTextFields.plainTextField(
                    readOnly: true,
                    Style: TextStyle(
                      fontSize: 12,
                      color: AppColors.commonBlack.withOpacity(0.6),
                      overflow: TextOverflow.ellipsis,
                    ),
                    controller: _destController,
                    containerColor: AppColors.commonWhite,
                    leadingImage: AppImages.rectangleDest,
                    title: 'Enter destination',
                    hintStyle: const TextStyle(fontSize: 11),
                    imgHeight: 17,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Obx(() {
              final loading = driverSearchController.isCancelLoading.value;

              return AppButtons.button(
                size: 350,
                hasBorder: true,
                borderColor: AppColors.commonBlack.withOpacity(0.2),
                buttonColor: AppColors.commonWhite,
                textColor: AppColors.cancelRideColor,
                onTap: () {
                  if (loading) {
                    if (driverStartedRide) {
                      AppToasts.showInfoGlobal(
                        "Ride is in progress. Cancellation is not available now.",
                        title: 'Info',
                      );
                      return;
                    }
                    AppToasts.showInfoGlobal(
                      'Please wait a moment',
                      title: 'Info',
                    );
                    return;
                  }
                  AppButtons.showCancelRideBottomSheet(
                    context,
                    onConfirmCancel: (String selectedReason) {
                      return _handleCancelRide(selectedReason);
                    },
                  );
                },
                isLoading: driverSearchController.isCancelLoading.value,
                text: 'Cancel Ride',
              );
            }),
          ],
        );
      },
    );
  }

  Widget noDriverFoundUI() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            AppImages.emptyNoDrivers,
            width: 150,
            height: 150,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 20),
          Text(
            _seatUnavailableMessage.isNotEmpty
                ? "Seat not available"
                : "No drivers found",
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF14213A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _seatUnavailableMessage.isNotEmpty
                ? _seatUnavailableMessage
                : "We couldn't find any available drivers nearby.\nPlease try again in a few minutes",
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: Color(0xFF667085),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 30),
          AppButtons.button(
            buttonColor: Colors.blue,
            textColor: Colors.white,
            text: _seatUnavailableMessage.isNotEmpty
                ? "Choose another seat"
                : "Try Again",
            onTap: () async {
              // STRICT seat dispatch: "Try Again" would re-request the SAME taken
              // seat and fail again — so for a seat conflict we send the rider back
              // to the seat picker to choose a different seat (no auto-fallback).
              if (_seatUnavailableMessage.isNotEmpty) {
                if (mounted) Navigator.pop(context);
                return;
              }
              setState(() {
                isWaitingForDriver = true;
                noDriverFound = false;
              });

              final bookingId =
                  _bookingId.trim().isNotEmpty
                      ? _bookingId.trim()
                      : (shareRideController.sharedBooking.value?.bookingId ??
                              '')
                          .toString()
                          .trim();

              final pickup = _customerPickupLatLng ?? widget.pickupPosition;
              final drop = _customerDropLatLng ?? widget.dropPosition;

              if (bookingId.isEmpty) {
                AppToasts.showError(
                  context,
                  'Booking not found. Please create booking again.',
                );
                setState(() {
                  isWaitingForDriver = false;
                  noDriverFound = true;
                });
                return;
              }

              final result = await shareRideController.sendSharedDriverRequest(
                carType: widget.carType,
                pickupLatitude: pickup.latitude,
                pickupLongitude: pickup.longitude,
                dropLatitude: drop.latitude,
                dropLongitude: drop.longitude,
                bookingId: bookingId,
                context: context,
              );

              if (result == 'success') {
                startDriverSearch();
              } else {
                setState(() {
                  isWaitingForDriver = false;
                  noDriverFound = true;
                });
              }
            },
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                side: const BorderSide(color: Colors.black),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                'Go Home',
                style: TextStyle(
                  color: AppColors.commonBlack,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen driver-photo preview with a Hero transition from the avatar.
/// Tap anywhere or the close button to dismiss. Safe on a missing/bad URL.
class _DriverPhotoPreview extends StatelessWidget {
  final String imageUrl;
  const _DriverPhotoPreview({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: Center(
                child: Hero(
                  tag: 'driver-photo-hero',
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.contain,
                      placeholder: (context, url) => const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      errorWidget: (context, url, error) => const Icon(
                        Icons.person,
                        color: Colors.white,
                        size: 120,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            right: 14,
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 24),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

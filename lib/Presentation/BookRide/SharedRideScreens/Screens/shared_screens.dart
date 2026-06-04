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
import 'package:hopper/Presentation/BookRide/SharedRideScreens/Controller/share_ride_controller.dart';
import 'package:hopper/Presentation/BookRide/SharedRideScreens/Screens/shared_chat_screens.dart';
import 'package:hopper/Presentation/OnBoarding/Screens/home_screens.dart';

import 'package:hopper/Presentation/OnBoarding/Screens/payment_screen.dart';
import 'package:hopper/api/repository/api_consents.dart';
import 'package:hopper/uitls/netWorkHandling/network_handling_screen.dart';
import 'package:hopper/uitls/websocket/shared_web_socket.dart';
import 'package:hopper/uitls/map/customer/customer_ride_map_view.dart';
import 'package:hopper/uitls/map/customer/marker_icon_cache.dart' as icon_cache;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // ---------- RIDE STATE ----------
  bool isWaitingForDriver = true;
  bool noDriverFound = false;
  bool isTripCancelled = false;
  String _waitingServerMessage = '';

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

  bool isDriverConfirmed = false;
  bool driverStartedRide = false;
  bool destinationReached = false;
  bool _driverArrived = false;
  bool _nearDestination = false;
  String cancelReason = "";
  DateTime _lastMetricsAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _metricsInterval = const Duration(milliseconds: 1200);
  bool _didExitToHome = false;

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

  // Camera follow is handled by [RideTrackingMap].

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

  @override
  void initState() {
    super.initState();

    _bootstrapFromInitialRideState();

    _setupSocketListeners();

    _startController.text = widget.pickupAddress;
    _destController.text = widget.destinationAddress;

    // Start waiting timer only for fresh bookings (no driver yet).
    if (isWaitingForDriver && !isDriverConfirmed && !driverStartedRide) {
      startDriverSearch();
    }
  }

  @override
  void dispose() {
    _searchingElapsedTimer?.cancel();
    _noDriverFoundTimer?.cancel();
    _searchingElapsedSecondsVN?.dispose();
    super.dispose();
  }

  // ---------- ASSET → BITMAP (resize) ----------
  // ignore: unused_element
  Future<void> _loadMarkerIcons() async {
    // Deprecated: map rendering is owned by RideTrackingMap.
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
        assetPath: AppImages.pinLocation,
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
        assetPath: AppImages.pinLocation,
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
        assetPath: AppImages.rectangleDest,
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

      final String driverId = (payload['driverId'] ?? '').toString();
      final String driverFullName = (payload['driverName'] ?? '').toString();
      final double rating =
          double.tryParse(payload['driverRating']?.toString() ?? '') ?? 0.0;
      final String customerPhone = (payload['customerPhone'] ?? '').toString();
      final String color = (vehicle['color'] ?? '').toString();
      final String brand = (vehicle['brand'] ?? '').toString();
      final String model = (vehicle['model'] ?? '').toString();
      final String plate = (vehicle['plateNumber'] ?? '').toString();
      final String profilePic =
          (payload['profilePic'] ?? vehicle['profilePic'] ?? '').toString();
      final double amount =
          (payload['amount'] is num)
              ? (payload['amount'] as num).toDouble()
              : 0.0;
      final String carExteriorPhotos =
          (payload['carExteriorPhotos'] ?? '').toString();

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
      if (driverLoc is Map) {
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
        if (serverDestinationReached) destinationReached = true;
        if (serverRideStarted || serverDestinationReached) {
          driverStartedRide = true;
          _driverArrived = true;
          _nearDestination = false;
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
      final otpGenerated = (data['otpCode'] ?? '').toString().trim();
      if (otpGenerated.isEmpty) return;
      setState(() {
        otp = otpGenerated;
        // OTP only comes after booking is confirmed; ensure UI switches from waiting state.
        isDriverConfirmed = true;
        isWaitingForDriver = false;
      });
      if (_customerPickupLatLng != null) {
        updatePickup(_customerPickupLatLng!);
      }
      AppLogger.log.i("otp-generated: $data");
    });

    // Ride started (OTP success)
    rideShareSocket.on('ride-started', (data) async {
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

    rideShareSocket.on('driver-reached-destination', (data) {
      final String bookingId =
          shareRideController.sharedBooking.value?.bookingId ?? '';
      final status = data['status'];
      if (status == true) {
        if (!mounted) return;
        setState(() {
          destinationReached = true;
          _nearDestination = false;
        });
        final drop = _customerDropLatLng ?? widget.dropPosition;
        updateDrop(drop);
        final p = _driverLatLng;
        if (p != null) _updateLiveMetrics(p);
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          // Replace with your actual PaymentScreen import
          Get.to(() => PaymentScreen(bookingId: bookingId, amount: Amount));
        });
        AppLogger.log.i("driver_reached,$data");
      }
    });

    rideShareSocket.on('driver-arrived', (data) {
      AppLogger.log.i("driver-arrived: $data");
      if (!mounted) return;
      setState(() {
        _driverArrived = true;
      });
      final p = _driverLatLng;
      if (p != null) _updateLiveMetrics(p);
    });

    rideShareSocket.on('customer-cancelled', (data) async {
      AppLogger.log.i('customer-cancelled : $data');
      if (data != null && data['status'] == true) {
        if (!mounted) return;
        setState(() {
          isTripCancelled = true;
          cancelReason =
              (data['message'] ?? data['reason'] ?? "Trip cancelled")
                  .toString();
        });
        await Future.delayed(const Duration(seconds: 3));
        if (!mounted) return;
        if (_didExitToHome) return;
        _didExitToHome = true;
        Get.offAll(() => const HomeScreens());
      }
    });

    rideShareSocket.on('driver-cancelled', (data) async {
      AppLogger.log.i('driver-cancelled : $data');
      if (data != null && data['status'] == true) {
        if (!mounted) return;
        setState(() {
          isTripCancelled = true;
          cancelReason =
              (data['message'] ?? data['reason'] ?? "Trip cancelled")
                  .toString();
        });
        await Future.delayed(const Duration(seconds: 3));
        if (!mounted) return;
        if (_didExitToHome) return;
        _didExitToHome = true;
        Get.offAll(() => const HomeScreens());
      }
    });

    // SMOOTH driver-location updates
    rideShareSocket.onAck('driver-location', (data, ack) async {
      if (ack != null) {
        ack({"status": true, "message": "Driver location $ack"});
      }

      if (data == null) return;

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
      _lastAcceptedDriverLocationTsUtc =
          isSimulated && ts.isBefore(_lastAcceptedDriverLocationTsUtc)
              ? _lastAcceptedDriverLocationTsUtc.add(
                  const Duration(milliseconds: 1),
                )
              : ts;
      _lastAcceptedDriverLocationPos = newPos;
      final now0 = DateTime.now().toUtc();
      // If server clock is skewed too far into the future, treat it as "now"
      // to avoid the animation waiting/stalling.
      if (ts.isAfter(now0.add(const Duration(seconds: 12)))) {
        ts = now0;
      }
      _driverLatLng = newPos;

      // Trim route according to driver progress
      if (_activeRoute.isNotEmpty) {
        _trimRouteForDriver(newPos);

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
    if (simulated) {
      return nowUtc;
    }
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
      final tsDiffMs =
          receivedTsUtc.difference(lastAcceptedTsUtc).inMilliseconds.abs();
      if (samePoint && tsDiffMs <= 2500) {
        decision = 'duplicate_same_point';
        if (kDebugMode) {
          AppLogger.log.d(
            'shared tracking decision receivedTsUtc=$receivedTsUtc '
            'lastAcceptedTsUtc=$lastAcceptedTsUtc staleDecision=$decision markerUpdated=false',
          );
        }
        return false;
      }
      if (receivedTsUtc.isBefore(
        lastAcceptedTsUtc.subtract(const Duration(seconds: 3)),
      )) {
        if (simulated && !samePoint) {
          decision = 'simulator_reordered_accept';
        } else {
          decision = simulated ? 'simulator_out_of_order' : 'older_than_last';
          if (kDebugMode) {
            AppLogger.log.d(
              'shared tracking decision receivedTsUtc=$receivedTsUtc '
              'lastAcceptedTsUtc=$lastAcceptedTsUtc staleDecision=$decision markerUpdated=false',
            );
          }
          return false;
        }
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
              SizedBox(
                height: 550,
                width: double.infinity,
                child: RepaintBoundary(
                  child: CustomerRideMapView(
                    key: _mapKey,
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
                    mapPadding: const EdgeInsets.only(bottom: 210),
                  ),
                ),
              ),

              Positioned(
                top: 350,
                right: 10,
                child: SafeArea(
                  child: GestureDetector(
                    onTap: _onLocationFabTap,
                    onLongPress: () {
                      final mapState = _mapKey.currentState;
                      if (mapState == null) return;

                      final driverPos = _driverLatLng;

                      // Long-press: fit driver ↔ (pickup/drop) if driver exists,
                      // otherwise fit pickup ↔ drop.
                      final a =
                          driverPos ??
                          _customerPickupLatLng ??
                          widget.pickupPosition;
                      final b =
                          driverPos != null
                              ? (driverStartedRide
                                  ? (_customerDropLatLng ?? widget.dropPosition)
                                  : (_customerPickupLatLng ??
                                      widget.pickupPosition))
                              : (_customerDropLatLng ?? widget.dropPosition);

                      if (a.latitude == b.latitude &&
                          a.longitude == b.longitude) {
                        return;
                      }
                      _mapKey.currentState?.fitRoute(padding: 120);
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
                        border: Border.all(
                          color: Colors.black.withOpacity(0.05),
                        ),
                      ),
                      child: Icon(
                        Icons.my_location,
                        size: 22,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
              ),

              // ETA/distance is rendered by CustomerRideMapView (reusable card).

              // (Location FAB is unified above; no duplicate button in confirmed state.)

              // EMERGENCY BUTTON
              Positioned(
                top: 50,
                right: 15,
                child: GestureDetector(
                  onTap: () async {
                    try {
                      final prefs = await SharedPreferences.getInstance();
                      String? sosNumber = prefs.getString('sosNumber');

                      if (sosNumber == null || sosNumber.trim().isEmpty) {
                        AppToasts.showError(context, 'SOS number not set');
                        return;
                      }

                      sosNumber = sosNumber.trim();
                      final hasPlus = sosNumber.startsWith('+');
                      final digitsOnly = sosNumber.replaceAll(
                        RegExp(r'[^0-9]'),
                        '',
                      );
                      final normalized = hasPlus ? '+$digitsOnly' : digitsOnly;

                      if (normalized.isEmpty) {
                        AppToasts.showError(context, 'Invalid SOS number');
                        return;
                      }

                      final ok = await launchPhoneDialer(normalized);

                      if (!ok) {
                        AppToasts.showError(context, 'Could not open dialer');
                      }
                    } catch (e) {
                      AppToasts.showError(context, 'Failed to start call');
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      color: AppColors.emergencyColor,
                    ),
                    child: CustomTextFields.textWithStyles600(
                      'Emergency',
                      color: AppColors.commonWhite,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),

              // DRAGGABLE SHEET
              DraggableScrollableSheet(
                key: ValueKey(isDriverConfirmed),
                initialChildSize: isDriverConfirmed ? 0.65 : 0.5,
                minChildSize: 0.4,
                maxChildSize: isDriverConfirmed ? 0.9 : 0.80,
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
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.black12,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        if (!isDriverConfirmed && isWaitingForDriver) ...[
                          waitingForDriverUI(),
                        ] else if (!isDriverConfirmed && noDriverFound) ...[
                          noDriverFoundUI(),
                        ] else ...[
                          if (isTripCancelled)
                            Container(
                              padding: const EdgeInsets.all(10),
                              margin: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.cancel, color: Colors.red),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      cancelReason.trim().isEmpty
                                          ? "Your trip has been cancelled"
                                          : cancelReason,
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Center(
                              child: CustomTextFields.textWithImage(
                                fontSize: 20,
                                imageSize: 24,
                                fontWeight: FontWeight.w600,
                                text:
                                    destinationReached
                                        ? 'Ride Completed'
                                        : driverStartedRide
                                        ? 'Ride in Progress'
                                        : 'Your ride is confirmed',
                                colors: AppColors.commonBlack,
                                rightImagePath: AppImages.clrTick,
                              ),
                            ),

                          if (!isTripCancelled) ...[
                            const SizedBox(height: 6),
                            Center(child: _rideTypePill(shared: true)),
                          ],
                          const SizedBox(height: 12),
                          if (!isTripCancelled) ...[
                            _rideStatusTimeline(),
                            const SizedBox(height: 14),
                          ],
                          Row(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CustomTextFields.textWithStylesSmall(
                                    plateNumber,
                                    colors: AppColors.commonBlack,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  Row(
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            50,
                                          ),
                                          color: AppColors.containerColor1,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child:
                                              (ProfilePic.isNotEmpty)
                                                  ? CachedNetworkImage(
                                                    imageUrl: ProfilePic,
                                                    height: 20,
                                                    width: 20,
                                                    placeholder:
                                                        (
                                                          context,
                                                          url,
                                                        ) => const SizedBox(
                                                          height: 16,
                                                          width: 16,
                                                          child:
                                                              CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                              ),
                                                        ),
                                                    errorWidget:
                                                        (context, url, error) =>
                                                            const Icon(
                                                              Icons.person,
                                                              size: 20,
                                                            ),
                                                  )
                                                  : const Icon(
                                                    Icons.person,
                                                    size: 20,
                                                  ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      CustomTextFields.textWithStylesSmall(
                                        driverName,
                                        colors: AppColors.commonBlack,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ],
                                  ),
                                  CustomTextFields.textWithStylesSmall(
                                    carDetails,
                                    fontSize: 12,
                                    colors: AppColors.carTypeColor,
                                  ),
                                ],
                              ),
                              const Spacer(),
                              CarExteriorPhotos.isNotEmpty
                                  ? ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: CachedNetworkImage(
                                      fit: BoxFit.fill,
                                      height: 80,
                                      width: 100,
                                      imageUrl: CarExteriorPhotos,
                                      placeholder:
                                          (context, url) => const Center(
                                            child: SizedBox(
                                              height: 16,
                                              width: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                          ),
                                      errorWidget:
                                          (context, url, error) => Container(
                                            height: 80,
                                            width: 100,
                                            alignment: Alignment.center,
                                            color: Colors.grey.shade200,
                                            child: const Icon(
                                              Icons.broken_image,
                                              color: Colors.grey,
                                              size: 28,
                                            ),
                                          ),
                                    ),
                                  )
                                  : const SizedBox.shrink(),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // CALL + CHAT
                          Row(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(50),
                                  color: AppColors.containerColor1,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: InkWell(
                                    onTap: () async {
                                      try {
                                        var rawNumber = _driverPhone.trim();
                                        if (rawNumber.isEmpty) {
                                          AppToasts.showError(
                                            context,
                                            'Number Not set ',
                                          );
                                          return;
                                        }

                                        final hasPlus = rawNumber.startsWith(
                                          '+',
                                        );
                                        final digitsOnly = rawNumber.replaceAll(
                                          RegExp(r'[^0-9]'),
                                          '',
                                        );
                                        final normalized =
                                            hasPlus
                                                ? '+$digitsOnly'
                                                : digitsOnly;

                                        if (normalized.isEmpty) {
                                          AppToasts.showError(
                                            context,
                                            'Invalid number',
                                          );
                                          return;
                                        }

                                        final ok = await launchPhoneDialer(
                                          normalized,
                                        );

                                        if (!ok) {
                                          AppToasts.showError(
                                            context,
                                            'Could not open dialer',
                                          );
                                        }
                                      } catch (e) {
                                        AppToasts.showError(
                                          context,
                                          'Failed to start call',
                                        );
                                      }
                                    },
                                    child: Image.asset(
                                      AppImages.call,
                                      height: 20,
                                      width: 20,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: InkWell(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder:
                                            (context) => SharedChatScreens(
                                              bookingId:
                                                  shareRideController
                                                      .sharedBooking
                                                      .value
                                                      ?.bookingId
                                                      .toString() ??
                                                  '',
                                            ),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(20),
                                      color: AppColors.containerColor1,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Row(
                                        children: [
                                          CustomTextFields.textWithStylesSmall(
                                            'Message your driver',
                                            colors: AppColors.commonBlack,
                                          ),
                                          const Spacer(),
                                          Image.asset(
                                            AppImages.send,
                                            height: 16,
                                            width: 16,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          if (otp.isNotEmpty &&
                              !driverStartedRide &&
                              !destinationReached) ...[
                            _otpHighlightCard(),
                            const SizedBox(height: 16),
                          ],

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
                                            const Spacer(),
                                            otp.isEmpty
                                                ? const SizedBox.shrink()
                                                : Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 6,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                    color:
                                                        AppColors
                                                            .userChatContainerColor,
                                                  ),
                                                  child:
                                                      CustomTextFields.textWithStyles600(
                                                        'OTP - $otp',
                                                        fontSize: 16,
                                                        color:
                                                            AppColors
                                                                .commonWhite,
                                                      ),
                                                ),
                                          ],
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8.0,
                                          ),
                                          child: InkWell(
                                            onTap:
                                                () => setState(
                                                  () =>
                                                      isExpanded = !isExpanded,
                                                ),
                                            child: Row(
                                              children: [
                                                CustomTextFields.textWithStylesSmall(
                                                  'View Details',
                                                  colors:
                                                      AppColors
                                                          .changeButtonColor,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                const SizedBox(width: 10),
                                                AnimatedRotation(
                                                  turns: isExpanded ? 0.5 : 0,
                                                  duration: const Duration(
                                                    milliseconds: 300,
                                                  ),
                                                  child: Image.asset(
                                                    AppImages.dropDown,
                                                    height: 16,
                                                  ),
                                                ),
                                              ],
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
                                                            Row(
                                                              children: [
                                                                CustomTextFields.textWithStylesSmall(
                                                                  'Base Fare',
                                                                ),
                                                                const Spacer(),
                                                                CustomTextFields.textWithImage(
                                                                  colors:
                                                                      AppColors
                                                                          .commonBlack,
                                                                  text:
                                                                      (widget.baseFare ??
                                                                              0)
                                                                          .toString(),
                                                                  imagePath:
                                                                      AppImages
                                                                          .nBlackCurrency,
                                                                ),
                                                              ],
                                                            ),
                                                            Row(
                                                              children: [
                                                                CustomTextFields.textWithStylesSmall(
                                                                  'Distance Fare',
                                                                ),
                                                                const Spacer(),
                                                                CustomTextFields.textWithImage(
                                                                  colors:
                                                                      AppColors
                                                                          .commonBlack,
                                                                  text:
                                                                      (widget.distanceFare ??
                                                                              0)
                                                                          .toString(),
                                                                  imagePath:
                                                                      AppImages
                                                                          .nBlackCurrency,
                                                                ),
                                                              ],
                                                            ),
                                                            Row(
                                                              children: [
                                                                CustomTextFields.textWithStylesSmall(
                                                                  'Pickup Fare',
                                                                ),
                                                                const Spacer(),
                                                                CustomTextFields.textWithImage(
                                                                  colors:
                                                                      AppColors
                                                                          .commonBlack,
                                                                  text:
                                                                      (widget.pickupFare ??
                                                                              0)
                                                                          .toString(),
                                                                  imagePath:
                                                                      AppImages
                                                                          .nBlackCurrency,
                                                                ),
                                                              ],
                                                            ),
                                                            Row(
                                                              children: [
                                                                CustomTextFields.textWithStylesSmall(
                                                                  'Booking Fee',
                                                                ),
                                                                const Spacer(),
                                                                CustomTextFields.textWithImage(
                                                                  colors:
                                                                      AppColors
                                                                          .commonBlack,
                                                                  text:
                                                                      (widget.bookingFee ??
                                                                              0)
                                                                          .toString(),
                                                                  imagePath:
                                                                      AppImages
                                                                          .nBlackCurrency,
                                                                ),
                                                              ],
                                                            ),
                                                            Row(
                                                              children: [
                                                                CustomTextFields.textWithStylesSmall(
                                                                  'Time Fare',
                                                                ),
                                                                const Spacer(),
                                                                CustomTextFields.textWithImage(
                                                                  colors:
                                                                      AppColors
                                                                          .commonBlack,
                                                                  text:
                                                                      (widget.timeFare ??
                                                                              0)
                                                                          .toString(),
                                                                  imagePath:
                                                                      AppImages
                                                                          .nBlackCurrency,
                                                                ),
                                                              ],
                                                            ),
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

                          // DIRECTIONS CARD
                          GestureDetector(
                            onTap: () {},
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.containerColor1,
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(15),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CustomTextFields.textWithStyles600(
                                      'Directions to reach',
                                      fontSize: 14,
                                    ),
                                    CustomTextFields.textWithStylesSmall(
                                      'Help your driver partner reach you faster',
                                      fontSize: 12,
                                    ),
                                    CustomTextFields.textWithStylesSmall(
                                      'Add Direction',
                                      fontSize: 12,
                                      colors: AppColors.resendBlue,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

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
                                CustomTextFields.plainTextField(
                                  readOnly: true,
                                  Style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.commonBlack.withOpacity(
                                      0.6,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  controller: _startController,
                                  containerColor: AppColors.commonWhite,
                                  leadingImage: AppImages.circleStart,
                                  title: 'Search for an address or landmark',
                                  hintStyle: const TextStyle(fontSize: 11),
                                  imgHeight: 17,
                                ),
                                const Divider(
                                  height: 0,
                                  color: AppColors.containerColor,
                                ),
                                CustomTextFields.plainTextField(
                                  readOnly: true,
                                  Style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.commonBlack.withOpacity(
                                      0.6,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  controller: _destController,
                                  containerColor: AppColors.commonWhite,
                                  leadingImage: AppImages.rectangleDest,
                                  title: 'Enter destination',
                                  hintStyle: const TextStyle(fontSize: 11),
                                  imgHeight: 17,
                                ),
                                const Divider(
                                  height: 0,
                                  color: AppColors.containerColor,
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 15,
                                    vertical: 15,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Obx(() {
                                        final isCancelling =
                                            driverSearchController
                                                .isCancelLoading
                                                .value;
                                        final canCancel =
                                            !isCancelling &&
                                            !driverStartedRide &&
                                            !destinationReached;

                                        return CustomTextFields.textWithImage(
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
                                            AppButtons.showCancelRideBottomSheet(
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
                                          text:
                                              isCancelling
                                                  ? 'Cancelling...'
                                                  : 'Cancel Ride',
                                          fontWeight: FontWeight.w500,
                                          colors:
                                              canCancel
                                                  ? AppColors.cancelRideColor
                                                  : AppColors.cancelRideColor
                                                      .withOpacity(0.55),
                                          imagePath: AppImages.cancel,
                                        );
                                      }),
                                      const SizedBox(width: 10),
                                      SizedBox(
                                        height: 24,
                                        child: VerticalDivider(
                                          color: Colors.grey,
                                          thickness: 1,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      CustomTextFields.textWithImage(
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
                                        text: 'Support',
                                        fontWeight: FontWeight.w500,
                                        colors: AppColors.cancelRideColor,
                                        imagePath: AppImages.support,
                                      ),
                                      const SizedBox(width: 10),
                                      SizedBox(
                                        height: 24,
                                        child: VerticalDivider(
                                          color: Colors.grey,
                                          thickness: 1,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      CustomTextFields.textWithImage(
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
                                        text: 'Share',
                                        fontWeight: FontWeight.w500,
                                        colors: AppColors.cancelRideColor,
                                        imagePath: AppImages.share,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ],
                    ),
                  );
                },
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
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 80),
          const SizedBox(height: 20),
          const Text(
            "No Drivers Found",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.redAccent,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "We couldn't find any available drivers nearby.\nPlease try again in a few minutes",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 30),
          AppButtons.button(
            buttonColor: Colors.blue,
            textColor: Colors.white,
            text: "Try Again",
            onTap: () async {
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

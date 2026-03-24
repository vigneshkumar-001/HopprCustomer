import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:hopper/Core/Utility/app_buttons.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Core/Utility/app_toasts.dart';
import 'package:hopper/Presentation/Authentication/widgets/textFields.dart';
import 'package:hopper/Presentation/BookRide/Controllers/driver_search_controller.dart';
import 'package:hopper/Presentation/BookRide/SharedRideScreens/Controller/share_ride_controller.dart';
import 'package:hopper/Presentation/BookRide/SharedRideScreens/Screens/shared_chat_screens.dart';
import 'package:hopper/Presentation/OnBoarding/Screens/chat_screen.dart';
import 'package:hopper/Presentation/OnBoarding/Screens/home_screens.dart';

import 'package:hopper/Presentation/OnBoarding/Screens/payment_screen.dart';
import 'package:hopper/api/repository/api_consents.dart';
import 'package:hopper/uitls/map/shared_map.dart';
import 'package:hopper/uitls/netWorkHandling/network_handling_screen.dart';
import 'package:hopper/uitls/websocket/shared_web_socket.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:hopper/Presentation/CustomerSupport/screens/customer_support_list_screen.dart';

import 'package:http/http.dart' as http;

class DriverPose {
  final LatLng position;
  final double? bearing;
  final DateTime t;

  DriverPose({required this.position, this.bearing, DateTime? t})
    : t = t ?? DateTime.now();
}

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
    this.routePoints = const [],
    this.onCancel,
    required this.carType,
  });

  @override
  State<SharedScreens> createState() => _SharedScreensState();
}

class _SharedScreensState extends State<SharedScreens>
    with SingleTickerProviderStateMixin {
  // ---------- UI ANIMATION ----------
  late final AnimationController _controller;
  late final Animation<double> _progressAnimation;

  final TextEditingController _startController = TextEditingController();
  final TextEditingController _destController = TextEditingController();

  // ---------- MAP CONTROL ----------
  final GlobalKey<SharedMapState> _mapKey = GlobalKey<SharedMapState>();

  BitmapDescriptor? _pickupIcon;
  BitmapDescriptor? _dropIcon;
  BitmapDescriptor? _driverIcon;

  Set<Marker> _markers = <Marker>{};
  Set<Polyline> _polylines = <Polyline>{};

  // ---------- RIDE STATE ----------
  bool isWaitingForDriver = true;
  bool noDriverFound = false;
  bool isTripCancelled = false;

  final RideShareSocketService rideShareSocket = RideShareSocketService();
  final DriverSearchController driverSearchController = Get.put(
    DriverSearchController(),
  );
  final ShareRideController shareRideController = Get.put(
    ShareRideController(),
  );

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

  // ---------- SMOOTH MOTION STATE ----------
  DriverPose? _currentPose;
  final List<DriverPose> _poseQueue = <DriverPose>[];
  Timer? _motionTimer;

  final Duration _maxStale = const Duration(seconds: 6);
  final int _maxQueue = 24;
  final Duration _motionStep = const Duration(milliseconds: 60);
  final Duration _visualDelay = const Duration(milliseconds: 700);

  // ---------- CAMERA (order_confirm style) ----------
  double _currentZoomLevel = 16.6;
  DateTime _pauseAutoFollowUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastCameraMoveAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _cameraInterval = const Duration(milliseconds: 900);
  final Duration _userGesturePause = const Duration(seconds: 4);

  String _effectiveBookingId() {
    final fromSocket = _bookingId.trim();
    if (fromSocket.isNotEmpty) return fromSocket;
    final fromController =
        (shareRideController.sharedBooking.value?.bookingId ?? '').toString().trim();
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

    Future.delayed(const Duration(seconds: 30), () async {
      if (!isDriverConfirmed) {
        final hasDriver = await driverSearchController.noDriverFound(
          context: context,
          bookingId: _bookingId,
          status: true,
        );

        if (!mounted) return;
        setState(() {
          isWaitingForDriver = false;
          noDriverFound = !hasDriver;
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _progressAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );

    _loadMarkerIcons();
    _setupSocketListeners();

    _startController.text = widget.pickupAddress;
    _destController.text = widget.destinationAddress;
  }

  @override
  void dispose() {
    _controller.dispose();
    _motionTimer?.cancel();
    super.dispose();
  }

  // ---------- ASSET → BITMAP (resize) ----------
  Future<BitmapDescriptor> _bitmapFromAsset(
    String assetPath, {
    double widthDp = 42,
  }) async {
    final dpr = ui.window.devicePixelRatio;
    final targetWidth = (widthDp * dpr).round().clamp(1, 4096);
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List();

    final codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
    final frame = await codec.getNextFrame();
    final resizedBytes =
        (await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();

    return BitmapDescriptor.fromBytes(resizedBytes);
  }

  Future<void> _loadMarkerIcons() async {
    // Medium, clean marker size (match solo ride UX)
    _pickupIcon = await _bitmapFromAsset(AppImages.circleStart, widthDp: 26);
    _dropIcon = await _bitmapFromAsset(AppImages.rectangleDest, widthDp: 26);

    final t = widget.carType.toLowerCase();
    final driverAsset =
        (t.contains('bike') || t.contains('package'))
            ? AppImages.packageBike
            : AppImages.carHop;
    _driverIcon = await _bitmapFromAsset(driverAsset, widthDp: 32);

    _initRouteAndMarkers();
    if (!mounted) return;
    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mapState = _mapKey.currentState;
      if (mapState == null) return;
      mapState.animateTo(target: widget.pickupPosition, zoom: _currentZoomLevel);
    });
  }

  // ---------- INITIAL MARKERS + ROUTE ----------
  void _initRouteAndMarkers() {
    final pickupMarker = Marker(
      markerId: const MarkerId('pickup'),
      position: widget.pickupPosition,
      icon:
          _pickupIcon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      anchor: const Offset(0.5, 1.0),
    );

    final dropMarker = Marker(
      markerId: const MarkerId('drop'),
      position: widget.dropPosition,
      icon:
          _dropIcon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      anchor: const Offset(0.5, 1.0),
    );

    _markers = {pickupMarker, dropMarker};

    if (widget.routePoints.isNotEmpty) {
      _activeRoute = widget.routePoints;
      _polylines = {
        Polyline(
          polylineId: const PolylineId('route'),
          points: widget.routePoints,
          width: 4,
          color: Colors.black,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      };
    }

    _customerPickupLatLng = widget.pickupPosition;
    _customerDropLatLng = widget.dropPosition;
  }

  // ---------- GENERAL MARKER HELPERS ----------
  void updatePickup(LatLng pos) {
    _customerPickupLatLng = pos;
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'pickup');
      _markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: pos,
          icon:
              _pickupIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          anchor: const Offset(0.5, 1.0),
        ),
      );
    });
  }

  void updateDrop(LatLng pos) {
    _customerDropLatLng = pos;
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'drop');
      _markers.add(
        Marker(
          markerId: const MarkerId('drop'),
          position: pos,
          icon:
              _dropIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          anchor: const Offset(0.5, 1.0),
        ),
      );
    });
  }

  void updateRoute(List<LatLng> points) {
    setState(() {
      _polylines = {
        Polyline(
          polylineId: const PolylineId('route'),
          points: points,
          width: 4,
          color: Colors.black,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      };
      _activeRoute = points;
    });
  }

  void _updateDriverMarker(LatLng pos, {double? bearing}) {
    setState(() {
      _markers.removeWhere((m) => m.markerId.value == 'driver');
      _markers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: pos,
          icon:
              _driverIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          anchor: const Offset(0.5, 0.72),
          rotation: bearing ?? 0,
          flat: true,
        ),
      );
    });
  }

  void _onUserMapGesture() {
    _pauseAutoFollowUntil = DateTime.now().add(_userGesturePause);
  }

  void _autoCameraUpdate(LatLng driverPos, {bool force = false}) {
    final mapState = _mapKey.currentState;
    if (mapState == null) return;

    final now = DateTime.now();
    if (!force) {
      if (now.isBefore(_pauseAutoFollowUntil)) return;
      if (now.difference(_lastCameraMoveAt) < _cameraInterval) return;
      _lastCameraMoveAt = now;
    } else {
      _lastCameraMoveAt = now;
    }

    final LatLng? focusTarget =
        driverStartedRide ? _customerDropLatLng : _customerPickupLatLng;

    // Uber/Ola like: keep a closer follow-zoom so roads are readable.
    const double followZoom = 16.6;

    // Smart fit: if driver is far from pickup/drop, show both once in a while.
    if (focusTarget != null) {
      final d = _distanceMeters(driverPos, focusTarget);
      final threshold = driverStartedRide ? 2200.0 : 1200.0;
      if (d > threshold) {
        mapState.fitPointsBounds(<LatLng>[driverPos, focusTarget], padding: 120);
        return;
      }
    }

    final double z = _currentZoomLevel.clamp(15.5, 17.8).toDouble();
    mapState.animateTo(target: driverPos, zoom: z.isFinite ? z : followZoom);
  }

  void _followDriverNow() {
    final p = _driverLatLng;
    if (p == null) return;
    _pauseAutoFollowUntil = DateTime.fromMillisecondsSinceEpoch(0);
    _autoCameraUpdate(p, force: true);
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
            _driverArrived ? 'Arriving at pickup' : (etaCore.isEmpty ? '' : '$etaCore away');
      }
      _distanceChipText = distCore;
      _polylines = {
        Polyline(
          polylineId: const PolylineId('route'),
          points: points,
          width: 4,
          color: Colors.black,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          jointType: JointType.round,
        ),
      };
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
          final int? meters = (leg0['distance'] is Map)
              ? (leg0['distance']['value'] as num?)?.toInt()
              : null;
          final int? seconds = (leg0['duration'] is Map)
              ? (leg0['duration']['value'] as num?)?.toInt()
              : null;
          if (meters != null && meters > 0) _routeTotalMeters = meters.toDouble();
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

  /// Trim route so that only "remaining" path ahead of driver is drawn.
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
      final newRoute = _activeRoute.sublist(closestIndex);
      setState(() {
        _activeRoute = newRoute;
        _routeRemainingMeters = _computeRouteMeters(newRoute);
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
              _driverArrived ? 'Arriving at pickup' : (etaCore.isEmpty ? '' : '$etaCore away');
        }
        _distanceChipText = distCore;
        _polylines = {
          Polyline(
            polylineId: const PolylineId('route'),
            points: newRoute,
            width: 4,
            color: Colors.black,
            startCap: Cap.roundCap,
            endCap: Cap.roundCap,
            jointType: JointType.round,
          ),
        };
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
      if (_etaChipText == 'Arrived at destination' && _distanceChipText.isEmpty) {
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

    final int seconds =
        ((meters / 7.2).round()).clamp(1, 24 * 60 * 60).toInt();
    final etaCore = _formatEta(seconds);
    final distCore = _formatDistance(meters);

    final bool near = meters > 0 && meters <= 400 || seconds <= 120;
    final String etaText;
    if (driverStartedRide) {
      _nearDestination = near;
      etaText = near ? 'Near destination' : (etaCore.isEmpty ? '' : '$etaCore to drop');
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
      if (!driverStartedRide && (meters > 0 && meters <= 120 || seconds <= 60)) {
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

    final title = _isRoutingToDrop || driverStartedRide
        ? 'To destination'
        : 'To pickup';

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

      final vehicle = data['vehicle'] ?? {};

      final String driverId = (data['driverId'] ?? '').toString();
      final String driverFullName = (data['driverName'] ?? '').toString();
      final double rating =
          double.tryParse(data['driverRating']?.toString() ?? '') ?? 0.0;
      final String customerPhone = data['customerPhone'].toString();
      final String color = (vehicle['color'] ?? '').toString();
      final String brand = (vehicle['brand'] ?? '').toString();
      final String model = (vehicle['model'] ?? '').toString();
      final String plate = (vehicle['plateNumber'] ?? '').toString();
      final String profilePic = vehicle['profilePic'] ?? '';
      final double amount =
          (data['amount'] is num) ? (data['amount'] as num).toDouble() : 0.0;
      final String carExteriorPhotos =
          (data['carExteriorPhotos'] ?? '').toString();

      final String driverPhone = (data['driverPhone'] ?? '').toString();
      final String bookingId = (data['bookingId'] ?? '').toString();

      final bool driverAccepted = data['driver_accept_status'] == true;

      // customer pickup/drop
      final customerLoc = data['customerLocation'];
      if (customerLoc != null) {
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
      final driverLoc = data['driverLocation'];
      if (driverLoc != null) {
        final dLat = (driverLoc['latitude'] as num?)?.toDouble();
        final dLng = (driverLoc['longitude'] as num?)?.toDouble();
        if (dLat != null && dLng != null) {
          _driverLatLng = LatLng(dLat, dLng);
          _updateDriverMarker(_driverLatLng!);
          _updateLiveMetrics(_driverLatLng!);
        }
      }

      final hasDriver =
          driverAccepted ||
          driverId.trim().isNotEmpty ||
          _driverLatLng != null;

      setState(() {
        isDriverConfirmed = hasDriver;
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

      // draw DRIVER → PICKUP when accepted
      if (hasDriver &&
          _driverLatLng != null &&
          _customerPickupLatLng != null) {
        final mapState = _mapKey.currentState;
        if (mapState != null) {
          final d = _distanceMeters(_driverLatLng!, _customerPickupLatLng!);
          if (d > 1200) {
            mapState.fitPointsBounds(
              <LatLng>[_driverLatLng!, _customerPickupLatLng!],
              padding: 120,
            );
          } else {
            mapState.animateTo(target: _driverLatLng!, zoom: _currentZoomLevel);
          }
        }
        await _setRouteDriverToPickup();
      }

      if (driverId.trim().isNotEmpty) {
        rideShareSocket.emit('track-driver', {'driverId': driverId.trim()});
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
          // Uber/Ola flow: once ride starts, pickup pin shouldn't dominate the map
          _markers.removeWhere((m) => m.markerId.value == 'pickup');
        }
      });

      if (status) {
        // Now route from PICKUP → DROP
        await _setRoutePickupToDrop();
        final mapState = _mapKey.currentState;
        final driverPos = _driverLatLng;
        if (mapState != null && driverPos != null) {
          _pauseAutoFollowUntil = DateTime.fromMillisecondsSinceEpoch(0);
          mapState.animateTo(target: driverPos, zoom: _currentZoomLevel);
        }
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
              (data['message'] ?? data['reason'] ?? "Trip cancelled").toString();
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
              (data['message'] ?? data['reason'] ?? "Trip cancelled").toString();
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
      AppLogger.log.i("driver-location: $data");

      if (data == null) return;

      final double lat =
          (data['latitude'] as num?)?.toDouble() ??
          widget.pickupPosition.latitude;
      final double lng =
          (data['longitude'] as num?)?.toDouble() ??
          widget.pickupPosition.longitude;
      final double? bearing =
          (data['bearing'] != null)
              ? (data['bearing'] as num).toDouble()
              : null;

      DateTime ts;
      if (data['timestamp'] is int) {
        ts = DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int);
      } else if (data['timestamp'] is String) {
        ts = DateTime.tryParse(data['timestamp'] as String) ?? DateTime.now();
      } else {
        ts = DateTime.now();
      }

      final newPos = LatLng(lat, lng);
      _driverLatLng = newPos;

      // jitter filter
      if (_currentPose != null) {
        final d = _distanceMeters(_currentPose!.position, newPos);
        if (d < 0.8) return;
      }

      // stale filter
      if (DateTime.now().difference(ts).abs() > _maxStale) {
        return;
      }

      final pose = DriverPose(position: newPos, bearing: bearing, t: ts);

      // keep queue ordered by time
      final int idx = _poseQueue.indexWhere((p) => p.t.isAfter(ts));
      if (idx == -1) {
        _poseQueue.add(pose);
      } else {
        _poseQueue.insert(idx, pose);
      }

      // trim queue
      if (_poseQueue.length > _maxQueue) {
        _poseQueue.removeRange(0, _poseQueue.length - _maxQueue);
      }

      // Trim route according to driver progress
      if (_activeRoute.isNotEmpty) {
        _trimRouteForDriver(newPos);

        // OFF-ROUTE DETECTION:
        if (_isOffRoute(newPos)) {
          AppLogger.log.w("🚨 Driver is off route, recalculating...");
          if (_isRoutingToDrop && _customerDropLatLng != null) {
            _requestRoute(newPos, _customerDropLatLng!).then(_setActiveRoute);
          } else if (_isRoutingToPickup && _customerPickupLatLng != null) {
            _requestRoute(newPos, _customerPickupLatLng!).then(_setActiveRoute);
          }
        }
      }

      _startMotionTicker();
    });
  }

  void _startMotionTicker() {
    if (_motionTimer != null && _motionTimer!.isActive) return;

    _motionTimer = Timer.periodic(_motionStep, (timer) {
      if (_poseQueue.isEmpty) {
        timer.cancel();
        return;
      }

      final now = DateTime.now().subtract(_visualDelay);

      _currentPose ??= _poseQueue.first;

      while (_poseQueue.length >= 2 && _poseQueue[1].t.isBefore(now)) {
        _currentPose = _poseQueue.removeAt(0);
      }

      if (_poseQueue.isEmpty) {
        _updateDriverMarker(
          _currentPose!.position,
          bearing: _currentPose!.bearing,
        );
        _autoCameraUpdate(_currentPose!.position);
        _updateLiveMetrics(_currentPose!.position);
        return;
      }

      final nextPose = _poseQueue.first;

      final int totalMs = nextPose.t.difference(_currentPose!.t).inMilliseconds;
      if (totalMs <= 0) {
        _updateDriverMarker(nextPose.position, bearing: nextPose.bearing);
        _autoCameraUpdate(nextPose.position);
        _updateLiveMetrics(nextPose.position);
        _currentPose = nextPose;
        _poseQueue.removeAt(0);
        return;
      }

      final int elapsedMs = now.difference(_currentPose!.t).inMilliseconds;
      double t = elapsedMs / totalMs;
      t = t.clamp(0.0, 1.0);

      final double interpLat = _lerp(
        _currentPose!.position.latitude,
        nextPose.position.latitude,
        t,
      );
      final double interpLng = _lerp(
        _currentPose!.position.longitude,
        nextPose.position.longitude,
        t,
      );

      final LatLng interpPos = LatLng(interpLat, interpLng);

      // smooth bearing based on movement direction (left / right / U-turns)
      final double bearing = _computeBearing(_currentPose!.position, interpPos);

      _updateDriverMarker(interpPos, bearing: bearing);
      _autoCameraUpdate(interpPos);
      _updateLiveMetrics(interpPos);
    });
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

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

  double _computeBearing(LatLng from, LatLng to) {
    final double lat1 = _deg2rad(from.latitude);
    final double lat2 = _deg2rad(to.latitude);
    final double dLon = _deg2rad(to.longitude - from.longitude);

    final double y = math.sin(dLon) * math.cos(lat2);
    final double x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final double brng = math.atan2(y, x);
    return (brng * 180.0 / math.pi + 360.0) % 360.0;
  }

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

  // ---------- UI HELPERS ----------
  Widget _buildProgressBar() {
    return AnimatedBuilder(
      animation: _progressAnimation,
      builder: (context, child) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            children: [
              Container(height: 6, color: Colors.green.withOpacity(0.15)),
              FractionallySizedBox(
                widthFactor: _progressAnimation.value,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[
                        Colors.green.shade400,
                        Colors.green.shade700,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
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
                    completed || active ? Colors.black : const Color(0xFFD0D5DD);
                return Row(
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: completed || active ? Colors.black : Colors.white,
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
                              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
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
                  child: SharedMap(
                    key: _mapKey,
                    initialPosition: widget.initialPosition,
                    pickupPosition: driverStartedRide ? null : _customerPickupLatLng,
                    markers: _markers,
                    polylines: _polylines,
                    myLocationEnabled: false,
                    fitToBounds: false,
                    initialZoom: _currentZoomLevel,
                    minMaxZoomPreference: const MinMaxZoomPreference(11.0, 17.0),
                    compassEnabled: true,
                    rotateGesturesEnabled: false,
                    tiltGesturesEnabled: false,
                  onCameraMove:
                      (pos) =>
                          _currentZoomLevel =
                              pos.zoom.clamp(11.0, 17.0).toDouble(),
                   onCameraMoveStarted: _onUserMapGesture,
                   onTap: (_) => _onUserMapGesture(),
                   gestureRecognizers: {
                     Factory<OneSequenceGestureRecognizer>(
                        () => EagerGestureRecognizer(),
                    ),
                  },
                ),
              ),

              if (isDriverConfirmed && _etaChipText.isNotEmpty)
                Positioned(
                  top: 102,
                  left: 16,
                  right: 88,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      onTap: _showEtaDistanceSheet,
                      borderRadius: BorderRadius.circular(22),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.schedule_rounded,
                              size: 18,
                              color: Colors.black,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _etaChipText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (_distanceChipText.isNotEmpty) ...[
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Text(
                                  _distanceChipText,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(width: 10),
                            const Icon(
                              Icons.info_outline_rounded,
                              size: 18,
                              color: Colors.black54,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              if (isDriverConfirmed)
                Positioned(
                  top: 350,
                  right: 10,
                  child: SafeArea(
                    child: GestureDetector(
                      onTap: _followDriverNow,
                      onLongPress: () {
                        final mapState = _mapKey.currentState;
                        if (mapState == null) return;

                        final driverPos = _driverLatLng;
                        final target = driverStartedRide
                            ? _customerDropLatLng
                            : _customerPickupLatLng;

                        if (driverPos != null && target != null) {
                          _pauseAutoFollowUntil =
                              DateTime.now().add(const Duration(seconds: 4));
                          mapState.fitPointsBounds(
                            <LatLng>[driverPos, target],
                            padding: 120,
                          );
                        }
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
                        child: const Icon(
                          Icons.my_location,
                          size: 22,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ),

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

                      final Uri telUri = Uri(scheme: 'tel', path: normalized);
                      final ok = await launchUrl(
                        telUri,
                        mode: LaunchMode.externalApplication,
                      );

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
          placeholder: (context, url) => const Center(
            child: SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          errorWidget: (context, url, error) => Container(
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
                                        var rawNumber = CUSTOMERPHONE.trim();
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

                                        final Uri telUri = Uri(
                                          scheme: 'tel',
                                          path: normalized,
                                        );

                                        final ok = await launchUrl(
                                          telUri,
                                          mode: LaunchMode.externalApplication,
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
                                            onTap:
                                                canCancel
                                                    ? () {
                                                      AppButtons
                                                          .showCancelRideBottomSheet(
                                                            context,
                                                            onConfirmCancel: (
                                                              String
                                                              selectedReason,
                                                            ) {
                                                              return _handleCancelRide(
                                                                selectedReason,
                                                              );
                                                            },
                                                          );
                                                    }
                                                    : null,
                                            text:
                                                isCancelling
                                                    ? 'Cancelling...'
                                                    : 'Cancel Ride',
                                            fontWeight: FontWeight.w500,
                                            colors:
                                                canCancel
                                                    ? AppColors.cancelRideColor
                                                    : AppColors
                                                        .cancelRideColor
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
    return Column(
      children: [
        const Text(
          'Looking for the best drivers for you',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          borderRadius: BorderRadius.circular(10),
          minHeight: 7,
          backgroundColor: AppColors.linearIndicatorColor.withOpacity(0.2),
          color: AppColors.linearIndicatorColor,
        ),
        const SizedBox(height: 20),
        Image.asset(
          AppImages.confirmCar,
          height: 100,
          width: 100,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 20),
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

            // disable while loading
            onTap:
                    loading
                        ? null
                        : () {
                           AppButtons.showCancelRideBottomSheet(
                             context,
                             onConfirmCancel: (String selectedReason) {
                              return _handleCancelRide(selectedReason);
                             },
                           );
                         },
            isLoading: driverSearchController.isCancelLoading.value,
            // show loader instead of text
            text: 'Cancel Ride',
          );
        }),
        // AppButtons.button(
        //   hasBorder: true,
        //   borderColor: AppColors.commonBlack.withOpacity(0.2),
        //   buttonColor: AppColors.commonWhite,
        //   textColor: AppColors.cancelRideColor,
        //   onTap: () {
        //     AppButtons.showCancelRideBottomSheet(
        //       context,
        //       onConfirmCancel: (String selectedReason) {
        //         driverSearchController.cancelRide(
        //           bookingId:
        //               shareRideController.sharedBooking.value!.bookingId
        //                   .toString() ??
        //               '',
        //           selectedReason: selectedReason,
        //           context: context,
        //         );
        //       },
        //     );
        //   },
        //   text: 'Cancel Ride',
        // ),
      ],
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
            "We couldn’t find any available drivers nearby.\nPlease try again in a few minutes",
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
              final allData = driverSearchController.carBooking.value;
              String? result = await driverSearchController.sendDriverRequest(
                carType: widget.carType,
                pickupLatitude: allData?.fromLatitude ?? 0.0,
                pickupLongitude: allData?.fromLongitude ?? 0.0,
                dropLatitude: allData?.toLatitude ?? 0.0,
                dropLongitude: allData?.toLongitude ?? 0.0,
                bookingId: allData?.bookingId.toString() ?? '',
                context: context,
              );
              if (result != null) {
                startDriverSearch();
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
 

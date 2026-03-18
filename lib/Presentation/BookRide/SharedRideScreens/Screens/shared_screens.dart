import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
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
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

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
  bool _isPickupFocused = true;

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
  String cancelReason = "";

  // ---------- POSITIONS ----------
  LatLng? _customerPickupLatLng;
  LatLng? _customerDropLatLng;
  LatLng? _driverLatLng; // last known driver position

  // ---------- ROUTE / POLYLINE STATE ----------
  /// Current active route (either driver→pickup OR pickup→drop)
  List<LatLng> _activeRoute = <LatLng>[];

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
    int width = 42,
  }) async {
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List();

    final codec = await ui.instantiateImageCodec(bytes, targetWidth: width);
    final frame = await codec.getNextFrame();
    final resizedBytes =
        (await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();

    return BitmapDescriptor.fromBytes(resizedBytes);
  }

  Future<void> _loadMarkerIcons() async {
    _pickupIcon = await _bitmapFromAsset(AppImages.circleStart, width: 38);
    _dropIcon = await _bitmapFromAsset(AppImages.rectangleDest, width: 38);
    _driverIcon = await _bitmapFromAsset(AppImages.confirmCar, width: 46);

    _initRouteAndMarkers();
    if (!mounted) return;
    setState(() {});
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
          width: 5,
          color: Colors.white,
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
          width: 5,
          color: Colors.white,
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
          anchor: const Offset(0.5, 0.5),
          rotation: bearing ?? 0,
        ),
      );
    });
  }

  // ---------- ROUTE MANAGEMENT ----------

  /// Replace active route and polyline, and fit bounds once.
  void _setActiveRoute(List<LatLng> points) {
    if (!mounted || points.isEmpty) return;
    setState(() {
      _activeRoute = points;
      _polylines = {
        Polyline(
          polylineId: const PolylineId('route'),
          points: points,
          width: 5,
          color: Colors.black,
        ),
      };
    });
    _mapKey.currentState?.fitRouteBounds();
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

      final String encoded = routes[0]['overview_polyline']['points'] as String;
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
    if (_customerPickupLatLng == null || _customerDropLatLng == null) return;
    _isRoutingToPickup = false;
    _isRoutingToDrop = true;

    final pts = await _requestRoute(
      _customerPickupLatLng!,
      _customerDropLatLng!,
    );
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
        _polylines = {
          Polyline(
            polylineId: const PolylineId('route'),
            points: newRoute,
            width: 5,
            color: Colors.black,
          ),
        };
      });
    }
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
    // ensure this specific socket uses sharedBaseUrl
    rideShareSocket.initSocket(ApiConsents.sharedBaseUrl);

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
        }
      }

      setState(() {
        isDriverConfirmed = driverAccepted;
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
      if (driverAccepted &&
          _driverLatLng != null &&
          _customerPickupLatLng != null) {
        await _setRouteDriverToPickup();
      }

      if (driverId.trim().isNotEmpty) {
        rideShareSocket.emit('track-driver', {'driverId': driverId.trim()});
      }
    });

    // OTP generated
    rideShareSocket.on('otp-generated', (data) {
      if (!mounted) return;
      final otpGenerated = data['otpCode'].toString();
      setState(() {
        otp = otpGenerated;
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
      });

      if (status) {
        // Now route from PICKUP → DROP
        await _setRoutePickupToDrop();
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
        });
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
    });

    rideShareSocket.on('customer-cancelled', (data) async {
      AppLogger.log.i('customer-cancelled : $data');
      if (data != null && data['status'] == true) {
        if (!mounted) return;
        setState(() {
          isTripCancelled = true;
          cancelReason =
              data['reason'] ?? "Driver had to cancel due to an emergency";
        });
        await Future.delayed(const Duration(seconds: 3));
        if (!mounted) return;
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
        return;
      }

      final nextPose = _poseQueue.first;

      final int totalMs = nextPose.t.difference(_currentPose!.t).inMilliseconds;
      if (totalMs <= 0) {
        _updateDriverMarker(nextPose.position, bearing: nextPose.bearing);
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
                  pickupPosition: widget.pickupPosition,
                  markers: _markers,
                  polylines: _polylines,
                  myLocationEnabled: true,
                  fitToBounds: true,
                ),
              ),

              Positioned(
                top: 350,
                right: 10,
                child: SafeArea(
                  child: GestureDetector(
                    onTap: () {
                      final mapState = _mapKey.currentState;
                      if (mapState == null) return;

                      if (_isPickupFocused) {
                        mapState.focusPickup();
                      } else {
                        mapState.fitRouteBounds();
                      }

                      setState(() => _isPickupFocused = !_isPickupFocused);
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
                        _isPickupFocused
                            ? Icons.my_location
                            : Icons.crop_square_rounded,
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
                                children: const [
                                  Icon(Icons.cancel, color: Colors.red),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "Your trip has been cancelled",
                                          style: TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
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

                          const SizedBox(height: 12),
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
                                      imageUrl: CarExteriorPhotos,
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
                                      CustomTextFields.textWithImage(
                                        onTap:
                                            otp.isNotEmpty
                                                ? null
                                                : () {
                                                  AppButtons.showCancelRideBottomSheet(
                                                    context,
                                                    onConfirmCancel: (
                                                      String selectedReason,
                                                    ) {
                                                      driverSearchController
                                                          .cancelRide(
                                                            bookingId:
                                                                shareRideController
                                                                    .sharedBooking
                                                                    .value
                                                                    ?.bookingId
                                                                    .toString() ??
                                                                '',
                                                            selectedReason:
                                                                selectedReason,
                                                            context: context,
                                                          );
                                                    },
                                                  );
                                                },
                                        text:
                                            otp.isNotEmpty
                                                ? 'Ratings'
                                                : ' Cancel Ride',
                                        fontWeight: FontWeight.w500,
                                        colors: AppColors.cancelRideColor,
                                        imagePath:
                                            otp.isNotEmpty
                                                ? null
                                                : AppImages.cancel,
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
                                          AppLogger.log.w('yes iam clicked');
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder:
                                                  (context) => PaymentScreen(
                                                    bookingId: bookingId,
                                                    amount: 15000,
                                                  ),
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
                                        imagePath: AppImages.support,
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
          final loading = driverSearchController.isLoading.value;

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
                          driverSearchController.cancelRide(
                            bookingId:
                                shareRideController
                                    .sharedBooking
                                    .value!
                                    .bookingId
                                    .toString() ??
                                '',
                            selectedReason: selectedReason,
                            context: context,
                          );
                        },
                      );
                    },
            isLoading: driverSearchController.isLoading.value,
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

/*class DriverPose {
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
  final String? bookingFee;
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
  bool _isPickupFocused = true;

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
  String cancelReason = "";

  // ---------- POSITIONS ----------
  LatLng? _customerPickupLatLng;
  LatLng? _customerDropLatLng;
  LatLng? _driverLatLng; // last known driver position

  // ---------- ROUTE / POLYLINE STATE ----------
  /// Current active route (either driver→pickup OR pickup→drop)
  List<LatLng> _activeRoute = <LatLng>[];

  /// Are we routing driver → pickup (before ride-started)?
  bool _isRoutingToPickup = false;

  /// Are we routing pickup → drop (after ride-started)?
  bool _isRoutingToDrop = false;

  // ---------- SMOOTH MOTION STATE ----------
  DriverPose? _currentPose;
  final List<DriverPose> _poseQueue = <DriverPose>[];
  Timer? _motionTimer;

  final Duration _maxStale = const Duration(seconds: 6);
  final int _maxQueue = 24;
  final Duration _motionStep = const Duration(milliseconds: 60);
  final Duration _visualDelay = const Duration(milliseconds: 700);

  // ---------- WAITING TIMER ----------
  void startDriverSearch() {
    isWaitingForDriver = true;
    noDriverFound = false;

    Future.delayed(const Duration(seconds: 40), () async {
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
    int width = 42,
  }) async {
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List();

    final codec = await ui.instantiateImageCodec(bytes, targetWidth: width);
    final frame = await codec.getNextFrame();
    final resizedBytes =
        (await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();

    return BitmapDescriptor.fromBytes(resizedBytes);
  }

  Future<void> _loadMarkerIcons() async {
    _pickupIcon = await _bitmapFromAsset(AppImages.circleStart, width: 38);
    _dropIcon = await _bitmapFromAsset(AppImages.rectangleDest, width: 38);
    _driverIcon = await _bitmapFromAsset(AppImages.confirmCar, width: 46);

    _initRouteAndMarkers();
    if (!mounted) return;
    setState(() {});
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
          width: 5,
          color: Colors.white,
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
          width: 5,
          color: Colors.white,
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
          anchor: const Offset(0.5, 0.5),
          rotation: bearing ?? 0,
        ),
      );
    });
  }

  // ---------- ROUTE MANAGEMENT ----------

  /// Replace active route and polyline, and fit bounds once.
  void _setActiveRoute(List<LatLng> points) {
    if (!mounted || points.isEmpty) return;
    setState(() {
      _activeRoute = points;
      _polylines = {
        Polyline(
          polylineId: const PolylineId('route'),
          points: points,
          width: 5,
          color: Colors.white,
        ),
      };
    });
    _mapKey.currentState?.fitRouteBounds();
  }

  /// Request points for route; for now it just returns a straight line.
  /// You can replace this with your backend / Google Directions call that
  /// returns encoded polyline and decode with `_decodePolyline`.
  Future<List<LatLng>> _requestRoute(LatLng from, LatLng to) async {
    // TODO: Integrate your Directions API here and use `_decodePolyline`.
    return <LatLng>[from, to];
  }

  Future<void> _setRouteDriverToPickup() async {
    if (_driverLatLng == null || _customerPickupLatLng == null) return;
    _isRoutingToPickup = true;
    _isRoutingToDrop = false;

    final pts = await _requestRoute(_driverLatLng!, _customerPickupLatLng!);
    _setActiveRoute(pts);
  }

  Future<void> _setRoutePickupToDrop() async {
    if (_customerPickupLatLng == null || _customerDropLatLng == null) return;
    _isRoutingToPickup = false;
    _isRoutingToDrop = true;

    final pts = await _requestRoute(
      _customerPickupLatLng!,
      _customerDropLatLng!,
    );
    _setActiveRoute(pts);
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
        _polylines = {
          Polyline(
            polylineId: const PolylineId('route'),
            points: newRoute,
            width: 5,
            color: Colors.white,
          ),
        };
      });
    }
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
    // ensure this specific socket uses sharedBaseUrl
    rideShareSocket.initSocket(ApiConsents.sharedBaseUrl);

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

      // driver location
      final driverLoc = data['driverLocation'];
      if (driverLoc != null) {
        final dLat = (driverLoc['latitude'] as num?)?.toDouble();
        final dLng = (driverLoc['longitude'] as num?)?.toDouble();
        if (dLat != null && dLng != null) {
          _driverLatLng = LatLng(dLat, dLng);
          _updateDriverMarker(_driverLatLng!);
        }
      }

      setState(() {
        isDriverConfirmed = driverAccepted;
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
      if (driverAccepted &&
          _driverLatLng != null &&
          _customerPickupLatLng != null) {
        await _setRouteDriverToPickup();
      }

      if (driverId.trim().isNotEmpty) {
        rideShareSocket.emit('track-driver', {'driverId': driverId.trim()});
      }
    });

    // OTP generated
    rideShareSocket.on('otp-generated', (data) {
      if (!mounted) return;
      final otpGenerated = data['otpCode'].toString();
      setState(() {
        otp = otpGenerated;
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
      });

      if (status) {
        // Now route from PICKUP → DROP
        await _setRoutePickupToDrop();
      }
    });

    rideShareSocket.on('driver-reached-destination', (data) {
      final String bookingId =
          driverSearchController.carBooking.value!.bookingId;
      final status = data['status'];
      if (status == true) {
        if (!mounted) return;
        setState(() {
          destinationReached = true;
        });
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          Get.to(() => PaymentScreen(bookingId: bookingId, amount: Amount));
        });
        AppLogger.log.i("driver_reached,$data");
      }
    });

    rideShareSocket.on('driver-arrived', (data) {
      AppLogger.log.i("driver-arrived: $data");
    });

    rideShareSocket.on('customer-cancelled', (data) async {
      AppLogger.log.i('customer-cancelled : $data');
      if (data != null && data['status'] == true) {
        if (!mounted) return;
        setState(() {
          isTripCancelled = true;
          cancelReason =
              data['reason'] ?? "Driver had to cancel due to an emergency";
        });
        await Future.delayed(const Duration(seconds: 3));
        if (!mounted) return;
        Get.offAll(() => HomeScreens());
      }
    });

    // SMOOTH driver-location updates
    rideShareSocket.on('driver-location', (data) {
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
        return;
      }

      final nextPose = _poseQueue.first;

      final int totalMs = nextPose.t.difference(_currentPose!.t).inMilliseconds;
      if (totalMs <= 0) {
        _updateDriverMarker(nextPose.position, bearing: nextPose.bearing);
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

  // ---------- BUILD ----------
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
                  pickupPosition: widget.pickupPosition,
                  markers: _markers,
                  polylines: _polylines,
                  myLocationEnabled: true,
                  fitToBounds: true,
                ),
              ),

              // FOCUS / FIT BOUNDS BUTTON
              Positioned(
                top: 350,
                right: 10,
                child: SafeArea(
                  child: GestureDetector(
                    onTap: () {
                      final mapState = _mapKey.currentState;
                      if (mapState == null) return;

                      if (_isPickupFocused) {
                        mapState.focusPickup();
                      } else {
                        mapState.fitRouteBounds();
                      }

                      setState(() => _isPickupFocused = !_isPickupFocused);
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
                        _isPickupFocused
                            ? Icons.my_location
                            : Icons.crop_square_rounded,
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
                        AppToasts.showError('SOS number not set');
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
                        AppToasts.showError('Invalid SOS number');
                        return;
                      }

                      final Uri telUri = Uri(scheme: 'tel', path: normalized);
                      final ok = await launchUrl(
                        telUri,
                        mode: LaunchMode.externalApplication,
                      );

                      if (!ok) {
                        AppToasts.showError('Could not open dialer');
                      }
                    } catch (e) {
                      AppToasts.showError('Failed to start call');
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
                                children: const [
                                  Icon(Icons.cancel, color: Colors.red),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "Your trip has been cancelled",
                                          style: TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
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

                          const SizedBox(height: 12),
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
                                      imageUrl: CarExteriorPhotos,
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
                                          AppToasts.showError('Invalid number');
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
                                            'Could not open dialer',
                                          );
                                        }
                                      } catch (e) {
                                        AppToasts.showError(
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
                                            (context) => ChatScreen(
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
                                      CustomTextFields.textWithImage(
                                        onTap:
                                            otp.isNotEmpty
                                                ? null
                                                : () {
                                                  AppButtons.showCancelRideBottomSheet(
                                                    context,
                                                    onConfirmCancel: (
                                                      String selectedReason,
                                                    ) {
                                                      driverSearchController
                                                          .cancelRide(
                                                            bookingId:
                                                                driverSearchController
                                                                    .carBooking
                                                                    .value!
                                                                    .bookingId,
                                                            selectedReason:
                                                                selectedReason,
                                                            context: context,
                                                          );
                                                    },
                                                  );
                                                },
                                        text:
                                            otp.isNotEmpty
                                                ? 'Ratings'
                                                : ' Cancel Ride',
                                        fontWeight: FontWeight.w500,
                                        colors: AppColors.cancelRideColor,
                                        imagePath:
                                            otp.isNotEmpty
                                                ? null
                                                : AppImages.cancel,
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
                                              driverSearchController
                                                  .carBooking
                                                  .value!
                                                  .bookingId;
                                          final url =
                                              "https://hoppr-admin-e7bebfb9fb05.herokuapp.com/ride-tracker/$bookingId";
                                          Share.share(url);
                                        },
                                        text: 'Share',
                                        fontWeight: FontWeight.w500,
                                        colors: AppColors.cancelRideColor,
                                        imagePath: AppImages.support,
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
        AppButtons.button(
          hasBorder: true,
          borderColor: AppColors.commonBlack.withOpacity(0.2),
          buttonColor: AppColors.commonWhite,
          textColor: AppColors.cancelRideColor,
          onTap: () {
            AppButtons.showCancelRideBottomSheet(
              context,
              onConfirmCancel: (String selectedReason) {
                driverSearchController.cancelRide(
                  bookingId: driverSearchController.carBooking.value!.bookingId,
                  selectedReason: selectedReason,
                  context: context,
                );
              },
            );
          },
          text: 'Cancel Ride',
        ),
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
          SizedBox(height: 15),
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
                side: BorderSide(color: Colors.black),
                padding: EdgeInsets.symmetric(vertical: 16),
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
}*/

// import 'dart:async';
// import 'package:hopper/Presentation/BookRide/SharedRideScreens/Controller/share_ride_controller.dart';
// import 'package:hopper/Presentation/OnBoarding/Screens/chat_screen.dart';
// import 'package:hopper/api/repository/api_consents.dart';
// import 'package:share_plus/share_plus.dart';
// import 'package:cached_network_image/cached_network_image.dart';
// import 'package:get/get.dart';
// import 'package:hopper/Core/Utility/app_buttons.dart';
// import 'package:hopper/Presentation/BookRide/Controllers/driver_search_controller.dart';
// import 'package:hopper/Presentation/OnBoarding/Screens/home_screens.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'dart:math' as math;
// import 'dart:ui' as ui;
//
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:hopper/Core/Consents/app_colors.dart';
// import 'package:hopper/Core/Utility/app_toasts.dart';
// import 'package:hopper/Presentation/Authentication/widgets/textFields.dart';
// import 'package:hopper/uitls/netWorkHandling/network_handling_screen.dart';
// import 'package:url_launcher/url_launcher.dart';
//
// import 'package:hopper/Core/Consents/app_logger.dart';
// import 'package:hopper/Core/Utility/app_images.dart';
// import 'package:hopper/uitls/map/shared_map.dart'; // SharedMap + SharedMapState
// import 'package:hopper/uitls/websocket/shared_web_socket.dart'; // RideShareSocketService
//
// // ---------- SMALL HELPER MODEL FOR SMOOTH ANIMATION ----------
// class DriverPose {
//   final LatLng position;
//   final double? bearing;
//   final DateTime t;
//
//   DriverPose({required this.position, this.bearing, DateTime? t})
//     : t = t ?? DateTime.now();
// }
//
// class SharedScreens extends StatefulWidget {
//   final String pickupAddress;
//   final String destinationAddress;
//   final double? baseFare;
//   final double? serviceFare;
//   final double? distanceFare;
//   final double? pickupFare;
//   final String? bookingFee;
//   final double? timeFare;
//   final String carType;
//   final LatLng initialPosition; // where camera starts
//   final LatLng pickupPosition; // initial pickup
//   final LatLng dropPosition; // initial drop
//
//   /// Optional initial route (decoded polyline)
//   final List<LatLng> routePoints;
//
//   final VoidCallback? onCancel;
//
//   const SharedScreens({
//     super.key,
//     this.baseFare,
//     this.serviceFare,
//     this.distanceFare,
//     this.pickupFare,
//     this.bookingFee,
//     this.timeFare,
//     required this.pickupAddress,
//     required this.destinationAddress,
//     required this.initialPosition,
//     required this.pickupPosition,
//     required this.dropPosition,
//     this.routePoints = const [],
//     this.onCancel,
//     required this.carType,
//   });
//
//   @override
//   State<SharedScreens> createState() => _SharedScreensState();
// }
//
// class _SharedScreensState extends State<SharedScreens>
//     with SingleTickerProviderStateMixin {
//   // ---------- UI ANIMATION (bottom car + progress bar) ----------
//   late final AnimationController _controller;
//   late final Animation<double> _progressAnimation;
//   final TextEditingController _startController = TextEditingController();
//   final TextEditingController _destController = TextEditingController();
//   // ---------- MAP CONTROL ----------
//   final GlobalKey<SharedMapState> _mapKey = GlobalKey<SharedMapState>();
//   bool _isPickupFocused = true;
//
//   BitmapDescriptor? _pickupIcon;
//   BitmapDescriptor? _dropIcon;
//   BitmapDescriptor? _driverIcon;
//   bool isWaitingForDriver = true;
//   bool noDriverFound = false;
//   Set<Marker> _markers = <Marker>{};
//   Set<Polyline> _polylines = <Polyline>{};
//   bool isTripCancelled = false;
//   // ---------- SOCKET + DRIVER STATE ----------
//   final RideShareSocketService rideShareSocket = RideShareSocketService();
//   final DriverSearchController driverSearchController = Get.put(
//     DriverSearchController(),
//   );
//
//   final ShareRideController shareRideController = Get.put(
//     ShareRideController(),
//   );
//   LatLng? _customerPickupLatLng;
//   LatLng? _customerDropLatLng;
//   LatLng? _driverLatLng;
//
//   String _driverName = '';
//   String _carDetails = '';
//   double? _fareAmount;
//   String ProfilePic = '';
//
//   String driverName = '';
//   // extra info from joined-booking
//   bool isDriverConfirmed = false;
//   bool driverStartedRide = false;
//   bool destinationReached = false;
//   String carDetails = '';
//   String otp = '';
//   String plateNumber = '';
//   String CUSTOMERPHONE = '';
//   double Amount = 0.0;
//   String _carImageUrl = '';
//   String _driverProfileUrl = '';
//   String _driverPhone = '';
//   String _bookingId = '';
//   String CarExteriorPhotos = '';
//   bool isExpanded = false;
//   // ---------- SMOOTH MOTION STATE ----------
//   DriverPose? _currentPose; // last rendered
//   final List<DriverPose> _poseQueue = <DriverPose>[]; // ordered by time
//   Timer? _motionTimer;
//   String cancelReason = "";
//   final Duration _maxStale = const Duration(seconds: 6);
//   final int _maxQueue = 24;
//   final Duration _motionStep = const Duration(milliseconds: 60);
//   final Duration _visualDelay = const Duration(milliseconds: 700);
//   void startDriverSearch() {
//     isWaitingForDriver = true;
//     noDriverFound = false;
//
//     Future.delayed(const Duration(seconds: 40), () async {
//       if (!isDriverConfirmed) {
//         bool hasDriver = await driverSearchController.noDriverFound(
//           context: context,
//           bookingId: _bookingId,
//           status: true,
//         );
//
//         if (!mounted) return;
//         setState(() {
//           isWaitingForDriver = false;
//           noDriverFound = !hasDriver;
//         });
//       }
//     });
//   }
//
//   @override
//   void initState() {
//     super.initState();
//
//     _controller = AnimationController(
//       vsync: this,
//       duration: const Duration(seconds: 3),
//     )..repeat(reverse: true);
//
//     _progressAnimation = CurvedAnimation(
//       parent: _controller,
//       curve: Curves.easeInOut,
//     );
//
//     _loadMarkerIcons();
//     _setupSocketListeners();
//   }
//
//   @override
//   void dispose() {
//     _controller.dispose();
//     _motionTimer?.cancel();
//     super.dispose();
//   }
//
//   // ---------- ASSET → BITMAP (resize) ----------
//   Future<BitmapDescriptor> _bitmapFromAsset(
//     String assetPath, {
//     int width = 42,
//   }) async {
//     final data = await rootBundle.load(assetPath);
//     final bytes = data.buffer.asUint8List();
//
//     final codec = await ui.instantiateImageCodec(bytes, targetWidth: width);
//     final frame = await codec.getNextFrame();
//     final resizedBytes =
//         (await frame.image.toByteData(
//           format: ui.ImageByteFormat.png,
//         ))!.buffer.asUint8List();
//
//     return BitmapDescriptor.fromBytes(resizedBytes);
//   }
//
//   Future<void> _loadMarkerIcons() async {
//     _pickupIcon = await _bitmapFromAsset(AppImages.circleStart, width: 38);
//     _dropIcon = await _bitmapFromAsset(AppImages.rectangleDest, width: 38);
//     _driverIcon = await _bitmapFromAsset(AppImages.confirmCar, width: 46);
//
//     _initRouteAndMarkers();
//     if (!mounted) return;
//     setState(() {});
//   }
//
//   // ---------- INITIAL MARKERS + ROUTE ----------
//   void _initRouteAndMarkers() {
//     final pickupMarker = Marker(
//       markerId: const MarkerId('pickup'),
//       position: widget.pickupPosition,
//       icon:
//           _pickupIcon ??
//           BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
//       anchor: const Offset(0.5, 1.0),
//     );
//
//     final dropMarker = Marker(
//       markerId: const MarkerId('drop'),
//       position: widget.dropPosition,
//       icon:
//           _dropIcon ??
//           BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
//       anchor: const Offset(0.5, 1.0),
//     );
//
//     _markers = {pickupMarker, dropMarker};
//
//     if (widget.routePoints.isNotEmpty) {
//       _polylines = {
//         Polyline(
//           polylineId: const PolylineId('route'),
//           points: widget.routePoints,
//           width: 5,
//           color: Colors.white,
//         ),
//       };
//     }
//
//     _customerPickupLatLng = widget.pickupPosition;
//     _customerDropLatLng = widget.dropPosition;
//   }
//
//   // ---------- GENERAL MARKER HELPERS (REUSABLE) ----------
//   void updatePickup(LatLng pos) {
//     _customerPickupLatLng = pos;
//     setState(() {
//       _markers.removeWhere((m) => m.markerId.value == 'pickup');
//       _markers.add(
//         Marker(
//           markerId: const MarkerId('pickup'),
//           position: pos,
//           icon:
//               _pickupIcon ??
//               BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
//           anchor: const Offset(0.5, 1.0),
//         ),
//       );
//     });
//   }
//
//   void updateDrop(LatLng pos) {
//     _customerDropLatLng = pos;
//     setState(() {
//       _markers.removeWhere((m) => m.markerId.value == 'drop');
//       _markers.add(
//         Marker(
//           markerId: const MarkerId('drop'),
//           position: pos,
//           icon:
//               _dropIcon ??
//               BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
//           anchor: const Offset(0.5, 1.0),
//         ),
//       );
//     });
//   }
//
//   void updateRoute(List<LatLng> points) {
//     setState(() {
//       _polylines = {
//         Polyline(
//           polylineId: const PolylineId('route'),
//           points: points,
//           width: 5,
//           color: Colors.white,
//         ),
//       };
//     });
//   }
//
//   void _updateDriverMarker(LatLng pos, {double? bearing}) {
//     setState(() {
//       _markers.removeWhere((m) => m.markerId.value == 'driver');
//       _markers.add(
//         Marker(
//           markerId: const MarkerId('driver'),
//           position: pos,
//           icon:
//               _driverIcon ??
//               BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
//           anchor: const Offset(0.5, 0.5),
//           rotation: bearing ?? 0,
//         ),
//       );
//     });
//   }
//
//   // ---------- SOCKET LISTENERS ----------
//   void _setupSocketListeners() {
//     rideShareSocket.initSocket(
//       ApiConsents.sharedBaseUrl,
//     ); // if you have such method
//     rideShareSocket.on('connect', (_) {
//       if (!mounted) return;
//       AppLogger.log.i("✅ Shared socket connected on shared screen");
//     });
//
//
//     rideShareSocket.on('joined-booking', (data) {
//       if (!mounted || data == null) return;
//       AppLogger.log.i("🚕 joined-booking: $data");
//
//       final vehicle = data['vehicle'] ?? {};
//
//       final String driverId = (data['driverId'] ?? '').toString();
//       final String driverFullName = (data['driverName'] ?? '').toString();
//       final double rating =
//           double.tryParse(data['driverRating']?.toString() ?? '') ?? 0.0;
//       final String customerPhone = data['customerPhone'].toString();
//       final String color = (vehicle['color'] ?? '').toString();
//       final String brand = (vehicle['brand'] ?? '').toString();
//       final String model = (vehicle['model'] ?? '').toString();
//       final String plate = (vehicle['plateNumber'] ?? '').toString();
//       final String profilePic = vehicle['profilePic'] ?? '';
//       final double amount =
//           (data['amount'] is num) ? (data['amount'] as num).toDouble() : 0.0;
//
//       final String carExteriorPhotos =
//           (data['carExteriorPhotos'] ?? '').toString();
//
//       final String driverPhone = (data['driverPhone'] ?? '').toString();
//       final String bookingId = (data['bookingId'] ?? '').toString();
//
//       // driver accepted?
//       final bool driverAccepted = data['driver_accept_status'] == true;
//
//       final customerLoc = data['customerLocation'];
//       if (customerLoc != null) {
//         final fromLat =
//             (customerLoc['fromLatitude'] as num?)?.toDouble() ?? 0.0;
//         final fromLng =
//             (customerLoc['fromLongitude'] as num?)?.toDouble() ?? 0.0;
//         final toLat = (customerLoc['toLatitude'] as num?)?.toDouble() ?? 0.0;
//         final toLng = (customerLoc['toLongitude'] as num?)?.toDouble() ?? 0.0;
//
//         updatePickup(LatLng(fromLat, fromLng));
//         updateDrop(LatLng(toLat, toLng));
//       }
//
//       setState(() {
//         isDriverConfirmed = driverAccepted;
//         // carDetails = '$color - $brand';
//         driverName =
//             rating > 0
//                 ? '$driverFullName  ⭐ ${rating.toStringAsFixed(2)}'
//                 : driverFullName;
//         CUSTOMERPHONE = customerPhone;
//         carDetails = <String>[
//           color,
//           brand,
//           model,
//         ].where((x) => x.trim().isNotEmpty).join(' · ');
//
//         Amount = amount;
//
//         plateNumber = plate;
//         CarExteriorPhotos = carExteriorPhotos;
//         ProfilePic = profilePic;
//         _driverPhone = driverPhone;
//         _bookingId = bookingId;
//       });
//
//       if (driverId.trim().isNotEmpty) {
//         rideShareSocket.emit('track-driver', {'driverId': driverId.trim()});
//       }
//     });
//     rideShareSocket.on('otp-generated', (data) {
//       if (!mounted) return;
//       final otpGenerated = data['otpCode'].toString();
//       setState(() {
//         otp = otpGenerated;
//       });
//       AppLogger.log.i("otp-generated: $data");
//     });
//     rideShareSocket.on('ride-started', (data) {
//       final bool status = data['status'] == true;
//       AppLogger.log.i("ride-started: $data");
//
//       driverStartedRide = status;
//       if (!mounted) return;
//       setState(() {});
//
//       if (status &&
//           _currentDriverLatLng != null &&
//           _customerToLatLang != null) {
//         final dropMarker = Marker(
//           markerId: const MarkerId("drop_marker"),
//           position: _customerToLatLang!,
//           icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
//           infoWindow: const InfoWindow(title: "Destination"),
//         );
//
//         setState(() {
//           _markers = {if (_driverMarker != null) _driverMarker!, dropMarker};
//         });
//
//         _drawPolylineFromDriverToCustomer(
//           driverLatLng: _currentDriverLatLng!,
//           customerLatLng: _customerToLatLang!,
//         );
//       }
//     });
//     rideShareSocket.on('driver-reached-destination', (data) {
//       final String bookingId =
//           driverSearchController.carBooking.value!.bookingId;
//       final status = data['status'];
//       if (status == true) {
//         if (!mounted) return;
//         setState(() {
//           destinationReached = true;
//         });
//         Future.delayed(const Duration(seconds: 2), () {
//           if (!mounted) return;
//           Get.to(() => PaymentScreen(bookingId: bookingId, amount: Amount));
//         });
//         AppLogger.log.i("driver_reached,$data");
//       }
//     });
//     rideShareSocket.on('driver-arrived', (data) {
//       AppLogger.log.i("driver-arrived: $data");
//     });
//     rideShareSocket.on('customer-cancelled', (data) async {
//       AppLogger.log.i('customer-cancelled : $data');
//       if (data != null && data['status'] == true) {
//         if (!mounted) return;
//         setState(() {
//           isTripCancelled = true;
//           cancelReason =
//               data['reason'] ?? "Driver had to cancel due to an emergency";
//         });
//         await Future.delayed(const Duration(seconds: 3));
//         if (!mounted) return;
//         Get.offAll(() => HomeScreens());
//       }
//     });
//     // TODO later:
//     // rideShareSocket.on('ride-started', (_) => setState(() => driverStartedRide = true));
//     // rideShareSocket.on('ride-completed', (_) => setState(() { driverStartedRide = false; destinationReached = true; }));
//
//     // SMOOTH driver-location updates
//     rideShareSocket.on('driver-location', (data) {
//       AppLogger.log.i("driver-location: $data");
//
//       if (data == null) return;
//
//       final double lat =
//           (data['latitude'] as num?)?.toDouble() ??
//           widget.pickupPosition.latitude;
//       final double lng =
//           (data['longitude'] as num?)?.toDouble() ??
//           widget.pickupPosition.longitude;
//       final double? bearing =
//           (data['bearing'] != null)
//               ? (data['bearing'] as num).toDouble()
//               : null;
//
//       DateTime ts;
//       if (data['timestamp'] is int) {
//         ts = DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int);
//       } else if (data['timestamp'] is String) {
//         ts = DateTime.tryParse(data['timestamp'] as String) ?? DateTime.now();
//       } else {
//         ts = DateTime.now();
//       }
//
//       final newPos = LatLng(lat, lng);
//
//       // jitter filter
//       if (_currentPose != null) {
//         final d = _distanceMeters(_currentPose!.position, newPos);
//         if (d < 0.8) return;
//       }
//
//       // stale filter
//       if (DateTime.now().difference(ts).abs() > _maxStale) {
//         return;
//       }
//
//       final pose = DriverPose(position: newPos, bearing: bearing, t: ts);
//
//       // keep queue ordered by time
//       final int idx = _poseQueue.indexWhere((p) => p.t.isAfter(ts));
//       if (idx == -1) {
//         _poseQueue.add(pose);
//       } else {
//         _poseQueue.insert(idx, pose);
//       }
//
//       // trim queue
//       if (_poseQueue.length > _maxQueue) {
//         _poseQueue.removeRange(0, _poseQueue.length - _maxQueue);
//       }
//
//       // each new driver position → recompute route (shortest path)
//       if (_customerDropLatLng != null) {
//         _updateRouteForDriver(newPos, _customerDropLatLng!);
//       }
//
//       _startMotionTicker();
//     });
//   }
//
//   void _startMotionTicker() {
//     if (_motionTimer != null && _motionTimer!.isActive) return;
//
//     _motionTimer = Timer.periodic(_motionStep, (timer) {
//       if (_poseQueue.isEmpty) {
//         timer.cancel();
//         return;
//       }
//
//       final now = DateTime.now().subtract(_visualDelay);
//
//       _currentPose ??= _poseQueue.first;
//
//       while (_poseQueue.length >= 2 && _poseQueue[1].t.isBefore(now)) {
//         _currentPose = _poseQueue.removeAt(0);
//       }
//
//       if (_poseQueue.isEmpty) {
//         _updateDriverMarker(
//           _currentPose!.position,
//           bearing: _currentPose!.bearing,
//         );
//         return;
//       }
//
//       final nextPose = _poseQueue.first;
//
//       final int totalMs = nextPose.t.difference(_currentPose!.t).inMilliseconds;
//       if (totalMs <= 0) {
//         _updateDriverMarker(nextPose.position, bearing: nextPose.bearing);
//         _currentPose = nextPose;
//         _poseQueue.removeAt(0);
//         return;
//       }
//
//       final int elapsedMs = now.difference(_currentPose!.t).inMilliseconds;
//       double t = elapsedMs / totalMs;
//       t = t.clamp(0.0, 1.0);
//
//       final double interpLat = _lerp(
//         _currentPose!.position.latitude,
//         nextPose.position.latitude,
//         t,
//       );
//       final double interpLng = _lerp(
//         _currentPose!.position.longitude,
//         nextPose.position.longitude,
//         t,
//       );
//
//       final double bearing = nextPose.bearing ?? _currentPose!.bearing ?? 0.0;
//
//       _updateDriverMarker(LatLng(interpLat, interpLng), bearing: bearing);
//     });
//   }
//
//   double _lerp(double a, double b, double t) => a + (b - a) * t;
//
//   double _distanceMeters(LatLng a, LatLng b) {
//     const double R = 6371000.0;
//     final double dLat = _deg2rad(b.latitude - a.latitude);
//     final double dLng = _deg2rad(b.longitude - a.longitude);
//     final double la1 = _deg2rad(a.latitude);
//     final double la2 = _deg2rad(b.latitude);
//
//     final double h =
//         math.sin(dLat / 2) * math.sin(dLat / 2) +
//         math.cos(la1) * math.cos(la2) * math.sin(dLng / 2) * math.sin(dLng / 2);
//     final double c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
//     return R * c;
//   }
//
//   double _deg2rad(double d) => d * math.pi / 180.0;
//
//   Future<void> _updateRouteForDriver(LatLng from, LatLng to) async {
//     // TODO: call Directions API instead of straight-line
//     updateRoute(<LatLng>[from, to]);
//
//     final map = _mapKey.currentState;
//     map?.fitRouteBounds();
//   }
//
//   // ---------- UI HELPERS ----------
//   Widget _buildProgressBar() {
//     return AnimatedBuilder(
//       animation: _progressAnimation,
//       builder: (context, child) {
//         return ClipRRect(
//           borderRadius: BorderRadius.circular(4),
//           child: Stack(
//             children: [
//               Container(height: 6, color: Colors.green.withOpacity(0.15)),
//               FractionallySizedBox(
//                 widthFactor: _progressAnimation.value,
//                 child: Container(
//                   height: 6,
//                   decoration: BoxDecoration(
//                     gradient: LinearGradient(
//                       colors: <Color>[
//                         Colors.green.shade400,
//                         Colors.green.shade700,
//                       ],
//                     ),
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         );
//       },
//     );
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final media = MediaQuery.of(context);
//
//     _startController.text = widget.pickupAddress;
//     _destController.text = widget.destinationAddress;
//     return NoInternetOverlay(
//       child: WillPopScope(
//         onWillPop: () async => false,
//         child: Scaffold(
//           backgroundColor: Colors.white,
//           body: Stack(
//             children: [
//               SizedBox(
//                 height: 550,
//                 width: double.infinity,
//                 child: SharedMap(
//                   key: _mapKey,
//                   initialPosition: widget.initialPosition,
//                   pickupPosition: widget.pickupPosition,
//                   markers: _markers,
//                   polylines: _polylines,
//                   myLocationEnabled: true,
//                   fitToBounds: true,
//                 ),
//               ),
//               // FOCUS / FIT BOUNDS BUTTON (above initial sheet height)
//               Positioned(
//                 top: 350,
//                 right: 10,
//                 child: SafeArea(
//                   child: GestureDetector(
//                     onTap: () {
//                       final mapState = _mapKey.currentState;
//                       if (mapState == null) return;
//
//                       if (_isPickupFocused) {
//                         mapState.focusPickup();
//                       } else {
//                         mapState.fitRouteBounds();
//                       }
//
//                       setState(() => _isPickupFocused = !_isPickupFocused);
//                     },
//                     child: Container(
//                       height: 42,
//                       width: 42,
//                       decoration: BoxDecoration(
//                         color: Colors.white,
//                         borderRadius: BorderRadius.circular(10),
//                         boxShadow: const [
//                           BoxShadow(
//                             color: Colors.black12,
//                             blurRadius: 8,
//                             offset: Offset(0, 3),
//                           ),
//                         ],
//                         border: Border.all(
//                           color: Colors.black.withOpacity(0.05),
//                         ),
//                       ),
//                       child: Icon(
//                         _isPickupFocused
//                             ? Icons.my_location
//                             : Icons.crop_square_rounded,
//                         size: 22,
//                         color: Colors.black87,
//                       ),
//                     ),
//                   ),
//                 ),
//               ),
//
//               Positioned(
//                 top: 50,
//                 right: 15,
//                 child: GestureDetector(
//                   onTap: () async {
//                     try {
//                       final prefs = await SharedPreferences.getInstance();
//                       String? sosNumber = prefs.getString('sosNumber');
//
//                       if (sosNumber == null || sosNumber.trim().isEmpty) {
//                         AppToasts.showError('SOS number not set');
//                         return;
//                       }
//
//                       sosNumber = sosNumber.trim();
//                       final hasPlus = sosNumber.startsWith('+');
//                       final digitsOnly = sosNumber.replaceAll(
//                         RegExp(r'[^0-9]'),
//                         '',
//                       );
//                       final normalized = hasPlus ? '+$digitsOnly' : digitsOnly;
//
//                       if (normalized.isEmpty) {
//                         AppToasts.showError('Invalid SOS number');
//                         return;
//                       }
//
//                       final Uri telUri = Uri(scheme: 'tel', path: normalized);
//
//                       // Try opening the dialer
//                       final ok = await launchUrl(
//                         telUri,
//                         mode:
//                             LaunchMode.externalApplication, // opens dialer app
//                       );
//
//                       if (!ok) {
//                         AppToasts.showError('Could not open dialer');
//                       }
//                     } catch (e) {
//                       AppToasts.showError('Failed to start call');
//                     }
//                   },
//                   child: Container(
//                     padding: EdgeInsets.symmetric(horizontal: 10, vertical: 2),
//                     decoration: BoxDecoration(
//                       borderRadius: BorderRadius.circular(15),
//                       color: AppColors.emergencyColor,
//                     ),
//                     child: CustomTextFields.textWithStyles600(
//                       'Emergency',
//                       color: AppColors.commonWhite,
//                       fontSize: 16,
//                     ),
//                   ),
//                 ),
//               ),
//
//               DraggableScrollableSheet(
//                 key: ValueKey(isDriverConfirmed),
//                 initialChildSize: isDriverConfirmed ? 0.65 : 0.5,
//                 minChildSize: 0.4,
//                 maxChildSize: isDriverConfirmed ? 0.9 : 0.80,
//                 builder: (context, scrollController) {
//                   return Container(
//                     padding: EdgeInsets.symmetric(horizontal: 15),
//                     decoration: const BoxDecoration(
//                       color: Colors.white,
//                       borderRadius: BorderRadius.vertical(
//                         top: Radius.circular(26),
//                       ),
//                       boxShadow: [
//                         BoxShadow(
//                           color: Colors.black12,
//                           offset: Offset(0, -4),
//                           blurRadius: 18,
//                         ),
//                       ],
//                     ),
//                     child: ListView(
//                       controller: scrollController,
//                       physics: const BouncingScrollPhysics(),
//                       children: [
//                         Center(
//                           child: Container(
//                             width: 40,
//                             height: 4,
//                             decoration: BoxDecoration(
//                               color: Colors.black12,
//                               borderRadius: BorderRadius.circular(2),
//                             ),
//                           ),
//                         ),
//                         const SizedBox(height: 16),
//                         if (!isDriverConfirmed && isWaitingForDriver) ...[
//                           waitingForDriverUI(),
//                         ] else if (!isDriverConfirmed && noDriverFound) ...[
//                           noDriverFoundUI(),
//                         ] else ...[
//                           if (isTripCancelled)
//                             Container(
//                               padding: const EdgeInsets.all(10),
//                               margin: const EdgeInsets.all(8),
//                               decoration: BoxDecoration(
//                                 color: Colors.red.shade50,
//                                 borderRadius: BorderRadius.circular(8),
//                                 border: Border.all(color: Colors.red.shade200),
//                               ),
//                               child: Row(
//                                 children: [
//                                   const Icon(Icons.cancel, color: Colors.red),
//                                   const SizedBox(width: 8),
//                                   const Expanded(
//                                     child: Column(
//                                       crossAxisAlignment:
//                                           CrossAxisAlignment.start,
//                                       children: [
//                                         Text(
//                                           "Your trip has been cancelled",
//                                           style: TextStyle(
//                                             color: Colors.red,
//                                             fontWeight: FontWeight.bold,
//                                           ),
//                                         ),
//                                       ],
//                                     ),
//                                   ),
//                                 ],
//                               ),
//                             )
//                           else
//                             Center(
//                               child: CustomTextFields.textWithImage(
//                                 fontSize: 20,
//                                 imageSize: 24,
//                                 fontWeight: FontWeight.w600,
//                                 text:
//                                     destinationReached
//                                         ? 'Ride Completed'
//                                         : driverStartedRide
//                                         ? 'Ride in Progress'
//                                         : 'Your ride is confirmed',
//                                 colors: AppColors.commonBlack,
//                                 rightImagePath: AppImages.clrTick,
//                               ),
//                             ),
//                           const SizedBox(height: 12),
//                           Row(
//                             children: [
//                               Column(
//                                 // NOTE: you had `spacing: 5` here; kept as-is if you use a custom extension.
//                                 crossAxisAlignment: CrossAxisAlignment.start,
//                                 children: [
//                                   CustomTextFields.textWithStylesSmall(
//                                     plateNumber,
//                                     colors: AppColors.commonBlack,
//                                     fontWeight: FontWeight.w500,
//                                   ),
//
//                                   Row(
//                                     children: [
//                                       Container(
//                                         decoration: BoxDecoration(
//                                           borderRadius: BorderRadius.circular(
//                                             50,
//                                           ),
//                                           color: AppColors.containerColor1,
//                                         ),
//                                         child: Padding(
//                                           padding: const EdgeInsets.all(8.0),
//                                           child:
//                                               (ProfilePic != null &&
//                                                       ProfilePic.isNotEmpty)
//                                                   ? CachedNetworkImage(
//                                                     imageUrl: ProfilePic,
//                                                     height: 20,
//                                                     width: 20,
//                                                     placeholder:
//                                                         (context, url) =>
//                                                             const CircularProgressIndicator(
//                                                               strokeWidth: 2,
//                                                             ),
//                                                     errorWidget:
//                                                         (context, url, error) =>
//                                                             const Icon(
//                                                               Icons.person,
//                                                               size: 20,
//                                                             ),
//                                                   )
//                                                   : const Icon(
//                                                     Icons.person,
//                                                     size: 20,
//                                                   ),
//                                         ),
//                                       ),
//                                       SizedBox(width: 10),
//                                       CustomTextFields.textWithStylesSmall(
//                                         driverName,
//                                         colors: AppColors.commonBlack,
//                                         fontWeight: FontWeight.w500,
//                                       ),
//                                     ],
//                                   ),
//
//                                   CustomTextFields.textWithStylesSmall(
//                                     carDetails,
//                                     fontSize: 12,
//                                     colors: AppColors.carTypeColor,
//                                   ),
//                                 ],
//                               ),
//                               const Spacer(),
//                               CarExteriorPhotos.isNotEmpty
//                                   ? ClipRRect(
//                                     borderRadius: BorderRadius.circular(
//                                       12,
//                                     ), // 👈 change radius as needed
//                                     child: CachedNetworkImage(
//                                       fit: BoxFit.fill,
//                                       height: 80,
//                                       width: 100,
//                                       placeholder:
//                                           (context, url) => const Center(
//                                             child: CircularProgressIndicator(
//                                               strokeWidth: 2,
//                                             ),
//                                           ),
//                                       imageUrl: CarExteriorPhotos,
//                                     ),
//                                   )
//                                   : const SizedBox.shrink(),
//
//                               // Image.asset(
//                               //   CARTYPE == 'sedan'
//                               //       ? AppImages.sedan
//                               //       : AppImages.luxuryCar,
//                               //   height: 50,
//                               // ),
//                             ],
//                           ),
//                           const SizedBox(height: 20),
//                           Row(
//                             children: [
//                               Container(
//                                 decoration: BoxDecoration(
//                                   borderRadius: BorderRadius.circular(50),
//                                   color: AppColors.containerColor1,
//                                 ),
//                                 child: Padding(
//                                   padding: const EdgeInsets.all(8.0),
//                                   child: InkWell(
//                                     onTap: () async {
//                                       try {
//                                         var rawNumber =
//                                             CUSTOMERPHONE?.trim() ?? '';
//                                         // var rawNumber =
//                                         //     CUSTOMERPHONE?.trim() ?? '';
//                                         if (rawNumber.isEmpty) {
//                                           AppToasts.showError(
//                                             'Number Not set ',
//                                           );
//                                           return;
//                                         }
//
//                                         final hasPlus = rawNumber.startsWith(
//                                           '+',
//                                         );
//                                         final digitsOnly = rawNumber.replaceAll(
//                                           RegExp(r'[^0-9]'),
//                                           '',
//                                         );
//                                         final normalized =
//                                             hasPlus
//                                                 ? '+$digitsOnly'
//                                                 : digitsOnly;
//
//                                         if (normalized.isEmpty) {
//                                           AppToasts.showError('Invalid number');
//                                           return;
//                                         }
//
//                                         final Uri telUri = Uri(
//                                           scheme: 'tel',
//                                           path: normalized,
//                                         );
//
//                                         final ok = await launchUrl(
//                                           telUri,
//                                           mode: LaunchMode.externalApplication,
//                                         );
//
//                                         if (!ok)
//                                           AppToasts.showError(
//                                             'Could not open dialer',
//                                           );
//                                       } catch (e) {
//                                         AppToasts.showError(
//                                           'Failed to start call',
//                                         );
//                                       }
//                                     },
//
//                                     child: Image.asset(
//                                       AppImages.call,
//                                       height: 20,
//                                       width: 20,
//                                     ),
//                                   ),
//                                 ),
//                               ),
//                               const SizedBox(width: 10),
//
//                               Expanded(
//                                 child: InkWell(
//                                   onTap: () {
//                                     Navigator.push(
//                                       context,
//                                       MaterialPageRoute(
//                                         builder:
//                                             (context) => ChatScreen(
//                                               bookingId:
//                                                   shareRideController
//                                                       .sharedBooking
//                                                       .value
//                                                       ?.bookingId
//                                                       .toString() ??
//                                                   '',
//                                             ),
//                                       ),
//                                     );
//                                   },
//                                   child: Container(
//                                     decoration: BoxDecoration(
//                                       borderRadius: BorderRadius.circular(20),
//                                       color: AppColors.containerColor1,
//                                     ),
//                                     child: Padding(
//                                       padding: const EdgeInsets.all(8.0),
//                                       child: Row(
//                                         children: [
//                                           CustomTextFields.textWithStylesSmall(
//                                             'Message your driver',
//                                             colors: AppColors.commonBlack,
//                                           ),
//                                           const Spacer(),
//                                           Image.asset(
//                                             AppImages.send,
//                                             height: 16,
//                                             width: 16,
//                                           ),
//                                         ],
//                                       ),
//                                     ),
//                                   ),
//                                 ),
//                               ),
//                             ],
//                           ),
//                           const SizedBox(height: 20),
//
//                           Container(
//                             decoration: BoxDecoration(
//                               color: AppColors.commonWhite,
//                               boxShadow: const [
//                                 BoxShadow(
//                                   color: Colors.black12,
//                                   blurRadius: 8,
//                                   offset: Offset(0, 4),
//                                 ),
//                               ],
//                               borderRadius: BorderRadius.circular(8),
//                             ),
//                             child: Padding(
//                               padding: const EdgeInsets.only(top: 20),
//                               child: Column(
//                                 children: [
//                                   Padding(
//                                     padding: const EdgeInsets.symmetric(
//                                       horizontal: 10,
//                                     ),
//                                     child: Column(
//                                       children: [
//                                         Row(
//                                           children: [
//                                             CustomTextFields.textWithImage(
//                                               fontWeight: FontWeight.w700,
//                                               fontSize: 16,
//                                               colors: AppColors.commonBlack,
//                                               text: 'Total Fare',
//                                               rightImagePath:
//                                                   AppImages.nBlackCurrency,
//                                               rightImagePathText: ' $Amount',
//                                             ),
//                                             const Spacer(),
//                                             otp.isEmpty
//                                                 ? const SizedBox.shrink()
//                                                 : Container(
//                                                   padding:
//                                                       const EdgeInsets.symmetric(
//                                                         horizontal: 10,
//                                                         vertical: 6,
//                                                       ),
//                                                   decoration: BoxDecoration(
//                                                     borderRadius:
//                                                         BorderRadius.circular(
//                                                           6,
//                                                         ),
//                                                     color:
//                                                         AppColors
//                                                             .userChatContainerColor,
//                                                   ),
//                                                   child:
//                                                       CustomTextFields.textWithStyles600(
//                                                         'OTP - $otp',
//                                                         fontSize: 16,
//                                                         color:
//                                                             AppColors
//                                                                 .commonWhite,
//                                                       ),
//                                                 ),
//                                           ],
//                                         ),
//                                         Padding(
//                                           padding: const EdgeInsets.symmetric(
//                                             horizontal: 8.0,
//                                           ),
//                                           child: InkWell(
//                                             onTap:
//                                                 () => setState(
//                                                   () =>
//                                                       isExpanded = !isExpanded,
//                                                 ),
//                                             child: Row(
//                                               children: [
//                                                 CustomTextFields.textWithStylesSmall(
//                                                   'View Details',
//                                                   colors:
//                                                       AppColors
//                                                           .changeButtonColor,
//                                                   fontSize: 13,
//                                                   fontWeight: FontWeight.w500,
//                                                 ),
//                                                 const SizedBox(width: 10),
//                                                 AnimatedRotation(
//                                                   turns: isExpanded ? 0.5 : 0,
//                                                   duration: const Duration(
//                                                     milliseconds: 300,
//                                                   ),
//                                                   child: Image.asset(
//                                                     AppImages.dropDown,
//                                                     height: 16,
//                                                   ),
//                                                 ),
//                                               ],
//                                             ),
//                                           ),
//                                         ),
//                                         AnimatedSwitcher(
//                                           duration: const Duration(
//                                             milliseconds: 300,
//                                           ),
//                                           switchInCurve: Curves.easeInOut,
//                                           switchOutCurve: Curves.easeInOut,
//                                           transitionBuilder: (
//                                             child,
//                                             animation,
//                                           ) {
//                                             return SizeTransition(
//                                               sizeFactor: animation,
//                                               axisAlignment: -1,
//                                               child: FadeTransition(
//                                                 opacity: animation,
//                                                 child: child,
//                                               ),
//                                             );
//                                           },
//                                           child:
//                                               isExpanded
//                                                   ? Column(
//                                                     key: const ValueKey(
//                                                       "expanded",
//                                                     ),
//                                                     children: [
//                                                       const SizedBox(
//                                                         height: 10,
//                                                       ),
//                                                       Container(
//                                                         margin:
//                                                             const EdgeInsets.only(
//                                                               top: 10,
//                                                             ),
//                                                         padding:
//                                                             const EdgeInsets.all(
//                                                               10,
//                                                             ),
//                                                         decoration: BoxDecoration(
//                                                           border: Border.all(
//                                                             color: AppColors
//                                                                 .commonBlack
//                                                                 .withOpacity(
//                                                                   0.1,
//                                                                 ),
//                                                           ),
//                                                           borderRadius:
//                                                               BorderRadius.circular(
//                                                                 8,
//                                                               ),
//                                                         ),
//                                                         child: Column(
//                                                           crossAxisAlignment:
//                                                               CrossAxisAlignment
//                                                                   .start,
//                                                           children: [
//                                                             const Text(
//                                                               "Fare Breakdown",
//                                                               style: TextStyle(
//                                                                 fontWeight:
//                                                                     FontWeight
//                                                                         .bold,
//                                                               ),
//                                                             ),
//                                                             const SizedBox(
//                                                               height: 5,
//                                                             ),
//
//                                                             Row(
//                                                               children: [
//                                                                 CustomTextFields.textWithStylesSmall(
//                                                                   'Base Fare',
//                                                                 ),
//                                                                 const Spacer(),
//                                                                 CustomTextFields.textWithImage(
//                                                                   colors:
//                                                                       AppColors
//                                                                           .commonBlack,
//                                                                   text:
//                                                                       (widget.baseFare ??
//                                                                               0)
//                                                                           .toString(),
//                                                                   imagePath:
//                                                                       AppImages
//                                                                           .nBlackCurrency,
//                                                                 ),
//                                                               ],
//                                                             ),
//                                                             Row(
//                                                               children: [
//                                                                 CustomTextFields.textWithStylesSmall(
//                                                                   'Distance Fare',
//                                                                 ),
//                                                                 const Spacer(),
//                                                                 CustomTextFields.textWithImage(
//                                                                   colors:
//                                                                       AppColors
//                                                                           .commonBlack,
//                                                                   text:
//                                                                       (widget.distanceFare ??
//                                                                               0)
//                                                                           .toString(),
//                                                                   imagePath:
//                                                                       AppImages
//                                                                           .nBlackCurrency,
//                                                                 ),
//                                                               ],
//                                                             ),
//                                                             Row(
//                                                               children: [
//                                                                 CustomTextFields.textWithStylesSmall(
//                                                                   'Pickup Fare',
//                                                                 ),
//                                                                 const Spacer(),
//                                                                 CustomTextFields.textWithImage(
//                                                                   colors:
//                                                                       AppColors
//                                                                           .commonBlack,
//                                                                   text:
//                                                                       (widget.pickupFare ??
//                                                                               0)
//                                                                           .toString(),
//                                                                   imagePath:
//                                                                       AppImages
//                                                                           .nBlackCurrency,
//                                                                 ),
//                                                               ],
//                                                             ),
//                                                             Row(
//                                                               children: [
//                                                                 CustomTextFields.textWithStylesSmall(
//                                                                   'Booking Fee',
//                                                                 ),
//                                                                 const Spacer(),
//                                                                 CustomTextFields.textWithImage(
//                                                                   colors:
//                                                                       AppColors
//                                                                           .commonBlack,
//                                                                   text:
//                                                                       (widget.bookingFee ??
//                                                                               0)
//                                                                           .toString(),
//                                                                   imagePath:
//                                                                       AppImages
//                                                                           .nBlackCurrency,
//                                                                 ),
//                                                               ],
//                                                             ),
//                                                             Row(
//                                                               children: [
//                                                                 CustomTextFields.textWithStylesSmall(
//                                                                   'Time Fare',
//                                                                 ),
//                                                                 const Spacer(),
//                                                                 CustomTextFields.textWithImage(
//                                                                   colors:
//                                                                       AppColors
//                                                                           .commonBlack,
//                                                                   text:
//                                                                       (widget.timeFare ??
//                                                                               0)
//                                                                           .toString(),
//                                                                   imagePath:
//                                                                       AppImages
//                                                                           .nBlackCurrency,
//                                                                 ),
//                                                               ],
//                                                             ),
//                                                             const SizedBox(
//                                                               height: 10,
//                                                             ),
//                                                           ],
//                                                         ),
//                                                       ),
//                                                       const SizedBox(
//                                                         height: 10,
//                                                       ),
//                                                     ],
//                                                   )
//                                                   : const SizedBox.shrink(
//                                                     key: ValueKey("collapsed"),
//                                                   ),
//                                         ),
//                                       ],
//                                     ),
//                                   ),
//                                 ],
//                               ),
//                             ),
//                           ),
//                           const SizedBox(height: 20),
//
//                           GestureDetector(
//                             onTap: () {},
//                             child: Container(
//                               decoration: BoxDecoration(
//                                 color: AppColors.containerColor1,
//                                 borderRadius: BorderRadius.circular(5),
//                               ),
//                               child: Padding(
//                                 padding: const EdgeInsets.all(15),
//                                 child: Column(
//                                   crossAxisAlignment: CrossAxisAlignment.start,
//                                   // (You had `spacing: 5`; keeping normal children list)
//                                   children: [
//                                     CustomTextFields.textWithStyles600(
//                                       'Directions to reach',
//                                       fontSize: 14,
//                                     ),
//                                     CustomTextFields.textWithStylesSmall(
//                                       'Help your driver partner reach you faster',
//                                       fontSize: 12,
//                                     ),
//                                     CustomTextFields.textWithStylesSmall(
//                                       'Add Direction',
//                                       fontSize: 12,
//                                       colors: AppColors.resendBlue,
//                                       fontWeight: FontWeight.w700,
//                                     ),
//                                   ],
//                                 ),
//                               ),
//                             ),
//                           ),
//                           const SizedBox(height: 20),
//
//                           Container(
//                             decoration: BoxDecoration(
//                               color: Colors.white,
//                               borderRadius: BorderRadius.circular(12),
//                               boxShadow: const [
//                                 BoxShadow(
//                                   color: Colors.black12,
//                                   blurRadius: 8,
//                                   offset: Offset(0, 4),
//                                 ),
//                               ],
//                             ),
//                             child: Column(
//                               children: [
//                                 CustomTextFields.plainTextField(
//                                   readOnly: true,
//                                   Style: TextStyle(
//                                     fontSize: 12,
//                                     color: AppColors.commonBlack.withOpacity(
//                                       0.6,
//                                     ),
//                                     overflow: TextOverflow.ellipsis,
//                                   ),
//                                   controller: _startController,
//                                   containerColor: AppColors.commonWhite,
//                                   leadingImage: AppImages.circleStart,
//                                   title: 'Search for an address or landmark',
//                                   hintStyle: const TextStyle(fontSize: 11),
//                                   imgHeight: 17,
//                                 ),
//                                 const Divider(
//                                   height: 0,
//                                   color: AppColors.containerColor,
//                                 ),
//                                 CustomTextFields.plainTextField(
//                                   readOnly: true,
//                                   Style: TextStyle(
//                                     fontSize: 12,
//                                     color: AppColors.commonBlack.withOpacity(
//                                       0.6,
//                                     ),
//                                     overflow: TextOverflow.ellipsis,
//                                   ),
//                                   controller: _destController,
//                                   containerColor: AppColors.commonWhite,
//                                   leadingImage: AppImages.rectangleDest,
//                                   title: 'Enter destination',
//                                   hintStyle: const TextStyle(fontSize: 11),
//                                   imgHeight: 17,
//                                 ),
//                                 const Divider(
//                                   height: 0,
//                                   color: AppColors.containerColor,
//                                 ),
//                                 Padding(
//                                   padding: const EdgeInsets.symmetric(
//                                     horizontal: 15,
//                                     vertical: 15,
//                                   ),
//                                   child: Row(
//                                     mainAxisAlignment: MainAxisAlignment.center,
//                                     children: [
//                                       CustomTextFields.textWithImage(
//                                         onTap:
//                                             otp.isNotEmpty
//                                                 ? null
//                                                 : () {
//                                                   AppButtons.showCancelRideBottomSheet(
//                                                     context,
//                                                     onConfirmCancel: (
//                                                       String selectedReason,
//                                                     ) {
//                                                       driverSearchController
//                                                           .cancelRide(
//                                                             bookingId:
//                                                                 driverSearchController
//                                                                     .carBooking
//                                                                     .value!
//                                                                     .bookingId,
//                                                             selectedReason:
//                                                                 selectedReason,
//                                                             context: context,
//                                                           );
//                                                     },
//                                                   );
//                                                 },
//                                         text:
//                                             otp.isNotEmpty
//                                                 ? 'Ratings'
//                                                 : ' Cancel Ride',
//                                         fontWeight: FontWeight.w500,
//                                         colors: AppColors.cancelRideColor,
//                                         imagePath:
//                                             otp.isNotEmpty
//                                                 ? null
//                                                 : AppImages.cancel,
//                                       ),
//                                       const SizedBox(width: 10),
//                                       SizedBox(
//                                         height: 24,
//                                         child: VerticalDivider(
//                                           color: Colors.grey,
//                                           thickness: 1,
//                                         ),
//                                       ),
//                                       const SizedBox(width: 10),
//                                       CustomTextFields.textWithImage(
//                                         text: 'Support',
//                                         fontWeight: FontWeight.w500,
//                                         colors: AppColors.cancelRideColor,
//                                         imagePath: AppImages.support,
//                                       ),
//                                       const SizedBox(width: 10),
//                                       SizedBox(
//                                         height: 24,
//                                         child: VerticalDivider(
//                                           color: Colors.grey,
//                                           thickness: 1,
//                                         ),
//                                       ),
//                                       const SizedBox(width: 10),
//                                       CustomTextFields.textWithImage(
//                                         onTap: () {
//                                           final String bookingId =
//                                               driverSearchController
//                                                   .carBooking
//                                                   .value!
//                                                   .bookingId;
//                                           final url =
//                                               "https://hoppr-admin-e7bebfb9fb05.herokuapp.com/ride-tracker/$bookingId";
//                                           Share.share(url);
//                                         },
//                                         text: 'Share',
//                                         fontWeight: FontWeight.w500,
//                                         colors: AppColors.cancelRideColor,
//                                         imagePath: AppImages.support,
//                                       ),
//                                     ],
//                                   ),
//                                 ),
//                               ],
//                             ),
//                           ),
//                           const SizedBox(height: 20),
//                         ],
//                       ],
//                     ),
//                   );
//                 },
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
//
//   Widget waitingForDriverUI() {
//     return Column(
//       children: [
//         const Text(
//           'Looking for the best drivers for you',
//           textAlign: TextAlign.center,
//           style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//         ),
//         const SizedBox(height: 12),
//         LinearProgressIndicator(
//           borderRadius: BorderRadius.circular(10),
//           minHeight: 7,
//           backgroundColor: AppColors.linearIndicatorColor.withOpacity(0.2),
//           color: AppColors.linearIndicatorColor,
//         ),
//         const SizedBox(height: 20),
//         Image.asset(
//           AppImages.confirmCar,
//           height: 100,
//           width: 100,
//           fit: BoxFit.contain,
//         ),
//         const SizedBox(height: 20),
//         Container(
//           decoration: BoxDecoration(
//             color: Colors.white,
//             borderRadius: BorderRadius.circular(12),
//             boxShadow: const [
//               BoxShadow(
//                 color: Colors.black12,
//                 blurRadius: 8,
//                 offset: Offset(0, 4),
//               ),
//             ],
//           ),
//           child: Column(
//             children: [
//               CustomTextFields.plainTextField(
//                 readOnly: true,
//                 Style: TextStyle(
//                   fontSize: 12,
//                   color: AppColors.commonBlack.withOpacity(0.6),
//                   overflow: TextOverflow.ellipsis,
//                 ),
//                 controller: _startController,
//                 containerColor: AppColors.commonWhite,
//                 leadingImage: AppImages.circleStart,
//                 title: 'Search for an address or landmark',
//                 hintStyle: const TextStyle(fontSize: 11),
//                 imgHeight: 17,
//               ),
//               const Divider(height: 0, color: AppColors.containerColor),
//               CustomTextFields.plainTextField(
//                 readOnly: true,
//                 Style: TextStyle(
//                   fontSize: 12,
//                   color: AppColors.commonBlack.withOpacity(0.6),
//                   overflow: TextOverflow.ellipsis,
//                 ),
//                 controller: _destController,
//                 containerColor: AppColors.commonWhite,
//                 leadingImage: AppImages.rectangleDest,
//                 title: 'Enter destination',
//                 hintStyle: const TextStyle(fontSize: 11),
//                 imgHeight: 17,
//               ),
//             ],
//           ),
//         ),
//         const SizedBox(height: 20),
//         AppButtons.button(
//           hasBorder: true,
//           borderColor: AppColors.commonBlack.withOpacity(0.2),
//           buttonColor: AppColors.commonWhite,
//           textColor: AppColors.cancelRideColor,
//           onTap: () {
//             AppButtons.showCancelRideBottomSheet(
//               context,
//               onConfirmCancel: (String selectedReason) {
//                 driverSearchController.cancelRide(
//                   bookingId: driverSearchController.carBooking.value!.bookingId,
//                   selectedReason: selectedReason,
//                   context: context,
//                 );
//               },
//             );
//           },
//           text: 'Cancel Ride',
//         ),
//       ],
//     );
//   }
//
//   Widget noDriverFoundUI() {
//     return Center(
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           const Icon(Icons.error_outline, color: Colors.redAccent, size: 80),
//           const SizedBox(height: 20),
//           const Text(
//             "No Drivers Found",
//             style: TextStyle(
//               fontSize: 22,
//               fontWeight: FontWeight.bold,
//               color: Colors.redAccent,
//             ),
//           ),
//           const SizedBox(height: 8),
//           const Text(
//             "We couldn’t find any available drivers nearby.\nPlease try again in a few minutes.",
//             textAlign: TextAlign.center,
//             style: TextStyle(fontSize: 16, color: Colors.grey),
//           ),
//           const SizedBox(height: 30),
//           AppButtons.button(
//             buttonColor: Colors.blue,
//             textColor: Colors.white,
//             text: "Try Again",
//             onTap: () async {
//               setState(() {
//                 isWaitingForDriver = true;
//                 noDriverFound = false;
//               });
//
//               final allData = driverSearchController.carBooking.value;
//               String? result = await driverSearchController.sendDriverRequest(
//                 carType: widget.carType,
//                 pickupLatitude: allData?.fromLatitude ?? 0.0,
//                 pickupLongitude: allData?.fromLongitude ?? 0.0,
//                 dropLatitude: allData?.toLatitude ?? 0.0,
//                 dropLongitude: allData?.toLongitude ?? 0.0,
//                 bookingId: allData?.bookingId.toString() ?? '',
//                 context: context,
//               );
//               if (result != null) {
//                 startDriverSearch();
//               }
//             },
//           ),
//           SizedBox(height: 15),
//           SizedBox(
//             width: double.infinity,
//             child: OutlinedButton(
//               onPressed: () {
//                 Navigator.pop(context);
//               },
//               style: OutlinedButton.styleFrom(
//                 shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(15),
//                 ),
//                 side: BorderSide(color: Colors.black),
//                 padding: EdgeInsets.symmetric(vertical: 16),
//               ),
//               child: Text(
//                 'Go Home',
//                 style: TextStyle(
//                   color: AppColors.commonBlack,
//                   fontSize: 16,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

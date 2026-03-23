import 'package:hopper/Core/Utility/app_toasts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:hopper/Presentation/OnBoarding/Controller/package_controller.dart';
import 'package:hopper/Presentation/OnBoarding/Screens/chat_screen.dart';
import 'package:dotted_line/dotted_line.dart';
 
import 'package:hopper/Presentation/OnBoarding/Widgets/custom_bottomnavigation.dart';
import 'package:hopper/Presentation/OnBoarding/Widgets/package_contoiner.dart';
import 'package:hopper/Presentation/OnBoarding/models/address_models.dart';
import 'package:hopper/uitls/netWorkHandling/network_handling_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';
import 'package:hopper/Presentation/OnBoarding/Screens/payment_screen.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Utility/app_buttons.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
import 'package:hopper/uitls/websocket/socket_io_client.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import '../../../api/repository/api_consents.dart';
import '../../BookRide/Controllers/driver_search_controller.dart';

class PackageMapConfirmScreen extends StatefulWidget {
  final String bookingId;
  final String discountCode;
  final AddressModel senderData;
  final AddressModel receiverData;
  const PackageMapConfirmScreen({
    super.key,
    required this.bookingId,
    required this.discountCode,
    required this.senderData,
    required this.receiverData,
  });

  @override
  State<PackageMapConfirmScreen> createState() =>
      _PackageMapConfirmScreenState();
}

class _PackageMapConfirmScreenState extends State<PackageMapConfirmScreen> {
  bool isExpanded = false;
  GoogleMapController? _mapController;
  final socketService = SocketService();
  LatLng? _currentPosition;
  Set<Polyline> _polylines = {};
  BitmapDescriptor? _carIcon;
  Set<Marker> _markers = {};
  Set<Circle> _circles = {};
  bool _isDriverConfirmed = false;
  Marker? _driverMarker;
  bool driverStartedRide = false;
  bool destinationReached = false;
  bool _autoFollowEnabled = true;
  bool _isDrawingPolyline = false;
  LatLng? _customerLatLng;
  LatLng? _customerToLatLang;
  String plateNumber = '';
  String driverName = '';
  double driverRating = 0.0;
  String carDetails = '';
  String CUSTOMERPHONE = '';
  String CARTYPE = '';
  String ProfilePic = '';
  String BookingId = '';
  int? MaxWeight;
  double Amount = 0.0;
  String PickupAddress = '';
  String DropAddress = '';
  bool _isOrderConfirmed = false;
  bool _isEnRoute = false;
  bool _isPackagePickup = false;
  bool _isPackageCollected = false;
  bool _isInTransit = false;
  bool _isOutForDelivery = false;
  String _estimateStt1 = '';
  String _estimateStt2 = '';
  String otp = '';
  LatLng? _currentDriverLatLng;
  bool isTripCancelled = false;
  String cancelReason = "";

  double? _routeMeters;
  int? _routeSeconds;
  bool _routeMetricsFromSocket = false;
  DateTime _routeMetricsFromSocketAt = DateTime.fromMillisecondsSinceEpoch(0);

  int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  Timer? _pulseTimer;
  double _pulsePhase = 0.0;
  LatLng? _pulseCenter;

  String _estimateText() {
    final a = _estimateStt1.trim();
    final b = _estimateStt2.trim();
    if (a.isEmpty && b.isEmpty) return '';
    if (a.isNotEmpty && b.isNotEmpty) return '$a\n$b';
    return a.isNotEmpty ? a : b;
  }

  String _shortPlace(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    final parts = s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    if (parts.length >= 3) {
      // city, state/region
      return '${parts[parts.length - 3]}, ${parts[parts.length - 2]}';
    }
    if (parts.length >= 2) return '${parts[parts.length - 2]}, ${parts.last}';
    return parts.first;
  }

  Future<void> _seedPickupDropMarkers() async {
    final pickup = _customerLatLng;
    final drop = _customerToLatLang;
    if (pickup == null && drop == null) return;

    final next = <Marker>{
      ..._markers.where(
        (m) =>
            m.markerId != const MarkerId("pickup_marker") &&
            m.markerId != const MarkerId("drop_marker"),
      ),
    };

    if (pickup != null) {
      next.add(
        Marker(
          markerId: const MarkerId("pickup_marker"),
          position: pickup,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: const InfoWindow(title: "Pickup"),
        ),
      );
    }

    if (drop != null) {
      next.add(
        Marker(
          markerId: const MarkerId("drop_marker"),
          position: drop,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: "Drop"),
        ),
      );
    }

    if (!mounted) return;
    setState(() => _markers = next.toSet());

    if (_mapController == null) return;

    try {
      if (pickup != null && drop != null) {
        final diag = Geolocator.distanceBetween(
          pickup.latitude,
          pickup.longitude,
          drop.latitude,
          drop.longitude,
        );
        final bounds = LatLngBounds(
          southwest: LatLng(
            math.min(pickup.latitude, drop.latitude),
            math.min(pickup.longitude, drop.longitude),
          ),
          northeast: LatLng(
            math.max(pickup.latitude, drop.latitude),
            math.max(pickup.longitude, drop.longitude),
          ),
        );
        if (diag.isFinite && diag < 260) {
          final mid = LatLng(
            (pickup.latitude + drop.latitude) / 2,
            (pickup.longitude + drop.longitude) / 2,
          );
          await _mapController!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: mid,
                zoom: _currentZoomLevel.clamp(12.0, 16.6).toDouble(),
              ),
            ),
          );
        } else {
          await _mapController!.animateCamera(
            CameraUpdate.newLatLngBounds(bounds, 120),
          );
          final z = await _mapController?.getZoomLevel();
          if (z != null && z > 16.6) {
            final mid = LatLng(
              (bounds.northeast.latitude + bounds.southwest.latitude) / 2,
              (bounds.northeast.longitude + bounds.southwest.longitude) / 2,
            );
            await _mapController!.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(target: mid, zoom: 16.6),
              ),
            );
          }
        }
      } else {
        final target = pickup ?? drop;
        if (target != null) {
          _mapController!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(target: target, zoom: _currentZoomLevel),
            ),
          );
        }
      }
    } catch (_) {}
  }

  void _startPulseAnimation() {
    _pulseTimer?.cancel();
    _pulseTimer = Timer.periodic(const Duration(milliseconds: 650), (_) {
      _pulsePhase += 0.9;
      _updatePulseCircle();
    });
  }

  void _updatePulseCircle() {
    final center = _pulseCenter ?? _currentDriverLatLng ?? _customerLatLng;
    if (center == null) return;
    if (!mounted) return;

    final t = (math.sin(_pulsePhase) + 1) / 2; // 0..1
    final radius = 20.0 + (45.0 * t); // meters
    final fillOpacity = 0.04 + (0.06 * (1 - t));

    setState(() {
      _circles = {
        Circle(
          circleId: const CircleId('pulse'),
          center: center,
          radius: radius,
          fillColor: Colors.black.withOpacity(fillOpacity),
          strokeColor: Colors.black.withOpacity(0.12),
          strokeWidth: 1,
        ),
      };
    });
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

  // ---------- camera follow (order_confirm style) ----------
  double _currentZoomLevel = 16.0;
  DateTime _pauseAutoFollowUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastCameraMoveAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _cameraInterval = const Duration(milliseconds: 900);
  final Duration _userGesturePause = const Duration(seconds: 6);

  // ---------- smooth driver motion ----------
  bool _isAnimatingDriver = false;
  LatLng? _pendingDriverTarget;
  double _lastBearing = 0.0;
  final double _hardJumpMeters = 120.0;
  final double _minMoveMeters = 1.2;

  // ---------- polyline throttle ----------
  DateTime _lastPolylineAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _polylineInterval = const Duration(seconds: 25);
  String? _activePolyId;

  Future<void> _loadCustomMarker() async {
    _carIcon = await BitmapDescriptor.asset(
      height: 60,
      ImageConfiguration(size: Size(52, 52)),
      AppImages.packageBike,
    );
  }

  final GlobalKey _senderKey = GlobalKey();
  final GlobalKey _receiverKey = GlobalKey();

  double lineHeight = 60;
  void _calculateLineHeight() {
    final senderBox =
        _senderKey.currentContext?.findRenderObject() as RenderBox?;
    final receiverBox =
        _receiverKey.currentContext?.findRenderObject() as RenderBox?;

    if (senderBox != null && receiverBox != null) {
      final senderPos = senderBox.localToGlobal(Offset.zero);
      final receiverPos = receiverBox.localToGlobal(Offset.zero);

      final calculatedHeight = receiverPos.dy - senderPos.dy - 30;
      setState(() {
        lineHeight = calculatedHeight > 0 ? calculatedHeight : 0;
      });
    }
  }

  Future<void> _initLocation() async {
    Position position = await Geolocator.getCurrentPosition();
    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
    });
    AppLogger.log.i(_currentPosition);

    if (_currentPosition != null && _mapController != null) {
      _mapController?.moveCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _currentPosition!,
            zoom: _currentZoomLevel,
            bearing: 0,
            tilt: 0,
          ),
        ),
      );
    }
  }

  void _goToCurrentLocation() async {
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    final latLng = LatLng(position.latitude, position.longitude);

    _pauseAutoFollowUntil = DateTime.fromMillisecondsSinceEpoch(0);
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: latLng,
          zoom: _currentZoomLevel,
          bearing: 0,
          tilt: 0,
        ),
      ),
    );
  }

  bool isWaitingForDriver = true;
  bool noDriverFound = false;
  void startDriverSearch() {
    isWaitingForDriver = true;
    noDriverFound = false;

    Future.delayed(Duration(minutes: 1), () async {
      if (!_isDriverConfirmed) {
        bool hasDriver = await driverSearchController.noDriverFound(
          context: context,
          bookingId: widget.bookingId,
          status: true,
        );

        setState(() {
          isWaitingForDriver = false;
          noDriverFound = !hasDriver;
        });
      }
    });
  }

  final PackageController packageController = Get.put(PackageController());
  @override
  void initState() {
    super.initState();
    _initLocation();
    _loadCustomMarker();
    initSocket();
    _bootSocket();
    _startPulseAnimation();
    WidgetsBinding.instance.addPostFrameCallback((_) => _calculateLineHeight());
    startDriverSearch();
  }

  Future<void> _bootSocket() async {
    try {
      socketService.initSocket(ApiConsents.baseUrl);

      final prefs = await SharedPreferences.getInstance();
      final customerId = (prefs.getString('customer_Id') ?? '').trim();
      if (customerId.isNotEmpty) socketService.registerUser(customerId);

      // Ensure we are in booking room so server pushes joined-booking + updates
      socketService.joinBookingRoom(bookingId: widget.bookingId);
    } catch (_) {}
  }

  void initSocket() {
    socketService.onConnect(() {
      AppLogger.log.i("✅ Socket connected on booking screen");
    });

    socketService.on('joined-booking', (data) {
      if (!mounted) return;
      AppLogger.log.i("Package Joined booking data: $data");
      final vehicle = (data['vehicle'] as Map?) ?? {};
      final String driverId = (data['driverId'] ?? '').toString();
      final String driverFullName = (data['driverName'] ?? '').toString();
      final String customerPhone = (data['customerPhone'] ?? '').toString();
      final double rating =
           double.tryParse(data['driverRating'].toString()) ?? 0.0;
      final String color = vehicle['color'] ?? '';
      final String model = vehicle['model'] ?? '';
      final String brand = vehicle['brand'] ?? '';
      final String carType = vehicle['carType'] ?? '';
      final rideHistory = (data['rideStatusHistory'] as List?) ?? const [];
      final acceptedFromHistory = rideHistory.any((e) {
        final m = e as Map?;
        final st = (m?['status'] ?? '').toString().toUpperCase();
        return st == 'ACCEPTED' || st == 'DRIVER_ACCEPTED';
      });

      final bool driverAccepted =
          data['driver_accept_status'] == true ||
          data['orderConfirmationStatus'] == true ||
          acceptedFromHistory;
      final String type = vehicle['type'] ?? '';
      final String plate = vehicle['plateNumber'] ?? '';
      final customerLoc =
          (data['customerLocation'] as Map?) ??
          ((data['basePayload'] as Map?)?['customerLocation'] as Map?) ??
          {};
      final amount = data['amount'];
      final String profilePic = (data['profilePic'] ?? '').toString();
      final String bookingId = (data['bookingId'] ?? '').toString();
      final int maxWeight =
          (data['maxWeight'] is num)
              ? (data['maxWeight'] as num).toInt()
              : int.tryParse((data['maxWeight'] ?? '').toString()) ?? 0;
      final String pickupAddress = (data['pickupAddress'] ?? '').toString();
      final String dropAddress = (data['dropAddress'] ?? '').toString();

      final fromLat =
          (customerLoc['fromLatitude'] is num)
              ? (customerLoc['fromLatitude'] as num).toDouble()
              : double.tryParse((customerLoc['fromLatitude'] ?? '').toString());
      final fromLng =
          (customerLoc['fromLongitude'] is num)
              ? (customerLoc['fromLongitude'] as num).toDouble()
              : double.tryParse((customerLoc['fromLongitude'] ?? '').toString());
      final toLat =
          (customerLoc['toLatitude'] is num)
              ? (customerLoc['toLatitude'] as num).toDouble()
              : double.tryParse((customerLoc['toLatitude'] ?? '').toString());
      final toLng =
          (customerLoc['toLongitude'] is num)
              ? (customerLoc['toLongitude'] as num).toDouble()
              : double.tryParse((customerLoc['toLongitude'] ?? '').toString());

      if (fromLat != null && fromLng != null) {
        _customerLatLng = LatLng(fromLat, fromLng);
      }
      if (toLat != null && toLng != null) {
        _customerToLatLang = LatLng(toLat, toLng);
      }

      setState(() {
        plateNumber = plate;
        driverName = '$driverFullName ⭐ $rating';
        carDetails = '$color - $brand';
        _isDriverConfirmed = driverAccepted;
        driverStartedRide =
            data['packageCollected'] == true ||
            data['inTransit'] == true ||
            data['outForDelivery'] == true;
        _isOrderConfirmed = data['orderConfirmationStatus'] ?? false;
        _isEnRoute = data['enRoute'] ?? false;
        _isPackagePickup = data['packagePickup'] ?? false;
        _isPackageCollected = data['packageCollected'] ?? false;
        _isInTransit = data['inTransit'] ?? false;
        _isOutForDelivery = data['outForDelivery'] ?? false;
        CUSTOMERPHONE = customerPhone;
        CARTYPE = carType;
        ProfilePic = profilePic;
        BookingId = bookingId;
        MaxWeight = maxWeight;
        PickupAddress = pickupAddress;
        DropAddress = dropAddress;
        Amount = (amount is num) ? amount.toDouble() : (double.tryParse((amount ?? '').toString()) ?? 0.0);
      });

      AppLogger.log.i("🚕 Joined booking data: $data");
      AppLogger.log.i("🚕 driverAccepted ==  $driverAccepted");

      _seedPickupDropMarkers();

      // Start real-time tracking
      if (driverId.trim().isNotEmpty) {
        AppLogger.log.i("📍 Tracking driver: $driverId");
        socketService.joinBooking(
          bookingId: widget.bookingId,
          driverId: driverId.trim(),
        );
      }
    });

    socketService.on('driver-location', (data) {
      AppLogger.log.i('📦 driver-location-updated: $data');

      final newDriverLatLng = LatLng(data['latitude'], data['longitude']);

      if (_currentDriverLatLng == null) {
        _currentDriverLatLng = newDriverLatLng;
        _updateDriverMarker(newDriverLatLng, _lastBearing);
        _maybeAutoFollow(newDriverLatLng);
        _maybeUpdatePolyline(newDriverLatLng, force: true);
        return;
      }

      // ✅ Animate movement
      _enqueueDriverMove(newDriverLatLng);

      // polyline handled by _enqueueDriverMove()

      // ✅ CASE 2: After ride starts → Draw polyline to drop
      // polyline handled by _enqueueDriverMove()

      // ✅ Update current driver position
      // _currentDriverLatLng is updated by smooth animation engine
      // 📦 Extract flags
      final basePayload = data['basePayload'] ?? {};
      final estimate = basePayload['getEstimateTime'] ?? {};
      final prevStarted = driverStartedRide;
      final nextStarted =
          basePayload['packageCollected'] == true ||
          basePayload['inTransit'] == true ||
          basePayload['outForDelivery'] == true;

      final socketMeters = _parseInt(
        data[nextStarted ? 'dropDistanceInMeters' : 'pickupDistanceInMeters'],
      );
      final socketMins = _parseInt(
        data[nextStarted ? 'dropDurationInMin' : 'pickupDurationInMin'],
      );
      if (!mounted) return;
      setState(() {
        driverStartedRide = nextStarted;
        _isOrderConfirmed = basePayload['orderConfirmationStatus'] ?? false;
        _isEnRoute = basePayload['enRoute'] ?? false;
        _isPackagePickup = basePayload['packagePickup'] ?? false;
        _isPackageCollected = basePayload['packageCollected'] ?? false;
        _isInTransit = basePayload['inTransit'] ?? false;
        _isOutForDelivery = basePayload['outForDelivery'] ?? false;
        _estimateStt1 = estimate['stt1'] ?? '';
        _estimateStt2 = estimate['stt2'] ?? '';

        // Prefer socket ETA metrics for display (prevents mismatch vs server values)
        if (socketMeters != null && socketMeters >= 0) {
          _routeMeters = socketMeters.toDouble();
          _routeMetricsFromSocket = true;
          _routeMetricsFromSocketAt = DateTime.now();
        }
        if (socketMins != null && socketMins >= 0) {
          _routeSeconds = socketMins * 60;
          _routeMetricsFromSocket = true;
          _routeMetricsFromSocketAt = DateTime.now();
        }
      });

      if (prevStarted != nextStarted) {
        _maybeUpdatePolyline(newDriverLatLng, force: true);
      }
    });

    socketService.on('driver-arrived', (data) {
      AppLogger.log.i("driver-arrived: $data");
    });

    socketService.on('otp-generated', (data) {
      if (!mounted) return;
      final otpGenerated = data['otpCode'];
      setState(() {
        otp = otpGenerated;
      });

      AppLogger.log.i("otp-generated: $data");
    });

    socketService.on('ride-started', (data) {
      final bool status = data['status'] == true;
      AppLogger.log.i("ride-started: $data");

      driverStartedRide = status; // don't wait for setState

      if (!mounted) return;
      setState(() {}); // only for UI like info card updates

      if (status &&
          _currentDriverLatLng != null &&
          _customerToLatLang != null) {
        final dropMarker = Marker(
          markerId: const MarkerId("drop_marker"),
          position: _customerToLatLang!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: "Destination"),
        );

        setState(() {
          _markers = {if (_driverMarker != null) _driverMarker!, dropMarker};
        });

        _maybeUpdatePolyline(_currentDriverLatLng!, force: true);
      }
    });
    socketService.on('driver-reached-destination', (data) {
      final status = data['status'];
      if (status == true || status.toString() == 'status') {
        if (!mounted) return;
        setState(() {
          destinationReached = true;
        });
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          final id = (BookingId.trim().isNotEmpty ? BookingId : widget.bookingId).trim();
          Get.to(
            () => PaymentScreen(
              bookingId: id,
              amount: Amount,
              sender: widget.senderData,
              receiver: widget.receiverData,
            ),
          );
        });

        AppLogger.log.i("driver_reached,$data");
      }
    });
    socketService.on('customer-cancelled', (data) async {
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
        Get.offAll(() => CommonBottomNavigation(initialIndex: 3));
      }
    });
    socketService.on('driver-cancelled', (data) async {
      AppLogger.log.i('driver-cancelled : $data');

      if (data != null && data['status'] == true) {
        if (!mounted) return;

        setState(() {
          isTripCancelled = true;
          cancelReason =
              data['reason'] ?? "Driver had to cancel due to an emergency";
        });

        await Future.delayed(const Duration(seconds: 3));
        if (!mounted) return;
        Get.offAll(() => CommonBottomNavigation(initialIndex: 3));
      }
    });
  }

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

  double _lerp(double start, double end, double t) {
    return start + (end - start) * t;
  }

  Future<void> _animateCarTo(LatLng from, LatLng to) async {
    const steps = 10;
    const duration = Duration(milliseconds: 800);
    final interval = duration.inMilliseconds ~/ steps;

    double currentBearing = _driverMarker?.rotation ?? 0;

    for (int i = 1; i <= steps; i++) {
      await Future.delayed(Duration(milliseconds: interval));

      final lat = _lerp(from.latitude, to.latitude, i / steps);
      final lng = _lerp(from.longitude, to.longitude, i / steps);
      final intermediate = LatLng(lat, lng);
      double newBearing = _getBearing(from, intermediate);

      if ((newBearing - currentBearing).abs() > 10) {
        currentBearing = newBearing;
      }

      _updateDriverMarker(intermediate, currentBearing);

      // ✅ Only auto-move camera if user is not interacting
      if (Geolocator.distanceBetween(
            _currentDriverLatLng!.latitude,
            _currentDriverLatLng!.longitude,
            intermediate.latitude,
            intermediate.longitude,
          ) >
          1) {
        _updateDriverMarker(intermediate, currentBearing);

        if (_autoFollowEnabled) {
          final zoom = await _mapController?.getZoomLevel() ?? 17;

          _mapController?.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: intermediate,
                zoom: zoom,
                tilt: 45, // optional
                bearing: currentBearing, // 👈 map rotates with car
              ),
            ),
          );
        }
      }
    }

    _currentDriverLatLng = to;

    if (driverStartedRide && _customerToLatLang != null) {
      await _drawPolylineFromDriverToCustomer(
        driverLatLng: to,
        customerLatLng: _customerToLatLang!,
      );
    } else if (!driverStartedRide && _customerLatLng != null) {
      await _drawPolylineFromDriverToCustomer(
        driverLatLng: to,
        customerLatLng: _customerLatLng!,
      );
    }
  }

  void _updateDriverMarker(LatLng position, double bearing) {
    _pulseCenter = position;
    _driverMarker = Marker(
      markerId: const MarkerId("driver_marker"),
      position: position,
      rotation: bearing,
      icon:
          _carIcon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      anchor: const Offset(0.5, 0.5),
      flat: true,
    );

    if (!mounted) return;
    setState(() {
      // 🟢 Remove old marker and add updated one
      _markers = {
        ..._markers.where((m) => m.markerId != const MarkerId("driver_marker")),
        _driverMarker!,
      };
    });
  }

  Future<void> _drawPolylineFromDriverToCustomer({
    required LatLng driverLatLng,
    required LatLng customerLatLng,
  }) async {
    if (_isDrawingPolyline) return; // prevent multiple calls
    _isDrawingPolyline = true;

    String apiKey = ApiConsents.googleMapApiKey;

    final url =
        'https://maps.googleapis.com/maps/api/directions/json?origin=${driverLatLng.latitude},${driverLatLng.longitude}&destination=${customerLatLng.latitude},${customerLatLng.longitude}&key=$apiKey';

    final response = await http.get(Uri.parse(url));
    final data = json.decode(response.body);
    if (!mounted) return;
    if (data['status'] == 'OK') {
      final legs = (data['routes']?[0]?['legs'] as List?) ?? const [];
      final leg0 = legs.isNotEmpty ? (legs.first as Map?) : null;
      final meters =
          (leg0?['distance']?['value'] is num)
              ? (leg0?['distance']?['value'] as num).toDouble()
              : null;
      final seconds =
          (leg0?['duration']?['value'] is num)
              ? (leg0?['duration']?['value'] as num).toInt()
              : null;

      final encoded = data['routes'][0]['overview_polyline']['points'];
      final points = _decodePolyline(encoded);
      if (!mounted) return;
      final socketFresh =
          _routeMetricsFromSocket &&
          DateTime.now().difference(_routeMetricsFromSocketAt) <
              const Duration(seconds: 75);
      setState(() {
        if (!socketFresh) {
          _routeMeters = meters;
          _routeSeconds = seconds;
          _routeMetricsFromSocket = false;
        }
        _polylines = {
          Polyline(
            polylineId: PolylineId(
              driverStartedRide ? "driver_to_drop" : "driver_to_pickup",
            ),
            points: points,
            color: Colors.black,
            width: 4,
          ),
        };
      });
    } else {
      print("❗ Error fetching directions: ${data['status']}");
    }
    _isDrawingPolyline = false;
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }

    return points;
  }

  String _formatDistance(double meters) {
    if (meters.isNaN || meters.isInfinite) return '';
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '';
    final mins = (seconds / 60).round();
    if (mins <= 1) return '1 min';
    if (mins < 60) return '$mins min';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  final DriverSearchController driverSearchController = Get.put(
    DriverSearchController(),
  );

  void _onUserMapGesture() {
    _pauseAutoFollowUntil = DateTime.now().add(_userGesturePause);
  }

  void _maybeAutoFollow(LatLng target) {
    if (!_autoFollowEnabled) return;
    final now = DateTime.now();
    if (now.isBefore(_pauseAutoFollowUntil)) return;
    if (now.difference(_lastCameraMoveAt) < _cameraInterval) return;
    _lastCameraMoveAt = now;

    try {
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: target,
            zoom: _currentZoomLevel,
            bearing: 0,
            tilt: 0,
          ),
        ),
      );
    } catch (_) {}
  }

  bool _shouldUpdatePolyline(String polyId, {bool force = false}) {
    if (force) {
      _activePolyId = polyId;
      _lastPolylineAt = DateTime.now();
      return true;
    }

    final now = DateTime.now();
    final byId = _activePolyId != polyId;
    final byTime = now.difference(_lastPolylineAt) >= _polylineInterval;
    if (!byId && !byTime) return false;

    _activePolyId = polyId;
    _lastPolylineAt = now;
    return true;
  }

  void _maybeUpdatePolyline(LatLng driverLatLng, {bool force = false}) {
    final customerTarget = driverStartedRide ? _customerToLatLang : _customerLatLng;
    if (customerTarget == null) return;

    final polyId = driverStartedRide ? "driver_to_drop" : "driver_to_pickup";
    if (!_shouldUpdatePolyline(polyId, force: force)) return;

    _drawPolylineFromDriverToCustomer(
      driverLatLng: driverLatLng,
      customerLatLng: customerTarget,
    );
  }

  void _enqueueDriverMove(LatLng to) {
    final from = _currentDriverLatLng;
    if (from == null) {
      _currentDriverLatLng = to;
      _updateDriverMarker(to, _lastBearing);
      _maybeAutoFollow(to);
      _maybeUpdatePolyline(to, force: true);
      return;
    }

    final dist = Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );

    if (dist < _minMoveMeters) return;

    if (dist > _hardJumpMeters) {
      _currentDriverLatLng = to;
      _lastBearing = _getBearing(from, to);
      _updateDriverMarker(to, _lastBearing);
      _maybeAutoFollow(to);
      _maybeUpdatePolyline(to, force: true);
      return;
    }

    if (_isAnimatingDriver) {
      _pendingDriverTarget = to;
      return;
    }

    _animateDriverSegment(from: from, to: to);
  }

  Future<void> _animateDriverSegment({required LatLng from, required LatLng to}) async {
    _isAnimatingDriver = true;

    final dist = Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
    final steps = (6 + (dist / 10).clamp(0, 10)).round().clamp(8, 16);
    final durationMs = (450 + (dist / 2).clamp(0, 650)).round().clamp(450, 1100);
    final interval = Duration(milliseconds: (durationMs / steps).round());

    for (int i = 1; i <= steps; i++) {
      await Future.delayed(interval);
      if (!mounted) break;

      final t = i / steps;
      final lat = _lerp(from.latitude, to.latitude, t);
      final lng = _lerp(from.longitude, to.longitude, t);
      final pos = LatLng(lat, lng);

      final bearing = _getBearing(from, pos);
      _lastBearing = bearing;
      _updateDriverMarker(pos, bearing);
      _maybeAutoFollow(pos);
    }

    _currentDriverLatLng = to;
    _isAnimatingDriver = false;

    _maybeUpdatePolyline(to);

    final pending = _pendingDriverTarget;
    if (pending != null) {
      _pendingDriverTarget = null;
      if (mounted) {
        await _animateDriverSegment(from: to, to: pending);
      }
    }
  }

  @override
  void dispose() {
    try {
      socketService.off('joined-booking');
      socketService.off('driver-location');
      socketService.off('driver-arrived');
      socketService.off('otp-generated');
      socketService.off('ride-started');
      socketService.off('driver-reached-destination');
      socketService.off('customer-cancelled');
      socketService.off('driver-cancelled');
    } catch (_) {}

    _pulseTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NoInternetOverlay(
      child: WillPopScope(
        onWillPop: () async {
          return await false;
        },
        child: Scaffold(
          body: Stack(
            children: [
               SizedBox(
                height: 550,
                width: double.infinity,
                child: GoogleMap(
                  compassEnabled: true,
                  rotateGesturesEnabled: false,
                  tiltGesturesEnabled: false,
                  buildingsEnabled: false,
                  indoorViewEnabled: false,
                  minMaxZoomPreference: const MinMaxZoomPreference(11.0, 17.0),
                  circles: _circles,
                  onCameraMove:
                      (pos) =>
                          _currentZoomLevel =
                              pos.zoom.clamp(11.0, 17.0).toDouble(),
                  onCameraMoveStarted: _onUserMapGesture,
                  onTap: (_) => _onUserMapGesture(),
                  initialCameraPosition: CameraPosition(
                    target: _currentPosition ?? LatLng(9.9144908, 78.0970899),
                    zoom: _currentZoomLevel,
                  ),
                  markers: _markers,
                  onMapCreated: (controller) async {
                    _mapController = controller;
                    String style = await DefaultAssetBundle.of(
                      context,
                    ).loadString('assets/map_style/map_style1.json');
                    _mapController?.setMapStyle(style);

                    if (_currentPosition != null) {
                      _mapController?.moveCamera(
                        CameraUpdate.newCameraPosition(
                          CameraPosition(
                            target: _currentPosition!,
                            zoom: _currentZoomLevel,
                            bearing: 0,
                            tilt: 0,
                          ),
                        ),
                      );
                    }
                  },
                  polylines: _polylines,
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  gestureRecognizers: {
                    Factory<OneSequenceGestureRecognizer>(
                      () => EagerGestureRecognizer(),
                    ),
                  },
                ),
              ),
              Positioned(
                top: 350,
                right: 10,
                child: FloatingActionButton(
                  mini: true,
                  backgroundColor: Colors.white,
                  onPressed: _goToCurrentLocation,
                  child: Icon(Icons.my_location, color: Colors.black),
                ),
              ),
              Positioned(
                top: 50,
                right: 15,
                child: GestureDetector(
                  onTap: () async {
                    try {
                      final prefs = await SharedPreferences.getInstance();
                      String? sosNumber = prefs.getString('sosNumber');

                      if (sosNumber == null || sosNumber.trim().isEmpty) {
                        AppToasts.showError(context,'SOS number not set');
                        return;
                      }

                      // Keep leading + if present; remove spaces and other junk
                      sosNumber = sosNumber.trim();
                      final hasPlus = sosNumber.startsWith('+');
                      final digitsOnly = sosNumber.replaceAll(
                        RegExp(r'[^0-9]'),
                        '',
                      );
                      final normalized = hasPlus ? '+$digitsOnly' : digitsOnly;

                      if (normalized.isEmpty) {
                        AppToasts.showError(context,'Invalid SOS number');
                        return;
                      }

                      final Uri telUri = Uri(scheme: 'tel', path: normalized);

                      // Try opening the dialer
                      final ok = await launchUrl(
                        telUri,
                        mode:
                            LaunchMode.externalApplication, // opens dialer app
                      );

                      if (!ok) {
                        AppToasts.showError(context,'Could not open dialer');
                      }
                    } catch (e) {
                      AppToasts.showError(context,'Failed to start call');
                    }
                  },

                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 2),
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
 
              DraggableScrollableSheet(
                key: ValueKey(_isDriverConfirmed),

                initialChildSize: _isDriverConfirmed ? 0.55 : 0.4,
                minChildSize: 0.3,
                maxChildSize: _isDriverConfirmed ? 0.90 : 0.5,
                builder: (context, scrollController) {
                  return Container(
                    decoration: BoxDecoration(color: Colors.white),
                    child: SafeArea(
                      top: false,
                      child: ListView(
                        physics: BouncingScrollPhysics(),
                        controller: scrollController,
                        padding: EdgeInsets.only(top: 15),
                        children: [
                          SizedBox(height: 20),
                          if (!_isDriverConfirmed && isWaitingForDriver) ...[
                          
                            waitingForDriverUI(),
                          ] else if (!_isDriverConfirmed && noDriverFound) ...[
                            noDriverFoundUI(),
                          ] else ...[
                            if (isTripCancelled)
                              Container(
                                padding: const EdgeInsets.all(10),
                                margin: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.red.shade200,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.cancel, color: Colors.red),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            "Your trip has been cancelled",
                                            style: TextStyle(
                                              color: Colors.red,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            cancelReason,
                                            style: const TextStyle(
                                              color: Colors.red,
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

                            Divider(
                              thickness: 2,
                              color: AppColors.dividerColor1,
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 15,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Column(
                                        spacing: 5,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          CustomTextFields.textWithStylesSmall(
                                            'PKG - ${BookingId}',
                                            colors: AppColors.commonBlack,
                                            fontWeight: FontWeight.w500,
                                          ),

                                          Row(
                                            children: [
                                              ClipOval(
                                                child: Image.network(
                                                  ProfilePic,
                                                  fit: BoxFit.cover,
                                                  height: 40,
                                                  width: 40,
                                                ),
                                              ),
                                              SizedBox(width: 5),
                                              CustomTextFields.textWithStylesSmall(
                                                fontSize: 14,
                                                driverName,
                                                colors: AppColors.commonBlack,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              // SizedBox(width: 5),
                                              // Image.asset(
                                              //   AppImages.star,
                                              //   width: 13,
                                              //   height: 13,
                                              // ),
                                              // SizedBox(width: 5),
                                              // CustomTextFields.textWithStyles600(
                                              //   '4.5',
                                              // ),
                                            ],
                                          ),
                                          CustomTextFields.textWithStylesSmall(
                                            fontWeight: FontWeight.w500,
                                            fontSize: 14,
                                            'Vehicle: Bike ($plateNumber)',
                                            colors:
                                                AppColors
                                                    .rideShareContainerColor2,
                                          ),
                                        ],
                                      ),
                                      Spacer(),
                                      Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            50,
                                          ),
                                          color:
                                              AppColors.chatCallContainerColor,
                                        ),

                                        child: Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: InkWell(
                                            onTap: () async {
                                              const phoneNumber =
                                                  'tel:8248191110';
                                              AppLogger.log.i(phoneNumber);
                                              final Uri url = Uri.parse(
                                                phoneNumber,
                                              );
                                              if (await canLaunchUrl(url)) {
                                                await launchUrl(url);
                                              } else {
                                                print(
                                                  'Could not launch dialer',
                                                );
                                              }
                                            },
                                            child: Image.asset(
                                              AppImages.chatCall,
                                              height: 20,
                                              width: 20,
                                            ),
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 10),
                                      Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            50,
                                          ),
                                          color: AppColors.chatBlueColor,
                                        ),

                                        child: Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: InkWell(
                                            onTap: () async {
                                              Get.to(ChatScreen(bookingId: ''));
                                            },
                                            child: Image.asset(
                                              AppImages.chat,
                                              height: 20,
                                              width: 20,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (otp.isNotEmpty &&
                                      !driverStartedRide &&
                                      !destinationReached) ...[
                                    _otpHighlightCard(),
                                    const SizedBox(height: 16),
                                  ],
                               

                                  GestureDetector(
                                    onTap: () {},
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        color: AppColors.chatBlueColor
                                            .withOpacity(0.5),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 17,
                                        ),
                                        child: Column(
                                          children: [
                                            Row(
                                              children: [
                                                Image.asset(
                                                  AppImages.direction,
                                                  height: 20,
                                                  width: 20,
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    _estimateStt1,
                                                    softWrap: true,
                                                    style: const TextStyle(
                                                      color: AppColors.commonBlack,
                                                      fontWeight: FontWeight.w600,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Row(
                                              children: [
                                                const SizedBox(width: 30),
                                                Expanded(
                                                  child: CustomTextFields.textWithStylesSmall(
                                                    maxLines: null,
                                                    overflow: TextOverflow.visible,
                                                    fontWeight: FontWeight.w500,
                                                    colors:
                                                        _isDriverConfirmed
                                                            ? AppColors
                                                                .changeButtonColor
                                                            : AppColors
                                                                .greyDark,
                                                    _estimateStt2,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (_routeMeters != null || _routeSeconds != null) ...[
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.route_outlined,
                                                size: 16,
                                                color: AppColors.commonBlack,
                                              ),
                                              const SizedBox(width: 6),
                                              CustomTextFields.textWithStylesSmall(
                                                [
                                                  if (_routeMeters != null)
                                                    _formatDistance(_routeMeters!),
                                                  if (_routeSeconds != null)
                                                    _formatDuration(_routeSeconds!),
                                                ].where((e) => e.trim().isNotEmpty).join(' • '),
                                                colors: AppColors.commonBlack,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 12,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],

                                  SizedBox(height: 25),
                                  _isOrderConfirmed && !_isPackageCollected
                                      ? PackageContainer.pickUpFields(
                                        imagePath: AppImages.clrTick1,
                                        title: 'Order Confirmed',
                                        subTitle:
                                            _estimateText().isNotEmpty
                                                ? _estimateText()
                                                : (_isEnRoute
                                                    ? 'Courier en route to pickup'
                                                    : 'Waiting for courier'),
                                      )
                                      : PackageContainer.pickUpFields(
                                        imagePath: AppImages.clrTick1,
                                        title: 'Package Collected',
                                        subTitle:
                                            _shortPlace(PickupAddress).isNotEmpty
                                                ? 'From ${_shortPlace(PickupAddress)}'
                                                : 'Package collected',
                                      ),
                                  const SizedBox(height: 10),
                                  _isEnRoute && !_isInTransit
                                      ? PackageContainer.pickUpFields(
                                        imagePath: AppImages.clrDirection,
                                        title: 'Courier En Route',
                                        subTitle:
                                            _estimateText().isNotEmpty
                                                ? _estimateText()
                                                : 'On the way',
                                      )
                                      : PackageContainer.pickUpFields(
                                        imagePath: AppImages.clrBox1,
                                        title: 'In Transit',
                                        subTitle:
                                            _shortPlace(DropAddress).isNotEmpty
                                                ? 'To ${_shortPlace(DropAddress)}'
                                                : 'In transit',
                                      ),
                                  const SizedBox(height: 10),
                                  _isPackagePickup && !_isOutForDelivery
                                      ? PackageContainer.pickUpFields(
                                        title1: 'Ready',
                                        imagePath: AppImages.box,
                                        title: 'Package Pickup',
                                        subTitle: 'Ready for Pickup',
                                      )
                                      : PackageContainer.pickUpFields(
                                        title1: 'Ready',
                                        imagePath: AppImages.clrHome,
                                        title: 'Out for Delivery',
                                        subTitle: 'Attempting delivery',
                                      ),

                                  SizedBox(height: 15),
                                  Divider(color: AppColors.dividerColor1),

                                  Row(
                                    children: [
                                      CustomTextFields.textWithStylesSmall(
                                        'Order ID',
                                        fontWeight: FontWeight.w500,
                                        fontSize: 15,
                                        colors: AppColors.commonBlack,
                                      ),
                                      Spacer(),
                                      CustomTextFields.textWithStylesSmall(
                                        'PKG- ${BookingId}',
                                        fontWeight: FontWeight.w500,
                                        fontSize: 12,
                                        colors: AppColors.commonBlack,
                                      ),
                                      SizedBox(width: 10),
                                      Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () {
                                            final textToCopy =
                                                'PKG- ${BookingId}';
                                            Clipboard.setData(
                                              ClipboardData(text: textToCopy),
                                            );

                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Copied: $textToCopy',
                                                ),
                                                duration: const Duration(
                                                  seconds: 1,
                                                ),
                                              ),
                                            );
                                          },
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ), // Match with Material
                                          splashColor: Colors.blue.withOpacity(
                                            0.3,
                                          ), // Splash effect color
                                          highlightColor: Colors.blue
                                              .withOpacity(
                                                0.1,
                                              ), // Highlight color on tap down
                                          child: Padding(
                                            padding: const EdgeInsets.all(8.0),
                                            child: Image.asset(
                                              AppImages.paste,
                                              height: 15,
                                              width: 15,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 5),
                                  Row(
                                    children: [
                                      CustomTextFields.textWithStylesSmall(
                                        'Package Weight',
                                        fontWeight: FontWeight.w500,
                                        fontSize: 15,
                                        colors: AppColors.commonBlack,
                                      ),
                                      Spacer(),
                                      CustomTextFields.textWithStylesSmall(
                                        '${MaxWeight} kg',
                                        fontWeight: FontWeight.w500,
                                        fontSize: 12,
                                        colors: AppColors.commonBlack,
                                      ),
                                    ],
                                  ),
                                  Divider(color: AppColors.dividerColor1),

                                  const SizedBox(height: 12),
                                  GestureDetector(
                                    onTap: () {
                                      Get.to(
                                        PaymentScreen(
                                          amount: Amount,
                                          bookingId: widget.bookingId,
                                        ),
                                      );
                                    },
                                    child: Card(
                                      elevation: 5,
                                      color: AppColors.commonWhite,
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 20),
                                        child: Column(
                                          children: [
                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                  ),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child:
                                                        CustomTextFields.textWithImage(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          fontSize: 13,
                                                          colors:
                                                              AppColors.commonBlack,
                                                          text: 'Total Fare',
                                                          rightImagePath:
                                                              AppImages
                                                                  .nBlackCurrency,
                                                          rightImagePathText:
                                                              ' ${Amount.toStringAsFixed(2)}',
                                                        ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Flexible(
                                                    child: Container(
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
                                                        color: AppColors
                                                            .commonBlack,
                                                      ),
                                                      child: CustomTextFields
                                                          .textWithStylesSmall(
                                                        'PKG - ${BookingId}',
                                                        maxLines: 1,
                                                        colors: AppColors
                                                            .commonWhite,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            SizedBox(height: 20),
                                             ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Stack(
                                    children: [
                                      Card(
                                        elevation: 5,
                                        color: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Column(
                                          children: [
                                            // Pickup Address
                                            Padding(
                                              padding: const EdgeInsets.all(
                                                16.0,
                                              ),
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 2,
                                                        ),
                                                    child: Icon(
                                                      Icons.circle,
                                                      color: Colors.green,
                                                      size: 12,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          'Pickup Address',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 14,
                                                          ),
                                                        ),
                                                        SizedBox(height: 4),
                                                        Text(
                                                          PickupAddress,
                                                          style: TextStyle(
                                                            color:
                                                                Colors.black54,
                                                            fontSize: 13,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                            Divider(
                                              height: 0,
                                              color: Colors.grey[200],
                                            ),

                                            // Delivery Address
                                            Padding(
                                              padding: const EdgeInsets.all(
                                                16.0,
                                              ),
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 5,
                                                        ),
                                                    child: Icon(
                                                      Icons.circle,
                                                      color: Colors.orange,
                                                      size: 12,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          'Delivery Address',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 14,
                                                          ),
                                                        ),
                                                        SizedBox(height: 4),
                                                        Text(
                                                          DropAddress,
                                                          style: TextStyle(
                                                            color:
                                                                Colors.black54,
                                                            fontSize: 13,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                            Divider(
                                              height: 0,
                                              color: Colors.grey[300],
                                            ),

                                            Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 35,
                                                    vertical: 10,
                                                  ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Obx(() {
                                                    final loading =
                                                        driverSearchController
                                                            .isCancelLoading
                                                            .value;
                                                    final canCancel =
                                                        !loading &&
                                                        !destinationReached &&
                                                        !isTripCancelled;
                                                    return GestureDetector(
                                                      onTap:
                                                          canCancel
                                                              ? () {
                                                                AppLogger.log.i(
                                                                  BookingId,
                                                                );

                                                                AppButtons
                                                                    .showPackageCancelBottomSheet(
                                                                  context,
                                                                  onConfirmCancel: (
                                                                    String
                                                                    selectedReason,
                                                                  ) {
                                                                    return driverSearchController
                                                                        .cancelRide(
                                                                      bookingId:
                                                                          BookingId
                                                                              .toString(),
                                                                      selectedReason:
                                                                          selectedReason,
                                                                      context:
                                                                          context,
                                                                    );
                                                                  },
                                                                );
                                                              }
                                                              : null,
                                                      child: Row(
                                                        children: [
                                                          if (loading)
                                                            SizedBox(
                                                              width: 16,
                                                              height: 16,
                                                              child:
                                                                  CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                                valueColor:
                                                                    AlwaysStoppedAnimation<
                                                                      Color
                                                                    >(Colors.red),
                                                              ),
                                                            )
                                                          else
                                                            Icon(
                                                              Icons.close,
                                                              color: Colors.red,
                                                              size: 16,
                                                            ),
                                                          const SizedBox(
                                                            width: 5,
                                                          ),
                                                          Text(
                                                            loading
                                                                ? 'Cancelling...'
                                                                : 'Cancel Courier',
                                                            style: const TextStyle(
                                                              color: Colors.red,
                                                              fontWeight:
                                                                  FontWeight.w500,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                  }),
                                                  Expanded(
                                                    child: Container(
                                                      height:
                                                          24, // Set the height you need
                                                      child: VerticalDivider(
                                                        color: Colors.grey,
                                                        thickness: 1,
                                                      ),
                                                    ),
                                                  ),
                                                  Row(
                                                    children: [
                                                      const Icon(
                                                        Icons.support_agent_rounded,
                                                        size: 18,
                                                        color: Colors.black,
                                                      ),
                                                      const SizedBox(width: 5),
                                                      Text(
                                                        'Support',
                                                        style: const TextStyle(
                                                          color: Colors.black,
                                                          fontWeight:
                                                              FontWeight.w500,
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

                                      Positioned(
                                        top: 37,
                                        left: 25,
                                        child: DottedLine(
                                          direction: Axis.vertical,
                                          lineLength: 80,
                                          dashLength: 4,
                                          dashColor: AppColors.dotLineColor,
                                        ),
                                      ),
                                    ],
                                  ),

                                  SizedBox(height: 20),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
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
        Text(
          textAlign: TextAlign.center,
          'Looking for the best drivers for you',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 12),
        LinearProgressIndicator(
          borderRadius: BorderRadius.circular(10),
          minHeight: 7,
          backgroundColor: AppColors.linearIndicatorColor.withOpacity(0.2),
          color: AppColors.linearIndicatorColor,
        ),
        SizedBox(height: 20),
        Image.asset(
          AppImages.packageLoading,
          height: 100,
          width: 100,
          fit: BoxFit.contain,
        ),
        SizedBox(height: 20),

        SizedBox(height: 20),
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
                              driverSearchController.cancelRide(
                                bookingId: widget.bookingId.toString(),
                                selectedReason: selectedReason,
                                context: context,
                              );
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
        //     // setState(() {
        //     //   isDriverConfirmed = !isDriverConfirmed;
        //     // });
        //     AppButtons.showCancelRideBottomSheet(
        //       context,
        //       onConfirmCancel: (String selectedReason) {
        //         print(widget.bookingId);
        //         driverSearchController.cancelRide(
        //           bookingId: widget.bookingId.toString() ?? '',
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
            "We couldn’t find any available drivers nearby.\nPlease try again in a few minutes.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 30),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 15),
            child: Column(
              children: [
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
                    setState(() {
                      isWaitingForDriver = true;
                      noDriverFound = false;
                    });
                    String? result = await packageController
                        .sendPackageDriverRequest(
                          discountCode: widget.discountCode ?? '',
                          bookingId: widget.bookingId,
                          receiverData: widget.receiverData,
                          senderData: widget.senderData,
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
          ),
        ],
      ),
    );
  }
}

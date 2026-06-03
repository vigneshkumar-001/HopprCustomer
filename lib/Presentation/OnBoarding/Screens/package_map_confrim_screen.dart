import 'package:hopper/Core/Utility/app_toasts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:hopper/Presentation/OnBoarding/Controller/package_controller.dart';
import 'package:hopper/Presentation/OnBoarding/Screens/chat_screen.dart';
import 'package:dotted_line/dotted_line.dart';

import 'package:hopper/Presentation/OnBoarding/Widgets/custom_bottomnavigation.dart';
import 'package:hopper/Presentation/OnBoarding/Widgets/package_contoiner.dart';
import 'package:hopper/Presentation/OnBoarding/models/address_models.dart';
import 'package:hopper/uitls/netWorkHandling/network_handling_screen.dart';
import 'package:hopper/uitls/map/map_ui_defaults.dart';
import 'package:flutter/foundation.dart';
import 'package:hopper/Presentation/OnBoarding/Screens/payment_screen.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Utility/app_buttons.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Core/Utility/phone_launcher.dart';
import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
import 'package:hopper/uitls/websocket/socket_io_client.dart';
import 'package:hopper/uitls/map/compact_marker_icons.dart';
import 'package:hopper/uitls/map/driver_motion_engine.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:hopper/uitls/map/route_tracking_math.dart';
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

class _PackageMapConfirmScreenState extends State<PackageMapConfirmScreen>
    with TickerProviderStateMixin {
  bool isExpanded = false;
  GoogleMapController? _mapController;
  final socketService = SocketService();
  LatLng? _currentPosition;
  final ValueNotifier<Set<Polyline>> _polylinesNotifier =
      ValueNotifier<Set<Polyline>>(<Polyline>{});
  BitmapDescriptor? _carIcon;
  BitmapDescriptor? _pickupPinIcon;
  BitmapDescriptor? _dropPinIcon;
  BitmapDescriptor? _pickupWaitingLabelIcon;
  BitmapDescriptor? _pickupLabelIcon;
  BitmapDescriptor? _dropLabelIcon;
  final ValueNotifier<Set<Marker>> _markersNotifier =
      ValueNotifier<Set<Marker>>(<Marker>{});
  Set<Circle> _circles = {};
  bool _isDriverConfirmed = false;
  Marker? _driverMarker;
  Timer? _driverMarkerFlushTimer;
  LatLng? _pendingDriverMarkerPos;
  double? _pendingDriverMarkerBearing;
  DateTime _lastDriverMarkerCommitAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _driverMarkerMinInterval = Duration(milliseconds: 90);
  bool driverStartedRide = false;
  bool destinationReached = false;
  bool _autoFollowEnabled = true;
  final ValueNotifier<bool> _isFollowingNotifier = ValueNotifier<bool>(true);
  bool _locationToggleFit = false;
  bool _didFitDriverToPickup = false;
  bool _didFitDriverToDrop = false;
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
  String cancelTitle = "";

  double? _routeMeters;
  int? _routeSeconds;
  bool _routeMetricsFromSocket = false;
  DateTime _routeMetricsFromSocketAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _navigatedToPayment = false;
  Timer? _paymentNavTimer;
  String _vehicleType = '';

  static const double _preferredInitialZoom = 16.4;
  static const double _minFollowZoom = 15.8;

  Widget _driverAvatar() {
    final raw = ProfilePic.trim();
    final isHttp = raw.startsWith('http://') || raw.startsWith('https://');
    if (!isHttp) {
      return CircleAvatar(
        radius: 20,
        backgroundColor: Colors.grey.shade300,
        child: const Icon(Icons.person, color: Colors.white),
      );
    }

    return Image.network(
      raw,
      fit: BoxFit.cover,
      height: 40,
      width: 40,
      errorBuilder: (_, __, ___) {
        return CircleAvatar(
          radius: 20,
          backgroundColor: Colors.grey.shade300,
          child: const Icon(Icons.person, color: Colors.white),
        );
      },
      // Avoid unnecessary decode work on scrolling rebuilds.
      filterQuality: FilterQuality.low,
    );
  }

  bool _isTruthy(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().trim().toLowerCase();
    if (s.isEmpty) return false;
    return s == 'true' || s == '1' || s == 'yes' || s == 'y';
  }

  int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  DateTime _parseServerTime(dynamic ts) {
    try {
      if (ts == null) return DateTime.now();
      if (ts is int) {
        // seconds (10-digit) vs milliseconds (13-digit)
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

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
    return const <String, dynamic>{};
  }

  Map<String, dynamic> _normalizeSocketPayload(dynamic data) {
    try {
      // socket.io can send ACK style payloads: [payload, (ackFn)].
      if (data is List) {
        for (final item in data) {
          final m = _normalizeSocketPayload(item);
          if (m.isNotEmpty) return m;
        }
        return const <String, dynamic>{};
      }
      if (data is String) {
        final decoded = json.decode(data);
        return _normalizeSocketPayload(decoded);
      }
      return _asMap(data);
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  String _normalizePhone(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    final hasPlus = s.startsWith('+');
    final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 6) return '';
    return hasPlus ? '+$digits' : digits;
  }

  String _extractDriverPhone(Map<String, dynamic> payload) {
    try {
      final direct =
          (payload['driverPhone'] ??
                  payload['driver_phone'] ??
                  payload['phone'] ??
                  payload['mobile'] ??
                  payload['driverMobile'] ??
                  payload['driver_mobile'])
              ?.toString() ??
          '';
      final normalizedDirect = _normalizePhone(direct);
      if (normalizedDirect.isNotEmpty) return normalizedDirect;

      final driverRaw = payload['driver'] ?? payload['driverDetails'];
      if (driverRaw is Map) {
        final m = Map<String, dynamic>.from(driverRaw as Map);
        final v =
            (m['phone'] ??
                    m['mobile'] ??
                    m['driverPhone'] ??
                    m['driver_phone'] ??
                    m['driverMobile'])
                ?.toString() ??
            '';
        final normalizedNested = _normalizePhone(v);
        if (normalizedNested.isNotEmpty) return normalizedNested;
      }
    } catch (_) {}
    return '';
  }

  String _extractCancelTitle(dynamic payload, {required String fallback}) {
    final data = _asMap(payload);
    final title = (data['title'] ?? '').toString().trim();
    if (title.isNotEmpty) return title;

    final cancelledBy =
        (data['cancelledBy'] ?? data['canceledBy'] ?? '').toString().trim();
    if (cancelledBy.isNotEmpty) {
      final who = cancelledBy.toLowerCase();
      if (who.contains('driver')) return 'Driver cancelled';
      if (who.contains('customer') || who.contains('user')) {
        return 'Booking cancelled';
      }
      return 'Cancelled';
    }

    return fallback;
  }

  String _extractCancelReason(dynamic payload, {required String fallback}) {
    final data = _asMap(payload);
    final v =
        data['reason'] ??
        data['message'] ??
        data['cancelReason'] ??
        data['cancellationReason'] ??
        data['remarks'];
    final s = (v ?? '').toString().trim();
    return s.isNotEmpty ? s : fallback;
  }

  Timer? _pulseTimer;
  double _pulsePhase = 0.0;

  late final AnimationController _searchingAnimController;
  Timer? _searchingElapsedTimer;
  int _searchingElapsedSeconds = 0;

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
    final parts =
        s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    if (parts.length >= 3) {
      // city, state/region
      return '${parts[parts.length - 3]}, ${parts[parts.length - 2]}';
    }
    if (parts.length >= 2) return '${parts[parts.length - 2]}, ${parts.last}';
    return parts.first;
  }

  void _navigateToPayment({required bool replace}) {
    if (_navigatedToPayment) return;
    _paymentNavTimer?.cancel();
    _paymentNavTimer = null;

    _navigatedToPayment = true;
    final id =
        (BookingId.trim().isNotEmpty ? BookingId : widget.bookingId).trim();

    final screen = PaymentScreen(
      bookingId: id,
      amount: Amount,
      sender: widget.senderData,
      receiver: widget.receiverData,
      driverName: driverName,
      driverProfilePic: ProfilePic,
    );

    if (replace) {
      Get.off(() => screen);
    } else {
      Get.to(() => screen);
    }
  }

  void _schedulePaymentNavigation({
    required Duration delay,
    required bool replace,
  }) {
    if (_navigatedToPayment) return;
    _paymentNavTimer?.cancel();
    _paymentNavTimer = Timer(delay, () {
      if (!mounted) return;
      _navigateToPayment(replace: replace);
    });
  }

  bool _isDestinationReachedPayload(dynamic data) {
    if (data == null) return false;
    if (data is bool) return data;

    if (data is String) {
      final s = data.trim().toLowerCase();
      if (s.isEmpty) return false;
      if (s == 'false' || s == '0' || s == 'no' || s == 'n') return false;
      // common server status strings
      if (s.contains('reach') || s.contains('arriv')) return true;
      if (s.contains('complete') || s.contains('delivered')) return true;
      if (s.contains('success') || s.contains('ok')) return true;
    }

    final payload = _asMap(data);
    final status = payload['status'];
    if (_isTruthy(status)) return true;
    if (status is String) {
      final s = status.trim().toLowerCase();
      if (s.contains('reach') || s.contains('arriv')) return true;
      if (s.contains('complete') || s.contains('delivered')) return true;
      if (s.contains('success') || s.contains('ok')) return true;
    }

    return _isTruthy(payload['destinationReached']) ||
        _isTruthy(payload['driverReachedDestination']) ||
        _isTruthy(payload['reached']);
  }

  Future<void> _loadCustomMarkerForVehicle(String vehicleType) async {
    final asset = AppImages.packageBike;

    try {
      final dpr = ui.window.devicePixelRatio;
      final icon = await CompactMarkerIcons.assetContained(
        assetPath: asset,
        sizeDp: MapUiDefaults.vehicleBadgeDiameterDp,
        dpr: dpr,
      );
      if (!mounted) return;
      setState(() => _carIcon = icon);
      final pos = _currentDriverLatLng;
      if (pos != null) _updateDriverMarker(pos, _lastBearing);
    } catch (_) {}
  }

  Future<void> _loadPickupDropIcons() async {
    try {
      _pickupPinIcon = await CompactMarkerIcons.assetPin(
        assetPath: AppImages.pinLocation,
        widthDp: MapUiDefaults.pickupDropPinWidthDp,
      );
    } catch (_) {
      _pickupPinIcon = null;
    }
    try {
      _dropPinIcon = await CompactMarkerIcons.assetPin(
        assetPath: AppImages.rectangleDest,
        widthDp: MapUiDefaults.pickupDropPinWidthDp,
      );
    } catch (_) {
      _dropPinIcon = null;
    }
    try {
      _pickupWaitingLabelIcon = await CompactMarkerIcons.labeledPin(
        label: MapUiDefaults.placeLabel(PickupAddress, fallback: 'Pickup'),
        assetPath: AppImages.pinLocation,
        bubbleWidthDp: MapUiDefaults.pickupDropBubbleWidthDp,
        bubbleHeightDp: MapUiDefaults.pickupDropBubbleHeightDp,
        pinWidthDp: MapUiDefaults.pickupDropPinWidthDp,
        fontSizeDp: MapUiDefaults.pickupDropFontSizeDp,
        textAlign: TextAlign.left,
      );
    } catch (_) {
      _pickupWaitingLabelIcon = _pickupPinIcon;
    }
    try {
      _pickupLabelIcon = await CompactMarkerIcons.labeledPin(
        label: MapUiDefaults.placeLabel(PickupAddress, fallback: 'Pickup'),
        assetPath: AppImages.pinLocation,
        bubbleWidthDp: MapUiDefaults.pickupDropBubbleWidthDp,
        bubbleHeightDp: MapUiDefaults.pickupDropBubbleHeightDp,
        pinWidthDp: MapUiDefaults.pickupDropPinWidthDp,
        fontSizeDp: MapUiDefaults.pickupDropFontSizeDp,
        textAlign: TextAlign.left,
      );
    } catch (_) {
      _pickupLabelIcon = _pickupPinIcon;
    }
    try {
      _dropLabelIcon = await CompactMarkerIcons.labeledPin(
        label: MapUiDefaults.placeLabel(DropAddress, fallback: 'Drop'),
        assetPath: AppImages.rectangleDest,
        bubbleWidthDp: MapUiDefaults.pickupDropBubbleWidthDp,
        bubbleHeightDp: MapUiDefaults.pickupDropBubbleHeightDp,
        pinWidthDp: MapUiDefaults.pickupDropPinWidthDp,
        fontSizeDp: MapUiDefaults.pickupDropFontSizeDp,
        textAlign: TextAlign.left,
      );
    } catch (_) {
      _dropLabelIcon = _dropPinIcon;
    }
  }

  Widget _buildPickupDeliveryStatusCard() {
    final est = _estimateText();
    final pickedUp = _isPackageCollected || _isInTransit || _isOutForDelivery;

    if (_isOutForDelivery) {
      return PackageContainer.pickUpFields(
        title1: 'Ready',
        imagePath: AppImages.clrHome,
        title: 'Out for Delivery',
        subTitle: est.isNotEmpty ? est : 'Delivering to destination',
      );
    }

    if (pickedUp) {
      return PackageContainer.pickUpFields(
        title1: 'Ready',
        imagePath: AppImages.box,
        title: 'Picked Up',
        subTitle:
            _shortPlace(PickupAddress).isNotEmpty
                ? 'From ${_shortPlace(PickupAddress)}'
                : (est.isNotEmpty ? est : 'Package picked up'),
      );
    }

    if (_isPackagePickup) {
      return PackageContainer.pickUpFields(
        title1: 'Ready',
        imagePath: AppImages.box,
        title: 'Package Pickup',
        subTitle: est.isNotEmpty ? est : 'Ready for pickup',
      );
    }

    return PackageContainer.pickUpFields(
      title1: 'Ready',
      imagePath: AppImages.box,
      title: 'Pickup Pending',
      subTitle: est.isNotEmpty ? est : 'Waiting for pickup',
    );
  }

  Future<void> _seedPickupDropMarkers() async {
    final pickup = _customerLatLng;
    final drop = _customerToLatLang;
    if (pickup == null && drop == null) return;

    final showPickup = !driverStartedRide && !destinationReached;
    final showDrop = driverStartedRide || destinationReached;

    final next = <Marker>{
      ..._markersNotifier.value.where(
        (m) =>
            m.markerId != const MarkerId("pickup_marker") &&
            m.markerId != const MarkerId("drop_marker"),
      ),
    };

    if (showPickup && pickup != null) {
      next.add(
        Marker(
          markerId: const MarkerId("pickup_marker"),
          position: pickup,
          icon:
              (isWaitingForDriver && !_isDriverConfirmed
                  ? _pickupWaitingLabelIcon
                  : _pickupLabelIcon) ??
              _pickupPinIcon ??
              BitmapDescriptor.defaultMarkerWithHue(
                MapUiDefaults.pickupDropMarkerHueGreen,
              ),
          infoWindow: InfoWindow.noText,
          anchor: const Offset(0.5, 1.0),
        ),
      );
    }

    if (showDrop && drop != null) {
      next.add(
        Marker(
          markerId: const MarkerId("drop_marker"),
          position: drop,
          icon:
              _dropLabelIcon ??
              _dropPinIcon ??
              BitmapDescriptor.defaultMarkerWithHue(
                MapUiDefaults.pickupDropMarkerHueRed,
              ),
          infoWindow: InfoWindow.noText,
          anchor: const Offset(0.5, 1.0),
        ),
      );
    }

    if (!mounted) return;
    _markersNotifier.value = next.toSet();

    if (_mapController == null) return;

    try {
      final target = pickup ?? drop;
      if (target == null) return;
      final zoom = math.max(_currentZoomLevel, _preferredInitialZoom);
      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: target, zoom: zoom, bearing: 0, tilt: 0),
        ),
      );
    } catch (_) {}
  }

  void _syncPhaseMarkers() {
    final pickup = _customerLatLng;
    final drop = _customerToLatLang;
    final showPickup = !driverStartedRide && !destinationReached;
    final showDrop = driverStartedRide || destinationReached;

    final next = <Marker>{
      ..._markersNotifier.value.where(
        (m) =>
            m.markerId != const MarkerId("pickup_marker") &&
            m.markerId != const MarkerId("drop_marker") &&
            m.markerId != const MarkerId("driver_marker"),
      ),
    };

    if (_driverMarker != null) next.add(_driverMarker!);

    if (showPickup && pickup != null) {
      next.add(
        Marker(
          markerId: const MarkerId("pickup_marker"),
          position: pickup,
          icon:
              (isWaitingForDriver && !_isDriverConfirmed
                  ? _pickupWaitingLabelIcon
                  : _pickupLabelIcon) ??
              _pickupPinIcon ??
              BitmapDescriptor.defaultMarkerWithHue(
                MapUiDefaults.pickupDropMarkerHueGreen,
              ),
          infoWindow: InfoWindow.noText,
          anchor: const Offset(0.5, 1.0),
        ),
      );
    }

    if (showDrop && drop != null) {
      next.add(
        Marker(
          markerId: const MarkerId("drop_marker"),
          position: drop,
          icon:
              _dropLabelIcon ??
              _dropPinIcon ??
              BitmapDescriptor.defaultMarkerWithHue(
                MapUiDefaults.pickupDropMarkerHueRed,
              ),
          infoWindow: InfoWindow.noText,
          anchor: const Offset(0.5, 1.0),
        ),
      );
    }

    if (!mounted) return;
    _markersNotifier.value = next.toSet();

    if (kDebugMode) {
      AppLogger.log.i(
        'pkg map markers updated: count=${_markersNotifier.value.length} hasDriver=${_driverMarker != null} hasPolyline=${_polylinesNotifier.value.isNotEmpty}',
      );
    }
  }

  bool _isValidCoordinate(LatLng p) {
    if (p.latitude.abs() < 0.000001 && p.longitude.abs() < 0.000001)
      return false;
    if (p.latitude < -90 || p.latitude > 90) return false;
    if (p.longitude < -180 || p.longitude > 180) return false;
    return true;
  }

  double? _parseBearingDeg(dynamic v) {
    final d = _toDouble(v);
    if (d == null) return null;
    if (!d.isFinite) return null;
    final norm = (d % 360 + 360) % 360;
    return norm;
  }

  /// Google Directions supported modes: driving, walking, bicycling, transit.
  /// For "bike", we first try bicycling and fall back to driving if needed.
  String _preferredRouteMode() {
    final t = _vehicleType.toString().trim().toLowerCase();
    if (t.contains('bike') || t.contains('two')) return 'bicycling';
    return 'driving';
  }

  void _startPulseAnimation() {
    _pulseTimer?.cancel();
    _pulseTimer = Timer.periodic(const Duration(milliseconds: 650), (_) {
      _pulsePhase += 0.9;
      _updatePulseCircle();
    });
  }

  void _updatePulseCircle() {
    // Pulse should highlight the active target:
    // - Before pickup: pickup point
    // - After pickup (in transit): destination point
    final LatLng? center =
        (driverStartedRide || destinationReached)
            ? (_customerToLatLang ?? _currentDriverLatLng ?? _customerLatLng)
            : (_customerLatLng ?? _currentDriverLatLng ?? _customerToLatLang);
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
  double _currentZoomLevel = _preferredInitialZoom;
  DateTime _pauseAutoFollowUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastCameraMoveAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _cameraInterval = const Duration(milliseconds: 900);
  final Duration _userGesturePause = const Duration(seconds: 6);

  // ---------- smooth driver motion (production-grade) ----------
  late final DriverMotionEngine _motion;
  bool _motionReady = false;
  double _lastBearing = 0.0;
  DateTime _lastDriverLocationLogAt = DateTime.fromMillisecondsSinceEpoch(0);

  // ---------- polyline throttle ----------
  DateTime _lastPolylineAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _polylineInterval = const Duration(seconds: 25);
  String? _activePolyId;

  // ---------- reroute / off-route detection ----------
  List<LatLng> _activeRoutePoints = const <LatLng>[];
  DateTime _lastRouteFetchAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastOffRouteCheckAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _rerouteMinInterval = Duration(seconds: 20);
  static const Duration _offRouteCheckInterval = Duration(milliseconds: 700);
  static const double _offRouteThresholdMeters = 50.0;

  // ---------- route progress trim ----------
  int _lastTrimSegIndex = -1;
  DateTime _lastTrimAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _trimInterval = Duration(milliseconds: 450);
  static const double _trimMaxSnapMeters = 55.0;
  static const double _routeSnapToleranceMeters = 42.0;

  DateTime _lastBoundsAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _boundsInterval = Duration(seconds: 4);

  Future<void> _loadCustomMarker() async {
    await _loadCustomMarkerForVehicle(_vehicleType);
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
      _mapController?.animateCamera(
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

  Future<void> _goToCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
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
    } catch (_) {}
  }

  Future<void> _fitActiveBounds() async {
    if (_mapController == null) return;
    final driverPos = _currentDriverLatLng;
    final target = driverStartedRide ? _customerToLatLang : _customerLatLng;
    if (_activeRoutePoints.length >= 2) {
      try {
        await _animateBoundsSafe(
          focusPoints: [
            ..._activeRoutePoints,
            if (driverPos != null) driverPos,
            if (target != null) target,
          ],
        );
      } catch (_) {}
      return;
    }
    if (driverPos != null && target != null) {
      try {
        await _animateBoundsSafe(focusPoints: [driverPos, target]);
      } catch (_) {}
      return;
    }
    if (_customerLatLng == null || _customerToLatLang == null) return;
    try {
      await _animateBoundsSafe(
        focusPoints: [_customerLatLng!, _customerToLatLang!],
      );
    } catch (_) {}
  }

  Future<void> _onLocationFabTap() async {
    if (_mapController == null) return;

    // Explicit recenter -> re-enable auto-follow until user pans again.
    _autoFollowEnabled = true;
    _isFollowingNotifier.value = true;
    _pauseAutoFollowUntil = DateTime.fromMillisecondsSinceEpoch(0);
    if (_locationToggleFit) {
      _locationToggleFit = false;
      await _fitActiveBounds();
      return;
    }

    _locationToggleFit = true;
    final target = _currentDriverLatLng;
    if (target == null) {
      await _goToCurrentLocation();
      return;
    }
    try {
      _pauseAutoFollowUntil = DateTime.fromMillisecondsSinceEpoch(0);
      await _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: target,
            zoom: math.max(_currentZoomLevel, 17.6),
            bearing: 0,
            tilt: 0,
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> _fitDriverAndTargetOnce({required bool toDrop}) async {
    if (_mapController == null) return;
    final driverPos = _currentDriverLatLng;
    final target = toDrop ? _customerToLatLang : _customerLatLng;
    if (driverPos == null || target == null) return;

    if (toDrop) {
      if (_didFitDriverToDrop) return;
      _didFitDriverToDrop = true;
    } else {
      if (_didFitDriverToPickup) return;
      _didFitDriverToPickup = true;
    }

    try {
      if (_activeRoutePoints.length >= 2) {
        await _animateBoundsSafe(
          focusPoints: [..._activeRoutePoints, driverPos, target],
        );
      } else {
        await _animateBoundsSafe(focusPoints: [driverPos, target]);
      }
    } catch (_) {}
  }

  Future<void> _animateBoundsSafe({
    List<LatLng> focusPoints = const <LatLng>[],
  }) async {
    final controller = _mapController;
    if (controller == null) return;
    final pts = focusPoints;
    if (pts.length < 2) return;

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

    final diag = Geolocator.distanceBetween(minLat, minLng, maxLat, maxLng);
    final target = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    final zoom =
        diag <= 250
            ? 16.8
            : diag <= 700
            ? 16.0
            : diag <= 1500
            ? 15.2
            : diag <= 3000
            ? 14.4
            : diag <= 6000
            ? 13.7
            : 13.0;
    try {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: target, zoom: zoom, bearing: 0, tilt: 0),
        ),
      );
    } catch (_) {}
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

    // Seed pickup/drop immediately from the data we already have, so the
    // "Your pickup spot" marker is reliable even if socket payload is delayed
    // or missing coordinates.
    _customerLatLng = LatLng(
      widget.senderData.latitude,
      widget.senderData.longitude,
    );
    _customerToLatLang = LatLng(
      widget.receiverData.latitude,
      widget.receiverData.longitude,
    );
    PickupAddress =
        widget.senderData.mapAddress.isNotEmpty
            ? widget.senderData.mapAddress
            : widget.senderData.address;
    DropAddress =
        widget.receiverData.mapAddress.isNotEmpty
            ? widget.receiverData.mapAddress
            : widget.receiverData.address;

    _searchingAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _motion = DriverMotionEngine(
      vsync: this,
      onUpdate: (pos, bearing) {
        final snapped = _snapAndBearing(
          pos,
          rawBearing: bearing,
          toleranceMeters: _routeSnapToleranceMeters,
        );
        _currentDriverLatLng = snapped.position;
        _lastBearing = snapped.bearing;
        _updateDriverMarker(snapped.position, snapped.bearing);
      },
      onFrameSideEffects: (pos) {
        final snapped = _snapAndBearing(
          pos,
          rawBearing: _lastBearing,
          toleranceMeters: _trimMaxSnapMeters,
        );
        _currentDriverLatLng = snapped.position;
        _lastBearing = snapped.bearing;
        _maybeAutoFollow(snapped.position);
        _maybeUpdatePolyline(snapped.position);
        _trimActivePolyline(snapped.position);
      },
    );

    _searchingElapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _searchingElapsedSeconds += 1);
    });
    _initLocation();
    _loadPickupDropIcons();
    _loadCustomMarker();
    initSocket();
    _bootSocket();
    _startPulseAnimation();
    WidgetsBinding.instance.addPostFrameCallback((_) => _calculateLineHeight());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _seedPickupDropMarkers();
      _syncPhaseMarkers();
    });
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

    socketService.on('booking-update', (data) {
      if (!mounted) return;
      final payload = _normalizeSocketPayload(data);
      if (payload.isEmpty) return;

      final status = (payload['status'] ?? '').toString().trim().toUpperCase();
      final driverId = (payload['driverId'] ?? '').toString().trim();

      final isAccepted =
          status == 'DRIVER_ACCEPTED' ||
          status == 'ACCEPTED' ||
          status == 'DRIVER_ASSIGNED';
      if (!isAccepted) return;

      setState(() {
        _isDriverConfirmed = true;
        isWaitingForDriver = false;
        noDriverFound = false;
      });
      _syncPhaseMarkers();

      if (driverId.isNotEmpty) {
        AppLogger.log.i("📍 Tracking driver (booking-update): $driverId");
        socketService.joinBooking(
          bookingId: widget.bookingId,
          driverId: driverId,
        );
      }
    });

    socketService.on('joined-booking', (data) {
      if (!mounted) return;
      if (kDebugMode) {
        AppLogger.log.i("Package Joined booking data: $data");
      }

      final payload = _normalizeSocketPayload(data);

      // Vehicle might also be nested JSON.
      Map vehicle = <String, dynamic>{};
      try {
        final rawVeh = payload['vehicle'];
        if (rawVeh is Map) {
          vehicle = rawVeh;
        } else if (rawVeh is String) {
          final decodedVeh = json.decode(rawVeh);
          vehicle = (decodedVeh is Map) ? decodedVeh : <String, dynamic>{};
        }
      } catch (_) {}

      final String driverId = (payload['driverId'] ?? '').toString();
      final String driverFullName = (payload['driverName'] ?? '').toString();
      final String driverPhone = _extractDriverPhone(payload);
      final double rating =
          double.tryParse(payload['driverRating'].toString()) ?? 0.0;
      final String color = vehicle['color'] ?? '';
      final String model = vehicle['model'] ?? '';
      final String brand = vehicle['brand'] ?? '';
      final String carType = vehicle['carType'] ?? '';
      final rideHistory = (payload['rideStatusHistory'] as List?) ?? const [];
      final acceptedFromHistory = rideHistory.any((e) {
        final m = e as Map?;
        final st = (m?['status'] ?? '').toString().toUpperCase();
        return st == 'ACCEPTED' || st == 'DRIVER_ACCEPTED';
      });

      final bool driverAccepted =
          payload['driver_accept_status'] == true ||
          payload['orderConfirmationStatus'] == true ||
          acceptedFromHistory;
      final String type = vehicle['type'] ?? '';
      final String plate = vehicle['plateNumber'] ?? '';
      final customerLoc =
          (payload['customerLocation'] as Map?) ??
          ((payload['basePayload'] as Map?)?['customerLocation'] as Map?) ??
          {};
      final amount = payload['amount'];
      final String profilePic = (payload['profilePic'] ?? '').toString();
      final String bookingId = (payload['bookingId'] ?? '').toString();
      final int maxWeight =
          (payload['maxWeight'] is num)
              ? (payload['maxWeight'] as num).toInt()
              : int.tryParse((payload['maxWeight'] ?? '').toString()) ?? 0;
      final String pickupAddress = (payload['pickupAddress'] ?? '').toString();
      final String dropAddress = (payload['dropAddress'] ?? '').toString();

      final fromLat =
          (customerLoc['fromLatitude'] is num)
              ? (customerLoc['fromLatitude'] as num).toDouble()
              : double.tryParse((customerLoc['fromLatitude'] ?? '').toString());
      final fromLng =
          (customerLoc['fromLongitude'] is num)
              ? (customerLoc['fromLongitude'] as num).toDouble()
              : double.tryParse(
                (customerLoc['fromLongitude'] ?? '').toString(),
              );
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

      final driverLoc =
          (payload['driverLocation'] as Map?) ??
          ((payload['basePayload'] as Map?)?['driverLocation'] as Map?);
      final joinedDriverLat = _toDouble(
        driverLoc?['latitude'] ?? driverLoc?['lat'],
      );
      final joinedDriverLng = _toDouble(
        driverLoc?['longitude'] ?? driverLoc?['lng'] ?? driverLoc?['lon'],
      );

      setState(() {
        _vehicleType =
            type.toString().trim().isNotEmpty
                ? type.toString()
                : (payload['serviceType'] ?? carType).toString();
        plateNumber = plate;
        driverName = '$driverFullName ⭐ $rating';
        carDetails = '$color - $brand';
        _isDriverConfirmed = driverAccepted;
        driverStartedRide =
            payload['packageCollected'] == true ||
            payload['inTransit'] == true ||
            payload['outForDelivery'] == true;
        _isOrderConfirmed = payload['orderConfirmationStatus'] ?? false;
        _isEnRoute = payload['enRoute'] ?? false;
        _isPackagePickup = payload['packagePickup'] ?? false;
        _isPackageCollected = payload['packageCollected'] ?? false;
        _isInTransit = payload['inTransit'] ?? false;
        _isOutForDelivery = payload['outForDelivery'] ?? false;
        CUSTOMERPHONE = driverPhone;
        CARTYPE = carType;
        ProfilePic = profilePic;
        BookingId = bookingId;
        MaxWeight = maxWeight;
        PickupAddress = pickupAddress;
        DropAddress = dropAddress;
        Amount =
            (amount is num)
                ? amount.toDouble()
                : (double.tryParse((amount ?? '').toString()) ?? 0.0);
      });

      if (kDebugMode) {
        AppLogger.log.i("🚕 Joined booking data: $data");
        AppLogger.log.i("🚕 driverAccepted ==  $driverAccepted");
      }

      _loadCustomMarkerForVehicle(_vehicleType);
      _loadPickupDropIcons().whenComplete(() {
        _seedPickupDropMarkers();
        _syncPhaseMarkers();
      });

      if (joinedDriverLat != null && joinedDriverLng != null) {
        final joinedDriverPos = LatLng(joinedDriverLat, joinedDriverLng);
        _currentDriverLatLng = joinedDriverPos;
        _pendingDriverMarkerPos = joinedDriverPos;
        _pendingDriverMarkerBearing = _lastBearing;
        if (!_motionReady) {
          _motion.reset(joinedDriverPos, bearing: _lastBearing);
          _motionReady = true;
        }
        _commitDriverMarker(force: true);
        _maybeUpdatePolyline(joinedDriverPos, force: true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _fitDriverAndTargetOnce(toDrop: driverStartedRide);
        });
      }

      // If driver-location reached the screen before joined-booking (common),
      // we may already have driver lat/lng but couldn't render a route yet.
      // Trigger marker + polyline now once pickup/drop are known, even if the
      // next driver packet is identical (no movement -> no animation).
      final driverPos = _currentDriverLatLng;
      if (driverPos != null) {
        _pendingDriverMarkerPos = driverPos;
        _pendingDriverMarkerBearing = _lastBearing;
        _commitDriverMarker(force: true);
        _maybeUpdatePolyline(driverPos, force: true);
      }

      // Start real-time tracking
      if (driverId.trim().isNotEmpty) {
        AppLogger.log.i("📍 Tracking driver: $driverId");
        socketService.joinBooking(
          bookingId: widget.bookingId,
          driverId: driverId.trim(),
        );
      }
    });

    // Backend emits `ride-estimate` independently of `driver-location`.
    // Listening to it avoids UI delay when heartbeat packets are sparse.
    socketService.on('ride-estimate', (data) {
      final payload = _asMap(data);
      final stt1 = (payload['stt1'] ?? '').toString();
      final stt2 = (payload['stt2'] ?? '').toString();

      if (!mounted) return;
      if (stt1 == _estimateStt1 && stt2 == _estimateStt2) return;

      setState(() {
        _estimateStt1 = stt1;
        _estimateStt2 = stt2;
      });

      if (kDebugMode) {
        AppLogger.log.i('ride-estimate: stt1="$stt1" stt2="$stt2"');
      }
    });

    socketService.on('driver-location', (data) {
      if (kDebugMode) {
        final now = DateTime.now();
        if (now.difference(_lastDriverLocationLogAt) >
            const Duration(seconds: 3)) {
          _lastDriverLocationLogAt = now;
          AppLogger.log.i('📦 driver-location-updated: $data');
        }
      }

      final payload = _normalizeSocketPayload(data);
      if (payload.isEmpty) return;

      final lat = _toDouble(payload['latitude'] ?? payload['lat']);
      final lng = _toDouble(
        payload['longitude'] ?? payload['lng'] ?? payload['lon'],
      );
      if (lat == null || lng == null) {
        AppLogger.log.e("Invalid driver-location payload: $payload");
        return;
      }
      final newDriverLatLng = LatLng(lat, lng);

      if (!_isValidCoordinate(newDriverLatLng)) return;

      final ts = _parseServerTime(
        payload['timestamp'] ?? payload['ts'] ?? payload['time'],
      );
      final bearing = _parseBearingDeg(
        payload['bearing'] ?? payload['heading'] ?? payload['rotation'],
      );

      final driverPhone = _normalizePhone(
        (payload['driverPhone'] ?? payload['phone'] ?? payload['mobile'] ?? '')
            .toString(),
      );
      if (driverPhone.isNotEmpty) {
        CUSTOMERPHONE = driverPhone;
      }

      // Smooth motion engine (shared with BookRide maps):
      // socket GPS -> DriverMotionEngine.ingest -> onUpdate -> marker via ValueNotifier
      final b0 = bearing ?? _lastBearing;
      if (!_motionReady) {
        if (!_isFreshTrackingTimestamp(ts)) {
          if (kDebugMode) {
            AppLogger.log.w(
              'Ignoring stale initial package driver-location ts=$ts '
              'lat=${newDriverLatLng.latitude} lng=${newDriverLatLng.longitude}',
            );
          }
          return;
        }
        _motion.reset(newDriverLatLng, bearing: b0);
        _motionReady = true;
        _currentDriverLatLng = newDriverLatLng;
        _lastBearing = b0;
        _maybeUpdatePolyline(newDriverLatLng, force: true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _fitDriverAndTargetOnce(toDrop: driverStartedRide);
        });
      } else {
        _motion.ingest(newDriverLatLng, serverTs: ts, bearing: b0);
        if (_polylinesNotifier.value.isEmpty) {
          _maybeUpdatePolyline(newDriverLatLng, force: true);
        }
      }

      // Always check deviation after each socket update (reroute trigger).
      _checkRouteDeviation(newDriverLatLng);

      // ✅ Animate movement

      // polyline handled by _enqueueDriverMove()

      // ✅ CASE 2: After ride starts → Draw polyline to drop
      // polyline handled by _enqueueDriverMove()

      // ✅ Update current driver position
      // _currentDriverLatLng is updated by smooth animation engine
      // 📦 Extract flags
      final basePayload = payload['basePayload'] ?? {};
      final estimate = basePayload['getEstimateTime'] ?? {};
      final prevStarted = driverStartedRide;
      final nextStarted =
          basePayload['packageCollected'] == true ||
          basePayload['inTransit'] == true ||
          basePayload['outForDelivery'] == true;

      final socketMeters = _parseInt(
        payload[nextStarted
            ? 'dropDistanceInMeters'
            : 'pickupDistanceInMeters'],
      );
      final socketMins = _parseInt(
        payload[nextStarted ? 'dropDurationInMin' : 'pickupDurationInMin'],
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
        if (nextStarted) {
          _didFitDriverToDrop = false;
        }
        _maybeUpdatePolyline(newDriverLatLng, force: true);
        _syncPhaseMarkers();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _fitDriverAndTargetOnce(toDrop: nextStarted);
        });
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

      if (status) _syncPhaseMarkers();
      if (status && _currentDriverLatLng != null) {
        _didFitDriverToDrop = false;
        _maybeUpdatePolyline(_currentDriverLatLng!, force: true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _fitDriverAndTargetOnce(toDrop: true);
        });
      }
    });
    socketService.on('driver-reached-destination', (data) {
      if (!_isDestinationReachedPayload(data)) return;
      if (_navigatedToPayment || destinationReached) return;

      final payload = _asMap(data);
      final amount = _toDouble(payload['amount']);
      if (amount != null && amount > 0) Amount = amount;

      if (!mounted) return;
      setState(() => destinationReached = true);
      _syncPhaseMarkers();

      _schedulePaymentNavigation(
        delay: const Duration(milliseconds: 1200),
        replace: true,
      );

      AppLogger.log.i("driver-reached-destination,$payload");
    });
    socketService.on('customer-cancelled', (data) async {
      AppLogger.log.i('customer-cancelled : $data');

      final payload = _asMap(data);
      if (payload.isNotEmpty && payload['status'] == true) {
        if (!mounted) return;

        setState(() {
          isTripCancelled = true;
          cancelTitle = _extractCancelTitle(
            payload,
            fallback: 'Booking cancelled',
          );
          cancelReason = _extractCancelReason(payload, fallback: 'Cancelled');
        });

        await Future.delayed(const Duration(seconds: 3));
        if (!mounted) return;
        Get.offAll(() => CommonBottomNavigation(initialIndex: 3));
      }
    });
    socketService.on('driver-cancelled', (data) async {
      AppLogger.log.i('driver-cancelled : $data');

      final payload = _asMap(data);
      if (payload.isNotEmpty && payload['status'] == true) {
        if (!mounted) return;

        setState(() {
          isTripCancelled = true;
          cancelTitle = _extractCancelTitle(
            payload,
            fallback: 'Driver cancelled',
          );
          cancelReason = _extractCancelReason(payload, fallback: 'Cancelled');
        });

        await Future.delayed(const Duration(seconds: 3));
        if (!mounted) return;
        Get.offAll(() => CommonBottomNavigation(initialIndex: 3));
      }
    });
  }

  void _updateDriverMarker(LatLng position, double bearing) {
    _pendingDriverMarkerPos = position;
    _pendingDriverMarkerBearing = bearing;

    if (_driverMarkerFlushTimer != null) return;
    _driverMarkerFlushTimer = Timer(_driverMarkerMinInterval, () {
      _driverMarkerFlushTimer = null;
      _commitDriverMarker(force: false);
    });
  }

  void _commitDriverMarker({required bool force}) {
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastDriverMarkerCommitAt) < _driverMarkerMinInterval) {
      return;
    }
    _lastDriverMarkerCommitAt = now;

    final position = _pendingDriverMarkerPos ?? _currentDriverLatLng;
    if (position == null) return;
    final rawBearing = _pendingDriverMarkerBearing ?? _lastBearing;
    final t = _vehicleType.trim().toLowerCase();
    final isCar =
        t.contains('car') ||
        t.contains('sedan') ||
        t.contains('suv') ||
        t.contains('van');
    final bearing = MapUiDefaults.normalizeBearing(
      rawBearing +
          (isCar
              ? MapUiDefaults.carBearingIconOffsetDeg
              : MapUiDefaults.bikeBearingIconOffsetDeg),
    );

    _driverMarker = Marker(
      markerId: const MarkerId("driver_marker"),
      position: position,
      rotation: bearing,
      icon:
          _carIcon ??
          BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
      anchor: const Offset(0.5, 0.5),
      flat: true,
      zIndex: 5,
      infoWindow: InfoWindow(
        title: driverName.trim().isNotEmpty ? driverName.trim() : 'Driver',
        snippet: carDetails.trim().isNotEmpty ? carDetails.trim() : null,
      ),
    );

    if (!mounted) return;
    final next = <Marker>{
      ..._markersNotifier.value.where(
        (m) => m.markerId != const MarkerId("driver_marker"),
      ),
      _driverMarker!,
    };
    _markersNotifier.value = next;

    // Ensure the marker becomes visible even if driver-location arrived before
    // the map controller was ready.
    _maybeAutoFollow(position);
  }

  _SnappedDriverPose _snapAndBearing(
    LatLng raw, {
    double? rawBearing,
    double? toleranceMeters,
  }) {
    final fallbackBearing = rawBearing ?? _lastBearing;
    if (_activeRoutePoints.length < 2) {
      return _SnappedDriverPose(position: raw, bearing: fallbackBearing);
    }

    final nearest = nearestPointOnPolyline(raw, _activeRoutePoints);
    if (nearest == null) {
      return _SnappedDriverPose(position: raw, bearing: fallbackBearing);
    }

    final maxSnap = toleranceMeters ?? _routeSnapToleranceMeters;
    if (!nearest.distanceMeters.isFinite || nearest.distanceMeters > maxSnap) {
      return _SnappedDriverPose(position: raw, bearing: fallbackBearing);
    }

    final prevIdx = nearest.segmentIndex.clamp(
      0,
      _activeRoutePoints.length - 1,
    );
    final nextIdx = (nearest.segmentIndex + 1).clamp(
      0,
      _activeRoutePoints.length - 1,
    );
    final prev = _activeRoutePoints[prevIdx];
    final next = _activeRoutePoints[nextIdx];
    final routeBearing = bearingBetween(prev, next);
    final smooth = smoothBearing(
      currentDeg: fallbackBearing,
      targetDeg: routeBearing,
      alpha: 0.22,
    );

    return _SnappedDriverPose(position: nearest.point, bearing: smooth);
  }

  bool _routeMatchesCurrentPhase(
    List<LatLng> points,
    LatLng expectedDestination,
  ) {
    if (points.length < 2) return true;
    final endDistance = haversineDistanceMeters(
      points.last,
      expectedDestination,
    );
    return endDistance <= 90.0;
  }

  List<LatLng> _decodeStepsPolyline(dynamic legs) {
    try {
      final leg0 =
          (legs is List && legs.isNotEmpty) ? (legs.first as Map?) : null;
      final steps = (leg0?['steps'] as List?) ?? const [];
      if (steps.isEmpty) return const [];

      final out = <LatLng>[];
      for (final step in steps) {
        final m = step as Map?;
        final enc = (m?['polyline']?['points'] ?? '').toString();
        if (enc.isEmpty) continue;
        final pts = _decodePolyline(enc);
        if (pts.isEmpty) continue;
        if (out.isNotEmpty && out.last == pts.first) {
          out.addAll(pts.skip(1));
        } else {
          out.addAll(pts);
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _drawRoute({
    required LatLng origin,
    required LatLng destination,
    required String polylineId,
    required bool isDashedStyle,
    bool forceKeepOldOnFailure = false,
  }) async {
    if (_isDrawingPolyline) return; // prevent multiple calls
    _isDrawingPolyline = true;

    try {
      final apiKey = ApiConsents.googleMapApiKey;
      final preferredMode = _preferredRouteMode();
      final vt = _vehicleType.toString().trim().toLowerCase();
      final avoidHighways =
          (vt.contains('bike') || vt.contains('two') || vt.contains('auto'))
              ? '&avoid=highways'
              : '';

      Future<Map<String, dynamic>> fetch(String mode) async {
        final url =
            'https://maps.googleapis.com/maps/api/directions/json?origin=${origin.latitude},${origin.longitude}&destination=${destination.latitude},${destination.longitude}&mode=$mode$avoidHighways&region=in&key=$apiKey';
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 8));
        return json.decode(response.body) as Map<String, dynamic>;
      }

      final startedAt = DateTime.now();
      _lastRouteFetchAt = startedAt;

      Map<String, dynamic> data = await fetch(preferredMode);
      if (data['status'] != 'OK' && preferredMode == 'bicycling') {
        data = await fetch('driving');
      }
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

        final stepPoints = _decodeStepsPolyline(legs);
        final encoded =
            (data['routes']?[0]?['overview_polyline']?['points'] ?? '')
                .toString();
        final decoded =
            stepPoints.isNotEmpty ? stepPoints : _decodePolyline(encoded);
        // Fallback: always show at least a straight line if Directions gives
        // an empty/short polyline (happens on very short routes / edge cases).
        final points =
            decoded.length >= 2 ? decoded : <LatLng>[origin, destination];
        if (!_routeMatchesCurrentPhase(points, destination)) {
          if (kDebugMode) {
            AppLogger.log.w(
              'Ignoring stale package route id=$polylineId endDistance='
              '${haversineDistanceMeters(points.last, destination).toStringAsFixed(1)}m',
            );
          }
          return;
        }
        if (!mounted) return;
        final socketFresh =
            _routeMetricsFromSocket &&
            DateTime.now().difference(_routeMetricsFromSocketAt) <
                const Duration(seconds: 75);
        if (mounted) {
          setState(() {
            if (!socketFresh) {
              _routeMeters = meters;
              _routeSeconds = seconds;
              _routeMetricsFromSocket = false;
            }
          });
        }
        _polylinesNotifier.value = _styledRoutePolylines(
          points,
          id: polylineId,
          isDashed: isDashedStyle,
        );
        _activeRoutePoints = points;
        _lastTrimSegIndex = -1;
        _maybeFitBounds(points, extraPoints: <LatLng>[origin, destination]);
        if (kDebugMode) {
          AppLogger.log.i(
            'pkg map polyline set: pts=${points.length} id=$polylineId dashed=$isDashedStyle',
          );
        }
      } else {
        // Keep the current route if Directions fails (production-safe). If we
        // don't have any route yet, draw a minimal fallback line.
        if (mounted &&
            _polylinesNotifier.value.isEmpty &&
            !forceKeepOldOnFailure) {
          _polylinesNotifier.value = _styledRoutePolylines(
            <LatLng>[origin, destination],
            id: polylineId,
            isDashed: isDashedStyle,
          );
          _activeRoutePoints = <LatLng>[origin, destination];
          _lastTrimSegIndex = -1;
        }
        if (kDebugMode) {
          AppLogger.log.e("Directions error: ${data['status']}");
        }
      }
    } catch (e) {
      // Network hiccup/timeouts shouldn't clear the current route.
      if (mounted &&
          _polylinesNotifier.value.isEmpty &&
          !forceKeepOldOnFailure) {
        _polylinesNotifier.value = _styledRoutePolylines(
          <LatLng>[origin, destination],
          id: polylineId,
          isDashed: isDashedStyle,
        );
        _activeRoutePoints = <LatLng>[origin, destination];
        _lastTrimSegIndex = -1;
      }
      if (kDebugMode) {
        AppLogger.log.e("Directions exception: $e");
      }
    } finally {
      _isDrawingPolyline = false;
    }
  }

  Set<Polyline> _styledRoutePolylines(
    List<LatLng> points, {
    required String id,
    required bool isDashed,
  }) {
    if (points.length < 2) return const <Polyline>{};

    // Production-safe: keep route high-contrast (black) and leave dashed
    // "secondary" guidance grey.
    final color = isDashed ? const Color(0xFF9E9E9E) : const Color(0xFF000000);
    final width = isDashed ? 4 : 5;

    return {
      Polyline(
        polylineId: PolylineId(id),
        points: points,
        color: color,
        width: width,
        zIndex: 2,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
        jointType: JointType.round,
        patterns:
            isDashed
                ? <PatternItem>[PatternItem.dash(20), PatternItem.gap(10)]
                : const <PatternItem>[],
      ),
    };
  }

  void _maybeFitBounds(
    List<LatLng> routePoints, {
    List<LatLng> extraPoints = const <LatLng>[],
  }) {
    if (_mapController == null) return;
    if (!_autoFollowEnabled) return;
    final now = DateTime.now();
    if (now.isBefore(_pauseAutoFollowUntil)) return;
    if (now.difference(_lastBoundsAt) < _boundsInterval) return;
    _lastBoundsAt = now;

    try {
      final bounds = boundsFromRoutePoints(
        routePoints,
        extraPoints: extraPoints,
      );
      _mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 120));
    } catch (_) {}
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

  Widget _etaChip() {
    final etaText =
        (_routeSeconds != null) ? _formatDuration(_routeSeconds!) : '';
    final distText =
        (_routeMeters != null) ? _formatDistance(_routeMeters!) : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
          if (etaText.isNotEmpty)
            Flexible(
              child: Text(
                etaText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (etaText.isNotEmpty && distText.isNotEmpty)
            const SizedBox(width: 10),
          if (distText.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.06),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                distText,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          const SizedBox(width: 10),
          const Icon(Icons.timer_outlined, size: 18, color: Colors.black),
        ],
      ),
    );
  }

  Future<void> _showEtaDistanceSheet() async {
    final etaText =
        (_routeSeconds != null) ? _formatDuration(_routeSeconds!) : '';
    final distText =
        (_routeMeters != null) ? _formatDistance(_routeMeters!) : '';
    if (etaText.isEmpty && distText.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Trip info',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                if (etaText.isNotEmpty)
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          etaText,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                if (etaText.isNotEmpty && distText.isNotEmpty)
                  const SizedBox(height: 10),
                if (distText.isNotEmpty)
                  Row(
                    children: [
                      const Icon(Icons.route_rounded, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          distText,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  final DriverSearchController driverSearchController = Get.put(
    DriverSearchController(),
  );

  void _onUserMapGesture() {
    _autoFollowEnabled = false;
    _isFollowingNotifier.value = false;
    _pauseAutoFollowUntil = DateTime.now().add(_userGesturePause);
  }

  Widget _tripInfoInline() {
    final etaText =
        (_routeSeconds != null) ? _formatDuration(_routeSeconds!) : '';
    final distText =
        (_routeMeters != null) ? _formatDistance(_routeMeters!) : '';

    if (etaText.isEmpty && distText.isEmpty) return const SizedBox.shrink();

    Widget chip(IconData icon, String text) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.black),
            const SizedBox(width: 6),
            Text(
              text,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        if (etaText.isNotEmpty) chip(Icons.timer_outlined, etaText),
        if (distText.isNotEmpty) chip(Icons.route_rounded, distText),
      ],
    );
  }

  void _maybeAutoFollow(LatLng target) {
    if (!_autoFollowEnabled) return;
    final now = DateTime.now();
    if (now.isBefore(_pauseAutoFollowUntil)) return;
    if (now.difference(_lastCameraMoveAt) < _cameraInterval) return;
    _lastCameraMoveAt = now;

    try {
      final followZoom = math.max(_currentZoomLevel, _minFollowZoom);
      // Always keep map North-up. Only the vehicle marker rotates.
      const bearing = 0.0;
      const tilt = 0.0;
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: target,
            zoom: followZoom,
            bearing: bearing,
            tilt: tilt,
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
    final pickup = _customerLatLng;
    final drop = _customerToLatLang;
    if (pickup == null || drop == null) return;

    // PHASE 1: driver -> pickup (dashed grey)
    if (!driverStartedRide) {
      const polyId = "driver_to_pickup";
      if (!_shouldUpdatePolyline(polyId, force: force)) return;
      _drawRoute(
        origin: driverLatLng,
        destination: pickup,
        polylineId: polyId,
        isDashedStyle: true,
      );
      return;
    }

    // PHASE 2: driver -> drop (solid)
    const polyId = "driver_to_drop";
    if (!_shouldUpdatePolyline(polyId, force: force)) return;
    _drawRoute(
      origin: driverLatLng,
      destination: drop,
      polylineId: polyId,
      isDashedStyle: false,
    );
  }

  void _checkRouteDeviation(LatLng driverLatLng) {
    _maybeRerouteIfOffRoute(driverLatLng);
  }

  void _trimActivePolyline(LatLng driverLatLng) {
    final id = _activePolyId;
    if (id == null) return;
    if (_activeRoutePoints.length < 2) return;

    final now = DateTime.now();
    if (now.difference(_lastTrimAt) < _trimInterval) return;
    _lastTrimAt = now;

    // Only trim when we're close to the current route (avoid trimming while off-route).
    final nearest = nearestPointOnPolyline(driverLatLng, _activeRoutePoints);
    if (nearest == null) return;
    if (!nearest.distanceMeters.isFinite ||
        nearest.distanceMeters > _trimMaxSnapMeters) {
      return;
    }
    final maxTrimStart = (_activeRoutePoints.length - 2).clamp(
      0,
      _activeRoutePoints.length - 1,
    );
    final trimIndex = nearest.segmentIndex.clamp(0, maxTrimStart);
    if (trimIndex <= _lastTrimSegIndex) return;
    _lastTrimSegIndex = trimIndex;

    final remaining = <LatLng>[
      nearest.point,
      ..._activeRoutePoints.skip(trimIndex + 1),
    ];
    if (remaining.length < 2) return;

    _activeRoutePoints = remaining;
    _polylinesNotifier.value = _styledRoutePolylines(
      remaining,
      id: id,
      isDashed: !driverStartedRide,
    );
  }

  void _maybeRerouteIfOffRoute(LatLng driverLatLng) {
    final destination =
        driverStartedRide ? _customerToLatLang : _customerLatLng;
    if (destination == null) return;
    if (_activeRoutePoints.length < 2) return;

    final now = DateTime.now();
    if (now.difference(_lastOffRouteCheckAt) < _offRouteCheckInterval) return;
    _lastOffRouteCheckAt = now;

    final should = shouldReroute(
      activeRoute: _activeRoutePoints,
      driver: driverLatLng,
      destination: destination,
      now: now,
      lastRouteFetchAt: _lastRouteFetchAt,
      minInterval: _rerouteMinInterval,
      offRouteThresholdMeters: _offRouteThresholdMeters,
    );
    if (!should) return;

    // Apply cooldown immediately (even if the API fails) to avoid spamming.
    _lastRouteFetchAt = now;
    _drawRoute(
      origin: driverLatLng,
      destination: destination,
      polylineId: driverStartedRide ? 'driver_to_drop' : 'driver_to_pickup',
      isDashedStyle: !driverStartedRide,
      forceKeepOldOnFailure: true,
    );
  }

  // (Driver motion is handled by DriverMotionEngine.)

  @override
  void dispose() {
    try {
      socketService.off('booking-update');
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
    _driverMarkerFlushTimer?.cancel();
    _paymentNavTimer?.cancel();
    _searchingElapsedTimer?.cancel();
    _searchingAnimController.dispose();
    _motion.dispose();
    _markersNotifier.dispose();
    _polylinesNotifier.dispose();
    _isFollowingNotifier.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initialTarget =
        _customerLatLng ??
        _currentPosition ??
        const LatLng(9.9144908, 78.0970899);

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
                child: ValueListenableBuilder<Set<Marker>>(
                  valueListenable: _markersNotifier,
                  builder: (context, markers, _) {
                    return ValueListenableBuilder<Set<Polyline>>(
                      valueListenable: _polylinesNotifier,
                      builder: (context, polylines, __) {
                        return GoogleMap(
                          compassEnabled: true,
                          rotateGesturesEnabled: false,
                          tiltGesturesEnabled: false,
                          buildingsEnabled: false,
                          indoorViewEnabled: false,
                          minMaxZoomPreference: const MinMaxZoomPreference(
                            11.0,
                            17.0,
                          ),
                          circles: _circles,
                          onCameraMove:
                              (pos) =>
                                  _currentZoomLevel =
                                      pos.zoom.clamp(11.0, 17.0).toDouble(),
                          onCameraMoveStarted: _onUserMapGesture,
                          onTap: (_) => _onUserMapGesture(),
                          initialCameraPosition: CameraPosition(
                            target: initialTarget,
                            zoom: math.max(
                              _currentZoomLevel,
                              _preferredInitialZoom,
                            ),
                          ),
                          padding: const EdgeInsets.only(bottom: 230),
                          markers: markers,
                          onMapCreated: (controller) async {
                            _mapController = controller;
                            String style = await DefaultAssetBundle.of(
                              context,
                            ).loadString('assets/map_style.json');
                            _mapController?.setMapStyle(style);

                            if (_currentDriverLatLng != null &&
                                (driverStartedRide
                                    ? _customerToLatLang != null
                                    : _customerLatLng != null)) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) return;
                                _fitDriverAndTargetOnce(
                                  toDrop: driverStartedRide,
                                );
                              });
                            } else {
                              final focus = _customerLatLng ?? _currentPosition;
                              if (focus != null) {
                                _mapController?.animateCamera(
                                  CameraUpdate.newCameraPosition(
                                    CameraPosition(
                                      target: focus,
                                      zoom: math.max(
                                        _currentZoomLevel,
                                        _preferredInitialZoom,
                                      ),
                                      bearing: 0,
                                      tilt: 0,
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                          polylines: polylines,
                          myLocationEnabled: false,
                          myLocationButtonEnabled: false,
                          zoomControlsEnabled: false,
                          gestureRecognizers: {
                            Factory<OneSequenceGestureRecognizer>(
                              () => EagerGestureRecognizer(),
                            ),
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              Positioned(
                top: 350,
                right: 10,
                child: ValueListenableBuilder<bool>(
                  valueListenable: _isFollowingNotifier,
                  builder: (context, isFollowing, _) {
                    return AnimatedOpacity(
                      opacity: isFollowing ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 250),
                      child: IgnorePointer(
                        ignoring: isFollowing,
                        child: FloatingActionButton(
                          heroTag: 'pkg_my_location_${widget.bookingId}',
                          mini: true,
                          backgroundColor: Colors.white,
                          onPressed: _onLocationFabTap,
                          child: const Icon(
                            Icons.my_location,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    );
                  },
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
                        AppToasts.showError(context, 'SOS number not set');
                        return;
                      }

                      // Keep leading + if present; remove spaces and other junk
                      sosNumber = sosNumber.trim();
                      final normalized = sanitizePhoneNumber(sosNumber);

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

              // Trip info is shown inside the bottom sheet (under the status).
              DraggableScrollableSheet(
                key: ValueKey(_isDriverConfirmed),

                initialChildSize: _isDriverConfirmed ? 0.55 : 0.5,
                minChildSize: 0.3,
                maxChildSize: _isDriverConfirmed ? 0.90 : 0.5,
                builder: (context, scrollController) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
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
                                          Text(
                                            cancelTitle.trim().isNotEmpty
                                                ? cancelTitle
                                                : "Booking cancelled",
                                            style: const TextStyle(
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
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CustomTextFields.textWithImage(
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
                                    if (_isDriverConfirmed &&
                                        !destinationReached &&
                                        (_routeMeters != null ||
                                            _routeSeconds != null)) ...[
                                      const SizedBox(height: 10),
                                      _tripInfoInline(),
                                    ],
                                  ],
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
                                              ClipOval(child: _driverAvatar()),
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
                                              final ph = _normalizePhone(
                                                CUSTOMERPHONE,
                                              );
                                              if (ph.isEmpty) {
                                                AppToasts.showError(
                                                  context,
                                                  'Driver phone not available',
                                                );
                                                return;
                                              }

                                              final ok =
                                                  await launchPhoneDialer(ph);
                                              if (!ok) {
                                                AppToasts.showError(
                                                  context,
                                                  'Could not open dialer',
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
                                              final id =
                                                  (BookingId.trim().isNotEmpty
                                                          ? BookingId
                                                          : widget.bookingId)
                                                      .trim();
                                              if (id.isEmpty) {
                                                AppToasts.showError(
                                                  context,
                                                  'Booking ID not available yet',
                                                );
                                                return;
                                              }
                                              Get.to(
                                                () => ChatScreen(
                                                  bookingId: id,
                                                  pickupLatitude:
                                                      widget
                                                          .senderData
                                                          .latitude,
                                                  pickupLongitude:
                                                      widget
                                                          .senderData
                                                          .longitude,
                                                ),
                                              );
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
                                                      color:
                                                          AppColors.commonBlack,
                                                      fontWeight:
                                                          FontWeight.w600,
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
                                                    overflow:
                                                        TextOverflow.visible,
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
                                  if (_routeMeters != null ||
                                      _routeSeconds != null) ...[
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
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
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
                                                        _formatDistance(
                                                          _routeMeters!,
                                                        ),
                                                      if (_routeSeconds != null)
                                                        _formatDuration(
                                                          _routeSeconds!,
                                                        ),
                                                    ]
                                                    .where(
                                                      (e) =>
                                                          e.trim().isNotEmpty,
                                                    )
                                                    .join(' - '),
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
                                            _shortPlace(
                                                  PickupAddress,
                                                ).isNotEmpty
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
                                            _estimateText().isNotEmpty
                                                ? _estimateText()
                                                : (_shortPlace(
                                                      DropAddress,
                                                    ).isNotEmpty
                                                    ? 'To ${_shortPlace(DropAddress)}'
                                                    : 'Moving to destination'),
                                      ),
                                  const SizedBox(height: 10),
                                  _buildPickupDeliveryStatusCard(),

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
                                      if (!destinationReached) {
                                        AppToasts.showError(
                                          context,
                                          'Payment available after delivery is completed',
                                        );
                                        return;
                                      }
                                      _navigateToPayment(replace: false);
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
                                                    child: CustomTextFields.textWithImage(
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
                                                        color:
                                                            AppColors
                                                                .commonBlack,
                                                      ),
                                                      child:
                                                          CustomTextFields.textWithStylesSmall(
                                                            'PKG - ${BookingId}',
                                                            maxLines: 1,
                                                            colors:
                                                                AppColors
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

                                                                AppButtons.showPackageCancelBottomSheet(
                                                                  context,
                                                                  courierName:
                                                                      driverName,
                                                                  orderId:
                                                                      BookingId,
                                                                  distanceMeters:
                                                                      _routeMeters,
                                                                  durationSeconds:
                                                                      _routeSeconds,
                                                                  statusMessage:
                                                                      destinationReached
                                                                          ? 'Delivery completed'
                                                                          : driverStartedRide
                                                                          ? 'Courier is delivering your package'
                                                                          : (_isEnRoute
                                                                              ? 'Courier is on the way to pickup'
                                                                              : 'Waiting for courier'),
                                                                  policyTitle:
                                                                      'Cancellation Policy',
                                                                  policyMessage:
                                                                      driverStartedRide
                                                                          ? 'The courier has already started; cancellation charges may apply.'
                                                                          : (_isEnRoute
                                                                              ? 'The courier is on the way; cancellation charges may apply.'
                                                                              : 'You can cancel now.'),
                                                                  totalPaid:
                                                                      Amount,
                                                                  onConfirmCancel: (
                                                                    String
                                                                    selectedReason,
                                                                  ) {
                                                                    return driverSearchController.cancelRide(
                                                                      bookingId:
                                                                          BookingId.toString(),
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
                                                              child: CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                                valueColor:
                                                                    AlwaysStoppedAnimation<
                                                                      Color
                                                                    >(
                                                                      Colors
                                                                          .red,
                                                                    ),
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
                                                            style:
                                                                const TextStyle(
                                                                  color:
                                                                      Colors
                                                                          .red,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500,
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
                                                        Icons
                                                            .support_agent_rounded,
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
    Widget buildStep({
      required String title,
      required bool isDone,
      required bool isActive,
    }) {
      final icon =
          isDone
              ? Icons.check_circle
              : (isActive ? Icons.radio_button_checked : Icons.circle_outlined);
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

    final t = _searchingElapsedSeconds;
    final step1Done = t >= 5;
    final step2Done = t >= 12;
    final step3Done = t >= 22;

    return AnimatedBuilder(
      animation: _searchingAnimController,
      builder: (context, _) {
        final v = _searchingAnimController.value;
        final oscillate = (math.sin(v * math.pi * 2) + 1) / 2; // 0..1
        final dots = '.' * (1 + (v * 3).floor());
        final progressValue = 0.15 + (0.75 * oscillate);
        final type = CARTYPE.trim().toLowerCase();
        final isCar = type.contains('car');
        final heroAsset =
            isCar ? AppImages.confirmCar : AppImages.packageLoading;
        final heroFit = isCar ? BoxFit.contain : BoxFit.cover;
        final title = isCar ? 'Finding a driver' : 'Finding a courier';
        final step1Title =
            isCar ? 'Requesting nearby drivers' : 'Requesting nearby couriers';
        final step2Title =
            isCar ? 'Finding the best price' : 'Checking best time & price';
        final cancelText = isCar ? 'Cancel Ride' : 'Cancel Courier';

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
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
                        Transform.scale(
                          scale: 1 + (0.14 * oscillate),
                          child: Container(
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
                        ),
                        Container(
                          height: 44,
                          width: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.15),
                          ),
                          child: const Icon(
                            Icons.local_shipping_outlined,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Searching nearby drivers$dots',
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
                              value: progressValue,
                              backgroundColor: Colors.white.withOpacity(0.18),
                              valueColor: const AlwaysStoppedAnimation<Color>(
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
              Image.asset(heroAsset, height: 150, width: 150, fit: heroFit),

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
                      title: step1Title,
                      isDone: step1Done,
                      isActive: !step1Done,
                    ),
                    buildStep(
                      title: step2Title,
                      isDone: step2Done,
                      isActive: step1Done && !step2Done,
                    ),
                    buildStep(
                      title: 'Confirming your driver',
                      isDone: step3Done,
                      isActive: step2Done && !step3Done,
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "Keep your phone reachable. We'll confirm a driver shortly.",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade800,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Obx(() {
                final loading = driverSearchController.isCancelLoading.value;

                return AppButtons.button(
                  size: 350,
                  hasBorder: true,
                  borderColor: AppColors.commonBlack.withOpacity(0.2),
                  buttonColor: AppColors.commonWhite,
                  textColor: AppColors.cancelRideColor,
                  onTap:
                      loading
                          ? null
                          : () {
                            AppButtons.showCancelRideBottomSheet(
                              context,
                              onConfirmCancel: (String selectedReason) {
                                return driverSearchController.cancelRide(
                                  bookingId: widget.bookingId.toString(),
                                  selectedReason: selectedReason,
                                  context: context,
                                );
                              },
                            );
                          },
                  isLoading: driverSearchController.isCancelLoading.value,
                  text: cancelText,
                );
              }),
              const SizedBox(height: 10),
            ],
          ),
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
            "We couldn't find any available drivers nearby.\nPlease try again in a few minutes.",
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

class _SnappedDriverPose {
  final LatLng position;
  final double bearing;

  const _SnappedDriverPose({required this.position, required this.bearing});
}

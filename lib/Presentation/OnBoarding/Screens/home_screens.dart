// ========================= home_screens.dart (FULL UPDATED) =========================
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hopper/Presentation/Drawer/screens/favourites_screen.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Consents/app_texts.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Core/Utility/skeleton_loaders.dart';
import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
import 'package:hopper/Presentation/BookRide/Models/active_booking_response.dart';
import 'package:hopper/Presentation/BookRide/Screens/book_map_screen.dart';
import 'package:hopper/Presentation/BookRide/Screens/order_confirm_screen.dart';
import 'package:hopper/Presentation/BookRide/Screens/search_screen.dart';
import 'package:hopper/Presentation/BookRide/SharedRideScreens/Screens/shared_screens.dart';
import 'package:hopper/Presentation/Drawer/screens/drawer_screen.dart';
import 'package:hopper/Presentation/OnBoarding/Widgets/custom_bottomnavigation.dart';
import 'package:hopper/Presentation/OnBoarding/Widgets/package_contoiner.dart';
import 'package:hopper/Presentation/OnBoarding/Screens/package_map_confrim_screen.dart';
import 'package:hopper/Presentation/OnBoarding/Screens/payment_screen.dart';
import 'package:hopper/Presentation/OnBoarding/models/address_models.dart';
import 'package:hopper/api/dataSource/apiDataSource.dart';
import 'package:hopper/api/repository/request.dart';
import 'package:hopper/api/repository/api_consents.dart';
import 'package:hopper/uitls/netWorkHandling/network_handling_screen.dart';
import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:hopper/Presentation/Safety/safety_setup_screen.dart';
import 'package:hopper/uitls/websocket/shared_web_socket.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Controller/home_map_controller.dart';

/// Icon for a quick-destination category (see [_popularCategoryFromTypes] and
/// the 'recent' pseudo-category).
IconData _quickDestIcon(String category) {
  switch (category) {
    case 'airport':
      return Icons.flight_takeoff_rounded;
    case 'train':
      return Icons.train_rounded;
    case 'bus':
      return Icons.directions_bus_rounded;
    case 'mall':
      return Icons.local_mall_rounded;
    case 'hospital':
      return Icons.local_hospital_rounded;
    case 'school':
      return Icons.school_rounded;
    case 'stadium':
      return Icons.stadium_rounded;
    case 'park':
      return Icons.park_rounded;
    case 'hotel':
      return Icons.hotel_rounded;
    case 'attraction':
      return Icons.attractions_rounded;
    case 'food':
      return Icons.restaurant_rounded;
    case 'worship':
      return Icons.place_rounded;
    case 'recent':
      return Icons.history_rounded;
    default:
      return Icons.location_on_rounded;
  }
}

/// Accent colour for a quick-destination category (used as a soft icon tint).
Color _quickDestColor(String category) {
  switch (category) {
    case 'airport':
      return const Color(0xFF2563EB);
    case 'train':
      return const Color(0xFF7C3AED);
    case 'bus':
      return const Color(0xFF0891B2);
    case 'mall':
      return const Color(0xFFDB2777);
    case 'hospital':
      return const Color(0xFFDC2626);
    case 'school':
      return const Color(0xFFD97706);
    case 'stadium':
      return const Color(0xFF059669);
    case 'park':
      return const Color(0xFF16A34A);
    case 'hotel':
      return const Color(0xFF9333EA);
    case 'attraction':
      return const Color(0xFFEA580C);
    case 'food':
      return const Color(0xFFE11D48);
    case 'recent':
      return const Color(0xFF475569);
    default:
      return const Color(0xFF334155);
  }
}

class _HomeHeroBanner {
  final String id;
  final String title;
  final String imageUrl;
  final String ctaLink;

  const _HomeHeroBanner({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.ctaLink,
  });

  factory _HomeHeroBanner.fromJson(Map<String, dynamic> json) {
    return _HomeHeroBanner(
      id: (json['_id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      imageUrl: (json['imageUrl'] ?? '').toString(),
      ctaLink:
          (json['ctaLink'] ?? json['deepLink'] ?? json['ctaText'] ?? '')
              .toString(),
    );
  }
}

bool _isParcelActiveBooking(ActiveBookingData ride) {
  final bookingType = ride.bookingType.trim().toLowerCase();
  if (bookingType.isNotEmpty) return bookingType == 'parcel';

  // Fallback for older API: bike was only used for parcel flow in the app.
  final rideType = ride.rideType.trim().toLowerCase();
  return rideType == 'bike';
}

bool _isPaymentPending(ActiveBookingData ride) {
  final ps = (ride.paymentStatus ?? '').toString().trim().toUpperCase();
  final st = ride.status.trim().toUpperCase();
  return ps == 'PAYMENT_PENDING' ||
      st == 'PAYMENT_PENDING' ||
      ps.contains('PENDING') ||
      st.contains('PENDING');
}

bool _isPaymentSettled(ActiveBookingData ride) {
  final ps = (ride.paymentStatus ?? '').toString().trim().toUpperCase();
  if (ps.isEmpty) return false;
  return ps == 'PAID' ||
      ps == 'COMPLETED' ||
      ps == 'SUCCESS' ||
      ps == 'SUCCEEDED' ||
      ps == 'CAPTURED' ||
      ps.contains('PAID') ||
      ps.contains('SUCCESS');
}

bool _isCompletedStatus(ActiveBookingData ride) {
  final st = ride.status.trim().toUpperCase();
  return st == 'COMPLETED' ||
      st == 'COMPLETE' ||
      st == 'FINISHED' ||
      st.contains('COMPLETED') ||
      st.contains('FINISHED');
}

bool _isCustomerTerminalRide(ActiveBookingData ride) {
  if (ride.cancelled) return true;
  if (_isCompletedStatus(ride)) return true;
  return ride.destinationReached && _isPaymentSettled(ride);
}

AddressModel _activeBookingToAddress({
  required ActiveBookingData ride,
  required bool pickup,
}) {
  return AddressModel(
    name: pickup ? 'Sender' : 'Receiver',
    phone: '',
    address: pickup ? ride.pickupAddress : ride.dropAddress,
    landmark: '',
    mapAddress: pickup ? ride.pickupAddress : ride.dropAddress,
    latitude: pickup ? ride.fromLatitude : ride.toLatitude,
    longitude: pickup ? ride.fromLongitude : ride.toLongitude,
  );
}

class HomeScreens extends StatefulWidget {
  /// Bumped by the bottom nav each time the Home tab is (re)selected. The Home
  /// is kept alive (map never reloads), so we use this to replay the entrance
  /// transition when the user lands back on Home.
  final int activeTick;
  const HomeScreens({super.key, this.activeTick = 0});

  @override
  State<HomeScreens> createState() => _HomeScreensState();
}

class _HomeScreensState extends State<HomeScreens>
    with
        AutomaticKeepAliveClientMixin,
        WidgetsBindingObserver,
        SingleTickerProviderStateMixin {
  static const String _customerCompletedCashBookingKey =
      'customer_completed_cash_booking_id';

  @override
  bool get wantKeepAlive => true;

  final HomeMapController mapC =
      Get.isRegistered<HomeMapController>()
          ? Get.find<HomeMapController>()
          : Get.put(HomeMapController(), permanent: true);
  final ApiDataSource _apiDataSource = ApiDataSource();

  bool _busy = false;

  bool _initialPinAligned = false;
  // First valid map position. Once set we NEVER fall back to the loading
  // spinner, so the GoogleMap is created once and not destroyed/recreated
  // (that re-creation was the "map keeps reloading" you saw).
  LatLng? _firstMapPos;
  // True once the GoogleMap is created and given a beat to draw tiles; drives
  // the smooth fade-out of the premium "locating you" placeholder.
  bool _mapReady = false;
  final GlobalKey _mapKey = GlobalKey();
  final GlobalKey _pinKey = GlobalKey();
  static const double _pinTipVisualAdjustPx = 0;
  bool _mapScaleCaptured = false;
  double _mapScreenCoordScale = 1.0;
  Worker? _gateReadyWorker;
  bool _aligningUnderPin = false;

  String _pickupText = 'Pickup';
  LatLng? _pickupPos;

  bool _checkingActiveRide = false;
  String? _lastDismissedBookingId;
  ActiveBookingData? _activeRide;

  bool _loadingHomeHeroBanners = false;
  List<_HomeHeroBanner> _homeHeroBanners = const [];

  // DO NOT remove/add card from Stack. Only show/hide internally.
  final ValueNotifier<bool> _showActiveRideCard = ValueNotifier<bool>(false);

  final ValueNotifier<double> _sheetHeightN = ValueNotifier<double>(0);

  // Smooth one-time entrance when the home screen first appears (top bar drops
  // in, bottom sheet rises, everything fades up) for a premium open.
  late final AnimationController _entranceCtrl;
  late final Animation<double> _entranceFade;
  late final Animation<Offset> _topEntrance;
  late final Animation<Offset> _sheetEntrance;

  Future<String?> _getLocallyCompletedCashBookingId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_customerCompletedCashBookingKey);
  }

  Future<void> _clearLocallyCompletedCashBookingId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_customerCompletedCashBookingKey);
  }

  Future<bool> _shouldSuppressActiveRide(ActiveBookingData ride) async {
    final storedBookingId = await _getLocallyCompletedCashBookingId();

    if (storedBookingId != null && storedBookingId == ride.bookingId) {
      return true;
    }

    if (_isCustomerTerminalRide(ride)) {
      if (storedBookingId == ride.bookingId) {
        await _clearLocallyCompletedCashBookingId();
      }
      return true;
    }
    return false;
  }

  void _onSheetHeightChanged(double h) {
    if (!mounted) return;
    if (h <= 0) return;

    final prev = _sheetHeightN.value;
    if ((h - prev).abs() > 2) _sheetHeightN.value = h;
  }

  Future<void> _tryAlignCurrentLocationUnderPinOnce() async {
    if (!mounted) return;
    if (_initialPinAligned) return;
    if (_sheetHeightN.value <= 0) return;
    if (mapC.mapController == null) return;
    if (!mapC.gate.isReady.value) return;

    final ok = await _alignCurrentLocationUnderPin(immediateGeocode: true);
    if (!mounted) return;
    if (ok) _initialPinAligned = true;
  }

  Future<bool> _alignCurrentLocationUnderPin({
    required bool immediateGeocode,
  }) async {
    if (_aligningUnderPin) return false;
    _aligningUnderPin = true;
    try {
      // Wait for the pin overlay to lay out, otherwise RenderBoxes can be null.
      await Future.delayed(const Duration(milliseconds: 180));
      if (!mounted) return false;

      await _captureMapScreenScaleIfNeeded();
      final tip = _pinTipInMap();
      final center = _mapCenterInMap();
      if (tip == null || center == null) return false;

      await mapC.goToCurrentLocation();
      if (!mounted) return false;
      await Future.delayed(const Duration(milliseconds: 260));
      await _captureMapScreenScaleIfNeeded();

      final gps = mapC.devicePosition ?? mapC.currentPosition;
      if (gps == null) return false;

      await mapC.placeLatLngUnderScreenPoint(
        latLng: gps,
        desiredPoint: tip,
        centerPoint: center,
      );
      await Future.delayed(const Duration(milliseconds: 120));
      await mapC.placeLatLngUnderScreenPoint(
        latLng: gps,
        desiredPoint: tip,
        centerPoint: center,
      );

      if (immediateGeocode) {
        await mapC.onCameraIdleAt(
          pinTip: tip,
          immediateGeocode: true,
          suppressible: false,
        );
      }

      return true;
    } catch (_) {
      return false;
    } finally {
      _aligningUnderPin = false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // The HomeMapController is permanent, so whenever Home is re-created (after a
    // ride / payment / courier flow that rebuilds the bottom nav) it ALREADY
    // knows the user's location. Seed the map from it and skip the "locating"
    // placeholder so the map appears instantly at the known spot — Uber/Ola
    // style — instead of showing a fresh "Finding your location" load each time.
    final cachedPos = mapC.currentPosition;
    if (cachedPos != null) {
      _firstMapPos = cachedPos;
      _mapReady = true;
    }

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _entranceFade = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.0, 0.75, curve: Curves.easeOut),
    );
    _topEntrance = Tween<Offset>(
      begin: const Offset(0, -0.35),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOutCubic),
      ),
    );
    _sheetEntrance = Tween<Offset>(
      begin: const Offset(0, 0.22),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entranceCtrl.forward();
    });

    // Align pin + blue dot as soon as location permission becomes available.
    _gateReadyWorker = ever<bool>(mapC.gate.isReady, (ready) {
      if (!ready) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _tryAlignCurrentLocationUnderPinOnce();
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final screenH = MediaQuery.of(context).size.height;
      if (_sheetHeightN.value <= 0 && screenH > 0) {
        _sheetHeightN.value = screenH * 0.42;
      }

      // Safety: ensure no stale focus from previous auth screens causes keyboard insets animation.
      FocusManager.instance.primaryFocus?.unfocus();
      try {
        await SystemChannels.textInput.invokeMethod('TextInput.hide');
      } catch (_) {}

      await mapC.start();
      if (!mounted) return;
      await _loadActiveRide();
      if (!mounted) return;
      await _loadHomeHeroBanners();
      if (!mounted) return;
      _tryAlignCurrentLocationUnderPinOnce();
    });
  }

  Future<void> _loadHomeHeroBanners() async {
    if (!mounted) return;
    if (_loadingHomeHeroBanners) return;

    setState(() {
      _loadingHomeHeroBanners = true;
    });

    try {
      const url = 'https://bk.myhoppr.com/api/customer/advertisement-banners';
      final res = await Request.sendGetRequest(
        url,
        {'placement': 'HOME_HERO', 'limit': 5},
        'GET',
        true,
      );

      final data = res?.data;
      if (data is! Map) return;
      if (data['success'] != true) return;

      final inner = data['data'];
      if (inner is! Map) return;

      final raw = inner['banners'];
      if (raw is! List) return;

      final parsed = raw
          .whereType<Map>()
          .map((e) => _HomeHeroBanner.fromJson(Map<String, dynamic>.from(e)))
          .where((b) => b.imageUrl.trim().isNotEmpty)
          .toList(growable: false);

      if (!mounted) return;
      setState(() => _homeHeroBanners = parsed);
    } catch (_) {
      // ignore banner failures; home should still work
    } finally {
      if (!mounted) return;
      setState(() => _loadingHomeHeroBanners = false);
    }
  }

  @override
  void didUpdateWidget(covariant HomeScreens oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Home tab re-selected (kept alive in the IndexedStack) -> replay the
    // entrance transition. The map is NOT touched, so it never reloads.
    if (widget.activeTick != oldWidget.activeTick) {
      _entranceCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _entranceCtrl.dispose();
    _gateReadyWorker?.dispose();
    _showActiveRideCard.dispose();
    _sheetHeightN.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadActiveRide();
    }
  }

  // Bottom sheet is draggable now; its height is tracked via _onSheetHeightChanged.

  Future<void> _captureMapScreenScaleIfNeeded() async {
    if (_mapScaleCaptured) return;

    final mapBox = _mapKey.currentContext?.findRenderObject() as RenderBox?;
    final controller = mapC.mapController;
    final pos = mapC.cameraTarget;
    if (mapBox == null || controller == null || pos == null) return;

    final w2 = mapBox.size.width / 2;
    final h2 = mapBox.size.height / 2;
    if (w2 <= 0 || h2 <= 0) return;

    try {
      // Give the platform view a moment to settle; otherwise screen coords can
      // be reported as 0,0 on some devices.
      await Future.delayed(const Duration(milliseconds: 250));

      // When map opens, camera target == currentPosition, so its screen point
      // should be at the map center. We use this to infer the coordinate scale
      // used by the GoogleMap platform view (logical vs physical pixels).
      final sc = await controller.getScreenCoordinate(pos);
      if (sc.x == 0 || sc.y == 0) return;
      final sx = sc.x / w2;
      final sy = sc.y / h2;
      final scale = ((sx + sy) / 2.0);

      if (!scale.isFinite || scale < 0.75 || scale > 8.0) return;

      if (!mounted) return;
      setState(() {
        _mapScaleCaptured = true;
        _mapScreenCoordScale = scale;
      });
    } catch (_) {}
  }

  ScreenCoordinate? _pinTipInMap() {
    final mapBox = _mapKey.currentContext?.findRenderObject() as RenderBox?;
    final pinBox = _pinKey.currentContext?.findRenderObject() as RenderBox?;
    if (mapBox == null || pinBox == null) return null;

    final mapOrigin = mapBox.localToGlobal(Offset.zero);
    final pinTipGlobal = pinBox.localToGlobal(
      Offset(pinBox.size.width / 2, pinBox.size.height),
    );
    final local = pinTipGlobal - mapOrigin;

    final scale =
        _mapScaleCaptured
            ? _mapScreenCoordScale
            : MediaQuery.of(context).devicePixelRatio;
    final maxX = (mapBox.size.width * scale).round();
    final maxY = (mapBox.size.height * scale).round();

    final x = (local.dx * scale).round().clamp(0, maxX);
    final y = ((local.dy - _pinTipVisualAdjustPx) * scale).round().clamp(
      0,
      maxY,
    );
    return ScreenCoordinate(x: x, y: y);
  }

  ScreenCoordinate? _mapCenterInMap() {
    final mapBox = _mapKey.currentContext?.findRenderObject() as RenderBox?;
    if (mapBox == null) return null;

    final scale =
        _mapScaleCaptured
            ? _mapScreenCoordScale
            : MediaQuery.of(context).devicePixelRatio;

    final x = (mapBox.size.width * scale / 2).round();
    final y = (mapBox.size.height * scale / 2).round();
    return ScreenCoordinate(x: x, y: y);
  }

  Future<void> _ensureCurrentPickup() async {
    final tip = _pinTipInMap();
    final latest =
        tip == null
            ? await mapC.onCameraIdle(
              immediateGeocode: true,
              suppressible: false,
            )
            : await mapC.onCameraIdleAt(
              pinTip: tip,
              immediateGeocode: true,
              suppressible: false,
            );

    if (mapC.currentPosition == null) {
      await mapC.initLocation();
      if (mapC.currentPosition == null) return;
    }

    _pickupPos = mapC.currentPosition;
    final liveAddress = (latest ?? mapC.address.value).trim();
    if (liveAddress.isNotEmpty && liveAddress != 'Fetching your location...') {
      _pickupText = liveAddress;
    } else {
      _pickupText = await mapC.getAddressFromLatLng(_pickupPos!);
    }
  }

  Future<void> _openBookRideSearch() async {
    if (_busy) return;
    _busy = true;
    try {
      await _ensureCurrentPickup();
      if (_pickupPos == null) return;

      // Keep home as "half map" only; booking flow continues on the search screen.
      Get.to(
        () => BookRideSearchScreen(
          isPickup: false,
          pickupData: {
            'description': _pickupText,
            'lat': _pickupPos!.latitude,
            'lng': _pickupPos!.longitude,
          },
        ),
        transition: Transition.downToUp,
        curve: Curves.easeOutCubic,
        duration: const Duration(milliseconds: 360),
      );
    } finally {
      _busy = false;
    }
  }

  Future<void> _loadActiveRide() async {
    if (_checkingActiveRide) return;

    if (mounted) {
      setState(() => _checkingActiveRide = true);
    }

    final result = await _apiDataSource.getActiveBooking();
    if (!mounted) return;

    await result.fold<Future<void>>(
      (_) async {
        // API fail -> don't disturb main screen
        setState(() {
          _checkingActiveRide = false;
        });
      },
      (response) async {
        final data = response.data;
        final shouldSuppressRide =
            data != null ? await _shouldSuppressActiveRide(data) : false;

        final hasValidActiveRide =
            response.success &&
            response.hasActiveBooking &&
            data != null &&
            !shouldSuppressRide;

        setState(() {
          _checkingActiveRide = false;

          if (hasValidActiveRide) {
            final previousBookingId = _activeRide?.bookingId;
            _activeRide = data;

            if (_lastDismissedBookingId == data.bookingId) {
              _showActiveRideCard.value = false;
            } else {
              _showActiveRideCard.value = true;
            }

            if (previousBookingId != null &&
                previousBookingId != data.bookingId) {
              _showActiveRideCard.value = true;
            }
          } else {
            _activeRide = null;
            _lastDismissedBookingId = null;
            _showActiveRideCard.value = false;
          }
        });

        if (!hasValidActiveRide && !shouldSuppressRide) {
          await _clearLocallyCompletedCashBookingId();
        }
      },
    );
  }

  Future<void> _resumeActiveRide() async {
    final ride = _activeRide;
    if (ride == null) return;

    if (await _shouldSuppressActiveRide(ride)) {
      if (mounted) {
        setState(() {
          _activeRide = null;
          _lastDismissedBookingId = null;
          _showActiveRideCard.value = false;
        });
      }
      return;
    }

    debugPrint(
      'ResumeActiveRide bookingType=${ride.bookingType} '
      'rideType=${ride.rideType} status=${ride.status} '
      'paymentStatus=${ride.paymentStatus}',
    );

    // If payment is pending, jump directly to the payment screen:
    // - Parcel/Bike -> payment screen with sender/receiver
    // - Car -> payment screen with driver details
    if (_isPaymentPending(ride)) {
      if (_isParcelActiveBooking(ride)) {
        await Get.to(
          () => PaymentScreen(
            bookingId: ride.bookingId,
            amount: ride.amount,
            sender: _activeBookingToAddress(ride: ride, pickup: true),
            receiver: _activeBookingToAddress(ride: ride, pickup: false),
            driverName: ride.driverName,
            driverProfilePic: ride.driverProfilePic,
          ),
        );
      } else {
        await Get.to(
          () => PaymentScreen(
            bookingId: ride.bookingId,
            amount: ride.amount,
            driverName: ride.driverName,
            driverProfilePic: ride.driverProfilePic,
          ),
        );
      }

      if (!mounted) return;
      await _loadActiveRide();
      return;
    }

    if (_isParcelActiveBooking(ride)) {
      await Get.to(
        () => PackageMapConfirmScreen(
          bookingId: ride.bookingId,
          discountCode: '',
          senderData: _activeBookingToAddress(ride: ride, pickup: true),
          receiverData: _activeBookingToAddress(ride: ride, pickup: false),
        ),
      );

      if (!mounted) return;
      await _loadActiveRide();
      return;
    }

    final serviceMode = ride.driverServiceMode.trim().toLowerCase();
    final isShared =
        ride.sharedBooking == true ||
        serviceMode == 'shared' ||
        serviceMode.contains('shared');

    if (isShared) {
      // Ensure shared socket joins the booking room before opening the screen.
      final s = RideShareSocketService();
      if (!s.connected) {
        s.initSocket(ApiConsents.sharedBaseUrl);
      }
      s.setBooking(ride.bookingId);

      await Get.to(
        () => SharedScreens(
          pickupAddress: ride.pickupAddress,
          destinationAddress: ride.dropAddress,
          // Carry the fare breakdown into the resumed shared ride. Without these
          // the Fare Breakdown card rendered all 0.0 on resume (the normal
          // confirm flow passes them, the resume path previously did not).
          baseFare: ride.baseFare,
          serviceFare: ride.serviceFare,
          distanceFare: ride.distanceFare,
          pickupFare: ride.pickupFare,
          bookingFee: ride.bookingFee,
          timeFare: ride.timeFare,
          initialPosition:
              ride.driverLocation != null
                  ? LatLng(
                    ride.driverLocation!.latitude,
                    ride.driverLocation!.longitude,
                  )
                  : LatLng(ride.fromLatitude, ride.fromLongitude),
          pickupPosition: LatLng(ride.fromLatitude, ride.fromLongitude),
          dropPosition: LatLng(ride.toLatitude, ride.toLongitude),
          carType: ride.rideType.trim().isNotEmpty ? ride.rideType : 'car',
          initialStatus: ride.status,
          initialRideStarted: ride.rideStarted,
          initialDestinationReached: ride.destinationReached,
          resumeDriverId: ride.driverId.isEmpty ? null : ride.driverId,
          initialDriverPosition:
              ride.driverLocation != null
                  ? LatLng(
                    ride.driverLocation!.latitude,
                    ride.driverLocation!.longitude,
                  )
                  : null,
        ),
      );

      if (!mounted) return;
      await _loadActiveRide();
      return;
    }

    final vehicle = ride.vehicle;
    final carType =
        vehicle?.carType.trim().isNotEmpty == true
            ? vehicle!.carType
            : ride.rideType.toLowerCase();

    final initialCarDetails = [
      vehicle?.color ?? '',
      vehicle?.brand ?? '',
      vehicle?.model ?? '',
    ].where((item) => item.trim().isNotEmpty).join(' - ');

    await Get.to(
      () => OrderConfirmScreen(
        pickupData: {
          'description': ride.pickupAddress,
          'lat': ride.fromLatitude,
          'lng': ride.fromLongitude,
        },
        destinationData: {
          'description': ride.dropAddress,
          'lat': ride.toLatitude,
          'lng': ride.toLongitude,
        },
        pickupAddress: ride.pickupAddress,
        bookingId: ride.bookingId,
        carType: carType,
        destinationAddress: ride.dropAddress,
        resumeDriverId: ride.driverId.isEmpty ? null : ride.driverId,
        initialDriverName: ride.driverName,
        initialDriverProfilePic: ride.driverProfilePic,
        initialCarDetails: initialCarDetails,
        baseFare: ride.baseFare,
        serviceFare: ride.serviceFare,
        distanceFare: ride.distanceFare,
        pickupFare: ride.pickupFare,
        bookingFee: ride.bookingFee,
        timeFare: ride.timeFare,
        initialAmount: ride.amount > 0 ? ride.amount : (ride.total ?? 0.0),
        initialStatus: ride.status,
        initialRideStarted: ride.rideStarted,
        initialDestinationReached: ride.destinationReached,
      ),
    );

    if (!mounted) return;
    await _loadActiveRide();
  }

  Widget _activeRideCard(double topPad) {
    return Positioned(
      top: topPad + 76,
      left: 16,
      right: 16,
      child: ValueListenableBuilder<bool>(
        valueListenable: _showActiveRideCard,
        builder: (context, visible, _) {
          final ride = _activeRide;
          final shouldShow = visible && ride != null;

          final subtitle =
              ride != null && ride.driverName.trim().isNotEmpty
                  ? 'Driver ${ride.driverName} - ${ride.status.replaceAll('_', ' ')}'
                  : (ride?.status.replaceAll('_', ' ') ?? '');

          return IgnorePointer(
            ignoring: !shouldShow,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: shouldShow ? 1 : 0,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 180),
                offset: shouldShow ? Offset.zero : const Offset(0, -0.08),
                child:
                    ride == null
                        ? const SizedBox.shrink()
                        : Material(
                          color: Colors.transparent,
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.black.withOpacity(0.08),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 16,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: Colors.black,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.local_taxi,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Active ride in progress',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            subtitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.black.withOpacity(
                                                0.65,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  ride.pickupAddress,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  ride.dropAddress,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.black.withOpacity(0.6),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () {
                                          _lastDismissedBookingId =
                                              ride.bookingId;
                                          _showActiveRideCard.value = false;
                                        },
                                        child: const Text('Not now'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: _resumeActiveRide,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.black,
                                          foregroundColor: Colors.white,
                                        ),
                                        child: const Text('Resume ride'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final topPad = MediaQuery.of(context).padding.top;
    final screenH = MediaQuery.of(context).size.height;

    final fabBottomMax = (screenH - topPad - 160);

    return NoInternetOverlay(
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            Positioned.fill(
              child: Obx(() {
                // Ensure map rebuilds when nearby-driver markers update.
                mapC.markersRevision.value;
                final pos = mapC.currentPosition ?? _firstMapPos;
                // Remember the first fix; the map is created once from it and
                // never torn down even if currentPosition momentarily clears.
                _firstMapPos ??= pos;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_firstMapPos != null)
                      SizedBox(
                        key: _mapKey,
                        child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _firstMapPos!,
                      // Nearby drivers on pickup screen.
                      zoom: 15.5,
                    ),
                    // Keep padding zero so map projection matches overlay pin coordinates.
                    padding: EdgeInsets.zero,
                    markers: mapC.markers.toSet(),
                    circles: mapC.circles.toSet(),
                    onMapCreated: (controller) async {
                      debugPrint("Main Map created");
                      await mapC.attachMap(controller);
                      if (!mounted) return;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _captureMapScreenScaleIfNeeded();
                      });
                      _onSheetHeightChanged(_sheetHeightN.value);
                      _tryAlignCurrentLocationUnderPinOnce();
                      // Fade the "locating you" placeholder out once the map is
                      // created and tiles have a beat to paint — smooth reveal.
                      Future.delayed(const Duration(milliseconds: 650), () {
                        if (mounted && !_mapReady) {
                          setState(() => _mapReady = true);
                        }
                      });
                    },
                    onTap: (_) {},
                    onCameraMove: mapC.onCameraMove,
                    onCameraIdle: () async {
                      _captureMapScreenScaleIfNeeded();
                      final tip = _pinTipInMap();
                      if (tip == null) {
                        await mapC.onCameraIdle(immediateGeocode: false);
                      } else {
                        await mapC.onCameraIdleAt(
                          pinTip: tip,
                          immediateGeocode: false,
                        );
                      }
                    },
                    myLocationEnabled: mapC.gate.isReady.value,
                    myLocationButtonEnabled: false,
                    buildingsEnabled: false,
                    tiltGesturesEnabled: false,
                    minMaxZoomPreference: const MinMaxZoomPreference(
                      14.0,
                      18.0,
                    ),
                    mapToolbarEnabled: false,
                    zoomControlsEnabled: false,
                    gestureRecognizers: {
                      Factory<OneSequenceGestureRecognizer>(
                        () => EagerGestureRecognizer(),
                      ),
                    },
                  ),
                      ),
                    // Premium "locating you" placeholder over the map; fades out
                    // smoothly once the map is ready (no spinner, no flash).
                    IgnorePointer(
                      ignoring: _mapReady,
                      child: AnimatedOpacity(
                        opacity: _mapReady ? 0.0 : 1.0,
                        duration: const Duration(milliseconds: 550),
                        curve: Curves.easeOut,
                        child: const _HomeLoadingView(),
                      ),
                    ),
                  ],
                );
              }),
            ),

            // Smooth current-location pulse (Flutter overlay). Avoids map
            // `circles` updates which can feel laggy on Android.
            Positioned.fill(child: _HomePulseOverlay(mapC: mapC)),

            Positioned(
              top: topPad + 10,
              left: 16,
              right: 16,
              child: SlideTransition(
                position: _topEntrance,
                child: FadeTransition(
                  opacity: _entranceFade,
                  child: Row(
                    children: [
                      // LEFT: circular menu button (opens the drawer)
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => DrawerScreen()),
                          );
                        },
                        child: Container(
                          height: 48,
                          width: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.10),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.menu,
                            size: 22,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // MIDDLE: current-location search box with a heart
                      Expanded(
                        child: GestureDetector(
                          onTap: _openBookRideSearch,
                          child: Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.10),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.my_location,
                                  size: 18,
                                  color: AppColors.walletCurrencyColor,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Obx(
                                    () => Text(
                                      mapC.address.value.isEmpty
                                          ? 'Current Location'
                                          : mapC.address.value,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () =>
                                      Get.to(() => const FavouritesScreen()),
                                  child: const Icon(
                                    Icons.favorite_border,
                                    size: 20,
                                    color: Color(0xFFE53935),
                                  ),
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
            ),

            _activeRideCard(topPad),

            ValueListenableBuilder<double>(
              valueListenable: _sheetHeightN,
              builder: (context, sheetH, _) {
                final fabBottom =
                    (sheetH + 16)
                        .clamp(16.0, fabBottomMax > 16 ? fabBottomMax : 16.0)
                        .toDouble();

                return Positioned(
                  right: 12,
                  bottom: fabBottom,
                  child: FloatingActionButton(
                    heroTag: 'home_my_loc',
                    mini: true,
                    backgroundColor: Colors.white,
                    onPressed: () async {
                      await mapC.goToCurrentLocation();
                      if (!mounted) return;

                      final tip = _pinTipInMap();
                      final center = _mapCenterInMap();
                      if (tip != null && center != null) {
                        final gps = mapC.devicePosition ?? mapC.currentPosition;
                        if (gps != null) {
                          await mapC.placeLatLngUnderScreenPoint(
                            latLng: gps,
                            desiredPoint: tip,
                            centerPoint: center,
                          );
                        }
                        await mapC.onCameraIdleAt(
                          pinTip: tip,
                          immediateGeocode: true,
                          suppressible: false,
                        );
                      }

                      await _ensureCurrentPickup();
                    },
                    child: const Icon(Icons.my_location, color: Colors.black),
                  ),
                );
              },
            ),

            Positioned.fill(
              child: SlideTransition(
                position: _sheetEntrance,
                child: FadeTransition(
                  opacity: _entranceFade,
                  child: _HomeBottomSheet(
                    mapC: mapC,
                    onBookRideTap: _openBookRideSearch,
                    onHeightChanged: _onSheetHeightChanged,
                    banners: _homeHeroBanners,
                    bannersLoading: _loadingHomeHeroBanners,
                  ),
                ),
              ),
            ),

            ValueListenableBuilder<double>(
              valueListenable: _sheetHeightN,
              builder: (context, sheetH, _) {
                const homePinAlignY = -0.18;
                final hidePin =
                    screenH > 0 ? ((sheetH / screenH) >= 0.62) : false;

                return Positioned.fill(
                  child: IgnorePointer(
                    ignoring: hidePin,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 140),
                      opacity: hidePin ? 0 : 1,
                      child: Align(
                        alignment: const Alignment(0, homePinAlignY),
                        child: Column(
                          key: _pinKey,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 14,
                              height: 5,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Image.asset(
                              AppImages.pinLocation,
                              height: 44,
                              width: 28,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// BOTTOM SHEET
// -----------------------------------------------------------------------------
class _HomeBottomSheet extends StatelessWidget {
  final HomeMapController mapC;
  final VoidCallback onBookRideTap;
  final ValueChanged<double> onHeightChanged;
  final List<_HomeHeroBanner> banners;
  final bool bannersLoading;

  const _HomeBottomSheet({
    super.key,
    required this.mapC,
    required this.onBookRideTap,
    required this.onHeightChanged,
    required this.banners,
    required this.bannersLoading,
  });

  // Smooth, crash-safe banner deep-linking. Only known-built flows navigate;
  // everything else (referral / wallet / safety / coupon / url / unknown) is a
  // soft "coming soon" so a missing screen can never crash the app. `none` and
  // empty links are non-actionable.
  void _handleBannerTap(BuildContext context, _HomeHeroBanner b) {
    final link = b.ctaLink.trim().toLowerCase();
    if (link.isEmpty || link == 'none') return;

    switch (link) {
      case 'book_ride':
        HapticFeedback.mediumImpact();
        onBookRideTap();
        return;
      case 'send_parcel':
      case 'courier':
        HapticFeedback.mediumImpact();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const CommonBottomNavigation(initialIndex: 3),
          ),
        );
        return;
      case 'safety':
        HapticFeedback.mediumImpact();
        Get.to(() => const SafetySetupScreen());
        return;
      default:
        Get.snackbar(
          'Coming soon',
          'This will be available shortly.',
          snackPosition: SnackPosition.BOTTOM,
          margin: const EdgeInsets.all(16),
          borderRadius: 14,
          backgroundColor: Colors.black.withOpacity(0.85),
          colorText: Colors.white,
          duration: const Duration(seconds: 2),
        );
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;

    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (n) {
        if (screenH > 0) onHeightChanged(n.extent * screenH);
        return false;
      },
      child: DraggableScrollableSheet(
        initialChildSize: 0.47,
        minChildSize: 0.30,
        maxChildSize: 0.86,
        snap: true,
        snapAnimationDuration: const Duration(milliseconds: 280),
        snapSizes: const [0.30, 0.47, 0.68, 0.86],
        builder: (context, scrollController) {
          return Material(
            color: Colors.white,
            elevation: 14,
            shadowColor: Colors.black26,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(22),
              topRight: Radius.circular(22),
            ),
            clipBehavior: Clip.antiAlias,
            child: SafeArea(
              top: false,
              child: ListView(
                controller: scrollController,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: onBookRideTap,
                          child: PackageContainer.customRideContainer(
                            tittle: 'Book Ride',
                            subTitle: 'Best Drivers',
                            img: AppImages.carImage,
                            imgHeight: 25,
                            imgWeight: 45,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: PackageContainer.customRideContainer(
                          onTap: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (_) => const CommonBottomNavigation(
                                      initialIndex: 3,
                                    ),
                              ),
                            );
                          },
                          tittle: 'Courier',
                          subTitle: 'Fast Delivery',
                          img: AppImages.bikeImage,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  Card(
                    elevation: 3,
                    shadowColor: Colors.black.withOpacity(0.10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppColors.commonBlack.withOpacity(0.04),
                        ),
                        borderRadius: BorderRadius.circular(20),
                        color: AppColors.commonWhite,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                        child: Column(
                          children: [
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () async {
                                    if (mapC.currentPosition == null) {
                                      await mapC.initLocation();
                                      if (mapC.currentPosition == null) return;
                                    }

                                    final pickupAddress = await mapC
                                        .getAddressFromLatLng(
                                          mapC.currentPosition!,
                                        );

                                    final pickupData = {
                                      'description': pickupAddress,
                                      'lat': mapC.currentPosition!.latitude,
                                      'lng': mapC.currentPosition!.longitude,
                                    };

                                    Get.to(
                                      () => BookRideSearchScreen(
                                        isPickup: false,
                                        pickupData: pickupData,
                                      ),
                                      transition: Transition.downToUp,
                                      curve: Curves.easeOutCubic,
                                      duration: const Duration(
                                        milliseconds: 360,
                                      ),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 11,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color(0xFFF7F9FC),
                                          Color(0xFFEDF3FD),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: const Color(
                                          0xFF2563EB,
                                        ).withOpacity(0.10),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          height: 40,
                                          width: 40,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF2563EB),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(
                                                  0xFF2563EB,
                                                ).withOpacity(0.30),
                                                blurRadius: 10,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.search_rounded,
                                            color: Colors.white,
                                            size: 22,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Text(
                                                'Where to?',
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.commonBlack,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Search destination',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: AppColors.textColor,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(
                                                  0.06,
                                                ),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.arrow_forward_rounded,
                                            size: 16,
                                            color: Color(0xFF2563EB),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 8),

                            Obx(() {
                              final recents = mapC.recentLocations;
                              final popular = mapC.popularPlaces;

                              // Professional combined list: most-recent first
                              // then nearby popular destinations, deduped,
                              // capped at 4.
                              final items = <Map<String, dynamic>>[];
                              final seen = <String>{};

                              void add({
                                required String title,
                                required double lat,
                                required double lng,
                                required String category,
                              }) {
                                if (items.length >= 4) return;
                                final key = title.trim().toLowerCase();
                                if (key.isEmpty || seen.contains(key)) return;
                                seen.add(key);
                                items.add({
                                  'title': title,
                                  'lat': lat,
                                  'lng': lng,
                                  'category': category,
                                });
                              }

                              for (final r in recents.take(4)) {
                                add(
                                  title: r.description,
                                  lat: r.lat,
                                  lng: r.lng,
                                  category: 'recent',
                                );
                              }
                              for (final p in popular) {
                                add(
                                  title: p.name,
                                  lat: p.lat,
                                  lng: p.lng,
                                  category: p.category,
                                );
                              }

                              if (items.isEmpty) {
                                return const SizedBox.shrink();
                              }

                              return Column(
                                children: List.generate(items.length, (index) {
                                  final it = items[index];
                                  final category = it['category'] as String;
                                  final accent = _quickDestColor(category);

                                  return TweenAnimationBuilder<double>(
                                    key: ValueKey(it['title']),
                                    tween: Tween(begin: 0, end: 1),
                                    duration: Duration(
                                      milliseconds: 280 + index * 80,
                                    ),
                                    curve: Curves.easeOutCubic,
                                    builder: (context, t, child) {
                                      return Opacity(
                                        opacity: t.clamp(0.0, 1.0),
                                        child: Transform.translate(
                                          offset: Offset(0, (1 - t) * 12),
                                          child: child,
                                        ),
                                      );
                                    },
                                    child: Column(
                                    children: [
                                      InkWell(
                                        borderRadius: BorderRadius.circular(14),
                                        onTap: () async {
                                          if (mapC.currentPosition == null) {
                                            await mapC.initLocation();
                                            if (mapC.currentPosition == null) {
                                              return;
                                            }
                                          }

                                          final pickupAddress = await mapC
                                              .getAddressFromLatLng(
                                                mapC.currentPosition!,
                                              );

                                          Get.to(
                                            () => BookMapScreen(
                                              pickupData: {
                                                'name': pickupAddress,
                                                'lat':
                                                    mapC
                                                        .currentPosition
                                                        ?.latitude,
                                                'lng':
                                                    mapC
                                                        .currentPosition
                                                        ?.longitude,
                                              },
                                              destinationData: {
                                                'name': it['title'],
                                                'lat': it['lat'],
                                                'lng': it['lng'],
                                              },
                                              pickupAddress: pickupAddress,
                                              destinationAddress:
                                                  it['title'] as String,
                                            ),
                                          );
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 9,
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                height: 42,
                                                width: 42,
                                                alignment: Alignment.center,
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                    colors: [
                                                      accent.withOpacity(0.18),
                                                      accent.withOpacity(0.06),
                                                    ],
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(13),
                                                  border: Border.all(
                                                    color: accent.withOpacity(
                                                      0.20,
                                                    ),
                                                  ),
                                                ),
                                                child: Icon(
                                                  _quickDestIcon(category),
                                                  size: 21,
                                                  color: accent,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child:
                                                    CustomTextFields.textWithStylesSmall(
                                                      it['title'] as String,
                                                      maxLines: 1,
                                                      textAlign: TextAlign.left,
                                                      colors:
                                                          AppColors.commonBlack,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                              ),
                                              Icon(
                                                Icons.arrow_outward_rounded,
                                                size: 18,
                                                color: AppColors.commonBlack
                                                    .withOpacity(0.35),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (index != items.length - 1)
                                        Divider(
                                          height: 1,
                                          indent: 58,
                                          endIndent: 8,
                                          color: AppColors.commonBlack
                                              .withOpacity(0.06),
                                        ),
                                    ],
                                    ),
                                  );
                                }),
                              );
                            }),

                            const SizedBox(height: 5),
                            CustomTextFields.textWithStylesSmall(
                              AppTexts.tellUsYourDestination,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
  const SizedBox(height: 20),
                  if (banners.isNotEmpty) ...[
                    _HomeBannerCarousel(
                      banners: banners,
                      onBannerTap: (b) => _handleBannerTap(context, b),
                    ),
                  ] else if (bannersLoading) ...[
                    SkeletonLoaders.homeBanner(),
                  ],

                  // const SizedBox(height: 20),
                  // Container(
                  //   padding: const EdgeInsets.symmetric(vertical: 10),
                  //   decoration: BoxDecoration(
                  //     borderRadius: BorderRadius.circular(15),
                  //     color: AppColors.advertisementColor,
                  //   ),
                  //   child: ListTile(
                  //     title: RichText(
                  //       text: TextSpan(
                  //         children: [
                  //           TextSpan(
                  //             text: 'JUST IN ',
                  //             style: TextStyle(
                  //               color: AppColors.justInColor,
                  //               fontWeight: FontWeight.w900,
                  //               fontSize: 16,
                  //             ),
                  //           ),
                  //           const TextSpan(
                  //             text: 'Now, Pay at the drop location with ',
                  //             style: TextStyle(
                  //               color: Colors.black,
                  //               fontWeight: FontWeight.normal,
                  //               fontSize: 16,
                  //             ),
                  //           ),
                  //           TextSpan(
                  //             text: 'COD',
                  //             style: TextStyle(
                  //               color: AppColors.commonBlack,
                  //               fontWeight: FontWeight.w900,
                  //               fontSize: 16,
                  //             ),
                  //           ),
                  //         ],
                  //       ),
                  //     ),
                  //     trailing: Image.asset(AppImages.advertisement),
                  //   ),
                  // ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HomePulseOverlay extends StatefulWidget {
  final HomeMapController mapC;
  const _HomePulseOverlay({required this.mapC});

  @override
  State<_HomePulseOverlay> createState() => _HomePulseOverlayState();
}

class _HomePulseOverlayState extends State<_HomePulseOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: Obx(() {
        if (!widget.mapC.gate.isReady.value) return const SizedBox.shrink();
        final o = widget.mapC.pulseOffset.value;
        if (o == null) return const SizedBox.shrink();

        return RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              return CustomPaint(
                painter: _PulsePainter(center: o, t: _c.value),
              );
            },
          ),
        );
      }),
    );
  }
}

class _PulsePainter extends CustomPainter {
  final Offset center;
  final double t; // 0..1

  const _PulsePainter({required this.center, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    const ringColor = Color(0xFF34C759);

    // Ease in/out to reduce "steppy" feel.
    final eased =
        t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3).toDouble() / 2;

    final radius = 8.0 + (26.0 * eased); // px
    final alpha = (0.18 * (1.0 - eased)).clamp(0.0, 0.18);

    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = ringColor.withOpacity(alpha);

    // If offset is off-map, skip paint.
    if (center.dx.isNaN ||
        center.dy.isNaN ||
        center.dx < -80 ||
        center.dy < -80 ||
        center.dx > size.width + 80 ||
        center.dy > size.height + 80) {
      return;
    }

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _PulsePainter oldDelegate) {
    return oldDelegate.center != center || oldDelegate.t != t;
  }
}

// (Removed old commented duplicate HomeScreens code to avoid confusion.)

/// Premium "locating you" placeholder shown over the map until it is ready.
/// Replaces the old bare CircularProgressIndicator with a real-time GPS-style
/// radar pulse + a skeleton bottom sheet, so the first open feels light and
/// polished (Uber / Ola style) instead of a heavy white-screen spinner.
class _HomeLoadingView extends StatefulWidget {
  const _HomeLoadingView();

  @override
  State<_HomeLoadingView> createState() => _HomeLoadingViewState();
}

class _HomeLoadingViewState extends State<_HomeLoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  static const Color _mapTone = Color(0xFFF1F4F9);
  static const Color _skeleton = Color(0xFFE9ECF2);
  static const Color _skeletonHi = Color(0xFFF7F9FC);

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _mapTone,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Full-screen map placeholder shimmer (fills behind the sheet).
          _mapShimmer(),

          // Skeleton of the real bottom sheet so the reveal feels continuous.
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 22,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 4,
                    width: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E5EC),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Pickup + destination fields
                  _bar(height: 52, radius: 14),
                  const SizedBox(height: 12),
                  _bar(height: 52, radius: 14),
                  const SizedBox(height: 18),
                  // Recent / popular destination rows (icon + label)
                  _skeletonRow(),
                  const SizedBox(height: 14),
                  _skeletonRow(),
                  const SizedBox(height: 20),
                  // Promo banner placeholder ("down image")
                  _bar(height: 120, radius: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Full-bleed shimmering block for the map area.
  Widget _mapShimmer() {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final v = _c.value;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: const [_skeleton, _skeletonHi, _skeleton],
              stops: [
                (v - 0.3).clamp(0.0, 1.0),
                v.clamp(0.0, 1.0),
                (v + 0.3).clamp(0.0, 1.0),
              ],
            ),
          ),
        );
      },
    );
  }

  // A recent-destination row skeleton: square icon tile + a text bar.
  Widget _skeletonRow() {
    return Row(
      children: [
        Container(
          height: 42,
          width: 42,
          decoration: BoxDecoration(
            color: _skeleton,
            borderRadius: BorderRadius.circular(13),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: _bar(height: 14, radius: 7, widthFactor: 0.8)),
      ],
    );
  }

  // A shimmering skeleton bar that sweeps a soft highlight left-to-right.
  Widget _bar({
    required double height,
    double radius = 12,
    double widthFactor = 1.0,
  }) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final v = _c.value;
            return Container(
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: const [_skeleton, _skeletonHi, _skeleton],
                  stops: [
                    (v - 0.3).clamp(0.0, 1.0),
                    v.clamp(0.0, 1.0),
                    (v + 0.3).clamp(0.0, 1.0),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Home promo banner: a larger rounded image card carousel with page dots below
/// and an app tagline beneath them (server-driven images). Auto-advances.
class _HomeBannerCarousel extends StatefulWidget {
  final List<_HomeHeroBanner> banners;
  final ValueChanged<_HomeHeroBanner> onBannerTap;
  const _HomeBannerCarousel({
    required this.banners,
    required this.onBannerTap,
  });

  @override
  State<_HomeBannerCarousel> createState() => _HomeBannerCarouselState();
}

class _HomeBannerCarouselState extends State<_HomeBannerCarousel> {
  static const Color _ink = Color(0xFF161A2E);

  final PageController _pc = PageController();
  int _index = 0;
  Timer? _auto;

  // Real banner aspect ratio (width/height), read from the actual image so the
  // card fits it exactly — no crop ("missing content") and no empty bands,
  // identical on every device. Falls back to 2.0 until the image resolves.
  double _bannerRatio = 2.0;

  @override
  void initState() {
    super.initState();
    _startAuto();
    _resolveBannerRatio();
  }

  @override
  void didUpdateWidget(covariant _HomeBannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldUrl =
        oldWidget.banners.isNotEmpty ? oldWidget.banners.first.imageUrl : '';
    final newUrl =
        widget.banners.isNotEmpty ? widget.banners.first.imageUrl : '';
    if (oldUrl != newUrl) _resolveBannerRatio();
  }

  void _resolveBannerRatio() {
    if (widget.banners.isEmpty) return;
    final provider = CachedNetworkImageProvider(widget.banners.first.imageUrl);
    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        final w = info.image.width.toDouble();
        final h = info.image.height.toDouble();
        if (mounted && h > 0) {
          final r = (w / h).clamp(1.2, 3.2);
          if ((r - _bannerRatio).abs() > 0.001) {
            setState(() => _bannerRatio = r);
          }
        }
        stream.removeListener(listener);
      },
      onError: (_, __) => stream.removeListener(listener),
    );
    stream.addListener(listener);
  }

  void _startAuto() {
    _auto?.cancel();
    if (widget.banners.length < 2) return;
    _auto = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_pc.hasClients) return;
      final next = (_index + 1) % widget.banners.length;
      _pc.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banners = widget.banners;
    return Column(
      children: [
        // Banner card sized by a FIXED ASPECT RATIO (not a fixed pixel height)
        // so it looks identical on every device — a fixed height cropped the
        // image differently per screen width ("half image" on some devices).
        AspectRatio(
          aspectRatio: _bannerRatio,
          child: PageView.builder(
            controller: _pc,
            itemCount: banners.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, index) {
              final b = banners[index];
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onBannerTap(b),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: CachedNetworkImage(
                    imageUrl: b.imageUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    placeholder: (context, url) =>
                        Container(color: const Color(0xFFF2F4F7)),
                    errorWidget: (context, url, error) =>
                        Container(color: const Color(0xFFF2F4F7)),
                  ),
                ),
              );
            },
          ),
        ),

        // Page dots (only when there's more than one banner).
        if (banners.length > 1) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(banners.length, (i) {
              final active = i == _index;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                height: 7,
                width: active ? 20 : 7,
                decoration: BoxDecoration(
                  color: active ? _ink : const Color(0xFFD3D7DF),
                  borderRadius: BorderRadius.circular(99),
                ),
              );
            }),
          ),
        ],

        // App tagline beneath the dots.
        const SizedBox(height: 14),
        Text(
          'Book and move, anywhere in the city',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            height: 2.3,
            color: Colors.grey.shade500,
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

// ========================= home_screens.dart (FULL UPDATED) =========================
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Consents/app_texts.dart';
import 'package:hopper/Core/Utility/app_images.dart';
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
import 'package:cached_network_image/cached_network_image.dart';
import 'package:hopper/uitls/websocket/shared_web_socket.dart';

import '../Controller/home_map_controller.dart';

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
  const HomeScreens({super.key});

  @override
  State<HomeScreens> createState() => _HomeScreensState();
}

class _HomeScreensState extends State<HomeScreens>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;

  final HomeMapController mapC =
      Get.isRegistered<HomeMapController>()
          ? Get.find<HomeMapController>()
          : Get.put(HomeMapController(), permanent: true);
  final ApiDataSource _apiDataSource = ApiDataSource();

  bool _busy = false;

  bool _initialPinAligned = false;
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
      const url =
          'https://bk.myhoppr.com/api/customer/advertisement-banners';
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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

    result.fold(
      (_) {
        // API fail -> don't disturb main screen
        setState(() {
          _checkingActiveRide = false;
        });
      },
      (response) {
        final data = response.data;

        final hasValidActiveRide =
            response.success &&
            response.hasActiveBooking &&
            data != null &&
            !data.cancelled;

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
      },
    );
  }

  Future<void> _resumeActiveRide() async {
    final ride = _activeRide;
    if (ride == null) return;

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
                final pos = mapC.currentPosition;
                if (pos == null) {
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  );
                }

                return SizedBox(
                  key: _mapKey,
                  child: GoogleMap(
                     initialCameraPosition: CameraPosition(
                       target: pos,
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
              child: InkWell(
                onTap: _openBookRideSearch,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.black.withOpacity(0.06)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => DrawerScreen()),
                          );
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(5.0),
                          child: Icon(Icons.menu, size: 20),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Image.asset(
                          AppImages.dart,
                          height: 10,
                          width: 10,
                          color: AppColors.walletCurrencyColor,
                        ),
                      ),
                      Expanded(
                        child: Obx(
                          () => Text(
                            mapC.address.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
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
              child: _HomeBottomSheet(
                mapC: mapC,
                onBookRideTap: _openBookRideSearch,
                onHeightChanged: _onSheetHeightChanged,
                banners: _homeHeroBanners,
                bannersLoading: _loadingHomeHeroBanners,
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
        snapSizes: const [0.30, 0.42, 0.86],
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
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Center(
                    child: Container(
                      width: 46,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

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
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.containerColor),
                        borderRadius: BorderRadius.circular(15),
                        color: AppColors.commonWhite,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 12,
                        ),
                        child: Column(
                          children: [
                            CustomTextFields.plainTextField(
                              autofocus: false,
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
                                );
                              },
                              title: 'Search Destination',
                            ),
                            const SizedBox(height: 5),

                            Obx(() {
                              final recents = mapC.recentLocations;
                              final popular = mapC.popularPlaces;

                              if (recents.length >= 2) {
                                final list = recents.take(2).toList();

                                return Column(
                                  children: List.generate(list.length, (index) {
                                    final recent = list[index];

                                    return Column(
                                      children: [
                                        InkWell(
                                          onTap: () async {
                                            if (mapC.currentPosition == null) {
                                              await mapC.initLocation();
                                              if (mapC.currentPosition ==
                                                  null) {
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
                                                  'lat': recent.lat,
                                                  'lng': recent.lng,
                                                },
                                                pickupAddress: pickupAddress,
                                                destinationAddress:
                                                    recent.description,
                                              ),
                                            );
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 10,
                                            ),
                                            child: Row(
                                              children: [
                                                Image.asset(
                                                  AppImages.recentHistory,
                                                  height: 20,
                                                  width: 20,
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child:
                                                      CustomTextFields.textWithStylesSmall(
                                                        recent.description,
                                                        maxLines: 1,
                                                        textAlign:
                                                            TextAlign.left,
                                                        colors:
                                                            AppColors
                                                                .commonBlack,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                ),
                                                const Icon(
                                                  Icons.keyboard_arrow_right,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        if (index != list.length - 1)
                                          Divider(
                                            indent: 10,
                                            endIndent: 15,
                                            color: AppColors.commonBlack
                                                .withOpacity(0.1),
                                          ),
                                      ],
                                    );
                                  }),
                                );
                              }

                              return Column(
                                children: List.generate(popular.length, (
                                  index,
                                ) {
                                  final place = popular[index];

                                  return Column(
                                    children: [
                                      InkWell(
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
                                                'name': place.name,
                                                'lat': place.lat,
                                                'lng': place.lng,
                                              },
                                              pickupAddress: pickupAddress,
                                              destinationAddress: place.name,
                                            ),
                                          );
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 10,
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.location_on),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child:
                                                    CustomTextFields.textWithStylesSmall(
                                                      place.name,
                                                      maxLines: 1,
                                                      textAlign: TextAlign.left,
                                                      colors:
                                                          AppColors.commonBlack,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                              ),
                                              const Icon(
                                                Icons.keyboard_arrow_right,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (index != popular.length - 1)
                                        Divider(
                                          indent: 10,
                                          endIndent: 15,
                                          color: AppColors.commonBlack
                                              .withOpacity(0.1),
                                        ),
                                    ],
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

                  if (banners.isNotEmpty) ...[
                    SizedBox(
                      height: 120,
                      child: PageView.builder(
                        controller: PageController(viewportFraction: 0.97),
                        itemCount: banners.length,
                        itemBuilder: (context, index) {
                          final b = banners[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 0),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: CachedNetworkImage(
                                imageUrl: b.imageUrl,
                                fit: BoxFit.contain,
                                placeholder:
                                    (context, url) => Container(
                                      color: const Color(0xFFF2F4F7),
                                    ),
                                errorWidget:
                                    (context, url, error) =>
                                        const SizedBox.shrink(),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
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

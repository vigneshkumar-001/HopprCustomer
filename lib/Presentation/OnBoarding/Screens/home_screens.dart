// ========================= home_screens.dart (FULL UPDATED) =========================
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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
import 'package:hopper/Presentation/Drawer/screens/drawer_screen.dart';
import 'package:hopper/Presentation/OnBoarding/Widgets/custom_bottomnavigation.dart';
import 'package:hopper/Presentation/OnBoarding/Widgets/package_contoiner.dart';
import 'package:hopper/api/dataSource/apiDataSource.dart';
import 'package:hopper/uitls/netWorkHandling/network_handling_screen.dart';

import '../Controller/home_map_controller.dart';

class HomeScreens extends StatefulWidget {
  const HomeScreens({super.key});

  @override
  State<HomeScreens> createState() => _HomeScreensState();
}

class _HomeScreensState extends State<HomeScreens>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;

  final HomeMapController mapC = Get.put(HomeMapController());
  final ApiDataSource _apiDataSource = ApiDataSource();

  bool _selectMode = false;
  bool _busy = false;
  bool _userFingerDown = false;

  String _pickupText = 'Pickup';
  LatLng? _pickupPos;

  String _destText = 'Destination';
  LatLng? _destPos;

  bool _checkingActiveRide = false;
  String? _lastDismissedBookingId;
  ActiveBookingData? _activeRide;

  // ✅ DO NOT remove/add card from Stack. Only show/hide internally.
  final ValueNotifier<bool> _showActiveRideCard = ValueNotifier<bool>(false);

  final GlobalKey _sheetKey = GlobalKey();
  double _sheetHeight = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await mapC.start();
      await _loadActiveRide();
      _measureSheet();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _showActiveRideCard.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadActiveRide();
    }
  }

  void _measureSheet() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final ctx = _sheetKey.currentContext;
      if (ctx == null) return;

      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) return;

      final h = box.size.height;
      if (h <= 0) return;

      if ((h - _sheetHeight).abs() > 2) {
        setState(() => _sheetHeight = h);
      }
    });
  }

  Future<void> _ensureCurrentPickup() async {
    if (_pickupPos != null && _pickupText.isNotEmpty) return;

    if (mapC.currentPosition == null) {
      await mapC.initLocation();
      if (mapC.currentPosition == null) return;
    }

    _pickupPos = mapC.currentPosition;
    _pickupText = await mapC.getAddressFromLatLng(_pickupPos!);
  }

  Future<void> _enterSelectMode() async {
    if (_selectMode || _busy) return;

    _busy = true;
    try {
      await _ensureCurrentPickup();
      if (!mounted) return;
      setState(() => _selectMode = true);
    } finally {
      _busy = false;
    }
  }

  void _exitSelectMode() {
    if (!_selectMode) return;
    setState(() => _selectMode = false);
    _measureSheet();
  }

  Future<void> _onSelectMapIdle() async {
    if (!_selectMode) return;
    if (mapC.currentPosition == null) return;
    if (!mounted) return;

    _pickupPos = mapC.currentPosition;
    setState(() {
      _pickupText = mapC.address.value;
    });
  }

  Future<void> _changePickupBySearch() async {
    await _ensureCurrentPickup();
    if (_pickupPos == null) return;

    final result = await Get.to(
      () => BookRideSearchScreen(
        isPickup: true,
        pickupData: {
          'description': _pickupText,
          'lat': _pickupPos!.latitude,
          'lng': _pickupPos!.longitude,
        },
      ),
    );

    if (result == null || !mounted) return;

    setState(() {
      _pickupText = (result['description'] ?? 'Pickup').toString();
      _pickupPos = LatLng(
        (result['lat'] as num).toDouble(),
        (result['lng'] as num).toDouble(),
      );
    });

    await mapC.mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(_pickupPos!, 16),
    );
  }

  Future<void> _chooseDestination() async {
    await _ensureCurrentPickup();
    if (_pickupPos == null) return;

    final result = await Get.to(
      () => BookRideSearchScreen(
        isPickup: false,
        pickupData: {
          'description': _pickupText,
          'lat': _pickupPos!.latitude,
          'lng': _pickupPos!.longitude,
        },
      ),
    );

    if (result == null || !mounted) return;

    setState(() {
      _destText = (result['description'] ?? 'Destination').toString();
      _destPos = LatLng(
        (result['lat'] as num).toDouble(),
        (result['lng'] as num).toDouble(),
      );
    });

    if (_pickupPos != null && _destPos != null) {
      final pickupAddress = _pickupText;
      final destAddress = _destText;

      if (mounted) {
        setState(() => _selectMode = false);
      }

      Get.to(
        () => BookMapScreen(
          pickupData: {
            'name': pickupAddress,
            'lat': _pickupPos!.latitude,
            'lng': _pickupPos!.longitude,
          },
          destinationData: {
            'name': destAddress,
            'lat': _destPos!.latitude,
            'lng': _destPos!.longitude,
          },
          pickupAddress: pickupAddress,
          destinationAddress: destAddress,
        ),
      );
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
        // ✅ API fail -> main screen disturb ஆகக்கூடாது
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

            if (_lastDismissedBookingId == data!.bookingId) {
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
        initialAmount: ride.amount,
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
          final shouldShow = visible && !_selectMode && ride != null;

          final subtitle =
              ride != null && ride.driverName.trim().isNotEmpty
                  ? 'Driver ${ride.driverName} • ${ride.status.replaceAll('_', ' ')}'
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

    final double homePinAlignY =
        screenH <= 0 ? -0.18 : (-(_sheetHeight / screenH)).clamp(-0.45, 0.0);

    return NoInternetOverlay(
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _userFingerDown = true,
                onPointerUp: (_) => _userFingerDown = false,
                onPointerCancel: (_) => _userFingerDown = false,
                child: Obx(() {
                  if (!mapC.gate.isReady.value &&
                      mapC.currentPosition == null) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: mapC.currentPosition ?? const LatLng(0, 0),
                      zoom: 14,
                    ),
                    markers: mapC.markers.toSet(),
                    onMapCreated: (controller) async {
                      debugPrint("✅ Main Map created");
                      await mapC.attachMap(controller);
                    },
                    onTap: (_) => _enterSelectMode(),
                    onCameraMoveStarted: () {
                      if (_userFingerDown) _enterSelectMode();
                    },
                    onCameraMove: mapC.onCameraMove,
                    onCameraIdle: () async {
                      mapC.onCameraIdle();
                      if (_selectMode) {
                        await _onSelectMapIdle();
                      }
                    },
                    myLocationEnabled: mapC.gate.isReady.value,
                    myLocationButtonEnabled: false,
                    minMaxZoomPreference: const MinMaxZoomPreference(
                      12.0,
                      16.8,
                    ),
                    mapToolbarEnabled: false,
                    zoomControlsEnabled: false,
                    gestureRecognizers: {
                      Factory<OneSequenceGestureRecognizer>(
                        () => EagerGestureRecognizer(),
                      ),
                    },
                  );
                }),
              ),
            ),

            if (!_selectMode)
              Positioned(
                top: topPad + 10,
                left: 16,
                right: 16,
                child: InkWell(
                  onTap: _enterSelectMode,
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

            if (!_selectMode)
              Positioned(
                right: 12,
                bottom: 200,
                child: FloatingActionButton(
                  heroTag: 'home_my_loc',
                  mini: true,
                  backgroundColor: Colors.white,
                  onPressed: () async {
                    await mapC.goToCurrentLocation();
                  },
                  child: const Icon(Icons.my_location, color: Colors.black),
                ),
              ),

            if (_selectMode)
              Positioned(
                top: topPad + 12,
                left: 16,
                right: 16,
                child: _OlaPickupDropCard(
                  pickup: _pickupText,
                  destination: _destText,
                  onBack: _exitSelectMode,
                  onPickupTap: _changePickupBySearch,
                  onDestinationTap: _chooseDestination,
                ),
              ),

            if (_selectMode)
              Positioned(
                right: 14,
                bottom: 120,
                child: FloatingActionButton(
                  heroTag: 'full_my_loc',
                  mini: true,
                  backgroundColor: Colors.white,
                  onPressed: () async {
                    await mapC.goToCurrentLocation();
                    await _onSelectMapIdle();
                  },
                  child: const Icon(Icons.my_location, color: Colors.black),
                ),
              ),

            if (_selectMode)
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: InkWell(
                  onTap: _chooseDestination,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.96),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.black.withOpacity(0.06)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 14,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.search),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Choose destination',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Icon(Icons.keyboard_arrow_right),
                      ],
                    ),
                  ),
                ),
              ),

            if (!_selectMode)
              _HomeBottomSheet(
                key: _sheetKey,
                mapC: mapC,
                onEnterSelectMode: () async {
                  await _enterSelectMode();
                },
                onAfterLayout: _measureSheet,
              ),

            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment:
                      _selectMode
                          ? const Alignment(0, 0)
                          : Alignment(0, homePinAlignY),
                  child: Column(
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
                      Image.asset(AppImages.pinLocation, height: 44, width: 28),
                    ],
                  ),
                ),
              ),
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
  final VoidCallback onEnterSelectMode;
  final VoidCallback onAfterLayout;

  const _HomeBottomSheet({
    super.key,
    required this.mapC,
    required this.onEnterSelectMode,
    required this.onAfterLayout,
  });

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => onAfterLayout());

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(22),
            topRight: Radius.circular(22),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Column(
                children: [
                  Container(
                    width: 38,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: onEnterSelectMode,
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

                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      color: AppColors.advertisementColor,
                    ),
                    child: ListTile(
                      title: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: 'JUST IN ',
                              style: TextStyle(
                                color: AppColors.justInColor,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            const TextSpan(
                              text: 'Now, Pay at the drop location with ',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.normal,
                                fontSize: 16,
                              ),
                            ),
                            TextSpan(
                              text: 'COD',
                              style: TextStyle(
                                color: AppColors.commonBlack,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                      trailing: Image.asset(AppImages.advertisement),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// PICKUP/DROP CARD
// -----------------------------------------------------------------------------
class _OlaPickupDropCard extends StatelessWidget {
  final String pickup;
  final String destination;
  final VoidCallback onBack;
  final VoidCallback onPickupTap;
  final VoidCallback onDestinationTap;

  const _OlaPickupDropCard({
    required this.pickup,
    required this.destination,
    required this.onBack,
    required this.onPickupTap,
    required this.onDestinationTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.98),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 14,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              InkWell(
                onTap: onBack,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.arrow_back, size: 20),
                ),
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Pick up & Drop',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: onPickupTap,
            child: Row(
              children: [
                const Icon(Icons.my_location, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    pickup,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(Icons.edit, size: 16),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Divider(color: Colors.black.withOpacity(0.08)),
          const SizedBox(height: 10),
          InkWell(
            onTap: onDestinationTap,
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    destination,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Icon(Icons.keyboard_arrow_right),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/*
// ========================= home_screens.dart (FULL UPDATED) =========================
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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
import 'package:hopper/Presentation/Drawer/controller/profle_cotroller.dart';
import 'package:hopper/Presentation/Drawer/screens/drawer_screen.dart';
import 'package:hopper/Presentation/OnBoarding/Widgets/custom_bottomnavigation.dart';
import 'package:hopper/Presentation/OnBoarding/Widgets/package_contoiner.dart';
import 'package:hopper/api/dataSource/apiDataSource.dart';
import 'package:hopper/uitls/netWorkHandling/network_handling_screen.dart';
import '../Controller/home_map_controller.dart';

class HomeScreens extends StatefulWidget {
  const HomeScreens({super.key});

  @override
  State<HomeScreens> createState() => _HomeScreensState();
}

class _HomeScreensState extends State<HomeScreens>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;

  final HomeMapController mapC = Get.put(HomeMapController());
  final ProfleCotroller profileC = Get.find<ProfleCotroller>();

  String? _lastDismissedBookingId;
  bool _selectMode = false;
  bool _busy = false;

  String _pickupText = 'Pickup';
  LatLng? _pickupPos;

  String _destText = 'Destination';
  LatLng? _destPos;

  bool _userFingerDown = false;
  final ApiDataSource _apiDataSource = ApiDataSource();
  bool _checkingActiveRide = false;
  bool _dismissActiveRideCard = false;
  ActiveBookingData? _activeRide;

  // ✅ Measure bottom sheet height to keep pin in visible map center
  final GlobalKey _sheetKey = GlobalKey();
  double _sheetHeight = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await mapC.start();
      await _loadActiveRide();
      _measureSheet(); // first measure after build
    });
  }

  void _measureSheet() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _sheetKey.currentContext;
      if (ctx == null) return;

      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) return;

      final h = box.size.height;
      if (h <= 0) return;

      // update only if changed to avoid rebuild loops
      if ((h - _sheetHeight).abs() > 2) {
        setState(() => _sheetHeight = h);
      }
    });
  }

  Future<void> _ensureCurrentPickup() async {
    if (_pickupPos != null && _pickupText.isNotEmpty) return;

    if (mapC.currentPosition == null) {
      await mapC.initLocation();
      if (mapC.currentPosition == null) return;
    }

    _pickupPos = mapC.currentPosition;
    _pickupText = await mapC.getAddressFromLatLng(_pickupPos!);
  }

  Future<void> _enterSelectMode() async {
    if (_selectMode || _busy) return;
    _busy = true;
    try {
      await _ensureCurrentPickup();
      if (!mounted) return;
      setState(() => _selectMode = true);
    } finally {
      _busy = false;
    }
  }

  void _exitSelectMode() {
    if (!_selectMode) return;
    setState(() => _selectMode = false);
    _measureSheet(); // measure again when coming back to home
  }

  Future<void> _onSelectMapIdle() async {
    if (!_selectMode) return;
    if (mapC.currentPosition == null) return;

    _pickupPos = mapC.currentPosition;
    if (!mounted) return;

    setState(() {
      _pickupText = mapC.address.value;
    });
  }

  Future<void> _changePickupBySearch() async {
    await _ensureCurrentPickup();
    if (_pickupPos == null) return;

    final result = await Get.to(
      () => BookRideSearchScreen(
        isPickup: true,
        pickupData: {
          'description': _pickupText,
          'lat': _pickupPos!.latitude,
          'lng': _pickupPos!.longitude,
        },
      ),
    );

    if (result == null) return;

    setState(() {
      _pickupText = (result['description'] ?? 'Pickup').toString();
      _pickupPos = LatLng(
        (result['lat'] as num).toDouble(),
        (result['lng'] as num).toDouble(),
      );
    });

    await mapC.mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(_pickupPos!, 16),
    );
  }

  Future<void> _chooseDestination() async {
    await _ensureCurrentPickup();
    if (_pickupPos == null) return;

    final result = await Get.to(
      () => BookRideSearchScreen(
        isPickup: false,
        pickupData: {
          'description': _pickupText,
          'lat': _pickupPos!.latitude,
          'lng': _pickupPos!.longitude,
        },
      ),
    );

    if (result == null) return;

    setState(() {
      _destText = (result['description'] ?? 'Destination').toString();
      _destPos = LatLng(
        (result['lat'] as num).toDouble(),
        (result['lng'] as num).toDouble(),
      );
    });

    if (_pickupPos != null && _destPos != null) {
      final pickupAddress = _pickupText;
      final destAddress = _destText;

      if (mounted) setState(() => _selectMode = false);

      Get.to(
        () => BookMapScreen(
          pickupData: {
            'name': pickupAddress,
            'lat': _pickupPos!.latitude,
            'lng': _pickupPos!.longitude,
          },
          destinationData: {
            'name': destAddress,
            'lat': _destPos!.latitude,
            'lng': _destPos!.longitude,
          },
          pickupAddress: pickupAddress,
          destinationAddress: destAddress,
        ),
      );
    }
  }
  Future<void> _loadActiveRide({bool silent = true}) async {
    if (_checkingActiveRide) return;

    if (mounted) {
      setState(() => _checkingActiveRide = true);
    }

    final result = await _apiDataSource.getActiveBooking();
    if (!mounted) return;

    result.fold(
          (_) {
        // ✅ API fail ஆனாலும் main screen disturb ஆகக்கூடாது
        // old active ride இருந்தா அதையே விட்டுரலாம்
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
            _activeRide = data;

            // ✅ same booking previously dismissedனா மீண்டும் show பண்ண வேண்டாம்
            if (_lastDismissedBookingId != data!.bookingId) {
              _dismissActiveRideCard = false;
            }
          } else {
            // ✅ no active booking means card மட்டும் remove பண்ணு
            _activeRide = null;
            _dismissActiveRideCard = false;
            _lastDismissedBookingId = null;
          }
        });
      },
    );
  }
  // Future<void> _loadActiveRide() async {
  //   if (_checkingActiveRide) return;
  //
  //   setState(() => _checkingActiveRide = true);
  //   final result = await _apiDataSource.getActiveBooking();
  //   if (!mounted) return;
  //
  //   result.fold(
  //     (_) {
  //       setState(() {
  //         _checkingActiveRide = false;
  //         _activeRide = null;
  //       });
  //     },
  //     (response) {
  //       setState(() {
  //         _checkingActiveRide = false;
  //         if (response.success &&
  //             response.hasActiveBooking &&
  //             response.data != null &&
  //             !response.data!.cancelled) {
  //           _activeRide = response.data;
  //           _dismissActiveRideCard = false;
  //         } else {
  //           _activeRide = null;
  //         }
  //       });
  //     },
  //   );
  // }

  Future<void> _resumeActiveRide() async {
    final ride = _activeRide;
    if (ride == null) return;

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
        initialAmount: ride.amount,
      ),
    );

    if (!mounted) return;
    await _loadActiveRide();
  }
  Widget _activeRideCard(double topPad) {
    final ride = _activeRide;

    if (_selectMode || ride == null || _dismissActiveRideCard) {
      return const SizedBox.shrink();
    }

    final subtitle =
    ride.driverName.trim().isNotEmpty
        ? 'Driver ${ride.driverName} • ${ride.status.replaceAll('_', ' ')}'
        : ride.status.replaceAll('_', ' ');

    return Positioned(
      top: topPad + 76,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black.withOpacity(0.08)),
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
                    child: const Icon(Icons.local_taxi, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                            color: Colors.black.withOpacity(0.65),
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
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                ride.dropAddress,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.black.withOpacity(0.6)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _dismissActiveRideCard = true;
                          _lastDismissedBookingId = ride.bookingId;
                        });
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
    );
  }

  // Widget _activeRideCard(double topPad) {
  //   final ride = _activeRide;
  //   if (_selectMode || ride == null || _dismissActiveRideCard) {
  //     return const SizedBox.shrink();
  //   }
  //
  //   final subtitle =
  //       ride.driverName.trim().isNotEmpty
  //           ? 'Driver ${ride.driverName} � ${ride.status.replaceAll('_', ' ')}'
  //           : ride.status.replaceAll('_', ' ');
  //
  //   return Positioned(
  //     top: topPad + 76,
  //     left: 16,
  //     right: 16,
  //     child: Material(
  //       color: Colors.transparent,
  //       child: Container(
  //         padding: const EdgeInsets.all(14),
  //         decoration: BoxDecoration(
  //           color: Colors.white,
  //           borderRadius: BorderRadius.circular(18),
  //           border: Border.all(color: Colors.black.withOpacity(0.08)),
  //           boxShadow: [
  //             BoxShadow(
  //               color: Colors.black.withOpacity(0.08),
  //               blurRadius: 16,
  //               offset: const Offset(0, 8),
  //             ),
  //           ],
  //         ),
  //         child: Column(
  //           crossAxisAlignment: CrossAxisAlignment.start,
  //           children: [
  //             Row(
  //               children: [
  //                 Container(
  //                   width: 36,
  //                   height: 36,
  //                   decoration: BoxDecoration(
  //                     color: Colors.black,
  //                     borderRadius: BorderRadius.circular(12),
  //                   ),
  //                   child: const Icon(Icons.local_taxi, color: Colors.white),
  //                 ),
  //                 const SizedBox(width: 10),
  //                 Expanded(
  //                   child: Column(
  //                     crossAxisAlignment: CrossAxisAlignment.start,
  //                     children: [
  //                       const Text(
  //                         'Active ride in progress',
  //                         style: TextStyle(
  //                           fontSize: 16,
  //                           fontWeight: FontWeight.w800,
  //                         ),
  //                       ),
  //                       const SizedBox(height: 2),
  //                       Text(
  //                         subtitle,
  //                         maxLines: 1,
  //                         overflow: TextOverflow.ellipsis,
  //                         style: TextStyle(
  //                           fontSize: 13,
  //                           color: Colors.black.withOpacity(0.65),
  //                         ),
  //                       ),
  //                     ],
  //                   ),
  //                 ),
  //               ],
  //             ),
  //             const SizedBox(height: 12),
  //             Text(
  //               ride.pickupAddress,
  //               maxLines: 1,
  //               overflow: TextOverflow.ellipsis,
  //               style: const TextStyle(fontWeight: FontWeight.w600),
  //             ),
  //             const SizedBox(height: 4),
  //             Text(
  //               ride.dropAddress,
  //               maxLines: 1,
  //               overflow: TextOverflow.ellipsis,
  //               style: TextStyle(color: Colors.black.withOpacity(0.6)),
  //             ),
  //             const SizedBox(height: 12),
  //             Row(
  //               children: [
  //                 Expanded(
  //                   child: OutlinedButton(
  //                     onPressed: () {
  //                       setState(() {
  //                         _dismissActiveRideCard = true;
  //                         _lastDismissedBookingId = _activeRide?.bookingId;
  //                       });
  //                     },
  //                     child: const Text('Not now'),
  //                   ),
  //                 ),
  //                 const SizedBox(width: 10),
  //                 Expanded(
  //                   child: ElevatedButton(
  //                     onPressed: _resumeActiveRide,
  //                     style: ElevatedButton.styleFrom(
  //                       backgroundColor: Colors.black,
  //                       foregroundColor: Colors.white,
  //                     ),
  //                     child: const Text('Resume ride'),
  //                   ),
  //                 ),
  //               ],
  //             ),
  //           ],
  //         ),
  //       ),
  //     ),
  //   );
  //   @override
  //   void dispose() {
  //     WidgetsBinding.instance.removeObserver(this);
  //     super.dispose();
  //   }
  //
  //   @override
  //   void didChangeAppLifecycleState(AppLifecycleState state) {
  //     if (state == AppLifecycleState.resumed) {
  //       _loadActiveRide();
  //     }
  //   }
  // }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadActiveRide();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final topPad = MediaQuery.of(context).padding.top;
    final screenH = MediaQuery.of(context).size.height;

    // ✅ pin shift formula:
    // visibleMapCenter is moved up by sheetHeight/2 => alignment shift = -sheetHeight/screenHeight
    final double homePinAlignY =
        screenH <= 0 ? -0.18 : (-(_sheetHeight / screenH)).clamp(-0.45, 0.0);

    return NoInternetOverlay(
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            // ✅ ONE MAP ONLY (smooth)
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _userFingerDown = true,
                onPointerUp: (_) => _userFingerDown = false,
                onPointerCancel: (_) => _userFingerDown = false,
                child: Obx(() {
                  if (!mapC.gate.isReady.value &&
                      mapC.currentPosition == null) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  return GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: mapC.currentPosition ?? const LatLng(0, 0),
                      zoom: 14,
                    ),
                    markers: mapC.markers.toSet(), // ✅ nearby drivers WILL show
                    onMapCreated: (controller) async {
                      debugPrint("✅ Main Map created");
                      await mapC.attachMap(controller);
                    },
                    onTap: (_) => _enterSelectMode(),
                    onCameraMoveStarted: () {
                      if (_userFingerDown) _enterSelectMode();
                    },
                    onCameraMove: mapC.onCameraMove,
                    onCameraIdle: () async {
                      mapC.onCameraIdle();
                      if (_selectMode) await _onSelectMapIdle();
                    },
                    myLocationEnabled: mapC.gate.isReady.value,
                    myLocationButtonEnabled: false,
                    minMaxZoomPreference: const MinMaxZoomPreference(
                      12.0,
                      16.8,
                    ),
                    mapToolbarEnabled: false,
                    zoomControlsEnabled: false,
                    gestureRecognizers: {
                      Factory<OneSequenceGestureRecognizer>(
                        () => EagerGestureRecognizer(),
                      ),
                    },
                  );
                }),
              ),
            ),

            // ✅ TOP SEARCH BAR (home)
            if (!_selectMode)
              Positioned(
                top: topPad + 10,
                left: 16,
                right: 16,
                child: InkWell(
                  onTap: _enterSelectMode,
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

            // ✅ My location FAB (home)
            if (!_selectMode)
              Positioned(
                right: 12,
                bottom: 200,
                child: FloatingActionButton(
                  heroTag: 'home_my_loc',
                  mini: true,
                  backgroundColor: Colors.white,
                  onPressed: () async {
                    await mapC.goToCurrentLocation();
                    // keep home pin centered; no need to change pickup text here
                  },
                  child: const Icon(Icons.my_location, color: Colors.black),
                ),
              ),

            // ✅ Select mode top card
            if (_selectMode)
              Positioned(
                top: topPad + 12,
                left: 16,
                right: 16,
                child: _OlaPickupDropCard(
                  pickup: _pickupText,
                  destination: _destText,
                  onBack: _exitSelectMode,
                  onPickupTap: _changePickupBySearch,
                  onDestinationTap: _chooseDestination,
                ),
              ),

            // ✅ My location FAB (select)
            if (_selectMode)
              Positioned(
                right: 14,
                bottom: 120,
                child: FloatingActionButton(
                  heroTag: 'full_my_loc',
                  mini: true,
                  backgroundColor: Colors.white,
                  onPressed: () async {
                    await mapC.goToCurrentLocation();
                    await _onSelectMapIdle();
                  },
                  child: const Icon(Icons.my_location, color: Colors.black),
                ),
              ),

            // ✅ Choose destination bar (select)
            if (_selectMode)
              Positioned(
                left: 16,
                right: 16,
                bottom: 24,
                child: InkWell(
                  onTap: _chooseDestination,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.96),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.black.withOpacity(0.06)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 14,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.search),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Choose destination',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Icon(Icons.keyboard_arrow_right),
                      ],
                    ),
                  ),
                ),
              ),

            // ✅ Bottom sheet (home) + measure it
            if (!_selectMode)
              _HomeBottomSheet(
                key: _sheetKey,
                mapC: mapC,
                onEnterSelectMode: () async {
                  await _enterSelectMode();
                },
                onAfterLayout: _measureSheet,
              ),

            // ✅ PIN LAST (always visible, properly centered)
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment:
                      _selectMode
                          ? const Alignment(0, 0) // full screen true center
                          : Alignment(
                            0,
                            homePinAlignY,
                          ), // home: center of visible map
                  child: Column(
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
                      Image.asset(AppImages.pinLocation, height: 44, width: 28),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// BOTTOM SHEET (with key + notify for measurement)
// -----------------------------------------------------------------------------
class _HomeBottomSheet extends StatelessWidget {
  final HomeMapController mapC;
  final VoidCallback onEnterSelectMode;
  final VoidCallback onAfterLayout;

  const _HomeBottomSheet({
    super.key,
    required this.mapC,
    required this.onEnterSelectMode,
    required this.onAfterLayout,
  });

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => onAfterLayout());

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(22),
            topRight: Radius.circular(22),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Column(
                children: [
                  Container(
                    width: 38,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: onEnterSelectMode,
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
                        child: GestureDetector(
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
                                  BookRideSearchScreen(
                                    isPickup: false,
                                    pickupData: pickupData,
                                  ),
                                );
                              },
                              title: 'Search Destination',
                            ),

                            const SizedBox(height: 5),

                            // ✅ recent locations or popular places (reactive)
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
                                              if (mapC.currentPosition == null)
                                                return;
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

                              // fallback: popular places
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
                                            if (mapC.currentPosition == null)
                                              return;
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

                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      color: AppColors.advertisementColor,
                    ),
                    child: ListTile(
                      title: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: 'JUST IN ',
                              style: TextStyle(
                                color: AppColors.justInColor,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            const TextSpan(
                              text: 'Now, Pay at the drop location with ',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.normal,
                                fontSize: 16,
                              ),
                            ),
                            TextSpan(
                              text: 'COD',
                              style: TextStyle(
                                color: AppColors.commonBlack,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                      trailing: Image.asset(AppImages.advertisement),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// PICKUP/DROP CARD
// -----------------------------------------------------------------------------
class _OlaPickupDropCard extends StatelessWidget {
  final String pickup;
  final String destination;
  final VoidCallback onBack;
  final VoidCallback onPickupTap;
  final VoidCallback onDestinationTap;

  const _OlaPickupDropCard({
    required this.pickup,
    required this.destination,
    required this.onBack,
    required this.onPickupTap,
    required this.onDestinationTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.98),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 14,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              InkWell(
                onTap: onBack,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.arrow_back, size: 20),
                ),
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Pick up & Drop',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: onPickupTap,
            child: Row(
              children: [
                const Icon(Icons.my_location, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    pickup,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(Icons.edit, size: 16),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Divider(color: Colors.black.withOpacity(0.08)),
          const SizedBox(height: 10),
          InkWell(
            onTap: onDestinationTap,
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    destination,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Icon(Icons.keyboard_arrow_right),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
*/

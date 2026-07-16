import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/cupertino.dart';
import 'package:hopper/uitls/transitions/route_transitions.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hopper/Presentation/OnBoarding/Controller/home_map_controller.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:hopper/Core/Utility/app_buttons.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Core/Utility/empty_state_view.dart';
import 'package:hopper/Core/Utility/app_loader.dart';
import 'package:hopper/Core/Utility/skeleton_loaders.dart';
import 'package:hopper/Core/Utility/app_toasts.dart';

import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
import 'package:hopper/Presentation/BookRide/Controllers/driver_search_controller.dart';
import 'package:hopper/Presentation/BookRide/Controllers/book_map_controller.dart';
import 'package:hopper/Presentation/BookRide/Models/selected_location.dart';
import 'package:hopper/Presentation/BookRide/Screens/confirm_booking.dart';
import 'package:hopper/Presentation/BookRide/Screens/search_screen.dart';
import 'package:hopper/Presentation/BookRide/SharedRideScreens/Screens/ride_share_screen.dart';
import 'package:hopper/Presentation/OnBoarding/Widgets/custom_bottomnavigation.dart';
import 'package:hopper/Presentation/OnBoarding/Widgets/package_contoiner.dart';
import 'package:hopper/uitls/netWorkHandling/network_handling_screen.dart';

class BookMapScreen extends StatefulWidget {
  final Map<String, dynamic> pickupData;
  final Map<String, dynamic> destinationData;
  final String pickupAddress;
  final String destinationAddress;

  const BookMapScreen({
    super.key,
    required this.pickupData,
    required this.destinationData,
    required this.pickupAddress,
    required this.destinationAddress,
  });

  @override
  State<BookMapScreen> createState() => _BookMapScreenState();
}

class _BookMapScreenState extends State<BookMapScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _startController = TextEditingController();
  final TextEditingController _destController = TextEditingController();

  // Scroll-down hint: a bouncing arrow shown while there is more content below
  // the fold (so users know the vehicle list / Book button can be scrolled to).
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _showScrollHint = ValueNotifier<bool>(false);
  late final AnimationController _arrowBounceCtrl;

  // Initial camera target, derived synchronously from the pickup passed into
  // this screen — so the map opens already centred on the pickup instead of
  // flashing the ocean (0,0) and then jumping once positions resolve.
  LatLng? _initialCamTarget;

  final DriverSearchController driverController =
      Get.isRegistered<DriverSearchController>()
          ? Get.find<DriverSearchController>()
          : Get.put(DriverSearchController());
  final BookMapController mapC =
      Get.isRegistered<BookMapController>()
          ? Get.find<BookMapController>()
          : Get.put(BookMapController());

  // Navigation lock for handleBookMapBack() — prevents a double back-tap
  // (system gesture + the on-screen back button firing together, or rapid
  // repeated taps) from running the handler twice concurrently.
  bool _isHandlingBack = false;

  @override
  void initState() {
    super.initState();

    _arrowBounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);
    // Re-check the hint after the first layout (and again shortly after, once
    // the vehicle list has loaded and the scroll extent grows).
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshScrollHint());

    // Resume in place if the (shared) BookMapController already holds a
    // valid selection — e.g. this same widget instance rebuilding, or a
    // future permanent-controller scenario. Never overwrite a live
    // selection with the possibly-stale constructor args in that case.
    final existingPickup = mapC.pickupLocation.value;
    final existingDestination = mapC.destinationLocation.value;
    final resumingExisting =
        existingPickup?.isValid == true && existingDestination?.isValid == true;

    _startController.text =
        resumingExisting ? existingPickup!.address : widget.pickupAddress;
    _destController.text =
        resumingExisting
            ? existingDestination!.address
            : widget.destinationAddress;

    if (resumingExisting) {
      _initialCamTarget = existingPickup!.latLng;
      // Markers/route/camera already live on the shared controller from the
      // previous selection — nothing else to (re)initialise.
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _refreshScrollHint(),
        );
      }
      return;
    }

    // `widget.pickupAddress`/`widget.destinationAddress` are the
    // authoritative label — every caller supplies them, and some callers'
    // `pickupData`/`destinationData` maps use a different description key
    // (e.g. `'name'`) or omit one entirely. Only lat/lng/placeId/source come
    // from the map.
    final pickupLocation = SelectedLocation.fromMap(
      widget.pickupData,
      source: 'search',
    ).copyWith(
      address:
          widget.pickupAddress.trim().isNotEmpty
              ? widget.pickupAddress
              : null,
    );
    final destinationLocation = SelectedLocation.fromMap(
      widget.destinationData,
      source: 'search',
    ).copyWith(
      address:
          widget.destinationAddress.trim().isNotEmpty
              ? widget.destinationAddress
              : null,
    );

    if (!pickupLocation.isValid || !destinationLocation.isValid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Get.back();
        AppToasts.showErrorGlobal("Location data is missing", title: "Error");
      });
      return;
    }

    final resolvedPickup = pickupLocation.latLng;
    final resolvedDestination = destinationLocation.latLng;

    // Centre the map on the pickup from the very first frame (no ocean flash).
    _initialCamTarget = resolvedPickup;

    // optional: distance check
    final distance = Geolocator.distanceBetween(
      resolvedPickup.latitude,
      resolvedPickup.longitude,
      resolvedDestination.latitude,
      resolvedDestination.longitude,
    );
    AppLogger.log.i("distance meters: $distance");

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Reset any previous selection from another booking flow. Deferred to
      // post-frame so setting these Rx values never notifies an Obx during
      // the build phase (that caused a "setState during build" crash).
      driverController.selectedCarType.value = '';
      driverController.selectedSharedDriver.value = null;
      driverController.estimatedTime.value = '';
      driverController.markerAdded.value = false;

      await mapC.initPositions(
        pickup: resolvedPickup,
        destination: resolvedDestination,
        pickupLabel: pickupLocation.address,
        dropLabel: destinationLocation.address,
        pickupSource: pickupLocation.source,
        destinationSource: destinationLocation.source,
      );

      // Prefetch both once
      await Future.wait([
        driverController.getDriverSearch(
          pickupLat: resolvedPickup.latitude,
          pickupLng: resolvedPickup.longitude,
          dropLat: resolvedDestination.latitude,
          dropLng: resolvedDestination.longitude,
        ),
        // driverController.getSharedDriverSearch(
        //   pickupLat: resolvedPickup.latitude,
        //   pickupLng: resolvedPickup.longitude,
        //   dropLat: resolvedDestination.latitude,
        //   dropLng: resolvedDestination.longitude,
        // ),
      ]);

      // Vehicle cards just loaded → scroll extent likely grew; re-evaluate hint.
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _refreshScrollHint(),
        );
      }
    });
  }

  // ---- Scroll-down hint helpers -------------------------------------------
  void _updateHintFromMetrics(ScrollMetrics m) {
    // Show the arrow when there is a meaningful amount still below the fold.
    final moreBelow = (m.maxScrollExtent - m.pixels) > 24.0;
    if (_showScrollHint.value != moreBelow) {
      _showScrollHint.value = moreBelow;
    }
  }

  void _refreshScrollHint() {
    if (!mounted || !_scrollController.hasClients) return;
    _updateHintFromMetrics(_scrollController.position);
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  // ---- Back navigation ----------------------------------------------------

  /// Single entry point for leaving this screen — wired to BOTH the system
  /// back button/gesture (via PopScope) and the on-screen back arrow, so
  /// there is exactly one place deciding what "back" means here. Always
  /// performs its own explicit navigation rather than deferring to a plain
  /// pop, because a plain pop can't skip over Search/Map-picker/duplicate
  /// BookMapScreen/ConfirmBooking routes that may sit between here and Home.
  Future<bool> handleBookMapBack() async {
    // A. Another back action is already being handled — ignore this one.
    if (_isHandlingBack) return false;
    _isHandlingBack = true;
    try {
      // B. A critical booking submission is in flight — don't let the user
      // navigate away mid-request.
      if (driverController.isLoading.value) {
        if (mounted) {
          AppToasts.customToast(
            context,
            'Please wait while we process your booking.',
          );
        }
        return false;
      }

      // C. A booking was already created from this screen (e.g. the Book
      // button succeeded but the forward navigation hasn't completed yet) —
      // never treat that as an abandonable draft. Go to its tracking screen.
      final existingBooking = driverController.carBooking.value;
      if (existingBooking != null && existingBooking.bookingId.isNotEmpty) {
        await _goToActiveBooking(existingBooking);
        return false;
      }

      final hasDraft =
          (mapC.pickupLocation.value?.isValid ?? false) ||
          (mapC.destinationLocation.value?.isValid ?? false);

      // D. Nothing selected yet — nothing to lose, leave immediately.
      if (!hasDraft) {
        mapC.stopTransientWork();
        await _returnToHome();
        return false;
      }

      // E. A draft pickup/destination exists — confirm before discarding it.
      final leave = await _showLeaveBookingSheet();
      if (leave == true) {
        // G. Leave and Clear.
        mapC.stopTransientWork();
        mapC.clearAll();
        driverController.resetDraftSelection();
        _startController.clear();
        _destController.clear();
        await _returnToHome();
      }
      // F. Continue Booking (or the sheet was dismissed) — stay put, nothing
      // else to do.
      return false;
    } finally {
      _isHandlingBack = false;
    }
  }

  /// Reuses the exact same navigation the "Book" button uses on success —
  /// this is the ride lifecycle's own tracking entry point, not a new one.
  Future<void> _goToActiveBooking(dynamic existingBooking) async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => ConfirmBooking(
              carType: driverController.selectedCarType.value,
              bookingId: existingBooking.bookingId,
              selectedCarType: driverController.selectedCarType.value,
              pickupData: {
                'description':
                    mapC.pickupLocation.value?.address ??
                    widget.pickupAddress,
                'lat': mapC.pickupPosition?.latitude ?? 0.0,
                'lng': mapC.pickupPosition?.longitude ?? 0.0,
              },
              destinationData: {
                'description':
                    mapC.destinationLocation.value?.address ??
                    widget.destinationAddress,
                'lat': mapC.destinationPosition?.latitude ?? 0.0,
                'lng': mapC.destinationPosition?.longitude ?? 0.0,
              },
              pickupAddress:
                  mapC.pickupLocation.value?.address ?? widget.pickupAddress,
              destinationAddress:
                  mapC.destinationLocation.value?.address ??
                  widget.destinationAddress,
            ),
      ),
    );
  }

  /// Rounded-top confirmation sheet. Returns true = "Leave and Clear",
  /// false/null (dismissed) = "Continue Booking".
  Future<bool?> _showLeaveBookingSheet() {
    return showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Leave booking?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Your selected pickup and destination will be cleared if '
                  'you leave this screen.',
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: AppButtons.button(
                    text: 'Continue Booking',
                    onTap: () => Navigator.pop(sheetContext, false),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => Navigator.pop(sheetContext, true),
                    child: const Text(
                      'Leave and Clear',
                      style: TextStyle(fontWeight: FontWeight.w600),
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

  /// Pops down to the existing Home shell (`CommonBottomNavigation`) —
  /// verified to always be the root route in this app (installed once via
  /// `Get.off`/`Get.offAll` after splash/login, never pushed on top of
  /// itself) — so `isFirst` reliably identifies it without needing route
  /// names threaded through every call site that can reach this screen.
  /// Falls back to replacing whatever route we land on with a fresh Home
  /// ONLY if the stack is somehow missing it, and never pushes a second one
  /// on top of an existing Home.
  Future<void> _returnToHome() async {
    if (!mounted) return;
    final navigator = Navigator.of(context);

    // Checked BEFORE popping, while `context` is still guaranteed valid —
    // avoids having to introspect a possibly-already-disposed context
    // afterward. Only true in a corrupted/unusual stack (e.g. a deep link
    // that landed here with no Home installed yet).
    final noHomeBeneathUs = ModalRoute.of(context)?.isFirst ?? false;
    if (noHomeBeneathUs) {
      navigator.pushReplacement(
        MaterialPageRoute(
          builder: (_) => const CommonBottomNavigation(initialIndex: 0),
        ),
      );
      return;
    }

    // Normal case: an existing Home shell is already at the root of the
    // stack — reveal it by popping everything on top of it (Search screen,
    // map picker, a duplicate BookMapScreen, ConfirmBooking, etc.) instead
    // of pushing/replacing with a new instance.
    navigator.popUntil((route) => route.isFirst);
  }

  @override
  void dispose() {
    _arrowBounceCtrl.dispose();
    _scrollController.dispose();
    _showScrollHint.dispose();
    _startController.dispose();
    _destController.dispose();
    if (Get.isRegistered<BookMapController>()) {
      Get.delete<BookMapController>();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NoInternetOverlay(
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          // System back button/gesture. AppBar-equivalent back arrow calls
          // the same handleBookMapBack() below — one method decides "back"
          // for both triggers.
          if (didPop) return;
          await handleBookMapBack();
        },
        child: Scaffold(
          body: Stack(
            children: [
              NotificationListener<ScrollMetricsNotification>(
                onNotification: (n) {
                  _updateHintFromMetrics(n.metrics);
                  return false;
                },
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    _updateHintFromMetrics(n.metrics);
                    return true;
                  },
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                SliverAppBar(
                  backgroundColor: Colors.white,
                  expandedHeight: 320,
                  automaticallyImplyLeading: false,
                  pinned: true,
                  elevation: 0,
                  flexibleSpace: FlexibleSpaceBar(
                    background: Stack(
                      children: [
                        Obx(() {
                          // Reuse Home's LIVE nearby-driver markers (no duplicate
                          // socket listener — HomeMapController owns the stream).
                          // Reading markersRevision makes this Obx rebuild as cars move.
                          final homeC = Get.isRegistered<HomeMapController>()
                              ? Get.find<HomeMapController>()
                              : null;
                          homeC?.markersRevision.value;
                          final mergedMarkers = <Marker>{
                            ...mapC.markers,
                            if (homeC != null) ...homeC.markers,
                          };
                          return GoogleMap(
                            compassEnabled: false,
                            myLocationEnabled: true,
                            zoomControlsEnabled: false,
                            myLocationButtonEnabled: false,

                            initialCameraPosition: CameraPosition(
                              target:
                                  mapC.pickupPosition ??
                                  _initialCamTarget ??
                                  const LatLng(0, 0),
                              zoom: 14,
                            ),

                            onMapCreated: (controller) async {
                              await mapC.attachMap(controller);
                            },

                            onCameraIdle: mapC.onCameraIdle,
                            onCameraMoveStarted: mapC.onUserMapGesture,
                            onTap: (_) => mapC.onUserMapGesture(),

                            polylines: mapC.polylines.toSet(),
                            markers: mergedMarkers,
                            circles: mapC.circles.toSet(),

                            gestureRecognizers: {
                              Factory<OneSequenceGestureRecognizer>(
                                () => EagerGestureRecognizer(),
                              ),
                            },
                          );
                        }),

                        Positioned(
                          top: 270,
                          right: 10,
                          child: FloatingActionButton(
                            mini: true,
                            backgroundColor: Colors.white,
                            onPressed: () => mapC.onLocationButtonTap(),
                            child: const Icon(
                              Icons.my_location,
                              color: Colors.black,
                              size: 20,
                            ),
                          ),
                        ),

                        Positioned(
                          top: 50,
                          left: 15,
                          child: GestureDetector(
                            onTap: () => handleBookMapBack(),
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(30),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                AppImages.backImage,
                                height: 25,
                                width: 25,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 450),
                    curve: Curves.easeOutCubic,
                    builder: (context, t, child) {
                      return Opacity(
                        opacity: t.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, (1 - t) * 36),
                          child: child,
                        ),
                      );
                    },
                    child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 15,
                    ),
                    child: Column(
                      children: [
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
                                autofocus: false,
                                Style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.commonBlack.withOpacity(0.6),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                readOnly: true,
                                onTap: () async {
                                  final selected = await Navigator.push(
                                    context,
                                    bottomUpRoute(
                                      BookRideSearchScreen(
                                        isPickup: true,
                                        pickupData: {
                                          'description': _startController.text,
                                          'lat': mapC.pickupPosition?.latitude,
                                          'lng':
                                              mapC.pickupPosition?.longitude,
                                        },
                                        destinationData: {
                                          'description': _destController.text,
                                          'lat':
                                              mapC
                                                  .destinationPosition
                                                  ?.latitude,
                                          'lng':
                                              mapC
                                                  .destinationPosition
                                                  ?.longitude,
                                        },
                                      ),
                                      // Tells BookRideSearchScreen to pop back
                                      // to THIS screen with the result instead
                                      // of pushing a whole new BookMapScreen
                                      // (which used to leave a stale, still-
                                      // registered duplicate underneath).
                                      settings: const RouteSettings(
                                        arguments: 'fromMap',
                                      ),
                                    ),
                                  );

                                  if (selected != null &&
                                      selected['pickup'] != null) {
                                    final pickup = SelectedLocation.fromMap(
                                      Map<String, dynamic>.from(
                                        selected['pickup'],
                                      ),
                                      source: 'search',
                                    );
                                    if (pickup.isValid) {
                                      _startController.text = pickup.address;
                                      await mapC.setPickupLocation(pickup);
                                      // reset marker time cache
                                      driverController.markerAdded.value =
                                          false;
                                    }
                                  }
                                },
                                hintStyle: const TextStyle(fontSize: 11),
                                imgHeight: 17,
                                controller: _startController,
                                containerColor: AppColors.commonWhite,
                                leadingImage: AppImages.circleStart,
                                title: 'Search for an address or landmark',
                              ),
                              const Divider(
                                height: 0,
                                color: AppColors.containerColor,
                              ),

                              CustomTextFields.plainTextField(
                                autofocus: false,
                                Style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.commonBlack.withOpacity(0.6),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                readOnly: true,
                                onTap: () async {
                                  final selected = await Navigator.push(
                                    context,
                                    bottomUpRoute(
                                      BookRideSearchScreen(
                                        isPickup: false,
                                        pickupData: {
                                          'description': _startController.text,
                                          'lat': mapC.pickupPosition?.latitude,
                                          'lng':
                                              mapC.pickupPosition?.longitude,
                                        },
                                        destinationData: {
                                          'description': _destController.text,
                                          'lat':
                                              mapC
                                                  .destinationPosition
                                                  ?.latitude,
                                          'lng':
                                              mapC
                                                  .destinationPosition
                                                  ?.longitude,
                                        },
                                      ),
                                      settings: const RouteSettings(
                                        arguments: 'fromMap',
                                      ),
                                    ),
                                  );

                                  if (selected != null &&
                                      selected['destination'] != null) {
                                    final dest = SelectedLocation.fromMap(
                                      Map<String, dynamic>.from(
                                        selected['destination'],
                                      ),
                                      source: 'search',
                                    );
                                    if (dest.isValid) {
                                      _destController.text = dest.address;
                                      await mapC.setDestinationLocation(dest);
                                      driverController.markerAdded.value =
                                          false;
                                    }
                                  }
                                },
                                controller: _destController,
                                hintStyle: const TextStyle(fontSize: 11),
                                imgHeight: 17,
                                containerColor: AppColors.commonWhite,
                                leadingImage: AppImages.rectangleDest,
                                title: 'Enter destination',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        /// Solo Ride vs Shared Ride toggle
                        Obx(() {
                          return PackageContainer.bookContainers(
                            isSendSelected: mapC.isRideOnly.value,
                            onSelectionChanged: (selected) async {
                              if (selected == mapC.isRideOnly.value) return;
                              if (driverController.isGetLoading.value) return;
                              mapC.isRideOnly.value = selected;

                              AppLogger.log.i(
                                'Ride type: ${mapC.isRideOnly.value ? 'Solo Ride' : 'Shared Ride'}',
                              );

                              if (mapC.pickupPosition == null ||
                                  mapC.destinationPosition == null) {
                                AppToasts.customToast(
                                  context,
                                  'Pickup or destination is missing',
                                );
                                return;
                              }

                              final pickup = mapC.pickupPosition!;
                              final drop = mapC.destinationPosition!;

                              // Refresh drivers list for selected ride type.
                              if (mapC.isRideOnly.value) {
                                driverController.rideType.value =
                                    RideType.rideOnly;
                                await driverController.getDriverSearch(
                                  pickupLat: pickup.latitude,
                                  pickupLng: pickup.longitude,
                                  dropLat: drop.latitude,
                                  dropLng: drop.longitude,
                                );
                              } else {
                                driverController.rideType.value =
                                    RideType.shared;
                                await driverController.getSharedDriverSearch(
                                  pickupLat: pickup.latitude,
                                  pickupLng: pickup.longitude,
                                  dropLat: drop.latitude,
                                  dropLng: drop.longitude,
                                );
                              }
                            },
                          );
                        }),

                        const SizedBox(height: 20),

                        Obx(() {
                          if (driverController.isGetLoading.value) {
                            return SkeletonLoaders.bookRideCars();
                          }

                          final bool rideOnly = mapC.isRideOnly.value;

                          final normalDrivers = driverController.serviceType;
                          final sharedDrivers =
                              driverController.sharedServiceType;

                          final fetched =
                              rideOnly
                                  ? driverController.hasFetchedRideOnly.value
                                  : driverController.hasFetchedShared.value;

                          final hasDrivers =
                              rideOnly
                                  ? normalDrivers.isNotEmpty
                                  : sharedDrivers.isNotEmpty;

                          if (!hasDrivers) {
                            if (!fetched) {
                              // Avoid flashing "No drivers" before the first API response.
                              if (mapC.pickupPosition == null ||
                                  mapC.destinationPosition == null) {
                                return const SizedBox.shrink();
                              }
                              return SkeletonLoaders.bookRideCars();
                            }
                            return EmptyStateView(
                              imageSize: 120,
                              image: AppImages.emptyNoDrivers,
                              title: "No drivers nearby",
                              subtitle:
                                  "We couldn't find any drivers in your location right now.",
                            );
                          }

                          // ---------- RIDE ONLY ----------
                          if (rideOnly) {
                            // Support ALL server car types (Luxury / Sedan / SUV
                            // / Hatchback), not just two — one card per type that
                            // has a nearby driver.
                            const carTypes = [
                              'Luxury',
                              'Sedan',
                              'SUV',
                              'Hatchback',
                            ];

                            final rideCards = <Widget>[];
                            for (final t in carTypes) {
                              final d = normalDrivers.firstWhereOrNull(
                                (e) =>
                                    e.driverId.carType?.toLowerCase() ==
                                    t.toLowerCase(),
                              );
                              if (d == null) continue;
                              if (rideCards.isNotEmpty) {
                                rideCards.add(const SizedBox(height: 20));
                              }
                              rideCards.add(
                                PackageContainer.bookCarTypeContainer(
                                  borderColor:
                                      driverController.selectedCarType.value == t
                                          ? AppColors.commonBlack
                                          : AppColors.containerColor,
                                  carImg: AppImages.carImageForType(t),
                                  onTap: () {
                                    driverController.selectedCarType.value = t;
                                    driverController.estimatedTime.value =
                                        d.estimatedTime?.toString() ?? '';
                                    mapC.updateMarkersDebounced(
                                      pickupLabel:
                                          mapC.pickupLocation.value?.address ??
                                          widget.pickupAddress,
                                      dropLabel:
                                          mapC
                                              .destinationLocation
                                              .value
                                              ?.address ??
                                          widget.destinationAddress,
                                      estimatedMin:
                                          driverController.estimatedTime.value,
                                    );
                                  },
                                  carTitle: t,
                                  carMinRate: d.estimatedPrice.toString(),
                                  carMaxRate: d.estimatedPrice.toString(),
                                  carSubTitle: 'Comfy, Economical Cars',
                                  arrivingTime: '${d.estimatedTime ?? 0} min',
                                ),
                              );
                            }

                            // Set default marker once (first available type).
                            if (!driverController.markerAdded.value &&
                                rideCards.isNotEmpty) {
                              dynamic defaultDriver;
                              for (final t in carTypes) {
                                final d = normalDrivers.firstWhereOrNull(
                                  (e) =>
                                      e.driverId.carType?.toLowerCase() ==
                                      t.toLowerCase(),
                                );
                                if (d != null) {
                                  defaultDriver = d;
                                  break;
                                }
                              }
                              if (defaultDriver != null) {
                                driverController.estimatedTime.value =
                                    defaultDriver.estimatedTime?.toString() ??
                                    '';
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  mapC.updateMarkersDebounced(
                                    pickupLabel:
                                        mapC.pickupLocation.value?.address ??
                                        widget.pickupAddress,
                                    dropLabel:
                                        mapC
                                            .destinationLocation
                                            .value
                                            ?.address ??
                                        widget.destinationAddress,
                                    estimatedMin:
                                        driverController.estimatedTime.value,
                                  );
                                  driverController.markerAdded.value = true;
                                });
                              }
                            }

                            return Column(children: rideCards);
                          }

                          // ---------- SHARED ----------
                          const sharedCarTypes = [
                            'Luxury',
                            'Sedan',
                            'SUV',
                            'Hatchback',
                          ];

                          final sharedCards = <Widget>[];
                          for (final t in sharedCarTypes) {
                            final d = sharedDrivers.firstWhereOrNull(
                              (e) =>
                                  e.driverId?.carType?.toLowerCase() ==
                                  t.toLowerCase(),
                            );
                            if (d == null) continue;
                            if (sharedCards.isNotEmpty) {
                              sharedCards.add(const SizedBox(height: 20));
                            }
                            sharedCards.add(
                              PackageContainer.bookCarTypeContainer(
                                borderColor:
                                    driverController.selectedCarType.value == t
                                        ? AppColors.commonBlack
                                        : AppColors.containerColor,
                                carImg: AppImages.carImageForType(t),
                                onTap: () {
                                  driverController.selectedCarType.value = t;
                                  driverController.selectedSharedDriver.value = d;
                                  driverController.estimatedTime.value =
                                      d.estimatedTime?.toString() ?? '';
                                  mapC.updateMarkersDebounced(
                                    pickupLabel:
                                        mapC.pickupLocation.value?.address ??
                                        widget.pickupAddress,
                                    dropLabel:
                                        mapC
                                            .destinationLocation
                                            .value
                                            ?.address ??
                                        widget.destinationAddress,
                                    estimatedMin:
                                        driverController.estimatedTime.value,
                                  );
                                },
                                carTitle: t,
                                carMinRate: d.estimatedPrice.toString(),
                                carMaxRate: d.estimatedPrice.toString(),
                                carSubTitle: 'Shared comfy ride',
                                arrivingTime: '${d.estimatedTime ?? 0} min',
                              ),
                            );
                          }

                          if (!driverController.markerAdded.value &&
                              sharedCards.isNotEmpty) {
                            dynamic defaultDriver;
                            for (final t in sharedCarTypes) {
                              final d = sharedDrivers.firstWhereOrNull(
                                (e) =>
                                    e.driverId?.carType?.toLowerCase() ==
                                    t.toLowerCase(),
                              );
                              if (d != null) {
                                defaultDriver = d;
                                break;
                              }
                            }
                            if (defaultDriver != null) {
                              driverController.estimatedTime.value =
                                  defaultDriver.estimatedTime?.toString() ?? '';
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                mapC.updateMarkersDebounced(
                                  pickupLabel:
                                      mapC.pickupLocation.value?.address ??
                                      widget.pickupAddress,
                                  dropLabel:
                                      mapC.destinationLocation.value?.address ??
                                      widget.destinationAddress,
                                  estimatedMin:
                                      driverController.estimatedTime.value,
                                );
                                driverController.markerAdded.value = true;
                              });
                            }
                          }

                          return Column(children: sharedCards);
                        }),
                      ],
                    ),
                  ),
                  ),
                ),
              ],
                    ),
                  ),
                ),
              // Bouncing down-arrow hint — visible only while more content
              // remains below the fold. Tap to glide to the vehicle list / Book.
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: IgnorePointer(
                  ignoring: false,
                  child: Center(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _showScrollHint,
                      builder: (context, show, _) {
                        return AnimatedOpacity(
                          duration: const Duration(milliseconds: 220),
                          opacity: show ? 1 : 0,
                          child: AnimatedSlide(
                            duration: const Duration(milliseconds: 220),
                            offset: show ? Offset.zero : const Offset(0, 0.4),
                            child: GestureDetector(
                              onTap: show ? _scrollToBottom : null,
                              child: AnimatedBuilder(
                                animation: _arrowBounceCtrl,
                                builder: (context, child) {
                                  final dy =
                                      Curves.easeInOut.transform(
                                        _arrowBounceCtrl.value,
                                      ) *
                                      6.0;
                                  return Transform.translate(
                                    offset: Offset(0, dy),
                                    child: child,
                                  );
                                },
                                child: Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 8,
                                        offset: Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: Colors.black87,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),

          bottomNavigationBar: Obx(
            () => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child:
                  driverController.isLoading.value
                      ? AppLoader.appLoader()
                      : AppButtons.button(
                        buttonColor:
                            driverController.selectedCarType.value.isEmpty
                                ? AppColors.containerColor
                                : AppColors.commonBlack,
                        textColor: Colors.white,
                        onTap: () async {
                          if (driverController.selectedCarType.value.isEmpty) {
                            AppToasts.showInfoGlobal(
                              'Please select a car before proceeding.',
                              title: 'Info',
                            );
                            return;
                          }

                          final selectedCarType =
                              driverController.selectedCarType.value;

                          // Live selection from the controller — reflects any
                          // edit the passenger made to pickup/destination on
                          // this screen. `widget.pickupAddress`/
                          // `widget.destinationAddress` are the ORIGINAL
                          // constructor values and go stale after an edit.
                          final livePickupAddress =
                              mapC.pickupLocation.value?.address ??
                              widget.pickupAddress;
                          final liveDestinationAddress =
                              mapC.destinationLocation.value?.address ??
                              widget.destinationAddress;

                          if (mapC.isRideOnly.value) {
                            final result = await driverController
                                .createBookingCar(
                                  carType: selectedCarType,
                                  fromLatitude:
                                      mapC.pickupPosition?.latitude ?? 0.0,
                                  fromLongitude:
                                      mapC.pickupPosition?.longitude ?? 0.0,
                                  toLatitude:
                                      mapC.destinationPosition?.latitude ?? 0.0,
                                  toLongitude:
                                      mapC.destinationPosition?.longitude ??
                                      0.0,
                                  customerId: '',
                                  context: context,
                                );

                            if (result == null) {
                              final bookingId =
                                  driverController.carBooking.value?.bookingId;

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (context) => ConfirmBooking(
                                        carType: selectedCarType,
                                        bookingId: bookingId,
                                        selectedCarType: selectedCarType,
                                        pickupData: {
                                          'description': livePickupAddress,
                                          'lat':
                                              mapC.pickupPosition?.latitude ??
                                              0.0,
                                          'lng':
                                              mapC.pickupPosition?.longitude ??
                                              0.0,
                                        },
                                        destinationData: {
                                          'description': liveDestinationAddress,
                                          'lat':
                                              mapC
                                                  .destinationPosition
                                                  ?.latitude ??
                                              0.0,
                                          'lng':
                                              mapC
                                                  .destinationPosition
                                                  ?.longitude ??
                                              0.0,
                                        },
                                        pickupAddress: livePickupAddress,
                                        destinationAddress:
                                            liveDestinationAddress,
                                      ),
                                ),
                              );
                            }
                          } else {
                            final sharedDriver =
                                driverController.selectedSharedDriver.value;
                            if (sharedDriver == null) {
                              AppToasts.showInfoGlobal(
                                'Please select a shared car option first.',
                                title: 'Info',
                              );
                              return;
                            }

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (context) => RideShareScreen(
                                      occupiedSeats: sharedDriver.occupiedSeats,
                                      maxSeats: sharedDriver.maxSeats,
                                      sharedDriver: sharedDriver,
                                      seats: sharedDriver.seats,
                                      selectedCarType: selectedCarType,
                                      pickupData: {
                                        'description': livePickupAddress,
                                        'lat':
                                            mapC.pickupPosition?.latitude ??
                                            0.0,
                                        'lng':
                                            mapC.pickupPosition?.longitude ??
                                            0.0,
                                      },
                                      destinationData: {
                                        'description': liveDestinationAddress,
                                        'lat':
                                            mapC
                                                .destinationPosition
                                                ?.latitude ??
                                            0.0,
                                        'lng':
                                            mapC
                                                .destinationPosition
                                                ?.longitude ??
                                            0.0,
                                      },
                                      pickupAddress: livePickupAddress,
                                      destinationAddress:
                                          liveDestinationAddress,
                                    ),
                              ),
                            );
                          }
                        },
                        text:
                            driverController.selectedCarType.value.isEmpty
                                ? 'Book'
                                : 'Book ${driverController.selectedCarType.value}',
                      ),
            ),
          ),
        ),
      ),
    );
  }
}

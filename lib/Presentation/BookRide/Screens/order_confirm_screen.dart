import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Core/Utility/phone_launcher.dart';
import 'package:hopper/Presentation/BookRide/Controllers/order_confrim_controller.dart';
import 'package:hopper/Presentation/BookRide/SharedRideScreens/Widgets/shared_trip_status_card.dart';
import 'package:hopper/Presentation/OnBoarding/Controller/home_map_controller.dart';
import 'package:hopper/uitls/map/customer/customer_ride_map_view.dart';
import 'package:hopper/uitls/map/customer/marker_icon_cache.dart' as icon_cache;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:hopper/Presentation/BookRide/utils/trusted_contacts_store.dart';
import 'package:hopper/Presentation/CustomerSupport/screens/customer_support_list_screen.dart';

import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Utility/app_buttons.dart';
import 'package:hopper/Core/Utility/app_toasts.dart';
import 'package:hopper/Presentation/OnBoarding/Screens/chat_screen.dart';
import 'package:hopper/Presentation/OnBoarding/Screens/payment_screen.dart';
import 'package:hopper/Presentation/OnBoarding/Widgets/custom_bottomnavigation.dart';
import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
import 'package:hopper/uitls/netWorkHandling/network_handling_screen.dart';

class OrderConfirmScreen extends StatefulWidget {
  final Map<String, dynamic> pickupData;
  final Map<String, dynamic> destinationData;
  final String pickupAddress;
  final String bookingId;
  final String carType;
  final String destinationAddress;
  final double? baseFare;
  final double? serviceFare;
  final double? distanceFare;
  final double? pickupFare;
  final double? bookingFee;
  final double? timeFare;
  final String? resumeDriverId;
  final String? initialDriverName;
  final String? initialDriverProfilePic;
  final String? initialCarDetails;
  final double? initialAmount;
  final String? initialStatus;
  final bool? initialRideStarted;
  final bool? initialDestinationReached;

  const OrderConfirmScreen({
    super.key,
    required this.pickupData,
    required this.bookingId,
    required this.destinationData,
    required this.carType,
    required this.pickupAddress,
    required this.destinationAddress,
    this.baseFare,
    this.serviceFare,
    this.distanceFare,
    this.pickupFare,
    this.bookingFee,
    this.timeFare,
    this.resumeDriverId,
    this.initialDriverName,
    this.initialDriverProfilePic,
    this.initialCarDetails,
    this.initialAmount,
    this.initialStatus,
    this.initialRideStarted,
    this.initialDestinationReached,
  });

  @override
  State<OrderConfirmScreen> createState() => _OrderConfirmScreenState();
}

class _OrderConfirmScreenState extends State<OrderConfirmScreen>
    with
        AutomaticKeepAliveClientMixin,
        WidgetsBindingObserver,
        SingleTickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;

  late final OrderConfirmController c;
  final GlobalKey<CustomerRideMapViewState> _mapKey =
      GlobalKey<CustomerRideMapViewState>();
  late final LatLng _pickupLatLng;
  late final LatLng _dropLatLng;

  final TextEditingController _startController = TextEditingController();
  final TextEditingController _destController = TextEditingController();
  bool _hasNavigatedToPayment = false;
  bool _hasNavigatedHomeOnCancel = false;
  // Ride-status timeline: auto-center the active step (manual scroll allowed).
  final ScrollController _timelineCtrl = ScrollController();
  int _lastAutoScrolledStep = -1;
  static const MethodChannel _screenChannel = MethodChannel(
    'ride_screen_control',
  );

  Timer? _searchingElapsedTimer;
  int _searchingElapsedSeconds = 0;
  Worker? _rideSideEffectsWorker;

  // A2 + A3: driver-arrival alert + waiting timer.
  Worker? _arrivalWorker;
  Timer? _waitTimer;
  int _waitSeconds = 0;
  bool _arrivalHandled = false;

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setKeepScreenOn(true);

    _startController.text = widget.pickupAddress;
    _destController.text = widget.destinationAddress;

    c = Get.put(OrderConfirmController(), tag: widget.bookingId);
    // Map UI/camera is owned by CustomerRideMapView for consistent behavior.
    c.externalCameraControl = true;

    // Home map stays mounted UNDER this tracking screen (routes are pushed, not
    // replaced). Pause its GPS stream + nearby-driver animations so they don't
    // contend for CPU/battery on the device rendering the live driver marker.
    // Reversed in dispose(). Guarded so it's a no-op if home isn't registered.
    if (Get.isRegistered<HomeMapController>()) {
      Get.find<HomeMapController>().pauseForActiveTrip();
    }

    final pickupLat =
        _toDouble(widget.pickupData['lat']) ??
        _toDouble(widget.pickupData['latitude']);
    final pickupLng =
        _toDouble(widget.pickupData['lng']) ??
        _toDouble(widget.pickupData['longitude']);
    final dropLat =
        _toDouble(widget.destinationData['lat']) ??
        _toDouble(widget.destinationData['latitude']);
    final dropLng =
        _toDouble(widget.destinationData['lng']) ??
        _toDouble(widget.destinationData['longitude']);

    _pickupLatLng = LatLng(pickupLat ?? 9.9144908, pickupLng ?? 78.0970899);
    _dropLatLng = LatLng(dropLat ?? 9.9144908, dropLng ?? 78.0970899);

    c.init(
      bookingId: widget.bookingId,
      pickupAddress: widget.pickupAddress,
      destinationAddress: widget.destinationAddress,
      carType: widget.carType,
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      dropLat: dropLat,
      dropLng: dropLng,
      baseFare: widget.baseFare,
      serviceFare: widget.serviceFare,
      distanceFare: widget.distanceFare,
      pickupFare: widget.pickupFare,
      bookingFee: widget.bookingFee,
      timeFare: widget.timeFare,
      resumeDriverId: widget.resumeDriverId,
      initialDriverName: widget.initialDriverName,
      initialDriverProfilePic: widget.initialDriverProfilePic,
      initialCarDetails: widget.initialCarDetails,
      initialAmount: widget.initialAmount,
      initialStatus: widget.initialStatus,
      initialRideStarted: widget.initialRideStarted,
      initialDestinationReached: widget.initialDestinationReached,
    );

    // IMPORTANT: bind context after first frame (so timer & API always works)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      c.bindContext(context);

      final initialStatus = (widget.initialStatus ?? '').trim().toUpperCase();
      final resumedIntoActive =
          widget.initialDestinationReached == true ||
          widget.initialRideStarted == true ||
          initialStatus.contains('IN_PROGRESS') ||
          initialStatus.contains('RIDE_IN_PROGRESS') ||
          initialStatus.contains('RIDE_STARTED') ||
          initialStatus.contains('TRIP_STARTED') ||
          initialStatus.contains('STARTED');

      if (!resumedIntoActive) {
        c.startDriverSearchTimer(); // timer will always update UI
      }
      _setupRideSideEffectsWorker();
    });

    final initialStatus = (widget.initialStatus ?? '').trim().toUpperCase();
    final resumedIntoActive =
        widget.initialDestinationReached == true ||
        widget.initialRideStarted == true ||
        initialStatus.contains('IN_PROGRESS') ||
        initialStatus.contains('RIDE_IN_PROGRESS') ||
        initialStatus.contains('RIDE_STARTED') ||
        initialStatus.contains('TRIP_STARTED') ||
        initialStatus.contains('STARTED');

    if (!resumedIntoActive) {
      _searchingElapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _searchingElapsedSeconds += 1);
      });
    }
  }

  void _setupRideSideEffectsWorker() {
    _rideSideEffectsWorker?.dispose();
    _rideSideEffectsWorker = everAll(
      <RxInterface<dynamic>>[
        c.isDriverConfirmed,
        c.driverStartedRide,
        c.destinationReached,
        c.isTripCancelled,
      ],
      (_) {
        if (!mounted) return;
        _applyRideSideEffects();
      },
    );
    _applyRideSideEffects();

    // A2 + A3: alert + waiting timer when the driver arrives at pickup.
    _arrivalWorker?.dispose();
    _arrivalWorker = ever<bool>(c.driverArrived, (arrived) {
      if (mounted && arrived) _onDriverArrived();
    });
    if (c.driverArrived.value && !c.driverStartedRide.value) {
      _onDriverArrived();
    }
  }

  void _onDriverArrived() {
    if (_arrivalHandled) return;
    _arrivalHandled = true;
    HapticFeedback.heavyImpact();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF12B76A),
          duration: Duration(seconds: 4),
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your driver has arrived at the pickup point',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    _startWaitTimer();
  }

  void _startWaitTimer() {
    _waitTimer?.cancel();
    _waitSeconds = 0;
    _waitTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted ||
          c.driverStartedRide.value ||
          c.destinationReached.value ||
          c.isTripCancelled.value) {
        _waitTimer?.cancel();
        return;
      }
      setState(() => _waitSeconds += 1);
    });
  }

  String _fmtWait(int s) {
    final m = (s ~/ 60).toString();
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$m:$ss';
  }

  void _applyRideSideEffects() {
    // Battery: keep screen on only while waiting for a driver (pre-ride).
    final waitingForDriver =
        !c.isDriverConfirmed.value &&
        !c.driverStartedRide.value &&
        !c.destinationReached.value &&
        !c.isTripCancelled.value;

    unawaited(_setKeepScreenOn(waitingForDriver));

    if (!waitingForDriver) {
      _searchingElapsedTimer?.cancel();
    }
  }

  Future<String?> _handleCancelRide({
    required String bookingId,
    required String selectedReason,
  }) async {
    if (bookingId.trim().isEmpty) return 'Booking id missing';

    final res = await c.driverSearchController.cancelRide(
      bookingId: bookingId,
      selectedReason: selectedReason,
      context: context,
    );

    if (!mounted) return res;

    final ok = (res ?? '').trim().isEmpty;
    if (!ok) {
      final m = (res ?? '').toLowerCase();
      // Ride finished before the cancel landed -> it can't be cancelled; send
      // the customer to payment/completion instead of leaving them stuck.
      if (m.contains('complet')) {
        AppToasts.showInfoGlobal(
          'This ride is already completed.',
          title: 'Ride completed',
        );
        c.destinationReached.value = true; // triggers the payment navigation
        return '';
      }
      // Server says it's already cancelled -> reflect the cancelled state.
      if (m.contains('cancel')) {
        c.cancelReason.value = selectedReason;
        c.isTripCancelled.value = true;
        return '';
      }
      return res;
    }

    c.cancelReason.value = selectedReason;
    c.isTripCancelled.value = true;
    return '';
  }

  @override
  void dispose() {
    _timelineCtrl.dispose();
    _startController.dispose();
    _destController.dispose();
    _searchingElapsedTimer?.cancel();
    _rideSideEffectsWorker?.dispose();
    _arrivalWorker?.dispose();
    _waitTimer?.cancel();
    _setKeepScreenOn(false);
    WidgetsBinding.instance.removeObserver(this);
    // Re-arm the home map's GPS stream + nearby animations now that tracking
    // is leaving the foreground.
    if (Get.isRegistered<HomeMapController>()) {
      Get.find<HomeMapController>().resumeFromActiveTrip();
    }
    Get.delete<OrderConfirmController>(tag: widget.bookingId, force: true);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _applyRideSideEffects();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _setKeepScreenOn(false);
    }
  }

  Future<void> _setKeepScreenOn(bool enabled) async {
    try {
      await _screenChannel.invokeMethod('keepScreenOn', {'enabled': enabled});
    } catch (_) {}
  }

  String get _trackUrl =>
      'https://hoppr-admin-e7bebfb9fb05.herokuapp.com/ride-tracker/${widget.bookingId}';

  // A5: Safety toolkit sheet (emergency call, share live trip, trusted contacts).
  void _openSafetySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder:
          (_) => SafetySheet(
            trackUrl: _trackUrl,
            driverName: c.driverName.value,
          ),
    );
  }

  /// Full-screen, pinch-zoomable preview for the driver / car photos so the
  /// rider can verify their actual driver and vehicle before boarding.
  void _showImagePreview(String url, {String? caption}) {
    if (url.trim().isEmpty) return;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'driver-photo',
      barrierColor: Colors.white,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (ctx, _, __) => _DriverPhotoPreview(url: url, caption: caption),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return NoInternetOverlay(
      child: WillPopScope(
        onWillPop: () async => false,
        child: Scaffold(
          body: Stack(
            children: [
              SizedBox(
                height: 550,
                width: double.infinity,
                child: RepaintBoundary(
                  child: Obx(() {
                    final effectiveVehicleType =
                        c.cartypeFromServer.value.trim().isNotEmpty
                            ? c.cartypeFromServer.value
                            : widget.carType;

                    // ETA/distance now live on the reusable map card (same as
                    // the shared-ride screen) — the in-sheet chips were removed.
                    final etaPieces = c.etaChipText.value
                        .split('|')
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)
                        .toList();
                    final showTripMetrics =
                        c.isDriverConfirmed.value && !c.destinationReached.value;
                    final mapEta =
                        showTripMetrics && etaPieces.isNotEmpty
                            ? etaPieces.first
                            : '';
                    final mapDist =
                        showTripMetrics && etaPieces.length >= 2
                            ? etaPieces.last
                            : '';

                    return CustomerRideMapView(
                      key: _mapKey,
                      vehicleType:
                          effectiveVehicleType.toLowerCase().contains('bike')
                              ? icon_cache.VehicleType.bike
                              : icon_cache.VehicleType.car,
                      driverLocation: c.driverLocation.value,
                      driverLocationTs: c.driverLocationServerTs.value,
                      // Ensure Obx rebuilds when route points mutate.
                      routePoints: c.activeRoutePoints.toList(growable: false),
                      pickup: c.customerLatLng ?? _pickupLatLng,
                      drop: c.customerToLatLng ?? _dropLatLng,
                      mode:
                          c.driverStartedRide.value
                              ? RideMapMode.toDrop
                              : RideMapMode.toPickup,
                      etaText: mapEta,
                      distanceText: mapDist,
                      statusText:
                          c.driverStartedRide.value
                              ? 'Ride in progress'
                              : 'Driver reaching pickup',
                      // The embedded ride-map widget manages its own camera.
                      // Handing the same controller back to OrderConfirmController
                      // made two different follow systems animate the map at once.
                      onMapReady: null,
                      // Bottom sheet overlays the lower portion; keep map padding
                      // so Google logo/controls never overlap the sheet.
                      mapPadding: const EdgeInsets.only(bottom: 210),
                    );
                  }),
                ),
              ),

              // A5: Safety button (replaces the old Emergency dialer).
              Positioned(
                top: 50,
                right: 15,
                child: SafeArea(
                  child: GestureDetector(
                    onTap: _openSafetySheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: const Color(0xFFE11D48),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFE11D48).withOpacity(0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.shield_rounded,
                            color: Colors.white,
                            size: 17,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'Safety',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ETA/distance is rendered by CustomerRideMapView (reusable card).

              // OTP overlay (black card on map)
              // Positioned(
              //   top: 148,
              //   left: 16,
              //   right: 16,
              //   child: Obx(() {
              //     if (c.otp.value.isEmpty ||
              //         c.driverStartedRide.value ||
              //         c.destinationReached.value ||
              //         c.isTripCancelled.value) {
              //       return const SizedBox.shrink();
              //     }
              //     return _otpMapCard();
              //   }),
              // ),

              // locate / fit-route toggle
              Positioned(
                top: 350,
                right: 10,
                child: Obx(
                  () => FloatingActionButton(
                    heroTag: 'ride_follow_fit_${widget.bookingId}',
                    mini: true,
                    backgroundColor: Colors.white,
                    onPressed: () async {
                      if (c.focusDriverOnNextTap.value) {
                        c.focusDriverOnNextTap.value = false;
                        await _mapKey.currentState?.fitRoute(padding: 170);
                        return;
                      }
                      c.focusDriverOnNextTap.value = true;
                      await _mapKey.currentState?.recenter();
                    },
                    child: Icon(
                      c.focusDriverOnNextTap.value
                          ? Icons.fit_screen
                          : Icons.my_location,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),

              // Bottom sheet
              DraggableScrollableSheet(
                // No `key` → the sheet is NEVER recreated on phase change (no
                // rebuild / no "new screen" flash). The inner AnimatedSwitcher
                // morphs the content; the map underneath stays alive. One size
                // config for every phase — this sheet has no controller, so
                // dropping the key is fully safe (never a double-attach risk).
                initialChildSize: 0.5,
                minChildSize: 0.4,
                maxChildSize: 0.9,
                builder: (context, scrollController) {
                    return Obx(() {
                      final sheetStateKey =
                          '${c.isDriverConfirmed.value}-${c.isWaitingForDriver.value}-${c.noDriverFound.value}-${c.isTripCancelled.value}';
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        // Clean cross-fade (no default scale/zoom) so phases morph
                        // smoothly — matches the shared-ride sheet.
                        transitionBuilder: (child, anim) =>
                            FadeTransition(opacity: anim, child: child),
                        layoutBuilder: (currentChild, previousChildren) => Stack(
                          alignment: Alignment.topCenter,
                          children: [
                            ...previousChildren,
                            if (currentChild != null) currentChild,
                          ],
                        ),
                        child: Container(
                          key: ValueKey(sheetStateKey),
                          // 16px side padding — matches the shared-ride sheet
                          // (was 5, which made every card look border-to-border).
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(20),
                            ),
                          ),
                          child: ListView(
                            physics: const BouncingScrollPhysics(),
                            controller: scrollController,
                            children: [
                              Center(
                                child: Container(
                                  width: 40,
                                  height: 4,
                                  margin: const EdgeInsets.only(top: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[400],
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),

                              if (!c.isDriverConfirmed.value &&
                                  c.isTripCancelled.value)
                                _cancelledUI()
                              else if (!c.isDriverConfirmed.value &&
                                  c.isWaitingForDriver.value)
                                _waitingForDriverUI()
                              else if (!c.isDriverConfirmed.value &&
                                  c.noDriverFound.value)
                                _noDriverFoundUI()
                              else
                                _rideConfirmedUI(),

                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      );
                    });
                  },
                ),

              // Fixed bottom Call + Message bar — pinned under the draggable
              // sheet, same as the shared-ride screen.
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

  // ---------------- UI sections ----------------

  Widget _rideConfirmedUI() {
    return Obx(() {
      if (c.isTripCancelled.value) {
        return _cancelledUI();
      }

      if (c.destinationReached.value && !_hasNavigatedToPayment) {
        _hasNavigatedToPayment = true;
        Future.microtask(() async {
          await Future.delayed(const Duration(seconds: 2));
          final id =
              c.driverSearchController.carBooking.value?.bookingId ??
              c.bookingId;
          if (!mounted) return;
          // Clear the whole booking stack (search / confirm-booking / tracking)
          // so back from Payment can never land on confirm-booking again.
          Get.offAll(
            () => PaymentScreen(
              bookingId: id,
              amount: c.amount.value,
              driverName: c.driverName.value,
              driverProfilePic: c.profilePic.value,
            ),
          );
        });
      }

      return Column(
        children: [
          // Lead status card — SAME widget the shared-ride sheet uses
          // (SharedTripStatusCard): "ON TRIP" overline, bold stage title, and
          // the "8 min to drop · 2.3 km" detail line. Replaces the old plain
          // header text + tick.
          _buildReachStatusCard(),
          // DRIVER CARD directly under the status card (shared-ride order):
          // same bordered design — photo + rating badge, name → plate chip →
          // car details, car photo right, and the Solo ride tag INSIDE the card.
          const SizedBox(height: 12),
          _driverDetailsCard(),
          // ETA/distance chips removed — they now show on the map card and in
          // the status card detail, same as the shared-ride screen. Only the
          // arrived "Waiting" timer stays in the sheet (see _tripInfoInline).
          if (c.isDriverConfirmed.value && !c.destinationReached.value) ...[
            const SizedBox(height: 10),
            _tripInfoInline(),
          ],
          const SizedBox(height: 12),
          _rideStatusTimeline(),
          if (c.otp.value.isNotEmpty &&
              !c.driverStartedRide.value &&
              !c.destinationReached.value) ...[
            const SizedBox(height: 14),
            _otpHighlightCard(),
          ],
          const SizedBox(height: 14),
          _addressBox(),

          // Call + Message moved to the FIXED bottom action bar (shared-ride
          // parity) — see _buildFixedDriverActionBar().
          const SizedBox(height: 20),
          _fareBox(),
          const SizedBox(height: 20),
          _supportShareRow(),
          // Keep the last card clear of the fixed bottom Call/Message bar.
          const SizedBox(height: 78),
        ],
      );
    });
  }

  /// Lead status card — same UI as the shared-ride screen's
  /// _buildReachStatusCard, mapped to solo-ride state: PICKUP → ARRIVED →
  /// ON TRIP → COMPLETED. Detail line reuses etaChipText ("8 min | 2.3 km")
  /// joined as "8 min to drop · 2.3 km". No seat pill on solo rides.
  Widget _buildReachStatusCard() {
    String title;
    IconData icon;
    String badge;
    if (c.destinationReached.value) {
      icon = Icons.flag_rounded;
      title = 'You have reached your destination';
      badge = 'COMPLETED';
    } else if (c.driverStartedRide.value) {
      icon = Icons.navigation_rounded;
      badge = 'ON TRIP';
      title = 'On the way to your destination';
    } else if (c.driverArrived.value) {
      icon = Icons.local_taxi_rounded;
      title = 'Driver has arrived at pickup';
      badge = 'ARRIVED';
    } else {
      icon = Icons.directions_car_filled_rounded;
      badge = 'PICKUP';
      title = 'Driver is reaching you';
    }

    final detail = c.etaChipText.value
        .split('|')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .join('  ·  ');

    // "Action needed" stage gets a slightly stronger accent (same as shared).
    final bool emphasise = c.driverArrived.value && !c.driverStartedRide.value;

    final String stageKey = '$badge|$title|$detail';
    return AnimatedSize(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 340),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeIn,
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
        layoutBuilder:
            (currentChild, previousChildren) => Stack(
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
          detail: c.destinationReached.value ? '' : detail,
          icon: icon,
          emphasise: emphasise,
        ),
      ),
    );
  }

  /// Driver details card — identical design to the shared-ride screen's
  /// bordered driver card. Name/rating are parsed from driverName (backend
  /// sends "Name ⭐ 4.2" in one string, same as shared). Tap the driver photo
  /// or the car photo to open the full-screen verify preview.
  Widget _driverDetailsCard() {
    final rawName = c.driverName.value.trim();
    final starIdx = rawName.indexOf('⭐');
    final nameOnly =
        (starIdx >= 0 ? rawName.substring(0, starIdx) : rawName).trim();
    final ratingOnly =
        starIdx >= 0 ? rawName.substring(starIdx + 1).trim() : '';
    final profilePic = c.profilePic.value.trim();
    final carPhoto = c.carExteriorPhotos.value.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Driver photo + rating badge (tap → full-screen preview).
          SizedBox(
            width: 52,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomCenter,
              children: [
                GestureDetector(
                  onTap:
                      profilePic.isEmpty
                          ? null
                          : () => _showImagePreview(
                            profilePic,
                            caption: nameOnly,
                          ),
                  child: Container(
                    height: 52,
                    width: 52,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.containerColor1,
                      border: Border.all(
                        color: const Color(0xFF111418).withOpacity(0.25),
                        width: 2,
                      ),
                    ),
                    child:
                        profilePic.isNotEmpty
                            ? Image.network(
                              profilePic,
                              fit: BoxFit.cover,
                              errorBuilder:
                                  (_, __, ___) =>
                                      const Icon(Icons.person, size: 26),
                            )
                            : const Icon(Icons.person, size: 26),
                  ),
                ),
                if (ratingOnly.isNotEmpty)
                  Positioned(
                    bottom: -7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF111418),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            ratingOnly,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.star_rounded,
                            size: 10,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Name → plate chip → car details, each on its own line.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nameOnly.isEmpty ? 'Your driver' : nameOnly,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F3F5),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: Colors.black.withOpacity(0.08)),
                  ),
                  child: Text(
                    c.plateNumber.value.isEmpty ? '—' : c.plateNumber.value,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ),
                if (c.carDetails.value.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    c.carDetails.value,
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
          // Car exterior photo (right) — clean image, no "Verify" overlay;
          // tap still opens the full-screen preview.
          if (carPhoto.isNotEmpty)
            GestureDetector(
              onTap:
                  () => _showImagePreview(
                    carPhoto,
                    caption: 'Your car · ${c.plateNumber.value}'.trim(),
                  ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  carPhoto,
                  height: 66,
                  width: 86,
                  fit: BoxFit.cover,
                  errorBuilder:
                      (_, __, ___) => Container(
                        height: 66,
                        width: 86,
                        alignment: Alignment.center,
                        color: Colors.grey.shade200,
                        child: Icon(
                          Icons.directions_car,
                          color: Colors.grey.shade500,
                          size: 26,
                        ),
                      ),
                ),
              ),
            ),
        ],
          ),
          // Solo ride tag INSIDE the card (shared-ride parity — shared shows
          // its "Shared ride + Seat" tags in the same spot).
          const SizedBox(height: 14),
          Row(children: [_rideTypePill(shared: false)]),
        ],
      ),
    );
  }

  /// Fixed bottom app bar (Call + Message), pinned at the very bottom of the
  /// screen and always visible while the draggable sheet scrolls — identical
  /// styling to the shared-ride screen (black theme, haptic feedback on tap).
  Widget _buildFixedDriverActionBar() {
    return Obx(() {
      final show =
          c.isDriverConfirmed.value &&
          !c.destinationReached.value &&
          !c.isTripCancelled.value;
      if (!show) return const SizedBox.shrink();
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
                // Call — small rounded black button.
                GestureDetector(
                  onTap: () async {
                    HapticFeedback.mediumImpact();
                    try {
                      final rawNumber = c.driverPhone.value.trim();
                      if (rawNumber.isEmpty) {
                        AppToasts.showError(context, 'Driver number not set');
                        return;
                      }
                      final normalized = sanitizePhoneNumber(rawNumber);
                      if (normalized.isEmpty) {
                        AppToasts.showError(context, 'Invalid number');
                        return;
                      }
                      final ok = await launchPhoneDialer(normalized);
                      if (!ok) {
                        AppToasts.showError(context, 'Could not open dialer');
                      }
                    } catch (_) {
                      AppToasts.showError(context, 'Failed to start call');
                    }
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
                    child: const Icon(
                      Icons.call_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Message — wider rounded outlined button.
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      final booking =
                          c
                              .driverSearchController
                              .carBooking
                              .value
                              ?.bookingId ??
                          c.bookingId;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (_) => ChatScreen(
                                bookingId: booking,
                                pickupLatitude: _pickupLatLng.latitude,
                                pickupLongitude: _pickupLatLng.longitude,
                              ),
                        ),
                      );
                    },
                    child: Container(
                      height: 50,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.containerColor1,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.black.withOpacity(0.06),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 20,
                            color: Color(0xFF1A1A1A),
                          ),
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
    });
  }

  Widget _cancelledUI() {
    if (!_hasNavigatedHomeOnCancel) {
      _hasNavigatedHomeOnCancel = true;
      Future.microtask(() async {
        await Future.delayed(const Duration(seconds: 3));
        if (!mounted) return;
        Get.offAll(() => CommonBottomNavigation(initialIndex: 0));
      });
    }

    return Obx(() {
      final reason = c.cancelReason.value.trim();
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
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
              reason.isEmpty
                  ? "Your driver had to cancel this ride. You haven't been charged for the trip."
                  : reason,
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
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  Widget _tripInfoInline() {
    // ETA/distance chips moved to the map card (shared-ride parity); this
    // widget now only renders the arrived "Waiting" timer.
    // A3: waiting timer — shown once the driver has arrived at pickup.
    final waiting =
        c.driverArrived.value &&
        !c.driverStartedRide.value &&
        !c.destinationReached.value;

    if (!waiting) {
      return const SizedBox.shrink();
    }

    Widget chip(IconData icon, String text, {Color color = Colors.black}) {
      final isAccent = color != Colors.black;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(isAccent ? 0.12 : 0.05),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
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
        chip(
          Icons.timelapse_rounded,
          'Waiting ${_fmtWait(_waitSeconds)}',
          color: const Color(0xFF12B76A),
        ),
      ],
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
    final activeIndex = c.timelineIndex;

    // AUTO-CENTER the active step: when the stage advances, smoothly scroll so
    // the current step sits mid-viewport (manual horizontal scroll still works).
    // Item extent = 82 (step) + 34 (connector) = 116; +41 centers on the step.
    if (activeIndex != _lastAutoScrolledStep) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_timelineCtrl.hasClients) return;
        _lastAutoScrolledStep = activeIndex;
        final viewport = _timelineCtrl.position.viewportDimension;
        final target = (activeIndex * 116.0 + 41.0 - viewport / 2).clamp(
          0.0,
          _timelineCtrl.position.maxScrollExtent,
        );
        _timelineCtrl.animateTo(
          target,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        );
      });
    }

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
            controller: _timelineCtrl,
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
                  c.otp.value,
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
                const SizedBox(height: 6),
                Obx(() {
                  final cd = c.otpResendCooldown.value;
                  final busy = c.otpResending.value;
                  final disabled = busy || cd > 0;
                  return InkWell(
                    onTap: disabled ? null : c.resendRideOtp,
                    child: Text(
                      cd > 0
                          ? 'Resend OTP in ${cd}s'
                          : (busy ? 'Resending…' : "Didn't get it? Resend OTP"),
                      style: TextStyle(
                        color: disabled ? Colors.white54 : Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        decoration: disabled
                            ? TextDecoration.none
                            : TextDecoration.underline,
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: c.otp.value));
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

  // Widget _otpMapCard() {
  //   return Container(
  //     padding: const EdgeInsets.all(12),
  //     decoration: BoxDecoration(
  //       color: Colors.black,
  //       borderRadius: BorderRadius.circular(14),
  //       boxShadow: const [
  //         BoxShadow(
  //           color: Colors.black26,
  //           blurRadius: 10,
  //           offset: Offset(0, 6),
  //         ),
  //       ],
  //     ),
  //     child: Row(
  //       children: [
  //         Expanded(
  //           child: Column(
  //             crossAxisAlignment: CrossAxisAlignment.start,
  //             mainAxisSize: MainAxisSize.min,
  //             children: [
  //               const Text(
  //                 'Ride OTP',
  //                 style: TextStyle(
  //                   color: Colors.white70,
  //                   fontSize: 12,
  //                   fontWeight: FontWeight.w600,
  //                 ),
  //               ),
  //               const SizedBox(height: 4),
  //               Text(
  //                 c.otp.value,
  //                 style: const TextStyle(
  //                   color: Colors.white,
  //                   fontSize: 22,
  //                   fontWeight: FontWeight.w800,
  //                   letterSpacing: 2.5,
  //                 ),
  //               ),
  //             ],
  //           ),
  //         ),
  //         const SizedBox(width: 10),
  //         InkWell(
  //           onTap: () async {
  //             await Clipboard.setData(ClipboardData(text: c.otp.value));
  //             AppToasts.showSuccess(context, 'OTP copied');
  //           },
  //           child: Container(
  //             padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  //             decoration: BoxDecoration(
  //               color: Colors.white,
  //               borderRadius: BorderRadius.circular(12),
  //             ),
  //             child: const Icon(
  //               Icons.copy_rounded,
  //               size: 18,
  //               color: Colors.black,
  //             ),
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  Widget _fareBox() {
    return Obx(
      () => Container(
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
          padding: const EdgeInsets.only(top: 20, bottom: 12),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CustomTextFields.textWithImage(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          colors: AppColors.commonBlack,
                          text: 'Total Fare',
                          rightImagePath: AppImages.nBlackCurrency,
                          rightImagePathText: ' ${c.amount.value}',
                        ),
                        const Spacer(),
                        c.otp.value.isEmpty
                            ? const SizedBox.shrink()
                            : Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                color: Colors.black,
                              ),
                              child: CustomTextFields.textWithStyles600(
                                'OTP - ${c.otp.value}',
                                fontSize: 14,
                                color: Colors.white,
                              ),
                            ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: InkWell(
                        onTap: c.toggleFareDetails,
                        child: Row(
                          children: [
                            CustomTextFields.textWithStylesSmall(
                              'View Details',
                              colors: AppColors.changeButtonColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            const SizedBox(width: 10),
                            AnimatedRotation(
                              turns: c.isExpanded.value ? 0.5 : 0,
                              duration: const Duration(milliseconds: 300),
                              child: Image.asset(
                                AppImages.dropDown,
                                height: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    ClipRect(
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child:
                            c.isExpanded.value
                                ? _fareBreakdown()
                                : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _supportShareRow() {
    return Obx(() {
      final isCancelling = c.driverSearchController.isCancelLoading.value;
      final rideInProgress =
          c.driverStartedRide.value &&
          !c.destinationReached.value &&
          !c.isTripCancelled.value;
      final canCancel =
          !isCancelling &&
          !rideInProgress &&
          !c.destinationReached.value &&
          !c.isTripCancelled.value;

      final idRaw =
          c.driverSearchController.carBooking.value?.bookingId ?? c.bookingId;
      final id = idRaw.trim();
      final hasId = id.isNotEmpty;

      // Vertical action layout — icon on TOP, label BELOW (per design), with
      // even 16px padding and equal-width columns. Same bordered card style
      // as the rest of the sheet.
      Widget action({
        required IconData icon,
        required String label,
        required VoidCallback onTap,
        Color? color,
      }) {
        final effective = color ?? AppColors.cancelRideColor;
        return Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 22, color: effective),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: effective,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withOpacity(0.08)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              action(
                icon: Icons.cancel_outlined,
                label:
                    rideInProgress
                        ? 'Ride in progress'
                        : (isCancelling ? 'Cancelling...' : 'Cancel Ride'),
                color:
                    canCancel
                        ? AppColors.cancelRideColor
                        : AppColors.cancelRideColor.withOpacity(0.55),
                onTap: () {
                  if (rideInProgress) {
                    AppToasts.showInfoGlobal(
                      "Ride is in progress. Cancellation is not available now.",
                      title: 'Info',
                    );
                    return;
                  }
                  if (!canCancel) return;
                  if (!hasId) {
                    AppToasts.showError(
                      context,
                      'Booking id missing. Please try again.',
                    );
                    return;
                  }
                  AppButtons.showCancelRideBottomSheet(
                    context,
                    onConfirmCancel: (String selectedReason) async {
                      return _handleCancelRide(
                        bookingId: id,
                        selectedReason: selectedReason,
                      );
                    },
                  );
                },
              ),
              const SizedBox(
                height: 34,
                child: VerticalDivider(color: Colors.grey, thickness: 1),
              ),
              action(
                icon: Icons.support_agent_rounded,
                label: 'Support',
                onTap: () {
                  if (!hasId) return;
                  HapticFeedback.selectionClick();
                  Get.to(() => CustomerSupportListScreen(bookingId: id));
                },
              ),
              const SizedBox(
                height: 34,
                child: VerticalDivider(color: Colors.grey, thickness: 1),
              ),
              action(
                icon: Icons.ios_share_rounded,
                label: 'Share',
                onTap: () {
                  if (!hasId) return;
                  final url =
                      "https://hoppr-admin-e7bebfb9fb05.herokuapp.com/ride-tracker/$id";
                  Share.share(url);
                },
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _waitingForDriverUI() {
    final t = _searchingElapsedSeconds;
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

    final dots = '.' * (1 + (t % 3));
    return Padding(
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
          Image.asset(AppImages.confirmCar, height: 150, width: 220),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
          const SizedBox(height: 14),
          _addressBox(),
          const SizedBox(height: 14),
          Obx(() {
            final loading = c.driverSearchController.isCancelLoading.value;
            return AppButtons.button(
              hasBorder: true,
              borderColor: AppColors.commonBlack.withOpacity(0.2),
              buttonColor: AppColors.commonWhite,
              textColor: AppColors.cancelRideColor,
              isLoading: loading,
              onTap:
                  loading
                      ? null
                      : () {
                        AppButtons.showCancelRideBottomSheet(
                          context,
                          onConfirmCancel: (String selectedReason) async {
                            final id =
                                c
                                    .driverSearchController
                                    .carBooking
                                    .value
                                    ?.bookingId ??
                                c.bookingId;
                            return _handleCancelRide(
                              bookingId: id,
                              selectedReason: selectedReason,
                            );
                          },
                        );
                      },
              text: 'Cancel Ride',
            );
          }),
        ],
      ),
    );
  }

  Widget _fareBreakdown() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.commonBlack.withOpacity(0.1)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Fare Breakdown',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          _fareRow('Base Fare', widget.baseFare ?? 0),
          _fareRow('Distance Fare', widget.distanceFare ?? 0),
          _fareRow('Pickup Fare', widget.pickupFare ?? 0),
          _fareRow('Booking Fee', widget.bookingFee ?? 0),
          _fareRow('Time Fare', widget.timeFare ?? 0),
        ],
      ),
    );
  }

  Widget _fareRow(String title, num val) {
    return Row(
      children: [
        CustomTextFields.textWithStylesSmall(title),
        const Spacer(),
        CustomTextFields.textWithImage(
          colors: AppColors.commonBlack,
          text: val.toString(),
          imagePath: AppImages.nBlackCurrency,
        ),
      ],
    );
  }

  Widget _noDriverFoundUI() {
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
          const Text(
            "No drivers found",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF14213A),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "We couldn't find any available drivers nearby.\nPlease try again in a few minutes.",
            textAlign: TextAlign.center,
            style: TextStyle(
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
            text: "Try Again",
            isLoading: c.driverSearchController.isRetryLoading.value,
            onTap:
                c.driverSearchController.isRetryLoading.value
                    ? null
                    : () async {
                      c.isWaitingForDriver.value = true;
                      c.noDriverFound.value = false;

                      final allData = c.driverSearchController.carBooking.value;
                      final result = await c.driverSearchController
                          .sendDriverRequest(
                            carType: widget.carType,
                            pickupLatitude: allData?.fromLatitude ?? 0.0,
                            pickupLongitude: allData?.fromLongitude ?? 0.0,
                            dropLatitude: allData?.toLatitude ?? 0.0,
                            dropLongitude: allData?.toLongitude ?? 0.0,
                            bookingId: allData?.bookingId.toString() ?? '',
                            context: context,
                          );

                      if (!mounted) return;

                      if (result == 'success') {
                        c.startDriverSearchTimer();
                      }
                    },
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
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

  Widget _addressBox() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
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
            title: 'Pickup location',
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
            title: 'Drop location',
            hintStyle: const TextStyle(fontSize: 11),
            imgHeight: 17,
          ),
        ],
      ),
    );
  }
}

/// Clean, premium driver-photo preview on a white background: the photo in a
/// rounded card with a soft shadow, then the driver name (verified) and rating.
/// The rating is embedded in the name string ("Name ⭐️ 4.5"), so we split it.
class _DriverPhotoPreview extends StatelessWidget {
  final String url;
  final String? caption;

  const _DriverPhotoPreview({required this.url, this.caption});

  String get _name {
    final c = (caption ?? '').trim();
    final idx = c.indexOf('⭐');
    return (idx >= 0 ? c.substring(0, idx) : c).trim();
  }

  String? get _rating {
    final c = caption ?? '';
    final idx = c.indexOf('⭐');
    if (idx < 0) return null;
    final r =
        c.substring(idx).replaceAll('⭐️', '').replaceAll('⭐', '').trim();
    return r.isEmpty ? null : r;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final name = _name;
    final rating = _rating;

    return Material(
      color: Colors.white,
      child: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Photo card
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: media.size.width * 0.74,
                        maxHeight: media.size.height * 0.55,
                      ),
                      child: AspectRatio(
                        aspectRatio: 3 / 4,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.black.withOpacity(0.06),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.12),
                                blurRadius: 26,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(23),
                            child: InteractiveViewer(
                              minScale: 1,
                              maxScale: 4,
                              child: Image.network(
                                url,
                                fit: BoxFit.cover,
                                loadingBuilder: (c, child, progress) =>
                                    progress == null
                                        ? child
                                        : const ColoredBox(
                                          color: Color(0xFFF1F2F5),
                                          child: Center(
                                            child: CircularProgressIndicator(),
                                          ),
                                        ),
                                errorBuilder: (_, __, ___) => const ColoredBox(
                                  color: Color(0xFFF1F2F5),
                                  child: Center(
                                    child: Icon(
                                      Icons.person_rounded,
                                      color: Colors.black26,
                                      size: 72,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    // Driver name + verified tick
                    if (name.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.verified_rounded,
                            color: Color(0xFF2563EB),
                            size: 20,
                          ),
                        ],
                      ),
                    // Rating pill
                    if (rating != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7E6),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFFFFE3A3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: Color(0xFFE79700),
                              size: 19,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              rating,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF7A5A00),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Close button
            Positioned(
              top: 8,
              right: 12,
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1F2F5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close_rounded,
                    color: Colors.black87,
                    size: 22,
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

/// A5 + A4: Safety toolkit bottom sheet — emergency call, share live trip,
/// and trusted contacts (one-tap share the live link via SMS).
class SafetySheet extends StatefulWidget {
  final String trackUrl;
  final String driverName;

  const SafetySheet({required this.trackUrl, required this.driverName});

  @override
  State<SafetySheet> createState() => SafetySheetState();
}

class SafetySheetState extends State<SafetySheet> {
  final TrustedContactsStore _store = const TrustedContactsStore();
  List<TrustedContact> _contacts = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _store.load();
    if (!mounted) return;
    setState(() => _contacts = list);
  }

  String get _message => 'Track my Hoppr ride live: ${widget.trackUrl}';

  Future<void> _callEmergency() async {
    final prefs = await SharedPreferences.getInstance();
    final sos = (prefs.getString('sosNumber') ?? '').trim();
    if (sos.isEmpty) {
      if (mounted) AppToasts.showError(context, 'SOS number not set');
      return;
    }
    final n = sanitizePhoneNumber(sos);
    if (n.isEmpty) return;
    await launchPhoneDialer(n);
  }

  void _shareLiveTrip() => Share.share(_message);

  Future<void> _smsContact(TrustedContact ct) async {
    final uri = Uri.parse(
      'sms:${ct.phone}?body=${Uri.encodeComponent(_message)}',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      _shareLiveTrip();
    }
  }

  Future<void> _addContact() async {
    final nameC = TextEditingController();
    final phoneC = TextEditingController();

    Widget field({
      required TextEditingController controller,
      required String hint,
      required IconData icon,
      TextInputType? keyboard,
      TextCapitalization caps = TextCapitalization.none,
    }) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF5F6F8),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withOpacity(0.05)),
        ),
        child: TextField(
          controller: controller,
          keyboardType: keyboard,
          textCapitalization: caps,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: Colors.grey.shade600),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 16,
            ),
          ),
        ),
      );
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Container(
                        height: 44,
                        width: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withOpacity(0.10),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Icon(
                          Icons.person_add_alt_1_rounded,
                          color: Color(0xFF2563EB),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 13),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Add trusted contact',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Share your live trip with one tap',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  field(
                    controller: nameC,
                    hint: 'Name',
                    icon: Icons.person_outline_rounded,
                    caps: TextCapitalization.words,
                  ),
                  const SizedBox(height: 12),
                  field(
                    controller: phoneC,
                    hint: 'Phone number',
                    icon: Icons.phone_outlined,
                    keyboard: TextInputType.phone,
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Save contact',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (saved == true && phoneC.text.trim().isNotEmpty) {
      await _store.add(
        TrustedContact(
          name: nameC.text.trim().isEmpty ? 'Contact' : nameC.text.trim(),
          phone: phoneC.text.trim(),
        ),
      );
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
                  Container(
                    height: 40,
                    width: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE11D48).withOpacity(0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.shield_rounded,
                      color: Color(0xFFE11D48),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Safety toolkit',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Your safety, our priority',
                          style: TextStyle(fontSize: 12.5, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _actionCard(
                icon: Icons.emergency_share_rounded,
                color: const Color(0xFFE11D48),
                title: 'Call emergency',
                subtitle: 'Reach the Hoppr SOS line right away',
                onTap: _callEmergency,
              ),
              const SizedBox(height: 10),
              _actionCard(
                icon: Icons.ios_share_rounded,
                color: const Color(0xFF2563EB),
                title: 'Share live trip',
                subtitle: 'Send your live tracking link to anyone',
                onTap: _shareLiveTrip,
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Trusted contacts',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _addContact,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF2563EB),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (_contacts.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F8FA),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'Add a trusted contact to share your live trip with one tap.',
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                )
              else
                ..._contacts.map(_contactRow),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              Container(
                height: 42,
                width: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contactRow(TrustedContact ct) {
    final initial =
        ct.name.trim().isNotEmpty ? ct.name.trim()[0].toUpperCase() : '?';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF2563EB),
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ct.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    ct.phone,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: Colors.grey),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Share live trip',
              onPressed: () => _smsContact(ct),
              icon: const Icon(Icons.send_rounded, color: Color(0xFF2563EB)),
            ),
            IconButton(
              tooltip: 'Remove',
              onPressed: () async {
                await _store.remove(ct.phone);
                await _load();
              },
              icon: const Icon(Icons.close_rounded, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

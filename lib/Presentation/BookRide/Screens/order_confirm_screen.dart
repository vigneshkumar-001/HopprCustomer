import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Presentation/BookRide/Controllers/order_confrim_controller.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

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
  });

  @override
  State<OrderConfirmScreen> createState() => _OrderConfirmScreenState();
}

class _OrderConfirmScreenState extends State<OrderConfirmScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;

  late final OrderConfirmController c;

  final TextEditingController _startController = TextEditingController();
  final TextEditingController _destController = TextEditingController();
  bool _hasNavigatedToPayment = false;
  static const MethodChannel _screenChannel = MethodChannel(
    'ride_screen_control',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setKeepScreenOn(true);

    _startController.text = widget.pickupAddress;
    _destController.text = widget.destinationAddress;

    c = Get.put(OrderConfirmController(), tag: widget.bookingId);

    c.init(
      bookingId: widget.bookingId,
      pickupAddress: widget.pickupAddress,
      destinationAddress: widget.destinationAddress,
      carType: widget.carType,
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
    );

    // âœ… IMPORTANT: bind context after first frame (so timer & API always works)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      c.bindContext(context);
      c.startDriverSearchTimer(); // âœ… now timer will always update UI
    });
  }

  @override
  void dispose() {
    _startController.dispose();
    _destController.dispose();
    _setKeepScreenOn(false);
    WidgetsBinding.instance.removeObserver(this);
    Get.delete<OrderConfirmController>(tag: widget.bookingId, force: true);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setKeepScreenOn(true);
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
                child: Obx(
                  () => GoogleMap(
                    compassEnabled: true,
                    rotateGesturesEnabled: false,
                    tiltGesturesEnabled: false,

                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,

                    onCameraMove: c.onCameraMove,
                    onCameraMoveStarted: () => c.onUserMapGesture(),
                    onTap: (_) => c.onUserMapGesture(),

                    initialCameraPosition: CameraPosition(
                      target:
                          c.currentPosition ??
                          const LatLng(9.9144908, 78.0970899),
                      zoom: c.currentZoomLevel,
                      bearing: 0,
                      tilt: 0,
                    ),

                    markers: c.markers.toSet(),
                    polylines: c.polylines.toSet(),
                    circles: c.circles.toSet(),
                    minMaxZoomPreference: const MinMaxZoomPreference(
                      11.0,
                      17.0,
                    ),

                    onMapCreated: (controller) async {
                      // final style = await DefaultAssetBundle.of(context)
                      //     .loadString('assets/map_style/map_style1.json');
                      c.onMapCreated(controller /*style*/);
                    },

                    gestureRecognizers: {
                      Factory<OneSequenceGestureRecognizer>(
                        () => EagerGestureRecognizer(),
                      ),
                    },
                  ),
                ),
              ),

              // Emergency
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
                        AppToasts.showError(context,'Invalid SOS number');
                        return;
                      }

                      final uri = Uri(scheme: 'tel', path: normalized);
                      final ok = await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                      if (!ok) AppToasts.showError(context,'Could not open dialer');
                    } catch (_) {
                      AppToasts.showError(context,'Failed to start call');
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

              Positioned(
                top: 102,
                left: 16,
                right: 88,
                child: Obx(() {
                  if (!c.isDriverConfirmed.value ||
                      c.etaChipText.value.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: _etaChip(),
                  );
                }),
              ),

              // locate / fit-route toggle
              Positioned(
                top: 350,
                right: 10,
                child: Obx(
                  () => FloatingActionButton(
                    mini: true,
                    backgroundColor: Colors.white,
                    onPressed: c.onLocateActionTap,
                    child: Icon(
                      c.focusDriverOnNextTap.value
                          ? Icons.navigation
                          : Icons.fit_screen,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),

              // Bottom sheet
              Obx(
                () => DraggableScrollableSheet(
                  key: ValueKey(
                    '${c.isDriverConfirmed.value}-${c.isWaitingForDriver.value}-${c.noDriverFound.value}',
                  ),
                  initialChildSize: c.isDriverConfirmed.value ? 0.65 : 0.5,
                  minChildSize: 0.4,
                  maxChildSize: c.isDriverConfirmed.value ? 0.9 : 0.80,
                  builder: (context, scrollController) {
                    return Obx(() {
                      final sheetStateKey =
                          '${c.isDriverConfirmed.value}-${c.isWaitingForDriver.value}-${c.noDriverFound.value}';
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: Container(
                          key: ValueKey(sheetStateKey),
                          padding: const EdgeInsets.symmetric(horizontal: 15),
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
        Future.microtask(() async {
          await Future.delayed(const Duration(seconds: 3));
          if (mounted) {
            Get.offAll(() => CommonBottomNavigation(initialIndex: 0));
          }
        });

        return Container(
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
                  c.cancelReason.value.isEmpty
                      ? "Your trip has been cancelled"
                      : c.cancelReason.value,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      }

      if (c.destinationReached.value && !_hasNavigatedToPayment) {
        _hasNavigatedToPayment = true;
        Future.microtask(() async {
          await Future.delayed(const Duration(seconds: 2));
          final id =
              c.driverSearchController.carBooking.value?.bookingId ??
              c.bookingId;
          if (!mounted) return;
          Get.off(
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
          Center(
            child: CustomTextFields.textWithImage(
              fontSize: 20,
              imageSize: 24,
              fontWeight: FontWeight.w600,
              text:
                  c.destinationReached.value
                      ? 'Ride Completed'
                      : c.driverStartedRide.value
                      ? 'Ride in Progress'
                      : 'Your ride is confirmed',
              colors: AppColors.commonBlack,
              rightImagePath: AppImages.clrTick,
            ),
          ),
          const SizedBox(height: 12),
          _rideStatusTimeline(),
          if (c.otp.value.isNotEmpty &&
              !c.driverStartedRide.value &&
              !c.destinationReached.value) ...[
            const SizedBox(height: 14),
            _otpHighlightCard(),
          ],
          const SizedBox(height: 14),

          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CustomTextFields.textWithStylesSmall(
                    c.plateNumber.value,
                    colors: AppColors.commonBlack,
                    fontWeight: FontWeight.w500,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        height: 36,
                        width: 36,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(50),
                          color: AppColors.containerColor1,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child:
                            c.profilePic.value.isNotEmpty
                                ? Image.network(
                                  c.profilePic.value,
                                  fit: BoxFit.cover,
                                  errorBuilder:
                                      (_, __, ___) =>
                                          const Icon(Icons.person, size: 20),
                                )
                                : const Icon(Icons.person, size: 20),
                      ),
                      const SizedBox(width: 10),
                      CustomTextFields.textWithStylesSmall(
                        c.driverName.value,
                        colors: AppColors.commonBlack,
                        fontWeight: FontWeight.w500,
                      ),
                    ],
                  ),
                  CustomTextFields.textWithStylesSmall(
                    c.carDetails.value,
                    fontSize: 12,
                    colors: AppColors.carTypeColor,
                  ),
                ],
              ),
              const Spacer(),
              c.carExteriorPhotos.value.isNotEmpty
                  ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      c.carExteriorPhotos.value,
                      height: 80,
                      width: 100,
                      fit: BoxFit.fill,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  )
                  : const SizedBox.shrink(),
            ],
          ),

          const SizedBox(height: 20),

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
                      final phone = 'tel:${c.customerPhone.value}';
                      final uri = Uri.parse(phone);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      }
                    },
                    child: Image.asset(AppImages.call, height: 20, width: 20),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: () {
                    final booking =
                        c.driverSearchController.carBooking.value?.bookingId ??
                        c.bookingId;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(bookingId: booking),
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
                          Image.asset(AppImages.send, height: 16, width: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          _fareBox(),
          const SizedBox(height: 20),
          _supportShareRow(),
        ],
      );
    });
  }

  Widget _etaChip() {
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
          const Icon(Icons.schedule_rounded, size: 18, color: Colors.black),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              c.etaChipText.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
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
              ],
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: c.otp.value));
              AppToasts.showSuccess(context,'OTP copied');
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
          padding: const EdgeInsets.only(top: 20),
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
                                color: AppColors.userChatContainerColor,
                              ),
                              child: CustomTextFields.textWithStyles600(
                                'OTP - ${c.otp.value}',
                                fontSize: 16,
                                color: AppColors.commonWhite,
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
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child:
                          c.isExpanded.value
                              ? _fareBreakdown()
                              : const SizedBox.shrink(),
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
    return Obx(
      () => Container(
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CustomTextFields.textWithImage(
                onTap:
                    c.otp.value.isNotEmpty
                        ? null
                        : () {
                          AppButtons.showCancelRideBottomSheet(
                            context,
                            onConfirmCancel: (String selectedReason) {
                              c.driverSearchController.cancelRide(
                                bookingId:
                                    c
                                        .driverSearchController
                                        .carBooking
                                        .value!
                                        .bookingId,
                                selectedReason: selectedReason,
                                context: context,
                              );
                            },
                          );
                        },
                text: c.otp.value.isNotEmpty ? 'Ratings' : ' Cancel Ride',
                fontWeight: FontWeight.w500,
                colors: AppColors.cancelRideColor,
                imagePath: c.otp.value.isNotEmpty ? null : AppImages.cancel,
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 24,
                child: VerticalDivider(color: Colors.grey, thickness: 1),
              ),
              const SizedBox(width: 10),
              CustomTextFields.textWithImage(
                onTap: () {},
                text: 'Support',
                fontWeight: FontWeight.w500,
                colors: AppColors.cancelRideColor,
                imagePath: AppImages.support,
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 24,
                child: VerticalDivider(color: Colors.grey, thickness: 1),
              ),
              const SizedBox(width: 10),
              CustomTextFields.textWithImage(
                onTap: () {
                  final id =
                      c.driverSearchController.carBooking.value?.bookingId ??
                      c.bookingId;
                  final url =
                      "https://hoppr-admin-e7bebfb9fb05.herokuapp.com/ride-tracker/$id";
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
      ),
    );
  }

  Widget _waitingForDriverUI() {
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
        _addressBox(),
        const SizedBox(height: 20),
        AppButtons.button(
          hasBorder: true,
          borderColor: AppColors.commonBlack.withOpacity(0.2),
          buttonColor: AppColors.commonWhite,
          textColor: AppColors.cancelRideColor,
          isLoading: c.driverSearchController.isCancelLoading.value,
          onTap:
              c.driverSearchController.isCancelLoading.value
                  ? null
                  : () {
                    AppButtons.showCancelRideBottomSheet(
                      context,
                      onConfirmCancel: (String selectedReason) {
                        c.driverSearchController.cancelRide(
                          bookingId:
                              c
                                  .driverSearchController
                                  .carBooking
                                  .value!
                                  .bookingId,
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

  Widget _fareBreakdown() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
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
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 80),
          const SizedBox(height: 20),
          const Text(
            "No Driver Found",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.redAccent,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "We could not find any available drivers nearby.\nPlease try again in a few minutes.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
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
    );
  }
}

// import 'dart:async';
// import 'package:cached_network_image/cached_network_image.dart';
// import 'package:hopper/Core/Utility/app_toasts.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'dart:convert';
// import 'dart:math' as math;
//
// import 'package:hopper/Core/Consents/app_texts.dart';
// import 'package:hopper/Presentation/BookRide/Controllers/driver_search_controller.dart';
// import 'package:hopper/Presentation/OnBoarding/Screens/chat_screen.dart';
// // import 'package:hopper/api/repository/api_consents.dart';
// import 'package:hopper/uitls/netWorkHandling/network_handling_screen.dart';
// import 'package:url_launcher/url_launcher.dart';
//
// import 'package:flutter/foundation.dart';
// import 'package:hopper/Presentation/OnBoarding/Screens/payment_screen.dart';
// import 'package:http/http.dart' as http;
//
// import 'package:flutter/gestures.dart';
// import 'package:flutter/material.dart';
// import 'package:hopper/Core/Consents/app_colors.dart';
// import 'package:hopper/Core/Utility/app_buttons.dart';
// import 'package:hopper/Core/Utility/app_images.dart';
// import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
// import 'package:hopper/uitls/websocket/socket_io_client.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:hopper/Core/Consents/app_logger.dart';
// import 'package:geocoding/geocoding.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:get/get.dart';
// import 'package:share_plus/share_plus.dart';
//
// class DriverPose {
//   final LatLng latLng;
//   final DateTime t;
//   final double? bearing;
//   DriverPose(this.latLng, {DateTime? t, this.bearing})
//     : t = t ?? DateTime.now();
// }
//
// class OrderConfirmScreen extends StatefulWidget {
//   final Map<String, dynamic> pickupData;
//   final Map<String, dynamic> destinationData;
//   final String pickupAddress;
//   final String bookingId;
//   final String carType;
//   final String destinationAddress;
//   final double? baseFare;
//   final double? serviceFare;
//   final double? distanceFare;
//   final double? pickupFare;
//   final double? bookingFee;
//   final double? timeFare;
// final String? resumeDriverId;
// final String? initialDriverName;
// final String? initialDriverProfilePic;
// final String? initialCarDetails;
// final double? initialAmount;
//
//   const OrderConfirmScreen({
//     super.key,
//     required this.pickupData,
//     required this.bookingId,
//     required this.destinationData,
//     required this.carType,
//     required this.pickupAddress,
//     required this.destinationAddress,
//     this.baseFare,
//     this.serviceFare,
//     this.distanceFare,
//     this.pickupFare,
//     this.bookingFee,
//     this.timeFare,
//   });
//
//   @override
//   State<OrderConfirmScreen> createState() => _OrderConfirmScreenState();
// }
//
// class _OrderConfirmScreenState extends State<OrderConfirmScreen>
//     with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
//   @override
//   bool get wantKeepAlive => true;
//
//   // ---------------- UI state ----------------
//   bool isExpanded = false;
//   final TextEditingController _startController = TextEditingController();
//   final TextEditingController _destController = TextEditingController();
//   bool _isDrawingPolyline = false;
//   double _currentZoomLevel = 13.5;
//
//   bool isDriverConfirmed = false;
//   bool driverStartedRide = false;
//   bool destinationReached = false;
//   bool _autoFollowEnabled = false;
//   Timer? _autoFollowTimer;
//   String bookingId = ' ';
//   bool _userInteractingWithMap = false;
//   final socketService = SocketService();
//   GoogleMapController? _mapController;
//   LatLng? _pickedPosition;
//   double? _lastZoom;
//   final double _zoomThreshold = 0.01;
//   Marker? _driverMarker;
//   Set<Marker> _markers = {};
//   BitmapDescriptor? _carIcon;
//   BitmapDescriptor? _bikeIcon;
//   LatLng? _currentPosition;
//   LatLng? _customerLatLng;
//   LatLng? _customerToLatLang;
//   LatLng? _currentDriverLatLng;
//
//   String _address = 'Search...';
//   String plateNumber = '';
//   String ProfilePic = '';
//   String CarExteriorPhotos = '';
//   String driverName = '';
//   double driverRating = 0.0;
//   String carDetails = '';
//   String CUSTOMERPHONE = '';
//   String CARTYPE = '';
//   String otp = '';
//   double Amount = 0.0;
//   Set<Polyline> _polylines = {};
//   bool isTripCancelled = false;
//   String cancelReason = "";
//
//   // ---------------- Smooth motion engine ----------------
//   final List<DriverPose> _poseQueue = <DriverPose>[];
//   bool _isAnimatingSegment = false;
//   AnimationController? _moveCtrl;
//   double _lastBearing = 0;
//   Duration _minSeg = const Duration(milliseconds: 450);
//   Duration _maxSeg = const Duration(milliseconds: 1600);
//   static const double _autoFollowMinZoom = 15.0;
//   static const double _autoFollowMaxZoom = 17.0;
//   final Curve _ease = Curves.easeInOutCubic;
//
//   // ----- Smooth filters & limits (NEW) -----
//   LatLng? _emaPos;
//   double _emaAlphaSlow = 0.15; // smoother when slow
//   double _emaAlphaFast = 0.35; // snappier when fast
//   double _bearingEmaAlpha = 0.25;
//
//   int _maxQueue = 6;
//   Duration _maxStale = const Duration(seconds: 6);
//
//   DateTime _lastPolylineAt = DateTime.fromMillisecondsSinceEpoch(0);
//   Duration _polylineInterval = const Duration(seconds: 4);
//
//   // ---------------- Controllers ----------------
//   final DriverSearchController driverSearchController = Get.put(
//     DriverSearchController(),
//   );
//
//   // ---------------- Lifecycle ----------------
//   @override
//   void initState() {
//     super.initState();
//     _moveCtrl = AnimationController(vsync: this);
//
//     _loadCustomMarkers().then((_) {
//       _setupSocketListeners();
//       _initLocation();
//       _goToCurrentLocation();
//     });
//     startDriverSearch();
//   }
//
//   @override
//   void dispose() {
//     _moveCtrl?.dispose();
//     super.dispose();
//   }
//
//   // ---------------- Assets / Icons ----------------
//   Future<void> _loadCustomMarkers() async {
//     _carIcon = await BitmapDescriptor.fromAssetImage(
//       const ImageConfiguration(size: Size(52, 52)),
//       AppImages.movingCar,
//     );
//     _bikeIcon = await BitmapDescriptor.fromAssetImage(
//       const ImageConfiguration(size: Size(48, 48)),
//       AppImages.packageBike,
//     );
//   }
//
//   BitmapDescriptor _iconForVehicleType(String? type) {
//     final t = (type ?? '').toLowerCase();
//     switch (t) {
//       case 'bike':
//       case 'two_wheeler':
//       case '2w':
//       case 'motorbike':
//       case 'scooter':
//         return _bikeIcon ?? BitmapDescriptor.defaultMarker;
//       case 'car':
//       case 'sedan':
//       case 'hatchback':
//       case 'suv':
//       default:
//         return _carIcon ?? BitmapDescriptor.defaultMarker;
//     }
//   }
//
//   // ---------------- Location helpers ----------------
//   Future<void> _initLocation() async {
//     Position position = await Geolocator.getCurrentPosition();
//     setState(() {
//       _currentPosition = LatLng(position.latitude, position.longitude);
//     });
//     AppLogger.log.i(_currentPosition);
//   }
//
//   void _goToCurrentLocation() async {
//     Position position = await Geolocator.getCurrentPosition(
//       desiredAccuracy: LocationAccuracy.high,
//     );
//     final latLng = LatLng(position.latitude, position.longitude);
//     _mapController?.animateCamera(CameraUpdate.newLatLngZoom(latLng, 17));
//   }
//
//   // ---------------- Driver searching UI timing ----------------
//   bool isWaitingForDriver = true;
//   bool noDriverFound = false;
//
//   void startDriverSearch() {
//     isWaitingForDriver = true;
//     noDriverFound = false;
//
//     Future.delayed(const Duration(seconds: 40), () async {
//       if (!isDriverConfirmed) {
//         bool hasDriver = await driverSearchController.noDriverFound(
//           context: context,
//           bookingId: widget.bookingId,
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
//   // ---------------- Socket listeners ----------------
//   void _setupSocketListeners() {
//     socketService.onConnect(() {
//       AppLogger.log.i("âœ… Socket connected on booking screen");
//     });
//
//     socketService.on('joined-booking', (data) {
//       if (!mounted) return;
//       AppLogger.log.i("ðŸš• Joined booking data: $data");
//       final vehicle = data['vehicle'] ?? {};
//       final String driverId = data['driverId'] ?? '';
//       final String driverFullName = data['driverName'] ?? '';
//       final String customerPhone = data['customerPhone'].toString();
//       final double rating =
//           double.tryParse(data['driverRating'].toString()) ?? 0.0;
//       final String color = vehicle['color'] ?? '';
//       final String model = vehicle['model'] ?? '';
//       final String brand = vehicle['brand'] ?? '';
//       final String serviceType = vehicle['serviceType'] ?? '';
//       final bool driverAccepted = data['driver_accept_status'] == true;
//       final String type = vehicle['type'] ?? '';
//       final String plate = vehicle['plateNumber'] ?? '';
//       final String profilePic = vehicle['profilePic'] ?? '';
//       final customerLoc = data['customerLocation'];
//       final carExteriorPhotos = data['carExteriorPhotos'];
//       final amount =
//           (data['amount'] is num) ? (data['amount'] as num).toDouble() : 0.0;
//
//       _customerLatLng = LatLng(
//         (customerLoc['fromLatitude'] as num).toDouble(),
//         (customerLoc['fromLongitude'] as num).toDouble(),
//       );
//       _customerToLatLang = LatLng(
//         (customerLoc['toLatitude'] as num).toDouble(),
//         (customerLoc['toLongitude'] as num).toDouble(),
//       );
//
//       setState(() {
//         plateNumber = plate;
//         driverName = '$driverFullName â­ $rating';
//         carDetails = '$color - $brand';
//         isDriverConfirmed = driverAccepted;
//         CUSTOMERPHONE = customerPhone;
//         CARTYPE = serviceType;
//         Amount = amount;
//         ProfilePic = profilePic;
//         CarExteriorPhotos = carExteriorPhotos;
//       });
//
//       // Start real-time tracking
//       if (driverId.trim().isNotEmpty) {
//         AppLogger.log.i("ðŸ“ Tracking driver: $driverId");
//         socketService.emit('track-driver', {'driverId': driverId.trim()});
//       }
//     });
//
//     // >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>  SMOOTH POSE-QUEUE HANDLER  <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
//     socketService.on('driver-location', (data) {
//       AppLogger.log.i('ðŸ“¦ driver-location-updated: $data');
//
//       final lat = (data['latitude'] as num).toDouble();
//       final lng = (data['longitude'] as num).toDouble();
//       final ts =
//           (data['timestamp'] is int)
//               ? DateTime.fromMillisecondsSinceEpoch(data['timestamp'])
//               : DateTime.now();
//       final srvBearing =
//           (data['bearing'] != null)
//               ? (data['bearing'] as num).toDouble()
//               : null;
//
//       // small jitter guard (ignore sub-meter hops)
//       if (_currentDriverLatLng != null) {
//         final jitter = Geolocator.distanceBetween(
//           _currentDriverLatLng!.latitude,
//           _currentDriverLatLng!.longitude,
//           lat,
//           lng,
//         );
//         if (jitter < 0.8) {
//           return;
//         }
//       }
//
//       // Drop stale points
//       if (DateTime.now().difference(ts).abs() > _maxStale) {
//         return;
//       }
//
//       final pose = DriverPose(LatLng(lat, lng), t: ts, bearing: srvBearing);
//
//       // Keep queue ordered by timestamp (insertion for tiny lists)
//       int idx = _poseQueue.indexWhere((p) => p.t.isAfter(ts));
//       if (idx == -1) {
//         _poseQueue.add(pose);
//       } else {
//         _poseQueue.insert(idx, pose);
//       }
//       // Trim queue to avoid backlog
//       if (_poseQueue.length > _maxQueue) {
//         _poseQueue.removeRange(0, _poseQueue.length - _maxQueue);
//       }
//
//       // Route polyline (throttled)
//       if (!driverStartedRide &&
//           _customerLatLng != null &&
//           _shouldUpdatePolyline()) {
//         _drawPolylineFromDriverToCustomer(
//           driverLatLng: pose.latLng,
//           customerLatLng: _customerLatLng!,
//         );
//       }
//       if (driverStartedRide &&
//           _customerToLatLang != null &&
//           _shouldUpdatePolyline()) {
//         _drawPolylineFromDriverToCustomer(
//           driverLatLng: pose.latLng,
//           customerLatLng: _customerToLatLang!,
//         );
//       }
//
//       _pumpMotion();
//     });
//
//     socketService.on('driver-arrived', (data) {
//       AppLogger.log.i("driver-arrived: $data");
//     });
//
//     socketService.on('otp-generated', (data) {
//       if (!mounted) return;
//       final otpGenerated = data['otpCode'].toString();
//       setState(() {
//         otp = otpGenerated;
//       });
//       AppLogger.log.i("otp-generated: $data");
//     });
//
//     socketService.on('ride-started', (data) {
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
//
//     socketService.on('driver-reached-destination', (data) {
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
//
//     socketService.on('customer-cancelled', (data) async {
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
//
//     socketService.on('driver-cancelled', (data) async {
//       AppLogger.log.i('driver-cancelled : $data');
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
//   }
//
//   // ---------------- Smooth motion core ----------------
//   void _pumpMotion() {
//     if (_isAnimatingSegment) return;
//
//     // If marker not placed yet, seed with the first pose
//     if (_currentDriverLatLng == null && _poseQueue.isNotEmpty) {
//       final first = _poseQueue.removeAt(0);
//       _currentDriverLatLng = first.latLng;
//       _lastBearing = _driverMarker?.rotation ?? 0;
//       _emaPos = first.latLng; // seed EMA
//       _updateDriverMarker(first.latLng, _lastBearing);
//     }
//
//     if (_poseQueue.isEmpty || _currentDriverLatLng == null) return;
//
//     final LatLng from = _currentDriverLatLng!;
//     final DriverPose toPose = _poseQueue.removeAt(0);
//     final LatLng to = toPose.latLng;
//
//     final dist = Geolocator.distanceBetween(
//       from.latitude,
//       from.longitude,
//       to.latitude,
//       to.longitude,
//     );
//     final dtMs = toPose.t.difference(DateTime.now()).inMilliseconds.abs();
//
//     // Base duration scales with distance, blended with cadence if server timestamp present
//     int dur = (450 + (dist - 30).clamp(0, 3000) * 0.25).toInt();
//     if (dtMs > 0) {
//       dur = ((dur * 0.6) + (dtMs * 0.4)).toInt();
//     }
//     final segDur = Duration(
//       milliseconds: dur.clamp(_minSeg.inMilliseconds, _maxSeg.inMilliseconds),
//     );
//
//     final targetBearing = (toPose.bearing ?? _getBearing(from, to));
//     final startBearing = _lastBearing;
//     final bearingDelta = _shortestAngleDelta(startBearing, targetBearing);
//
//     _isAnimatingSegment = true;
//
//     _moveCtrl!
//       ..duration = segDur
//       ..removeListener(_tickDummy)
//       ..addListener(() => _onTick(from, to, startBearing, bearingDelta))
//       ..forward(from: 0).whenComplete(() {
//         _currentDriverLatLng = to;
//         _lastBearing = _normalizeAngle(startBearing + bearingDelta);
//         _updateDriverMarker(to, _lastBearing);
//
//         _isAnimatingSegment = false;
//
//         final coalesceMeters = 3.5;
//         if (_poseQueue.length >= 2) {
//           for (int i = _poseQueue.length - 2; i >= 0; i--) {
//             final a = _poseQueue[i].latLng;
//             final b = _poseQueue[i + 1].latLng;
//             final d = Geolocator.distanceBetween(
//               a.latitude,
//               a.longitude,
//               b.latitude,
//               b.longitude,
//             );
//             if (d < coalesceMeters) {
//               _poseQueue.removeAt(i);
//             }
//           }
//         }
//         if (_poseQueue.isNotEmpty) _pumpMotion();
//       });
//   }
//
//   // Used only to removeListener safely
//   void _tickDummy() {}
//
//   void _onTick(
//     LatLng from,
//     LatLng to,
//     double startBearing,
//     double bearingDelta,
//   ) {
//     final t = _ease.transform(_moveCtrl!.value);
//
//     // Raw linear interpolation
//     final rawLat = _lerp(from.latitude, to.latitude, t);
//     final rawLng = _lerp(from.longitude, to.longitude, t);
//     final rawPos = LatLng(rawLat, rawLng);
//
//     // Compute rough segment speed (m/s) for adaptive EMA
//     final rawDist = Geolocator.distanceBetween(
//       from.latitude,
//       from.longitude,
//       to.latitude,
//       to.longitude,
//     );
//     final segSeconds = (_moveCtrl!.duration?.inMilliseconds ?? 1) / 1000.0;
//     final speedMps = (segSeconds > 0) ? (rawDist / segSeconds) : 0.0;
//
//     // Position EMA
//     final emaAlpha = _alphaForSpeed(speedMps);
//     _emaPos =
//         (_emaPos == null) ? rawPos : _emaLatLng(_emaPos!, rawPos, emaAlpha);
//     final displayPos = _emaPos!;
//
//     // Bearing smoothing (shortest path)
//     final targetBearing = _wrap360(startBearing + bearingDelta * t);
//     _lastBearing = _emaAngle(_lastBearing, targetBearing, _bearingEmaAlpha);
//
//     _updateDriverMarker(displayPos, _lastBearing);
//
//     // Gentle auto-follow
//     if (_autoFollowEnabled && _mapController != null) {
//       final zoom = _currentZoomLevel.clamp(
//         _autoFollowMinZoom,
//         _autoFollowMaxZoom,
//       );
//       try {
//         _mapController!.moveCamera(
//           CameraUpdate.newCameraPosition(
//             CameraPosition(
//               target: displayPos,
//               zoom: zoom,
//               tilt: 50,
//               bearing: _lastBearing,
//             ),
//           ),
//         );
//       } catch (_) {}
//     }
//   }
//
//
//   void _updateDriverMarker(LatLng position, double bearing) {
//     final newMarker = Marker(
//       markerId: const MarkerId("driver_marker"),
//       position: position,
//       rotation: bearing,
//       icon: _iconForVehicleType(CARTYPE),
//       anchor: const Offset(
//         0.5,
//         0.6,
//       ), // tweak so rotation feels centered on car nose
//       flat: true,
//     );
//
//     setState(() {
//       _markers.removeWhere((m) => m.markerId.value == "driver_marker");
//       _markers.add(newMarker);
//       _driverMarker = newMarker;
//     });
//   }
//
//   Future<void> _drawPolylineFromDriverToCustomer({
//     required LatLng driverLatLng,
//     required LatLng customerLatLng,
//   }) async {
//     if (_isDrawingPolyline) return;
//     _isDrawingPolyline = true;
//
//     final apiKey = ApiConsents.googleMapApiKey;
//     final url =
//         'https://maps.googleapis.com/maps/api/directions/json?origin=${driverLatLng.latitude},${driverLatLng.longitude}&destination=${customerLatLng.latitude},${customerLatLng.longitude}&key=$apiKey';
//
//     final response = await http.get(Uri.parse(url));
//     final data = json.decode(response.body);
//     if (!mounted) return;
//
//     if (data['status'] == 'OK') {
//       final encoded = data['routes'][0]['overview_polyline']['points'];
//       final points = _decodePolyline(encoded);
//       if (!mounted) return;
//       setState(() {
//         _polylines = {
//           Polyline(
//             polylineId: PolylineId(
//               driverStartedRide ? "driver_to_drop" : "driver_to_pickup",
//             ),
//             points: points,
//             color: Colors.black,
//             width: 4,
//           ),
//         };
//       });
//     } else {
//       debugPrint("â— Error fetching directions: ${data['status']}");
//     }
//     _isDrawingPolyline = false;
//   }
//
//   List<LatLng> _decodePolyline(String encoded) {
//     List<LatLng> points = [];
//     int index = 0, len = encoded.length;
//     int lat = 0, lng = 0;
//
//     while (index < len) {
//       int b, shift = 0, result = 0;
//       do {
//         b = encoded.codeUnitAt(index++) - 63;
//         result |= (b & 0x1f) << shift;
//         shift += 5;
//       } while (b >= 0x20);
//       int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
//       lat += dlat;
//
//       shift = 0;
//       result = 0;
//       do {
//         b = encoded.codeUnitAt(index++) - 63;
//         result |= (b & 0x1f) << shift;
//         shift += 5;
//       } while (b >= 0x20);
//       int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
//       lng += dlng;
//
//       points.add(LatLng(lat / 1E5, lng / 1E5));
//     }
//     return points;
//   }
//
//   // ---------------- Math & smoothing helpers (NEW) ----------------
//   double _lerp(double start, double end, double t) => start + (end - start) * t;
//
//   double _getBearing(LatLng start, LatLng end) {
//     final lat1 = start.latitude * math.pi / 180;
//     final lon1 = start.longitude * math.pi / 180;
//     final lat2 = end.latitude * math.pi / 180;
//     final lon2 = end.longitude * math.pi / 180;
//
//     final dLon = lon2 - lon1;
//     final y = math.sin(dLon) * math.cos(lat2);
//     final x =
//         math.cos(lat1) * math.sin(lat2) -
//         math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
//     final bearing = math.atan2(y, x);
//     return (bearing * 180 / math.pi + 360) % 360;
//   }
//
//   double _normalizeAngle(double a) {
//     a %= 360.0;
//     if (a < 0) a += 360.0;
//     return a;
//   }
//
//   // returns signed delta in [-180, +180] to go shortest way
//   double _shortestAngleDelta(double from, double to) {
//     double diff = _normalizeAngle(to) - _normalizeAngle(from);
//     if (diff > 180) diff -= 360;
//     if (diff < -180) diff += 360;
//     return diff;
//   }
//
//   double _wrap360(double a) {
//     a %= 360.0;
//     if (a < 0) a += 360.0;
//     return a;
//   }
//
//   double _signedDelta(double from, double to) {
//     double diff = _wrap360(to) - _wrap360(from);
//     if (diff > 180) diff -= 360;
//     if (diff < -180) diff += 360;
//     return diff;
//   }
//
//   /// EMA for angles (respects wrap-around)
//   double _emaAngle(double prevDeg, double targetDeg, double alpha) {
//     final d = _signedDelta(prevDeg, targetDeg);
//     return _wrap360(prevDeg + alpha * d);
//   }
//
//   /// EMA for LatLng
//   LatLng _emaLatLng(LatLng prev, LatLng next, double alpha) {
//     return LatLng(
//       prev.latitude + (next.latitude - prev.latitude) * alpha,
//       prev.longitude + (next.longitude - prev.longitude) * alpha,
//     );
//   }
//
//   /// Choose EMA alpha based on speed (m/s)
//   double _alphaForSpeed(double mps) =>
//       (mps > 8.0) ? _emaAlphaFast : _emaAlphaSlow;
//
//   /// Safe throttle helper for polylines
//   bool _shouldUpdatePolyline() {
//     final now = DateTime.now();
//     if (now.difference(_lastPolylineAt) >= _polylineInterval) {
//       _lastPolylineAt = now;
//       return true;
//     }
//     return false;
//   }
//
//   // ---------------- Map callbacks ----------------
//   void _onCameraMove(CameraPosition position) {
//     _currentZoomLevel = position.zoom;
//   }
//
//   // ---------------- Build ----------------
//   @override
//   Widget build(BuildContext context) {
//     super.build(context);
//     _startController.text = widget.pickupAddress;
//     _destController.text = widget.destinationAddress;
//
//     return NoInternetOverlay(
//       child: WillPopScope(
//         onWillPop: () async => false,
//         child: Scaffold(
//           body: Stack(
//             children: [
//               SizedBox(
//                 height: 550,
//                 width: double.infinity,
//                 child: GoogleMap(
//                   compassEnabled: false,
//                   onCameraMoveStarted: () {
//                     _userInteractingWithMap = true;
//                     _autoFollowEnabled = false;
//                     _autoFollowTimer?.cancel();
//                     _autoFollowTimer = Timer(const Duration(seconds: 8), () {
//                       _autoFollowEnabled = true;
//                       _userInteractingWithMap = false;
//                     });
//                   },
//                   onCameraMove: _onCameraMove,
//                   initialCameraPosition: CameraPosition(
//                     target:
//                         _currentPosition ?? const LatLng(9.9144908, 78.0970899),
//                     zoom: _currentZoomLevel,
//                   ),
//                   markers: _markers,
//                   onMapCreated: (controller) async {
//                     _mapController = controller;
//                     String style = await DefaultAssetBundle.of(
//                       context,
//                     ).loadString('assets/map_style/map_style1.json');
//                     _mapController?.setMapStyle(style);
//                     _autoFollowEnabled = true; // Enable auto-follow on start
//                   },
//                   polylines: _polylines,
//                   myLocationEnabled: true,
//                   myLocationButtonEnabled: false,
//                   zoomControlsEnabled: false,
//                   gestureRecognizers: {
//                     Factory<OneSequenceGestureRecognizer>(
//                       () => EagerGestureRecognizer(),
//                     ),
//                   },
//                 ),
//               ),
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
//               Positioned(
//                 top: 350,
//                 right: 10,
//                 child: FloatingActionButton(
//                   mini: true,
//                   backgroundColor: Colors.white,
//                   onPressed: _goToCurrentLocation,
//                   child: const Icon(Icons.my_location, color: Colors.black),
//                 ),
//               ),
//               // ---------------- Bottom Sheet ----------------
//               DraggableScrollableSheet(
//                 key: ValueKey(isDriverConfirmed),
//                 initialChildSize: isDriverConfirmed ? 0.65 : 0.5,
//                 minChildSize: 0.4,
//                 maxChildSize: isDriverConfirmed ? 0.9 : 0.80,
//                 builder: (context, scrollController) {
//                   return Container(
//                     padding: const EdgeInsets.symmetric(horizontal: 15),
//                     decoration: const BoxDecoration(
//                       color: Colors.white,
//                       borderRadius: BorderRadius.vertical(
//                         top: Radius.circular(20),
//                       ),
//                     ),
//                     child: ListView(
//                       physics: const BouncingScrollPhysics(),
//                       controller: scrollController,
//                       children: [
//                         Center(
//                           child: Container(
//                             width: 40,
//                             height: 4,
//                             margin: const EdgeInsets.only(top: 8),
//                             decoration: BoxDecoration(
//                               color: Colors.grey[400],
//                               borderRadius: BorderRadius.circular(10),
//                             ),
//                           ),
//                         ),
//                         const SizedBox(height: 12),
//
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
//
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
//                                     ), // ðŸ‘ˆ change radius as needed
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
//
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
//                                       final phoneNumber = 'tel:$CUSTOMERPHONE';
//                                       AppLogger.log.i(phoneNumber);
//                                       final Uri url = Uri.parse(phoneNumber);
//                                       if (await canLaunchUrl(url)) {
//                                         await launchUrl(url);
//                                       } else {
//                                         debugPrint('Could not launch dialer');
//                                       }
//                                     },
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
//                                                   driverSearchController
//                                                       .carBooking
//                                                       .value!
//                                                       .bookingId,
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
//                           // ----- Fare Box -----
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
//                             onTap: () {
//                               print(widget.bookingId);
//                             },
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
//   // ---------------- Small UI fragments ----------------
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
//             "No Driver Found",
//             style: TextStyle(
//               fontSize: 22,
//               fontWeight: FontWeight.bold,
//               color: Colors.redAccent,
//             ),
//           ),
//           const SizedBox(height: 8),
//           const Text(
//             "We could not find any available drivers nearby.\nPlease try again in a few minutes.",
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
//               if (result == 'success') {
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
//

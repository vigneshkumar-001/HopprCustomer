import 'dart:io';
import 'package:hopper/Presentation/BookRide/SharedRideScreens/Controller/share_ride_controller.dart';
import 'package:hopper/Presentation/BookRide/SharedRideScreens/Screens/shared_screens.dart';
import 'package:hopper/Presentation/OnBoarding/Controller/package_controller.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:dotted_line/dotted_line.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:hopper/Core/Consents/app_texts.dart';
import 'package:hopper/Core/Utility/app_buttons.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Core/Utility/app_loader.dart';
import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
import 'package:hopper/Presentation/BookRide/Models/pricing_insights_model.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:get/get.dart';

import '../../../../Core/Utility/compressImage.dart';

class SharedConfrimBooking extends StatefulWidget {
  final String? selectedCarType;
  final String? bookingId;
  final Map<String, dynamic> pickupData;
  final Map<String, dynamic> destinationData;
  final String pickupAddress;
  final String destinationAddress;
  final String? carType;
  final List<LatLng> routePoints;
  final List<int> selectedSeats;
  const SharedConfrimBooking({
    super.key,
    this.selectedCarType,
    this.bookingId,
    required this.pickupData,
    this.carType,
    required this.destinationData,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.routePoints, // 🔹 NEW
    this.selectedSeats = const [],
  });

  @override
  State<SharedConfrimBooking> createState() => _SharedConfrimBookingState();
}

class _SharedConfrimBookingState extends State<SharedConfrimBooking> {
  final TextEditingController _startController = TextEditingController();
  final TextEditingController _destController = TextEditingController();
  ShareRideController driverController = Get.put(ShareRideController());
  final PackageController packageController = Get.put(PackageController());
  List<LatLng> _routePoints = [];

  LatLng? _pickupPosition;
  LatLng? _destinationPosition;
  @override
  @override
  void initState() {
    super.initState();

    // Safe coercion: pickupData/destinationData are dynamic maps; values may
    // arrive as int/String/null. A raw cast to double here threw in initState
    // and crashed the screen. Use the same num?->double pattern as the rest of
    // this file.
    _pickupPosition = LatLng(
      (widget.pickupData['lat'] as num?)?.toDouble() ?? 0.0,
      (widget.pickupData['lng'] as num?)?.toDouble() ?? 0.0,
    );

    _destinationPosition = LatLng(
      (widget.destinationData['lat'] as num?)?.toDouble() ?? 0.0,
      (widget.destinationData['lng'] as num?)?.toDouble() ?? 0.0,
    );
  }

  String formatDistance(double meters) {
    double kilometers = meters / 1000;
    return '${kilometers.toStringAsFixed(2)} Km';
  }

  String formatDuration(int minutes) {
    int hours = minutes ~/ 60;
    int remainingMinutes = minutes % 60;
    return hours > 0
        ? '$hours hr $remainingMinutes min'
        : '$remainingMinutes min';
  }

  @override
  Widget build(BuildContext context) {
    _startController.text = widget.pickupAddress;
    _destController.text = widget.destinationAddress;
    return Scaffold(
      body: SafeArea(
        child: Obx(() {
          if (driverController.isLoading.value) {
            return Center(child: AppLoader.appLoader());
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Image.asset(
                          AppImages.backImage,
                          height: 19,
                          width: 19,
                        ),
                      ),
                      Spacer(),

                      CustomTextFields.textWithStyles700(
                        'Confirm Booking',
                        fontSize: 20,
                      ),
                      Spacer(),
                    ],
                  ),
                  SizedBox(height: 20),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
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

                          hintStyle: TextStyle(fontSize: 11),
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

                          controller: _destController,

                          hintStyle: TextStyle(fontSize: 11),
                          imgHeight: 17,
                          containerColor: AppColors.commonWhite,
                          leadingImage: AppImages.rectangleDest,
                          title: 'Enter destination',
                          readOnly: true,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 30),
                  Container(
                    decoration: BoxDecoration(color: AppColors.containerColor),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        spacing: 7,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CustomTextFields.textWithStylesSmall('Your Ride'),
                            ],
                          ),

                          Row(
                            children: [
                              CustomTextFields.textWithStyles600(
                                '${widget.selectedCarType ?? ''}  ',
                                fontSize: 18,
                              ),
                              Icon(Icons.circle, size: 7),
                              CustomTextFields.textWithStyles600(
                                '  Share Ride',
                                fontSize: 18,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 30),
                  CustomTextFields.textWithStyles700(
                    'Price Details',
                    fontSize: 20,
                  ),
                  SizedBox(height: 15),
                  Obx(() {
                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.commonBlack.withOpacity(0.1),
                          width: 1.5,
                        ),
                      ),
                      child: ListTile(
                        subtitle: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5.0),
                          child: Column(
                            spacing: 5,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(AppTexts.baseFare)),
                                  CustomTextFields.textWithImage(
                                    text:
                                        driverController
                                            .sharedBooking
                                            .value
                                            ?.fareBreakdown[0]
                                            .baseFare
                                            .toString() ??
                                        '',
                                    imagePath: AppImages.nCurrency,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ],
                              ),
                              /*   Row(
                                children: [
                                  Expanded(child: Text(AppTexts.serviceFare)),
                                  CustomTextFields.textWithImage(
                                    text:
                                        driverController
                                            .carBooking
                                            .value
                                            ?.serviceFare
                                            .toString() ??
                                        "",

                                    imagePath: AppImages.nCurrency,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ],
                              ),*/
                              Row(
                                children: [
                                  Expanded(child: Text(AppTexts.distanceFare)),
                                  CustomTextFields.textWithImage(
                                    text:
                                        driverController
                                            .sharedBooking
                                            .value
                                            ?.fareBreakdown
                                            .first
                                            .distanceFare
                                            .toString() ??
                                        "",

                                    imagePath: AppImages.nCurrency,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Expanded(child: Text(AppTexts.pickupFare)),
                                  CustomTextFields.textWithImage(
                                    text:
                                        driverController
                                            .sharedBooking
                                            .value
                                            ?.fareBreakdown
                                            .first
                                            .pickupFare
                                            .toString() ??
                                        "",

                                    imagePath: AppImages.nCurrency,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Expanded(child: Text(AppTexts.bookingFee)),
                                  CustomTextFields.textWithImage(
                                    text:
                                        driverController
                                            .sharedBooking
                                            .value
                                            ?.fareBreakdown
                                            .first
                                            .bookingFee
                                            .toString() ??
                                        "",

                                    imagePath: AppImages.nCurrency,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Expanded(child: Text(AppTexts.timeFare)),
                                  CustomTextFields.textWithImage(
                                    text:
                                        driverController
                                            .sharedBooking
                                            .value
                                            ?.fareBreakdown
                                            .first
                                            .timeFare
                                            .toString() ??
                                        "",

                                    imagePath: AppImages.nCurrency,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ],
                              ),
                              SizedBox(height: 3),
                              SizedBox(
                                height: 2,
                                child: DottedLine(
                                  direction: Axis.horizontal,
                                  lineLength: double.infinity,
                                  lineThickness: 1.4,
                                  dashLength: 4.0,
                                  dashColor: Colors.grey.shade400,
                                ),
                              ),
                              SizedBox(height: 3),
                              Row(
                                children: [
                                  Expanded(child: Text(AppTexts.estTime)),
                                  CustomTextFields.textWithImage(
                                    text: formatDuration(
                                      driverController
                                              .sharedBooking
                                              .value
                                              ?.duration ??
                                          0,
                                    ),

                                    fontWeight: FontWeight.w900,
                                  ),
                                ],
                              ),

                              Row(
                                children: [
                                  Expanded(child: Text(AppTexts.totalKm)),
                                  CustomTextFields.textWithImage(
                                    text: formatDistance(
                                      (driverController
                                                  .sharedBooking
                                                  .value
                                                  ?.distance ??
                                              0)
                                          .toDouble(),
                                    ),

                                    fontWeight: FontWeight.w900,
                                  ),
                                ],
                              ),
                              SizedBox(height: 3),
                              SizedBox(
                                height: 2,
                                child: DottedLine(
                                  direction: Axis.horizontal,
                                  lineLength: double.infinity,
                                  lineThickness: 1.4,
                                  dashLength: 4.0,
                                  dashColor: Colors.grey.shade400,
                                ),
                              ),
                              SizedBox(height: 3),

                              Row(
                                children: [
                                  Expanded(
                                    child: CustomTextFields.textWithStyles600(
                                      AppTexts.total,
                                      fontSize: 14,
                                    ),
                                  ),

                                  CustomTextFields.textWithImage(
                                    text:
                                        driverController
                                            .sharedBooking
                                            .value
                                            ?.amount
                                            .toString() ??
                                        '',

                                    imagePath: AppImages.nBlackCurrency,
                                    fontWeight: FontWeight.w900,
                                    colors: AppColors.commonBlack,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  Obx(() {
                    final pricing =
                        driverController.sharedBooking.value?.pricingInsights;
                    if (pricing == null || !pricing.hasDynamicPricing) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: _buildDynamicPricingCard(pricing),
                    );
                  }),
                  SizedBox(height: 24),
                  CustomTextFields.textWithStyles700(
                    'Trip Summary',
                    fontSize: 17,
                  ),
                  SizedBox(height: 12),
                  Obx(() {
                    final booking = driverController.sharedBooking.value;
                    return _buildRideSummaryCard(
                      rideTypeLabel: widget.selectedCarType ?? 'Ride',
                      rideModeLabel: 'Shared ride',
                      etaText: formatDuration(booking?.duration ?? 0),
                      distanceText: formatDistance(
                        (booking?.distance ?? 0).toDouble(),
                      ),
                      amountText: (booking?.amount ?? 0).toString(),
                      pickupAddress: widget.pickupAddress,
                      dropAddress: widget.destinationAddress,
                    );
                  }),

                  SizedBox(height: 10),
                  CustomTextFields.textWithStylesSmall(
                    maxLines: 2,
                    'By confirming, you agree to our Terms of Service and Cancellation Policy',
                  ),
                ],
              ),
            ),
          );
        }),
      ),

      // bottomNavigationBar: Obx(() {
      //   return driverController.isLoading.value
      //       ? const SizedBox.shrink()
      //       : SafeArea(
      //         child: Padding(
      //           padding: const EdgeInsets.symmetric(
      //             horizontal: 20,
      //             vertical: 20,
      //           ),
      //           child: AppButtons.button(
      //             onTap: () async {
      //               final pickupLat =
      //                   (widget.pickupData['lat'] as num?)?.toDouble() ?? 0.0;
      //               final pickupLng =
      //                   (widget.pickupData['lng'] as num?)?.toDouble() ?? 0.0;
      //               final destLat =
      //                   (widget.destinationData['lat'] as num?)?.toDouble() ??
      //                   0.0;
      //               final destLng =
      //                   (widget.destinationData['lng'] as num?)?.toDouble() ??
      //                   0.0;
      //
      //               final pickupPos = LatLng(pickupLat, pickupLng);
      //               final destPos = LatLng(destLat, destLng);
      //
      //               final markers = <Marker>{
      //                 Marker(
      //                   markerId: const MarkerId('pickup'),
      //                   position: pickupPos,
      //                   infoWindow: const InfoWindow(title: 'Pickup'),
      //                 ),
      //                 Marker(
      //                   markerId: const MarkerId('drop'),
      //                   position: destPos,
      //                   infoWindow: const InfoWindow(title: 'Drop'),
      //                 ),
      //               };
      //
      //               Navigator.push(
      //                 context,
      //                 MaterialPageRoute(
      //                   builder:
      //                       (context) => SharedScreens(
      //                         pickupAddress: widget.pickupAddress,
      //                         destinationAddress: widget.destinationAddress,
      //                         initialPosition: pickupPos,
      //                         pickupPosition: pickupPos,
      //                         dropPosition: destPos,
      //                       ),
      //                 ),
      //               );
      //             },
      //             text: 'Confirm',
      //             rightImagePath: AppImages.nBlackCurrency,
      //             rightImagePathText:
      //                 driverController.sharedBooking.value?.amount ?? 0,
      //           ),
      //         ),
      //       );
      // }),
      bottomNavigationBar: Obx(() {
        return driverController.isLoading.value
            ? const SizedBox.shrink()
            : SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 20,
                ),
                child: AppButtons.button(
                  onTap: () async {
                    await _showPhotoConfirmationDialog(context);
                  },
                  text: 'Confirm',
                  rightImagePath: AppImages.nBlackCurrency,
                  rightImagePathText:
                      driverController.sharedBooking.value?.amount ?? 0,
                ),
              ),
            );
      }),
    );
  }

  Widget _buildRideSummaryCard({
    required String rideTypeLabel,
    required String rideModeLabel,
    required String etaText,
    required String distanceText,
    required String amountText,
    required String pickupAddress,
    required String dropAddress,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.containerColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.commonBlack.withOpacity(0.06)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(
                    color: AppColors.commonWhite,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.groups_rounded,
                    color: AppColors.commonBlack,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CustomTextFields.textWithStyles700(
                        rideTypeLabel,
                        fontSize: 16,
                      ),
                      const SizedBox(height: 4),
                      CustomTextFields.textWithStylesSmall(
                        rideModeLabel,
                        colors: AppColors.commonBlack.withOpacity(0.65),
                      ),
                    ],
                  ),
                ),
                CustomTextFields.textWithImage(
                  text: amountText,
                  imagePath: AppImages.nBlackCurrency,
                  fontWeight: FontWeight.w900,
                  colors: AppColors.commonBlack,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildSummaryChip(icon: Icons.schedule_rounded, label: etaText),
                _buildSummaryChip(
                  icon: Icons.route_rounded,
                  label: distanceText,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildSummaryAddressRow(
              iconPath: AppImages.circleStart,
              title: 'Pickup',
              value: pickupAddress,
            ),
            const SizedBox(height: 10),
            _buildSummaryAddressRow(
              iconPath: AppImages.rectangleDest,
              title: 'Drop',
              value: dropAddress,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDynamicPricingCard(PricingInsights pricing) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD68A)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 36,
                  width: 36,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.bolt_rounded,
                    color: Color(0xFFB86A00),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: CustomTextFields.textWithStyles700(
                    'Dynamic Pricing',
                    fontSize: 16,
                  ),
                ),
                CustomTextFields.textWithImage(
                  text: pricing.totalIncreaseAmount.toStringAsFixed(0),
                  imagePath: AppImages.nBlackCurrency,
                  fontWeight: FontWeight.w900,
                  colors: AppColors.commonBlack,
                ),
              ],
            ),
            if (pricing.summary.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              CustomTextFields.textWithStylesSmall(
                pricing.summary,
                maxLines: 4,
                overflow: TextOverflow.visible,
                colors: AppColors.commonBlack.withOpacity(0.72),
              ),
            ],
            if (pricing.activeReasons.isNotEmpty) ...[
              const SizedBox(height: 14),
              ...pricing.activeReasons.map(_buildDynamicPricingRow),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDynamicPricingRow(PricingReason reason) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomTextFields.textWithStyles600(
                  reason.label.isEmpty
                      ? _fallbackReasonLabel(reason.code)
                      : reason.label,
                  fontSize: 13,
                ),
                if (reason.percentage > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: CustomTextFields.textWithStylesSmall(
                      '${reason.percentage.toStringAsFixed(0)}% applied',
                      colors: AppColors.commonBlack.withOpacity(0.6),
                    ),
                  ),
              ],
            ),
          ),
          CustomTextFields.textWithImage(
            text: reason.amount.toStringAsFixed(0),
            imagePath: AppImages.nCurrency,
            fontWeight: FontWeight.w900,
          ),
        ],
      ),
    );
  }

  String _fallbackReasonLabel(String code) {
    switch (code) {
      case 'rain':
        return 'Rain surcharge';
      case 'thunderstorm':
        return 'Thunderstorm surcharge';
      case 'weather':
        return 'Weather surcharge';
      case 'night_surge':
        return 'Night surge';
      case 'demand_area_surge':
        return 'Demand area surge';
      default:
        return 'Surcharge';
    }
  }

  Widget _buildSummaryChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.commonWhite,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.commonBlack),
          const SizedBox(width: 8),
          CustomTextFields.textWithStyles600(label, fontSize: 13),
        ],
      ),
    );
  }

  Widget _buildSummaryAddressRow({
    required String iconPath,
    required String title,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Image.asset(iconPath, height: 16, width: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CustomTextFields.textWithStyles600(title, fontSize: 13),
              const SizedBox(height: 2),
              CustomTextFields.textWithStylesSmall(
                value,
                maxLines: 2,
                colors: AppColors.commonBlack.withOpacity(0.65),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showPhotoConfirmationDialog(BuildContext context) async {
    File? capturedImage;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: AppColors.commonWhite,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              title: const Text(
                "Photo Verification Required",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (capturedImage == null)
                    const Icon(
                      Icons.camera_alt_rounded,
                      size: 60,
                      color: Colors.black,
                    )
                  else
                    CircleAvatar(
                      radius: 50,
                      backgroundImage: FileImage(capturedImage!),
                    ),
                  const SizedBox(height: 15),
                  Text(
                    capturedImage == null
                        ? "To confirm your booking, we need to take a quick selfie for verification."
                        : "Preview your selfie. If it looks good, upload it to continue, or retake it.",
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15),
                  ),
                  if (capturedImage != null)
                    TextButton.icon(
                      onPressed: () async {
                        // Retake selfie
                        final image = await _captureSelfie();
                        if (image != null) {
                          setState(() => capturedImage = image);
                        }
                      },
                      icon: const Icon(Icons.refresh, color: Colors.black),
                      label: const Text(
                        "Retake",
                        style: TextStyle(color: Colors.black),
                      ),
                    ),
                ],
              ),
              actions: [
                if (capturedImage == null)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      "Cancel",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () async {
                    if (capturedImage == null) {
                      final image = await _captureSelfie();
                      if (image != null) setState(() => capturedImage = image);
                    } else {
                      setState(() => _isLoading = true); // start loader
                      try {
                        final success = await _uploadPhotoAndBook(
                          capturedImage!,
                        );
                        if (success) {
                          Navigator.pop(context);
                          final allData = driverController.sharedBooking.value;
                          final pickupLat =
                              (widget.pickupData['lat'] as num?)?.toDouble() ??
                              0.0;
                          final pickupLng =
                              (widget.pickupData['lng'] as num?)?.toDouble() ??
                              0.0;
                          final destLat =
                              (widget.destinationData['lat'] as num?)
                                  ?.toDouble() ??
                              0.0;
                          final destLng =
                              (widget.destinationData['lng'] as num?)
                                  ?.toDouble() ??
                              0.0;
                          final pickupPos = LatLng(pickupLat, pickupLng);
                          final destPos = LatLng(destLat, destLng);
                          final markers = <Marker>{
                            Marker(
                              markerId: const MarkerId('pickup'),
                              position: pickupPos,
                              infoWindow: const InfoWindow(title: 'Pickup'),
                            ),
                            Marker(
                              markerId: const MarkerId('drop'),
                              position: destPos,
                              infoWindow: const InfoWindow(title: 'Drop'),
                            ),
                          };
                          AppLogger.log.w(allData);
                          AppLogger.log.w(
                            'Booking Fee: ${allData?.fareBreakdown[0].bookingFee}',
                          );
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) => SharedScreens(
                                    baseFare:
                                        allData?.fareBreakdown[0].baseFare,
                                    bookingFee:
                                        allData?.fareBreakdown[0].bookingFee,

                                    pickupFare:
                                        allData?.fareBreakdown[0].pickupFare,
                                    timeFare:
                                        allData?.fareBreakdown[0].timeFare,
                                    distanceFare:
                                        allData?.fareBreakdown[0].distanceFare,

                                    pickupAddress: widget.pickupAddress,
                                    destinationAddress:
                                        widget.destinationAddress,
                                    initialPosition: pickupPos,
                                    pickupPosition: pickupPos,
                                    dropPosition: destPos,
                                    carType: widget.carType ?? '',
                                    selectedSeats: widget.selectedSeats,
                                  ),
                            ),
                          );
                        }
                      } finally {
                        setState(() => _isLoading = false);
                      }
                    }
                  },
                  child:
                      _isLoading
                          ? const Center(
                            child: SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          )
                          : Text(
                            capturedImage == null
                                ? "Take Photo"
                                : "Upload and Confirm Booking",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  bool _isLoading = false;
  Future<bool> _uploadPhotoAndBook(File image) async {
    try {
      printImageSize(image, label: "Before Upload (input)");
      final File uploadFile =
          (await compressImage(image, quality: 70)) ?? image;
      printImageSize(uploadFile, label: "Uploading File");
      final bookingId = driverController.sharedBooking.value?.bookingId;
      await packageController.submitProfileData(
        bookingId: bookingId ?? '',
        frontImageFile: uploadFile,
      );

      final allData = driverController.sharedBooking.value;
      String? result = await driverController.sendSharedDriverRequest(
        carType: widget.carType ?? '',
        pickupLatitude: widget.pickupData['lat'] ?? 0.0,
        pickupLongitude: widget.pickupData['lng'] ?? 0.0,
        dropLatitude: widget.destinationData['lat'] ?? 0.0,

        dropLongitude: widget.destinationData['lng'] ?? 0.0,
        bookingId: allData?.bookingId.toString() ?? '',
        context: context,
      );
      // BUGFIX: previously returned true unconditionally, so a FAILED driver
      // request still navigated the user to live tracking (infinite "searching"
      // with no driver dispatched). sendSharedDriverRequest returns 'success'
      // only on success (null / 'An error occurred' otherwise).
      return result == 'success';
    } catch (e) {
      debugPrint("Error uploading photo or sending booking: $e");
      return false;
    }
  }

  Future<File?> _captureSelfie() async {
    final ImagePicker picker = ImagePicker();
    final XFile? photo = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 100,
    );

    if (photo == null) return null;

    final original = File(photo.path);
    printImageSize(original, label: "Original Image");
    // Compress it
    final compressed = await compressImage(
      original,
      quality: 60,
      minWidth: 720,
      minHeight: 720,
    );
    if (compressed == null) {
      debugPrint("❌ Compression FAILED (returning original)");
      return original;
    }

    printImageSize(compressed, label: "Compressed Image");
    return compressed;
  }

  // Future<File?> _captureSelfie() async {
  //   final ImagePicker picker = ImagePicker();
  //   final XFile? photo = await picker.pickImage(
  //     source: ImageSource.camera,
  //     preferredCameraDevice: CameraDevice.front,
  //   );
  //   if (photo == null) return null;
  //   return File(photo.path);
  // }
}

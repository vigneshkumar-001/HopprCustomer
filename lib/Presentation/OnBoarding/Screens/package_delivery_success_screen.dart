// Customer-side package delivery success screen.
//
// Shown once when a parcel's status becomes DELIVERED — previously there was
// no dedicated completion moment on the customer side (the tracking screen
// just kept showing an inline POD card). Built on the shared SuccessView so
// this exact treatment is reusable for a completed Solo/Shared ride later.
//
// Rating: parcel-specific addition (mirrors the existing car-ride
// post-payment rating sheet in payment_screen.dart, reusing the same
// DriverSearchController.rateDriver() API — the backend's startRatting()
// isn't bookingType-aware, so the ride rating endpoint already works for a
// parcel bookingId as-is). Shown automatically once, right after this screen
// appears; Skip/Submit both just dismiss the sheet — unlike the ride flow,
// this screen already has its own persistent "Return home" button, so the
// rating sheet doesn't need to own navigation.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Utility/app_buttons.dart';
import 'package:hopper/Core/Utility/app_toasts.dart';
import 'package:hopper/Presentation/BookRide/Controllers/driver_search_controller.dart';
import 'package:hopper/Presentation/Shared/RideUI/ride_ui.dart';

class PackageDeliverySuccessScreen extends StatefulWidget {
  final String bookingId;
  final String? receiverName;
  final String? dropAddress;
  final String? podPhotoUrl;
  final DateTime? deliveredAt;
  final String? courierName;
  final String? courierProfilePic;

  const PackageDeliverySuccessScreen({
    super.key,
    required this.bookingId,
    this.receiverName,
    this.dropAddress,
    this.podPhotoUrl,
    this.deliveredAt,
    this.courierName,
    this.courierProfilePic,
  });

  @override
  State<PackageDeliverySuccessScreen> createState() =>
      _PackageDeliverySuccessScreenState();
}

class _PackageDeliverySuccessScreenState
    extends State<PackageDeliverySuccessScreen> {
  final DriverSearchController driverSearchController =
      Get.isRegistered<DriverSearchController>()
          ? Get.find<DriverSearchController>()
          : Get.put(DriverSearchController());

  bool _isRatingSheetOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showRatingBottomSheet();
    });
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final m = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.day}/${local.month}/${local.year}, $h:$m $ampm';
  }

  Future<void> _showRatingBottomSheet() async {
    if (_isRatingSheetOpen) return;
    _isRatingSheetOpen = true;
    int selectedRating = 0;
    bool isSubmitting = false;
    final courierLabel =
        (widget.courierName?.trim().isNotEmpty == true)
            ? widget.courierName!.trim()
            : 'your courier';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 48,
                        height: 5,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD0D5DD),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 22),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: CachedNetworkImage(
                          imageUrl: widget.courierProfilePic ?? '',
                          height: 72,
                          width: 72,
                          fit: BoxFit.cover,
                          placeholder:
                              (context, url) => Container(
                                height: 72,
                                width: 72,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF2F4F7),
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              ),
                          errorWidget:
                              (context, url, error) => Container(
                                height: 72,
                                width: 72,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF2F4F7),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.person,
                                  color: Color(0xFF98A2B3),
                                  size: 30,
                                ),
                              ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Package Delivered',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF101828),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Rate your experience with $courierLabel',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: Color(0xFF667085),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(5, (index) {
                          final active = index < selectedRating;
                          return GestureDetector(
                            onTap:
                                () => setModalState(
                                  () => selectedRating = index + 1,
                                ),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              height: 54,
                              width: 54,
                              decoration: BoxDecoration(
                                color:
                                    active
                                        ? const Color(0xFFFFF4E5)
                                        : const Color(0xFFF5F6F8),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color:
                                      active
                                          ? const Color(0xFFF59E0B)
                                          : const Color(0xFFE4E7EC),
                                ),
                              ),
                              child: Icon(
                                active
                                    ? Icons.star_rounded
                                    : Icons.star_border_rounded,
                                color:
                                    active
                                        ? const Color(0xFFF59E0B)
                                        : const Color(0xFF98A2B3),
                                size: 30,
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: AppButtons.button(
                              borderColor: const Color(0xFFD0D5DD),
                              hasBorder: true,
                              buttonColor: Colors.white,
                              textColor: AppColors.commonBlack,
                              onTap: () => Navigator.pop(sheetContext),
                              text: 'Skip',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppButtons.button(
                              buttonColor: AppColors.commonBlack,
                              isLoading: isSubmitting,
                              onTap:
                                  isSubmitting
                                      ? null
                                      : () async {
                                        if (selectedRating <= 0) {
                                          AppToasts.showError(
                                            sheetContext,
                                            'Please select a rating',
                                          );
                                          return;
                                        }
                                        setModalState(
                                          () => isSubmitting = true,
                                        );
                                        final result = await driverSearchController
                                            .rateDriver(
                                              bookingId: widget.bookingId,
                                              rating: selectedRating
                                                  .toString(),
                                              context: sheetContext,
                                            );
                                        if (!mounted) return;
                                        setModalState(
                                          () => isSubmitting = false,
                                        );
                                        if (result == '' &&
                                            Navigator.of(
                                              sheetContext,
                                            ).canPop()) {
                                          Navigator.pop(sheetContext);
                                        }
                                      },
                              text: 'Submit Rating',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (mounted) _isRatingSheetOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Get.until((route) => route.isFirst);
      },
      child: SuccessView(
        title: 'Package delivered',
        subtitle:
            widget.receiverName != null &&
                    widget.receiverName!.trim().isNotEmpty
                ? 'Handed to ${widget.receiverName!.trim()}'
                : 'Your package was delivered successfully.',
        previewImage:
            widget.podPhotoUrl != null && widget.podPhotoUrl!.trim().isNotEmpty
                ? Image.network(
                  widget.podPhotoUrl!,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder:
                      (_, __, ___) => Container(
                        height: 200,
                        color: RideUI.surfaceSecondary,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.broken_image_rounded,
                          color: RideUI.textMuted,
                        ),
                      ),
                )
                : null,
        details: [
          RideInfoRow(
            icon: Icons.local_shipping_rounded,
            label: 'Package ID',
            value: 'PKG-${widget.bookingId}',
          ),
          if (widget.deliveredAt != null)
            RideInfoRow(
              icon: Icons.check_circle_rounded,
              iconColor: RideUI.brandGreen,
              label: 'Delivered',
              value: _formatTime(widget.deliveredAt!),
            ),
          if (widget.dropAddress != null &&
              widget.dropAddress!.trim().isNotEmpty)
            RideInfoRow(
              icon: Icons.location_on_rounded,
              label: 'Delivered to',
              value: widget.dropAddress!.trim(),
            ),
        ],
        buttonLabel: 'Return home',
        onButtonPressed: () => Get.until((route) => route.isFirst),
      ),
    );
  }
}

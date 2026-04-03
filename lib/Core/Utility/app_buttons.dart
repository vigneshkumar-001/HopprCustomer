import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Core/Utility/app_toasts.dart';
import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
import 'package:get/get.dart';
import 'package:hopper/Presentation/BookRide/Controllers/driver_search_controller.dart';

class AppButtons {
  static final AppButtons _singleton = AppButtons._internal();

  AppButtons._internal();

  static AppButtons get instance => _singleton;
  static Widget button1({
    required GestureTapCallback? onTap,
    required Widget text,
    double? size = double.infinity,
    double? imgHeight = 24,
    double? imgWeight = 24,
    double? borderRadius = 4,

    Color? buttonColor,
    Color? foreGroundColor,
    Color? borderColor,
    Color? textColor = Colors.white,
    bool? isLoading,
    bool hasBorder = false,
    String? imagePath,
  }) {
    return SizedBox(
      width: size,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          foregroundColor: foreGroundColor,

          shape:
              hasBorder
                  ? RoundedRectangleBorder(
                    side: BorderSide(color: Color(0xff3F5FF2)),
                    borderRadius: BorderRadius.circular(borderRadius!),
                  )
                  : RoundedRectangleBorder(
                    side: BorderSide(color: borderColor ?? Colors.transparent),

                    borderRadius: BorderRadius.circular(borderRadius!),
                  ),
          elevation: 0,
          fixedSize: Size(150.w, 40.h),
          backgroundColor: buttonColor,
        ),
        child:
            isLoading == true
                ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CupertinoActivityIndicator(radius: 10),
                )
                : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (imagePath != null) ...[
                      Image.asset(
                        imagePath,
                        height: imgHeight!.sp,
                        width: imgWeight!.sp,
                      ),
                      SizedBox(width: 10.w),
                    ],
                    DefaultTextStyle(
                      style: TextStyle(
                        fontFamily: "Roboto-normal",
                        fontSize: 16.sp,
                        color: textColor,
                        fontWeight: FontWeight.bold,
                      ),
                      child: text,
                    ),
                  ],
                ),
      ),
    );
  }

  static button({
    required GestureTapCallback? onTap,
    required String text,
    double? size = double.infinity,
    double? fontSize = 16,
    Color? buttonColor = AppColors.commonBlack,
    Color? textColor = Colors.white,
    Color borderColor = const Color(0xff3F5FF2),

    bool? isLoading,
    bool hasBorder = false,

    String? imagePath,
    String? rightImagePath,
    num? rightImagePathText,
  }) {
    return SizedBox(
      width: size,

      child: ElevatedButton(
        onPressed: isLoading == true ? null : onTap,
        style: ElevatedButton.styleFrom(
          shape:
              hasBorder
                  ? RoundedRectangleBorder(
                    side: BorderSide(color: borderColor),
                    borderRadius: BorderRadius.circular(8),
                  )
                  : RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
          elevation: 0,
          fixedSize: Size(150.w, 40.h),
          backgroundColor: buttonColor,
        ),
        child:
            isLoading == true
                ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CupertinoActivityIndicator(radius: 10),
                )
                : Row(
                  mainAxisAlignment: MainAxisAlignment.center,

                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (imagePath != null) ...[
                      Image.asset(imagePath, height: 24.sp, width: 24.sp),
                      SizedBox(width: 10.w),
                    ],
                    Text(
                      text,
                      style: TextStyle(
                        fontFamily: "Roboto-normal",
                        fontSize: fontSize,
                        color: textColor,
                      ),
                    ),
                    if (rightImagePath != null) ...[
                      SizedBox(width: 10.w),
                      Image.asset(
                        rightImagePath,
                        height: 24.sp,
                        width: 24.sp,
                        color: AppColors.commonWhite,
                      ),
                      Text(
                        rightImagePathText?.toString() ?? '',
                        style: TextStyle(
                          fontFamily: "Roboto-normal",
                          fontSize: 20,
                          color: textColor,
                        ),
                      ),
                    ],
                  ],
                ),
      ),
    );
  }

  static backButton({required BuildContext context}) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Image.asset(AppImages.backImage, height: 25),
    );
  }

  static void showCancelRideBottomSheet(
    BuildContext context, {
    required Future<String?> Function(String selectedReason) onConfirmCancel,
  }) {
    String? selectedReason;
    bool showSuccess = false;
    final sheetContext = Navigator.of(context, rootNavigator: true).context;
    showModalBottomSheet(
      context: sheetContext,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (_) {
        final DriverSearchController driverSearchController =
            Get.isRegistered<DriverSearchController>()
                ? Get.find<DriverSearchController>()
                : Get.put(DriverSearchController());
        return StatefulBuilder(
          builder: (context, setState) {
            return DraggableScrollableSheet(
              maxChildSize: 0.60,
              minChildSize: 0.5,
              initialChildSize: 0.60,
              expand: false,
              builder: (context, scrollController) {
                return ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(25),
                  ),
                  child: Container(
                    decoration: const BoxDecoration(color: Colors.white),
                    padding: const EdgeInsets.all(20),
                    child: Obx(() {
                      final isLoading =
                          driverSearchController.isCancelLoading.value;
                      final selected = (selectedReason ?? '').trim();

                      if (showSuccess) {
                        return Column(
                          children: [
                            Expanded(
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 64,
                                      height: 64,
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.check_circle_rounded,
                                        color: Colors.green,
                                        size: 34,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    const Text(
                                      'Ride cancelled',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.commonBlack,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    if (selected.isNotEmpty)
                                      Text(
                                        'Reason: $selected',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.commonBlack
                                              .withOpacity(0.65),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(
                              width: double.infinity,
                              child: AppButtons.button(
                                onTap: () => Get.back(),
                                text: 'Done',
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                        );
                      }

                      return Column(
                        children: [
                          Expanded(
                            child: ListView(
                              controller: scrollController,
                              children: [
                                const SizedBox(height: 10),
                                Center(
                                  child: Container(
                                    width: 42,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade300,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 22),
                                CustomTextFields.textWithStyles600(
                                  'Still want to cancel the ride? Please tell us why',
                                ),
                                const SizedBox(height: 12),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 180),
                                  child:
                                      selected.isEmpty
                                          ? const SizedBox.shrink()
                                          : Container(
                                            key: ValueKey(selected),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF3F6FF),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: Colors.black.withOpacity(
                                                  0.06,
                                                ),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.check_circle_rounded,
                                                  size: 18,
                                                  color: Colors.green,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    'Selected: $selected',
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color:
                                                          AppColors.commonBlack,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                ),
                                const SizedBox(height: 16),
                                ...[
                                  'Driver denied pickup',
                                  'Driver demanded extra cash',
                                  'Selected wrong pickup',
                                  'My reason is not listed',
                                ].map((reason) {
                                  final isSelected = selectedReason == reason;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: InkWell(
                                      onTap:
                                          isLoading
                                              ? null
                                              : () {
                                                setState(() {
                                                  selectedReason = reason;
                                                });
                                              },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 15,
                                        ),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          color:
                                              isSelected
                                                  ? AppColors.commonBlack
                                                  : AppColors.containerColor1,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 15,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  reason,
                                                  style: TextStyle(
                                                    color:
                                                        isSelected
                                                            ? AppColors
                                                                .commonWhite
                                                            : AppColors
                                                                .commonBlack
                                                                .withOpacity(
                                                                  0.6,
                                                                ),
                                                    fontWeight:
                                                        isSelected
                                                            ? FontWeight.w700
                                                            : FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                              if (isSelected)
                                                const Icon(
                                                  Icons.check_rounded,
                                                  color: AppColors.commonWhite,
                                                  size: 18,
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                                if (isLoading) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Cancelling...',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.commonBlack.withOpacity(
                                        0.55,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: AppButtons.button(
                                  buttonColor: AppColors.containerColor1,
                                  textColor: AppColors.commonBlack,
                                  onTap: isLoading ? null : () => Get.back(),
                                  text: "Don't Cancel",
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: AppButtons.button(
                                  buttonColor: AppColors.cancelRideColor,
                                  isLoading: isLoading,
                                  onTap:
                                      isLoading
                                          ? null
                                          : () async {
                                            if ((selectedReason ?? '')
                                                .isEmpty) {
                                              AppToasts.showInfoGlobal(
                                                'Please Select a reason before proceeding',
                                                title: 'Info',
                                              );
                                              return;
                                            }

                                            final nav = Navigator.of(context);
                                            final res = await onConfirmCancel(
                                              selectedReason!,
                                            );
                                            if (res == null) {
                                              AppToasts.showErrorGlobal(
                                                'Cancellation failed. Please try again.',
                                              );
                                              return;
                                            }
                                            final ok = res.trim().isEmpty;
                                            if (!ok) {
                                              AppToasts.showErrorGlobal(
                                                res,
                                                title: '',
                                              );
                                              return;
                                            }

                                            setState(() {
                                              showSuccess = true;
                                            });

                                            Future.delayed(
                                              const Duration(milliseconds: 900),
                                              () {
                                                if (nav.mounted &&
                                                    nav.canPop()) {
                                                  nav.pop();
                                                }
                                              },
                                            );
                                          },
                                  text: 'Cancel Ride',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 15),
                        ],
                      );
                    }),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  static void showPackageCancelBottomSheet(
    BuildContext context, {
    String? courierName,
    String? orderId,
    double? distanceMeters,
    int? durationSeconds,
    String? statusMessage,
    String? policyTitle,
    String? policyMessage,
    double? totalPaid,
    double? cancellationFee,
    List<String>? reasons,
    required Future<String?> Function(String selectedReason) onConfirmCancel,
  }) {
    String? selectedReason;
    final DriverSearchController driverSearchController =
        Get.isRegistered<DriverSearchController>()
            ? Get.find<DriverSearchController>()
            : Get.put(DriverSearchController());
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setState) {
            final courier = (courierName ?? '').toString().trim();
            final safeCourier = courier.isEmpty ? 'Courier' : courier;
            final safeOrderId = (orderId ?? '').toString().trim();
            final dm = distanceMeters;
            final km = (dm != null && dm.isFinite) ? (dm / 1000.0) : null;
            final distText =
                (km != null)
                    ? '${km.toStringAsFixed(km >= 10 ? 0 : 1)} km away'
                    : '';
            final ds = durationSeconds;
            final mins = (ds != null && ds >= 0) ? (ds / 60.0) : null;
            final etaText = (mins != null) ? 'Time: ${mins.round()} min' : '';

            final metaBits =
                <String>[
                  distText,
                  etaText,
                  if (safeOrderId.isNotEmpty) 'Order: PKG-$safeOrderId',
                ].where((e) => e.trim().isNotEmpty).toList();
            final metaLine = metaBits.join(' - ');

            final r = reasons;
            final sheetReasons =
                (r == null || r.isEmpty)
                    ? <String>[
                      'Changed my mind',
                      'Wrong pickup address',
                      'Package not ready',
                      'Found alternative delivery',
                      'Other Reason',
                    ]
                    : r;

            String money(num v) {
              final d = v.toDouble();
              final isInt = (d - d.roundToDouble()).abs() < 0.000001;
              return isInt ? d.toStringAsFixed(0) : d.toStringAsFixed(2);
            }

            final tp = totalPaid;
            final paid = (tp != null && tp.isFinite && tp >= 0) ? tp : null;
            final cf = cancellationFee;
            final fee = (cf != null && cf.isFinite && cf >= 0) ? cf : null;
            final refund =
                (paid != null && fee != null)
                    ? (paid - fee).clamp(0.0, double.infinity)
                    : null;
            return DraggableScrollableSheet(
              maxChildSize: 0.90,
              minChildSize: 0.85,
              initialChildSize: 0.90,
              builder: (context, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    // borderRadius: BorderRadius.vertical(
                    //   top: Radius.circular(25),
                    // ),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFEFF4FF,
                                ), // light blue background
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Icon Circle
                                  Image.asset(
                                    AppImages.box,
                                    width: 27,
                                    height: 27,
                                  ),
                                  const SizedBox(width: 12),

                                  // Text Content
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Courier Status',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: Colors.black,
                                          ),
                                        ),
                                        SizedBox(height: 3),
                                        Text(
                                          (statusMessage ??
                                                  '$safeCourier is on the way')
                                              .toString(),
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.black87,
                                          ),
                                        ),

                                        CustomTextFields.textWithStylesSmall(
                                          maxLines: 2,
                                          fontSize: 11,
                                          metaLine.isNotEmpty
                                              ? metaLine
                                              : (safeOrderId.isNotEmpty
                                                  ? 'Order: PKG-$safeOrderId'
                                                  : ''),
                                          colors: AppColors.blueLight,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 10),
                            CustomTextFields.textWithStyles600(
                              'Why do you want to cancel?',
                            ),
                            const SizedBox(height: 5),
                            ...sheetReasons.map((reason) {
                              final isSelected = selectedReason == reason;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),

                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      selectedReason = reason;
                                    });
                                  },
                                  child: Container(
                                    padding: EdgeInsets.symmetric(vertical: 15),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      color:
                                          isSelected
                                              ? AppColors.commonBlack
                                              : AppColors.containerColor1,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 15,
                                      ),
                                      child: Row(
                                        children: [
                                          Text(
                                            reason,
                                            style: TextStyle(
                                              color:
                                                  isSelected
                                                      ? AppColors.commonWhite
                                                      : AppColors.commonBlack
                                                          .withOpacity(0.6),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                            CustomTextFields.textAndField(
                              maxLines: 2,
                              fontSize: 12,
                              tittle: 'Please specify your reason',
                              hintText:
                                  'Tell us more about why you want to cancel',
                            ),
                            SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(15),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFFFEDE7,
                                ), // light blue background
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Icon Circle
                                  Image.asset(
                                    AppImages.warning,
                                    width: 27,
                                    height: 27,
                                  ),
                                  const SizedBox(width: 12),

                                  // Text Content
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        CustomTextFields.textWithStyles600(
                                          fontSize: 14,
                                          (policyTitle ?? 'Cancellation Policy')
                                              .toString(),
                                          color: AppColors.cancelRideColor,
                                        ),
                                        SizedBox(height: 3),
                                        CustomTextFields.textWithStylesSmall(
                                          colors: AppColors.commonBlack
                                              .withOpacity(0.6),
                                          maxLines: 2,
                                          fontSize: 10,
                                          (policyMessage ??
                                                  (fee == null
                                                      ? 'Cancellation fee may apply.'
                                                      : (fee > 0
                                                          ? 'A cancellation fee of ₹${money(fee)} may apply.'
                                                          : 'No cancellation fee applies.')))
                                              .toString(),
                                        ),
                                        SizedBox(height: 5),
                                        if (paid != null)
                                          CustomTextFields.textWithStylesSmall(
                                            fontWeight: FontWeight.w500,
                                            colors: AppColors.commonBlack,
                                            fontSize: 10,
                                            'Total paid: ₹${money(paid)}',
                                          ),
                                        if (fee != null)
                                          CustomTextFields.textWithStylesSmall(
                                            fontWeight: FontWeight.w500,
                                            colors: AppColors.commonBlack,
                                            fontSize: 10,
                                            fee > 0
                                                ? 'Cancellation fee: ₹${money(fee)}'
                                                : 'Cancellation fee: ₹0',
                                          ),
                                        if (refund != null)
                                          CustomTextFields.textWithStylesSmall(
                                            colors: AppColors.commonBlack,
                                            fontWeight: FontWeight.w500,
                                            fontSize: 10,
                                            'Refund amount: ₹${money(refund)}',
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: 10),
                          ],
                        ),
                      ),

                      Row(
                        children: [
                          AppButtons.button(
                            size: 135,
                            buttonColor: AppColors.containerColor1,
                            textColor: AppColors.commonBlack,
                            onTap: () {
                              Get.back();
                            },
                            text: "Close",
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Obx(() {
                              final isLoading =
                                  driverSearchController.isCancelLoading.value;
                              return AppButtons.button(
                                buttonColor: AppColors.cancelRideColor,
                                size: 210,
                                isLoading: isLoading,
                                onTap:
                                    isLoading
                                        ? null
                                        : () async {
                                          if (selectedReason != null) {
                                            final res = await onConfirmCancel(
                                              selectedReason!,
                                            );
                                            final ok =
                                                (res ?? '').trim().isEmpty;
                                            if (ok) Get.back();
                                          } else {
                                            AppToasts.showInfoGlobal(
                                              'Please Select a reason before proceeding',
                                              title: 'Info',
                                            );
                                          }
                                        },
                                text: "Confirm Cancellation",
                              );
                            }),
                          ),
                        ],
                      ),
                      SizedBox(height: 10),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

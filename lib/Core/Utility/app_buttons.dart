import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Utility/app_images.dart';
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
        child: isLoading == true
            ? SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              textColor ?? Colors.white,
            ),
          ),
        )
            :Row(
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
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      textColor ?? Colors.white,
                    ),
                  ),
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
                        rightImagePathText.toString() ?? '',
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
    required Function(String selectedReason) onConfirmCancel,
  }) {
    String? selectedReason;
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
            return DraggableScrollableSheet(
              maxChildSize: 0.60,
              minChildSize: 0.5,
              initialChildSize: 0.60,
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
                            // const SizedBox(height: 10),
                            // Row(
                            //   children: [
                            //     Expanded(
                            //       flex: 3,
                            //       child: RichText(
                            //         text: TextSpan(
                            //           style: const TextStyle(
                            //             color: Colors.black,
                            //             fontSize: 15,
                            //             fontWeight: FontWeight.w500,
                            //           ),
                            //           children: const [
                            //             TextSpan(
                            //               text: 'Oluwaseun Michael',
                            //               style: TextStyle(
                            //                 fontWeight: FontWeight.w600,
                            //               ),
                            //             ),
                            //             TextSpan(
                            //               text:
                            //                   ' will reach in less than 5 mins',
                            //             ),
                            //           ],
                            //         ),
                            //       ),
                            //     ),
                            //     SizedBox(width: 30),
                            //     Expanded(
                            //       flex: 1,
                            //       child: Image.asset(AppImages.confirmCar),
                            //     ),
                            //   ],
                            // ),
                            const SizedBox(height: 30),
                            CustomTextFields.textWithStyles600(
                              'Still want to cancel the ride? Please tell us why',
                            ),
                            SizedBox(height: 20),
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
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: AppButtons.button(
                              buttonColor: AppColors.containerColor1,
                              textColor: AppColors.commonBlack,
                              onTap: () {
                                Get.back();
                              },
                              text: "Don't Cancel",
                            ),
                          ),
                          SizedBox(width: 20),
                          Expanded(
                            child: GetX<DriverSearchController>(
                              init: Get.isRegistered<DriverSearchController>()
                                  ? Get.find<DriverSearchController>()
                                  : Get.put(DriverSearchController()),
                              builder: (driverSearchController) {
                                final isLoading =
                                    driverSearchController.isLoading.value;
                                return AppButtons.button(
                                  isLoading: isLoading,
                                  onTap: isLoading
                                      ? null
                                      : () {
                                          if (selectedReason != null) {
                                            onConfirmCancel(selectedReason!);
                                          } else {
                                            Get.snackbar(
                                              'Info',
                                              'Please Select a reason before proceeding',
                                            );
                                          }
                                        },
                                  text: "Cancel Ride",
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 15),
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

  static void showPackageCancelBottomSheet(
    BuildContext context, {
    required Function(String selectedReason) onConfirmCancel,
  }) {
    String? selectedReason;
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
                                          'Rajesh Kumar is on the way to your location',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.black87,
                                          ),
                                        ),

                                        CustomTextFields.textWithStylesSmall(
                                          maxLines: 2,
                                          fontSize: 11,
                                          '2.1 km away • ETA: 8 minutes • Order: PKG-2025-7841',
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
                            ...[
                              'Changed my mind',
                              'Wrong pickup address',
                              'Package not ready',
                              'Found alternative delivery',
                              'Other Reason',
                            ].map((reason) {
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
                                          'Cancellation Policy',
                                          color: AppColors.cancelRideColor,
                                        ),
                                        SizedBox(height: 3),
                                        CustomTextFields.textWithStylesSmall(
                                          colors: AppColors.commonBlack
                                              .withOpacity(0.6),
                                          maxLines: 2,
                                          fontSize: 10,
                                          'Since the courier is already en route, a cancellation fee of ₹25 applies.',
                                        ),
                                        SizedBox(height: 5),
                                        CustomTextFields.textWithStylesSmall(
                                          fontWeight: FontWeight.w500,
                                          colors: AppColors.commonBlack,
                                          fontSize: 10,
                                          '• Total paid: ₹73',
                                        ),
                                        CustomTextFields.textWithStylesSmall(
                                          fontWeight: FontWeight.w500,
                                          colors: AppColors.commonBlack,
                                          fontSize: 10,
                                          '• Cancellation fee: ₹25',
                                        ),
                                        CustomTextFields.textWithStylesSmall(
                                          colors: AppColors.commonBlack,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 10,
                                          '• Refund amount: ₹48',
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
                            text: "Cancel",
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: AppButtons.button(
                              buttonColor: AppColors.cancelRideColor,
                              size: 210,
                              onTap: () {
                                if (selectedReason != null) {
                                  onConfirmCancel(selectedReason!);
                                  Get.back();
                                } else {
                                  Get.snackbar(
                                    'Info',
                                    'Please Select a reason before proceeding',
                                  );
                                }
                              },
                              text: "Confirm Cancellation",
                            ),
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


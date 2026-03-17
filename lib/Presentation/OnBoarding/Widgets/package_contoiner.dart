import 'package:flutter/material.dart';
import 'package:dotted_line/dotted_line.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Consents/app_texts.dart';
import 'package:hopper/Core/Utility/app_buttons.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';

class PackageContainer {
  static Widget customContainers({
    required bool isSendSelected,
    required ValueChanged<bool> onSelectionChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.containerColor1,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.0),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => onSelectionChanged(true),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSendSelected ? AppColors.commonWhite : null,
                    borderRadius: BorderRadius.circular(10),
                    border:
                        isSendSelected
                            ? Border.all(
                              color: AppColors.containerColor,
                              width: 2,
                            )
                            : null,
                  ),
                  child: ListTile(
                    title: Text(
                      'Send Parcel',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    trailing:
                        isSendSelected
                            ? Image.asset(AppImages.tick, height: 15, width: 15)
                            : null,
                    subtitle: Text(
                      'Send Within City Limit',
                      style: TextStyle(fontSize: 10, color: Colors.black),
                    ),
                  ),
                ),
              ),
            ),

            Expanded(
              child: GestureDetector(
                onTap: () => onSelectionChanged(false),
                child: Container(
                  decoration: BoxDecoration(
                    border:
                        !isSendSelected
                            ? Border.all(
                              color: AppColors.containerColor,
                              width: 2,
                            )
                            : null,
                    color: !isSendSelected ? AppColors.commonWhite : null,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ListTile(
                    title: Text(
                      'Receive Parcel',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    trailing:
                        !isSendSelected
                            ? Image.asset(AppImages.tick, height: 15, width: 15)
                            : null,
                    subtitle: Text(
                      'Get Parcel Within City Limit',
                      style: TextStyle(fontSize: 10, color: Colors.black),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget bookContainers({
    required bool isSendSelected,
    required ValueChanged<bool> onSelectionChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.containerColor1,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => onSelectionChanged(true),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSendSelected ? AppColors.commonWhite : null,
                    borderRadius: BorderRadius.circular(10),
                    border:
                        isSendSelected
                            ? Border.all(
                              color: AppColors.containerColor,
                              width: 2,
                            )
                            : null,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Image.asset(AppImages.alone, height: 20),
                        SizedBox(width: 15),
                        Text(
                          'Ride Only',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            Expanded(
              child: GestureDetector(
                onTap: () => onSelectionChanged(false),
                child: Container(
                  decoration: BoxDecoration(
                    color: !isSendSelected ? AppColors.commonWhite : null,
                    borderRadius: BorderRadius.circular(10),
                    border:
                        !isSendSelected
                            ? Border.all(
                              color: AppColors.containerColor,
                              width: 2,
                            )
                            : null,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Image.asset(AppImages.rideShare, height: 20),
                        SizedBox(width: 15),
                        Text(
                          'Ride Share',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget customPlainContainers({
    required Color containerColor,
    required String leadingImage,
    required String title,
    required String subTitle,
    required String userNameAndPhn,
    required bool isSelected,
    VoidCallback? onClear,
    VoidCallback? onTap,
    VoidCallback? onEditTap,
    Color? subColor = Colors.black45,
    Color? iconColor = AppColors.commonBlack,
    Color? trailingColor = AppColors.commonBlack,
    Color? titleColor = AppColors.commonBlack,
  }) {
    return GestureDetector(
      onTap: isSelected ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: containerColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.commonBlack.withOpacity(0.08),
            width: 1.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: isSelected ? 5 : 10),
              child: Image.asset(leadingImage, height: 21, width: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subTitle,
                    style: TextStyle(color: subColor, fontSize: 13),
                  ),
                  if (isSelected) ...[
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 2,
                      child: DottedLine(
                        direction: Axis.horizontal,
                        dashColor: Colors.grey.shade400,
                        lineThickness: 1,
                        dashLength: 5,
                        dashGapLength: 4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    CustomTextFields.textWithStylesSmall(
                      userNameAndPhn,
                      colors: titleColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            isSelected
                ? Row(
                  children: [
                    GestureDetector(
                      onTap: onEditTap,
                      child: Image.asset(
                        AppImages.edit,
                        height: 22,
                        width: 22,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(width: 13),
                    if (onClear != null)
                      GestureDetector(
                        onTap: onClear,
                        child: Icon(Icons.close, size: 22, color: iconColor),
                      ),
                  ],
                )
                : GestureDetector(
                  onTap: onTap,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10.0),
                      child: Image.asset(
                        AppImages.add,
                        height: 20,
                        width: 20,
                        color: trailingColor,
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  static customPlainContainerss({
    required Color containerColor,
    required String leadingImage,
    required String title,
    required String subTitle,
    VoidCallback? onClear, // <- add this
    VoidCallback? onTap,
    Color? subColor = Colors.black45,
    Color? trailingColor = AppColors.commonBlack,
    Color? titleColor = AppColors.commonBlack,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: containerColor,
          border: Border.all(
            color: AppColors.commonBlack.withOpacity(0.1),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: ListTile(
          leading: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [Image.asset(leadingImage, height: 22, width: 22)],
          ),
          trailing:
              onClear != null
                  ? IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    color: trailingColor,
                    onPressed: onClear,
                  )
                  : Image.asset(
                    AppImages.add,
                    height: 20,
                    width: 20,
                    color: trailingColor,
                  ),

          title: CustomTextFields.textWithStyles600(
            fontSize: 15,
            title,
            color: titleColor,
          ),
          subtitle: Text(subTitle, style: TextStyle(color: subColor)),
        ),
      ),
    );
  }

  static customRideContainer({
    required String tittle,
    required String subTitle,
    required String img,
    double imgHeight = 43,
    double imgWeight = 32,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: AppColors.containerColor,
        ),
        child: ListTile(
          title: Text(
            tittle,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          subtitle: Text(subTitle, style: TextStyle(fontSize: 10)),
          trailing: Image.asset(img, height: imgHeight, width: imgWeight),
        ),
      ),
    );
  }

  static customWalletContainer({
    required VoidCallback onTap,
    required String title,
    FontWeight? fontWeight = FontWeight.w600,
    required String leadingImagePath,
    Widget? trailing,
    Color containerColor = Colors.white,
    Color borderColor = const Color(0xFFE0E0E0),
    Color textColor = Colors.black,
    Color arrowColor = Colors.black,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: borderColor, width: 1),
          color: containerColor,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(vertical: 15.0, horizontal: 15),
        child: Row(
          children: [
            Image.asset(leadingImagePath, height: 26, width: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: fontWeight,
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  static bookCarTypeContainer({
    required VoidCallback onTap,
    required String carTitle,
    required String carMinRate,
    String? carMaxRate,
    required String carSubTitle,
    required String arrivingTime,
    required String carImg,
    Color borderColor = AppColors.containerColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.commonWhite,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: borderColor),
        ),
        child: ListTile(
          leading: Image.asset(carImg, height: 32, width: 65),
          title: Row(
            children: [
              CustomTextFields.textWithStyles600(carTitle),
              Spacer(),
              Image.asset(AppImages.nBlackCurrency, height: 14),

              CustomTextFields.textWithStyles600('$carMinRate'),
            ],
          ),
          subtitle: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              CustomTextFields.textWithStylesSmall(carSubTitle),
              Spacer(),
              Image.asset(AppImages.driverTime, height: 12, width: 12),

              CustomTextFields.textWithStylesSmall(
                ' $arrivingTime',
                colors: AppColors.walletCurrencyColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget rideShareContainer({
    String? leftImage,
    String? rightImage,
    double height = 45,
    double weight = 45,
    bool isSelected = false,
    bool isDisabled = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color:
            isDisabled
                ? AppColors.rideShareContainerColor
                : isSelected
                ? AppColors.changeButtonColor
                : AppColors.rideShareContainerColor3,
        borderRadius: BorderRadius.circular(5),
      ),
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 27),
      child: Image.asset(
        leftImage ?? '',
        height: height,
        width: weight,
        color:
            isDisabled
                ? null
                : isSelected
                ? AppColors.commonWhite
                : AppColors.walletCurrencyColor,
      ),
    );
  }

  static pickUpFields({
    required String imagePath,
    required String title,
    required String subTitle,
    String? title1,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Image.asset(imagePath, height: 35, width: 35),
        SizedBox(width: 10),

        // Title and description in a Column
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CustomTextFields.textWithStylesSmall(
                title,
                fontWeight: FontWeight.w500,
                fontSize: 15,
                colors: AppColors.commonBlack,
              ),

              CustomTextFields.textWithStylesSmall(subTitle),
            ],
          ),
        ),
        if (title1 != null)
          Container(
            padding: EdgeInsets.symmetric(horizontal: 15, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.chatCallContainerColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: CustomTextFields.textWithStylesSmall(
              title1 ?? '',
              colors: AppColors.walletCurrencyColor,
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }

  Widget historyCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// Title + Status
          Row(
            children: [
              const Text(
                "Electronics",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  "Completed",
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          /// Time
          const Text(
            "1:45 PM → 2:30 PM",
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 6),

          /// Order Info
          const Text(
            "TechStore Ltd → John Smith   #ORD-2024-001",
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),

          /// Pickup
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.circle, size: 10, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      "Pickup Address",
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 2),
                    Text(
                      "123 Main Street, TechStore",
                      style: TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          /// Delivery
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.circle, size: 10, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      "Delivery Address",
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 2),
                    Text(
                      "456 Oak Avenue, Apt 3B",
                      style: TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '"Handle with care - fragile electronics"',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),

          /// Rating + Price
          Row(
            children: [
              const Icon(Icons.star, color: Colors.orange, size: 20),
              const SizedBox(width: 4),
              const Text("4.5", style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: const [
                  Text(
                    "₦ 17.50",
                    style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    "₦ 12.50   ₦ 5.00 tip",
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget buildUnderDevelopmentDialog(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Image.asset(
            //   AppImages.developing,
            //   width: 80,
            //   height: 80,
            //   fit: BoxFit.contain,
            // ),
            // const SizedBox(height: 16),
            Text(
              'Feature in Development',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.commonBlack,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This feature is currently under development.\nStay tuned for updates!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.greyDark,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            AppButtons.button(
              onTap: () {
                Navigator.pop(context);
              },
              text: 'OK',
            ),
          ],
        ),
      ),
    );
  }
}

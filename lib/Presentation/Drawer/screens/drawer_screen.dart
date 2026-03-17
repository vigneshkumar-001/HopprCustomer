import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:get/get.dart';
import 'package:hopper/Presentation/Authentication/widgets/textfields.dart';
import 'package:hopper/Presentation/Drawer/controller/profle_cotroller.dart';
import 'package:hopper/Presentation/Drawer/screens/notification_screens.dart';
import 'package:hopper/Presentation/Drawer/screens/ride_and_package_history_screen.dart';
import 'package:hopper/Presentation/Drawer/screens/settings_screen.dart';
import 'package:hopper/Presentation/OnBoarding/Widgets/custom_bottomnavigation.dart';
import 'package:hopper/Presentation/wallet/screens/wallet_screens.dart';
import 'package:hopper/TutorialService_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../Authentication/screens/mobile_screens.dart';

class DrawerScreen extends StatefulWidget {
  const DrawerScreen({super.key});

  @override
  State<DrawerScreen> createState() => _DrawerScreenState();
}

class _DrawerScreenState extends State<DrawerScreen> {
  final ProfleCotroller controller = Get.find<ProfleCotroller>();
  @override
  void initState() {
    super.initState();
    if (controller.user.value == null) {
      controller.getProfileData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        return await false;
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFFFFD), // Top (#FFFFFD)
                Color(0xFFF6F7FF), // Bottom (#F6F7FF)
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 20,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (context) => CommonBottomNavigation(
                                            initialIndex: 0,
                                          ),
                                    ),
                                  );
                                  // Get.offAll(
                                  //   CommonBottomNavigation(initialIndex: 0),
                                  // );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.containerColor,
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  child: Image.asset(
                                    AppImages.close,
                                    height: 17,
                                    width: 17,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 40),
                          InkWell(
                            onTap: () {
                              Get.to(() => RideAndPackageHistoryScreen());
                            },
                            child: CustomTextFields.textWithStyles700(
                              'Ride Activity',
                            ),
                          ),
                          const SizedBox(height: 15),
                          Divider(
                            color: AppColors.dividerColor.withOpacity(0.1),
                            thickness: 1.5,
                          ),

                          const SizedBox(height: 30),
                          InkWell(
                            onTap: () {
                              Get.to(() => WalletScreen());
                            },
                            child: CustomTextFields.textWithStyles700('Wallet'),
                          ),
                          const SizedBox(height: 15),
                          Divider(
                            color: AppColors.dividerColor.withOpacity(0.1),
                            thickness: 1.5,
                          ),

                          const SizedBox(height: 30),
                          InkWell(
                            onTap: () {
                              Get.to(() => NotificationScreen());
                            },
                            child: CustomTextFields.textWithStyles700(
                              'Notifications',
                            ),
                          ),
                          const SizedBox(height: 20),
                          Divider(
                            color: AppColors.dividerColor.withOpacity(0.1),
                            thickness: 1.5,
                          ),
                          // const SizedBox(height: 30),
                          // CustomTextFields.textWithStyles700('Help'),
                          // const SizedBox(height: 20),
                          // Divider(
                          //   color: AppColors.dividerColor.withOpacity(0.1),
                          //   thickness: 1.5,
                          // ),
                          const SizedBox(height: 30),
                          InkWell(
                            onTap: () {
                              Get.to(() => SettingsScreen());
                            },
                            child: CustomTextFields.textWithStyles700(
                              'Settings',
                            ),
                          ),
                          const SizedBox(height: 20),
                          Divider(
                            color: AppColors.dividerColor.withOpacity(0.1),
                            thickness: 1.5,
                          ),
                          const SizedBox(height: 20),

                          // 🔴 NEW: Shared Booking toggle
                          InkWell(
                            onTap: () => _showLogoutDialog(context),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                CustomTextFields.textWithStyles700('Log out'),
                                const Icon(
                                  Icons.logout,
                                  color: Colors.red,
                                  size: 22,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Divider(color: AppColors.dividerColor1, thickness: 2),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 5,
                    ),
                    child: Obx(() {
                      final user = controller.user.value;
                      if (user == null) return const SizedBox();

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(50),
                            child: CachedNetworkImage(
                              imageUrl: user.profileImage ?? '',
                              height: 45,
                              width: 45,
                              fit: BoxFit.cover,
                              placeholder:
                                  (context, url) => const SizedBox(
                                    height: 45,
                                    width: 45,
                                    child: Center(
                                      child: SizedBox(
                                        height: 15,
                                        width: 15,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                              errorWidget:
                                  (context, url, error) => Container(
                                    height: 45,
                                    width: 45,
                                    decoration: BoxDecoration(
                                      color: Colors.grey,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.person,
                                      color: Colors.white,
                                    ),
                                  ),
                            ),
                          ),

                          const SizedBox(width: 15),

                          /// 🔥 THIS FIXES YOUR OVERFLOW
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    /// 🔥 THIS MAKES NAME WRAP IN MULTIPLE LINES
                                    Expanded(
                                      child: Text(
                                        user.firstName ?? '',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        softWrap: true,
                                        overflow: TextOverflow.visible,
                                        maxLines: 2, // <-- wrap long names
                                      ),
                                    ),

                                    const SizedBox(width: 10),

                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.commonWhite,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        children: [
                                          Image.asset(
                                            AppImages.star,
                                            height: 15,
                                            color:
                                                AppColors.walletCurrencyColor,
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            '${user.customerRating?.averageRating?.toStringAsFixed(2) ?? '0.0'}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 5),

                                Text(
                                  '${user.countryCode ?? ''} ${user.phone ?? ''}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }),
                  ),

                  /*Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 5,
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(50),
                          child: Image.asset(
                            AppImages.dummy,
                            height: 45,
                            width: 45,
                          ),
                        ),
                        const SizedBox(width: 15),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CustomTextFields.textWithStyles600(
                                  fontSize: 20,
                                  'Michael Francis',
                                ),
                                const SizedBox(width: 15),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.commonWhite,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      Image.asset(
                                        AppImages.star,
                                        height: 15,
                                        color: AppColors.walletCurrencyColor,
                                      ),
                                      const SizedBox(width: 5),
                                      CustomTextFields.textWithStyles600(
                                        fontSize: 15,
                                        '4.5',
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            CustomTextFields.textWithStylesSmall(
                              '+234 813 789 4562',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),*/
                  Divider(color: AppColors.dividerColor1, thickness: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: AppColors.commonWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.logout, color: Colors.red, size: 28),
                ),

                const SizedBox(height: 16),

                // Title
                const Text(
                  'Log out',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),

                const SizedBox(height: 8),

                // Message
                const Text(
                  'Do you want to log out?',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                ),

                const SizedBox(height: 24),

                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context); // No
                        },
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('No'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          _logout(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Yes'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('token');
    await prefs.remove('refreshToken');
    await prefs.remove('sessionToken');
    await prefs.remove('role');
    await prefs.remove('contacts_synced');

    if (!context.mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => MobileScreens()),
      (route) => false, // ❌ removes ALL previous routes
    );
  }
}


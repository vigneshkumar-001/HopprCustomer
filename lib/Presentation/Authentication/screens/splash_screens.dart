import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hopper/Core/Consents/app_texts.dart';
import 'package:hopper/Core/Utility/app_images.dart';
import 'package:hopper/Presentation/Authentication/controller/authController.dart';
import 'package:hopper/Presentation/Authentication/screens/mobile_screens.dart';
import 'package:hopper/Presentation/Drawer/controller/profle_cotroller.dart';
import 'package:hopper/Presentation/Drawer/controller/ride_history_controller.dart';
import 'package:hopper/Presentation/OnBoarding/Widgets/custom_bottomnavigation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreens extends StatefulWidget {
  const SplashScreens({super.key});

  @override
  State<SplashScreens> createState() => _SplashScreensState();
}

class _SplashScreensState extends State<SplashScreens> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
    );
    _navigateNext();
  }

  Future<void> _navigateNext() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    if (!mounted) return;

    if (token != null && token.isNotEmpty) {
      Get.off(() => CommonBottomNavigation(initialIndex: 0));
      unawaited(_warmupForLoggedInUser());
      return;
    }

    Get.off(() => const MobileScreens());
  }

  Future<void> _warmupForLoggedInUser() async {
    try {
      final rideHistoryController = Get.find<RideHistoryController>();
      final profileController = Get.find<ProfleCotroller>();
      final authController = Get.find<AuthController>();

      await Future.wait([
        authController.getAppSettings(),
        rideHistoryController.getRideHistory(isFirstLoad: true),
        profileController.getProfileData(),
      ]);
    } catch (_) {
      // Ignore warmup failures; user is already on the home flow.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFEEE), Color(0xFFF6F7FF)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10.0),
                child: Text(
                  AppTexts.appLogoText,
                  style: const TextStyle(
                    fontSize: 37,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 100),
              Image.asset(AppImages.splashLogo),
              const Spacer(),
              Text(
                AppTexts.exploreText,
                style: const TextStyle(
                  fontSize: 29,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 30),
              RichText(
                text: TextSpan(
                  style: TextStyle(color: Colors.black45, fontSize: 14),
                  children: [
                    TextSpan(
                      text:
                          'By continuing, you agree that you have read and accept our  ',
                    ),
                    TextSpan(
                      text: 'T&C',
                      style: TextStyle(decoration: TextDecoration.underline),
                    ),
                    TextSpan(text: ' and '),
                    TextSpan(
                      text: 'Privacy Policy.',
                      style: TextStyle(decoration: TextDecoration.underline),
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
}


import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hopper/api/repository/api_consents.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Firebase/firebase_service.dart';
import 'package:hopper/Core/Utility/app_toasts.dart';
import 'package:hopper/init_controller.dart';
import 'package:hopper/Presentation/Authentication/screens/splash_screens.dart';
import 'package:hopper/Core/Consents/app_logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Keep only critical init work before first frame.
  await Firebase.initializeApp();
  AppLogger.log.i('Firebase.initializeApp() completed in main()');

  // Register background handler BEFORE runApp (required for terminated/background delivery).
  try {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e, st) {
    AppLogger.log.w('FCM BG handler register failed: $e\n$st');
  }

  await initController();

  // Load the cached backend Maps key (gMapKey) so Maps HTTP calls use it
  // immediately, before app-settings refreshes it. Falls back to the static
  // key inside ApiConsents if none is cached yet.
  await _loadCachedMapsKey();

  Stripe.publishableKey =
      'pk_test_51RTgU2Qhzmr6TYhsKMWtfICaQ72crva7xVWCA0hPeV1qdH9CInnl9WwJLNcxIIUWKDhCeipRLztD82DTnBXKx05700iEGBQWjw';
  await Stripe.instance.applySettings();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.white,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const MyApp());
  unawaited(_bootstrapBackgroundServices());
}

Future<void> _loadCachedMapsKey() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    ApiConsents.setDynamicMapsKey(prefs.getString('gMapKey'));
  } catch (e) {
    AppLogger.log.w('Cached gMapKey load failed: $e');
  }
}

Future<void> _bootstrapBackgroundServices() async {
  try {
    final firebaseService = FirebaseService();
    await firebaseService.initializeFirebase();
    firebaseService.listenToMessages();
    final hasFcmToken = await firebaseService.fetchFCMTokenIfNeeded();
    AppLogger.log.i(
      hasFcmToken
          ? 'FirebaseService initialized and FCM token is ready'
          : 'FirebaseService initialized; FCM token will retry in background',
    );
  } catch (e, st) {
    AppLogger.log.e('Background bootstrap failed: $e\n$st');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(360, 690),
      builder: (context, child) {
        return GetMaterialApp(
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: AppToasts.messengerKey,
          // App-wide premium page transition for ALL GetX navigations
          // (Get.to / Get.off / Get.offAll). Smooth iOS-style slide.
          defaultTransition: Transition.cupertino,
          transitionDuration: const Duration(milliseconds: 300),
          theme: ThemeData(
            scaffoldBackgroundColor: AppColors.commonWhite,
            textSelectionTheme: const TextSelectionThemeData(
              selectionHandleColor: Colors.black,
            ),
            // App-wide premium page transition for ALL Navigator.push
            // (MaterialPageRoute) navigations — same smooth slide on every
            // platform, so the whole app feels consistent and polished.
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: CupertinoPageTransitionsBuilder(),
                TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
              },
            ),
          ),
          home: const SplashScreens(),
        );
      },
    );
  }
}

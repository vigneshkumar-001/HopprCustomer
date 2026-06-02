import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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

Future<void> _bootstrapBackgroundServices() async {
  try {
    final firebaseService = FirebaseService();
    await firebaseService.initializeFirebase();
    firebaseService.listenToMessages();
    await firebaseService.fetchFCMTokenIfNeeded();
    AppLogger.log.i('FirebaseService initialized and FCM token handled');
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
          theme: ThemeData(
            scaffoldBackgroundColor: AppColors.commonWhite,
            textSelectionTheme: const TextSelectionThemeData(
              selectionHandleColor: Colors.black,
            ),
          ),
          home: const SplashScreens(),
        );
      },
    );
  }
}

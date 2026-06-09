import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import 'package:hopper/api/repository/api_consents.dart';
import 'package:hopper/api/dataSource/apiDataSource.dart';
import 'package:hopper/Presentation/Authentication/models/sos_response.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Firebase/firebase_service.dart';
import 'package:hopper/Core/Utility/app_toasts.dart';
import 'package:hopper/init_controller.dart';
import 'package:hopper/Presentation/Authentication/screens/splash_screens.dart';
import 'package:hopper/Core/Consents/app_logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Pre-warm the Android Google Maps renderer (latest, faster + smoother) so the
  // very first map on the home screen opens quickly instead of feeling heavy.
  // Must run before any GoogleMap is built; a no-op on non-Android platforms.
  _initMapsRenderer();

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

  // Load the cached Maps key (gMapKey) and refresh it from the backend so all
  // Maps/Autocomplete HTTP calls use the billing-enabled key — even on the very
  // first launch, before the user reaches a map/search screen.
  await _initMapsKey();

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

void _initMapsRenderer() {
  try {
    final maps = GoogleMapsFlutterPlatform.instance;
    if (maps is GoogleMapsFlutterAndroid) {
      // Latest renderer = quicker init + smoother tiles/gestures. Fire-and-
      // forget; tolerate "already initialized" on hot restart.
      unawaited(
        maps
            .initializeWithRenderer(AndroidMapRenderer.latest)
            .catchError((_) => AndroidMapRenderer.latest),
      );
    }
  } catch (e) {
    AppLogger.log.w('Maps renderer pre-warm failed: $e');
  }
}

Future<void> _initMapsKey() async {
  String cached = '';
  try {
    final prefs = await SharedPreferences.getInstance();
    cached = (prefs.getString('gMapKey') ?? '').trim();
    if (cached.isNotEmpty) ApiConsents.setDynamicMapsKey(cached);
  } catch (e) {
    AppLogger.log.w('Cached gMapKey load failed: $e');
  }

  if (cached.isEmpty) {
    // FIRST launch (no cached key): briefly wait for the server gMapKey so the
    // first Autocomplete/Maps call uses the billing-enabled key instead of the
    // static fallback (which throws REQUEST_DENIED). Bounded so the splash
    // never hangs — if it times out the key still updates in the background.
    await _fetchAndApplyMapsKey().timeout(
      const Duration(milliseconds: 3000),
      onTimeout: () {},
    );
  } else {
    // Already have a usable key: refresh in the background for next time.
    unawaited(_fetchAndApplyMapsKey());
  }
}

Future<void> _fetchAndApplyMapsKey() async {
  try {
    final res = await ApiDataSource().getAppSettings();
    final SosResponse? settings = res.fold((_) => null, (s) => s);
    final key = (settings?.gMapKey ?? '').trim();
    if (key.isEmpty) return;

    ApiConsents.setDynamicMapsKey(key); // apply immediately (synchronous)
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('gMapKey', key);
      final sos = (settings?.sosNumber ?? '').trim();
      if (sos.isNotEmpty) await prefs.setString('sosNumber', sos);
    } catch (_) {}
  } catch (e) {
    AppLogger.log.w('gMapKey server refresh failed: $e');
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

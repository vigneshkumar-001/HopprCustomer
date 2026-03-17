import 'dart:convert';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:hopper/Presentation/Authentication/controller/otp_controller.dart';
import 'package:hopper/Presentation/OnBoarding/Screens/chat_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const AndroidNotificationChannel _highPriorityChannel =
    AndroidNotificationChannel(
      'flutter_notification',
      'High Priority Notifications',
      description: 'For important notifications',
      importance: Importance.max,
    );

final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

bool _localNotificationsInitialized = false;

Future<void> _ensureLocalNotificationsInitialized() async {
  if (_localNotificationsInitialized) return;

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings();
  const initSettings = InitializationSettings(
    android: androidInit,
    iOS: iosInit,
  );

  await _localNotificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (response) async {
      final payload = response.payload ?? '';
      if (payload.isEmpty) return;

      try {
        final Map<String, dynamic> data = jsonDecode(payload);
        FirebaseService().handleNotificationData(data);
      } catch (e, st) {
        AppLogger.log.e('Failed to parse notification payload: $e\n$st');
      }
    },
  );

  await _localNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(_highPriorityChannel);

  _localNotificationsInitialized = true;
}

Future<void> _showLocalNotification(RemoteMessage message) async {
  await _ensureLocalNotificationsInitialized();

  final data = message.data;
  final notification = message.notification;
  final title = notification?.title ?? data['title'] ?? 'Notification';
  final body = notification?.body ?? data['body'] ?? '';

  if (title.toString().isEmpty && body.toString().isEmpty && data.isEmpty) {
    return;
  }

  const androidDetails = AndroidNotificationDetails(
    'flutter_notification',
    'High Priority Notifications',
    channelDescription: 'For important notifications',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    ticker: 'ticker',
  );
  const iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  );

  final payload = data.isNotEmpty ? jsonEncode(data) : '{}';

  await _localNotificationsPlugin.show(
    Random().nextInt(1 << 31),
    title.toString(),
    body.toString(),
    const NotificationDetails(android: androidDetails, iOS: iosDetails),
    payload: payload,
  );
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
    await _showLocalNotification(message);
  } catch (e, st) {
    AppLogger.log.e('BG Firebase.initializeApp()/notification failed: $e\n$st');
  }

  AppLogger.log.i('[BG] messageId=${message.messageId}');
  AppLogger.log.i('[BG] Data: ${message.data}');
}

class FirebaseService {
  FirebaseService();

  final FlutterLocalNotificationsPlugin localNotifications =
      _localNotificationsPlugin;

  final OtpController otpController =
      Get.isRegistered<OtpController>()
          ? Get.find<OtpController>()
          : Get.put(OtpController());

  final AndroidNotificationChannel channel = _highPriorityChannel;

  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  Future<void> initializeFirebase() async {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await _ensureLocalNotificationsInitialized();

    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

    await _requestPermission();
  }

  Future<void> _requestPermission() async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    AppLogger.log.i('Notification permission: ${settings.authorizationStatus}');
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      Get.snackbar(
        'Notifications Disabled',
        'Enable notifications in device settings.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<bool> _isUserAuthenticated() async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('token');
    return authToken != null && authToken.isNotEmpty;
  }

  Future<void> _syncFcmTokenIfAuthenticated(String token) async {
    if (token.isEmpty) {
      return;
    }

    if (!await _isUserAuthenticated()) {
      AppLogger.log.i(
        'FCM token saved locally. Backend sync deferred until login.',
      );
      return;
    }

    try {
      await otpController.sendFcmToken(fcmToken: token);
    } catch (e) {
      AppLogger.log.e('sendFcmToken failed: $e');
    }
  }

  Future<void> fetchFCMTokenIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    _fcmToken = prefs.getString('fcmToken');

    if (_fcmToken == null || _fcmToken!.isEmpty) {
      try {
        final token = await FirebaseMessaging.instance.getToken();
        if (token != null && token.isNotEmpty) {
          _fcmToken = token;
          await prefs.setString('fcmToken', token);
          AppLogger.log.i('New FCM token saved: $token');
          await _syncFcmTokenIfAuthenticated(token);
        } else {
          AppLogger.log.w('FCM token null or empty');
        }
      } catch (e) {
        AppLogger.log.e('Error fetching FCM token: $e');
      }
    } else {
      AppLogger.log.i('Existing FCM token: $_fcmToken');
      await _syncFcmTokenIfAuthenticated(_fcmToken!);
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      AppLogger.log.i('Token refreshed: $newToken');
      _fcmToken = newToken;
      await prefs.setString('fcmToken', newToken);
      await _syncFcmTokenIfAuthenticated(newToken);
    });
  }

  Future<void> showNotification(RemoteMessage message) async {
    await _showLocalNotification(message);
  }

  void listenToMessages({
    void Function(RemoteMessage)? onForeground,
    void Function(RemoteMessage)? onOpenedApp,
  }) {
    FirebaseMessaging.onMessage.listen((msg) async {
      AppLogger.log.i(
        '[FOREGROUND] messageId=${msg.messageId} data=${msg.data}',
      );
      await showNotification(msg);
      if (onForeground != null) onForeground(msg);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      AppLogger.log.i(
        '[OPENED FROM BG] messageId=${msg.messageId} data=${msg.data}',
      );
      handleNotificationData(msg.data);
      if (onOpenedApp != null) onOpenedApp(msg);
    });

    FirebaseMessaging.instance.getInitialMessage().then((msg) {
      if (msg != null) {
        AppLogger.log.i(
          '[TERMINATED TAP] messageId=${msg.messageId} data=${msg.data}',
        );
        handleNotificationData(msg.data);
        if (onOpenedApp != null) onOpenedApp(msg);
      }
    });
  }

  void handleNotificationData(Map<String, dynamic> data) {
    try {
      AppLogger.log.i('Handling notification data: $data');

      final page =
          (data['page'] ?? data['pageName'] ?? '').toString().toLowerCase();
      final bookingId =
          (data['bookingId'] ?? data['booking_id'] ?? '').toString();

      if (page.isEmpty) {
        AppLogger.log.w(
          'Notification payload has no page field; ignoring navigation.',
        );
        return;
      }

      switch (page) {
        case 'chat':
        case 'conversation':
          if (bookingId.isNotEmpty) {
            Get.to(() => ChatScreen(bookingId: bookingId));
          } else {
            AppLogger.log.w('bookingId missing for chat page');
          }
          break;

        case 'booking':
          if (bookingId.isNotEmpty) {
            Get.to(() => ChatScreen(bookingId: bookingId));
          } else {
            AppLogger.log.w('booking page without bookingId');
          }
          break;

        default:
          AppLogger.log.w('Unknown notification page: $page');
          break;
      }
    } catch (e, st) {
      AppLogger.log.e('Error handling notification data: $e\n$st');
    }
  }
}

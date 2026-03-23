// // lib/Presentation/OnBoarding/Controller/chat_controller.dart
// import 'package:flutter/material.dart';
// import 'package:get/get.dart';
// import 'package:hopper/Presentation/OnBoarding/models/chat_history_response.dart';
// import 'package:hopper/api/dataSource/apiDataSource.dart';
//
// class ChatController extends GetxController {
//   final ApiDataSource apiDataSource = ApiDataSource();
//   final RxBool isLoading = false.obs;
//
//   /// Full messages from API
//   final RxList<ChatHistoryMessage> chatMessages = <ChatHistoryMessage>[].obs;
//
//   /// Header bits for app bar
//   final RxString driverName = ''.obs;
//   final RxString driverImage = ''.obs;
//   final RxString customerImage = ''.obs;
//
//   Future<void> fetchChatHistory({
//     required String bookingId,
//     required BuildContext context,
//   }) async {
//     isLoading.value = true;
//
//     try {
//       final results = await apiDataSource.chatHistory(
//         bookingId: bookingId,
//         pickupLatitude: '',
//         pickupLongitude: '',
//       );
//
//       results.fold(
//             (failure) {
//           isLoading.value = false;
//           // AppToasts.showErrorGlobal(failure.message, title: 'Error');
//         },
//             (response) {
//           isLoading.value = false;
//
//           // messages
//           final items = response.data?.contents ?? <ChatHistoryMessage>[];
//           items.sort((a, b) {
//             final ta = DateTime.tryParse(a.timestamp) ?? DateTime(1970);
//             final tb = DateTime.tryParse(b.timestamp) ?? DateTime(1970);
//             return ta.compareTo(tb);
//           });
//           chatMessages
//             ..clear()
//             ..addAll(items);
//
//           // driver header
//           driverName.value = response.data?.driver?.firstName ?? '';
//           driverImage.value = response.data?.driver?.profilePic ?? '';
//           customerImage.value = response.data?.customer?. profileImage ?? '';
//         },
//       );
//     } catch (_) {
//       isLoading.value = false;
//       // AppToasts.showErrorGlobal('An unexpected error occurred', title: 'Error');
//     }
//   }
// }


import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hopper/Core/Utility/app_toasts.dart';
import 'package:hopper/Presentation/OnBoarding/models/chat_history_response.dart';
import 'package:hopper/api/dataSource/apiDataSource.dart';

class ChatController extends GetxController {
  final ApiDataSource apiDataSource = ApiDataSource();
  final RxBool isLoading = false.obs;

  /// Full messages from API (history)
  final RxList<ChatHistoryMessage> chatMessages = <ChatHistoryMessage>[].obs;

  /// Header bits for app bar
  final RxString driverName = ''.obs;
  final RxString driverImage = ''.obs;    // full URL or ''
  final RxString customerImage = ''.obs;  // full URL or ''
  final RxString driverPhone = ''.obs;  // full URL or ''

  Future<void> fetchChatHistory({
    required String bookingId,
    required BuildContext context,
  }) async {
    isLoading.value = true;
    try {
      final results = await apiDataSource.chatHistory(
        bookingId: bookingId,
        pickupLatitude: '',
        pickupLongitude: '',
      );

      results.fold(
            (failure) {
          isLoading.value = false;
          AppToasts.showErrorGlobal(failure.message, title: 'Error');
        },
            (response) {
          isLoading.value = false;

          // messages
          final items = response.data?.contents ?? <ChatHistoryMessage>[];
          items.sort((a, b) {
            final ta = DateTime.tryParse(a.timestamp) ?? DateTime(1970);
            final tb = DateTime.tryParse(b.timestamp) ?? DateTime(1970);
            return ta.compareTo(tb);
          });
          chatMessages
            ..clear()
            ..addAll(items);

          // header (normalize to '' if null)
          driverName.value = (response.data?.driver?.firstName ?? '').trim();
          driverImage.value = (response.data?.driver?.profilePic ?? '').trim();
          customerImage.value = (response.data?.customer?.profileImage ?? '').trim();
          driverPhone.value = (response.data?.driver?.driverPhone ?? '').trim();
        },
      );
    } catch (_) {
      isLoading.value = false;
      AppToasts.showErrorGlobal('An unexpected error occurred', title: 'Error');
    }
  }
}

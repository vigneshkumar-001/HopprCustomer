import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:hopper/Presentation/Drawer/models/notification_response.dart';
import 'package:hopper/Presentation/Drawer/models/ride_history_response.dart';

import 'package:hopper/api/dataSource/apiDataSource.dart';
class NotificationController extends GetxController {
  final ApiDataSource apiDataSource = ApiDataSource();

  RxBool isLoading = false.obs;
  RxBool isMoreLoading = false.obs;

  RxList<NotificationData> notificationData = <NotificationData>[].obs;

  int currentPage = 1;
  int totalPages = 1;

  @override
  void onInit() {
    super.onInit();
    getNotification(isFirstLoad: true);
  }

  Future<void> getNotification({bool isFirstLoad = false}) async {
    if (isFirstLoad) {
      currentPage = 1;
      notificationData.clear();
      isLoading.value = true;
    } else {
      if (currentPage > totalPages) return;
      isMoreLoading.value = true;
    }

    try {
      final results = await apiDataSource.getNotification(
        page: currentPage.toString(),
      );

      results.fold(
            (failure) => AppLogger.log.e("Error: $failure"),
            (response) {
          totalPages = response.totalPages ?? 1;

          if (isFirstLoad) {
            notificationData.value = response.data;
          } else {
            notificationData.addAll(response.data);
          }

          currentPage++;  // ← NOW WORKS
          AppLogger.log.i("Next Page → $currentPage");
        },
      );
    } catch (e) {
      AppLogger.log.e("❌ Exception: $e");
    } finally {
      isLoading.value = false;
      isMoreLoading.value = false;
    }
  }
}


// class NotificationController extends GetxController {
//   final ApiDataSource apiDataSource = ApiDataSource();
//
//   final RxBool isLoading = false.obs;
//   RxList<NotificationData> notificationData = <NotificationData>[].obs;
//
//   @override
//   void onInit() {
//     super.onInit();
//     getNotification();
//   }
//
//   Future<void> getNotification() async {
//     isLoading.value = true;
//     try {
//       final results = await apiDataSource.getNotification();
//       results.fold(
//         (failure) {
//           AppLogger.log.e(" $failure");
//         },
//         (response) {
//           notificationData.value = response.data;
//           AppLogger.log.i("✅ Raw response: ${response.toJson()}");
//         },
//       );
//     } catch (e) {
//       AppLogger.log.e("❌ Exception while fetching rides: $e");
//     } finally {
//       isLoading.value = false;
//     }
//   }
// }

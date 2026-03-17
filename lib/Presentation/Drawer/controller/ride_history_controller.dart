import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:hopper/Presentation/Drawer/models/ride_history_response.dart';
import 'package:hopper/api/dataSource/apiDataSource.dart';

class RideHistoryController extends GetxController {
  final ApiDataSource apiDataSource = ApiDataSource();

  final RxBool isLoading = false.obs;
  final RxBool isMoreLoading = false.obs;

  final RxList<RideHistoryData> rideHistoryList = <RideHistoryData>[].obs;
  final RxList<RideHistoryData> parcelHistoryList = <RideHistoryData>[].obs;

  int currentPage = 1;
  int totalPages = 1;

  final ScrollController scrollController = ScrollController();

  Future<void> getRideHistory({bool isFirstLoad = false}) async {
    if (isFirstLoad) {
      if (isLoading.value) return;
      currentPage = 1;
      totalPages = 1;
      rideHistoryList.clear();
      parcelHistoryList.clear();
      isLoading.value = true;
    } else {
      if (isMoreLoading.value || isLoading.value || currentPage > totalPages) {
        return;
      }
      isMoreLoading.value = true;
    }

    try {
      final response = await apiDataSource.getRideHistory(page: currentPage);

      response.fold((failure) {
        AppLogger.log.e('Ride history fetch failed: $failure');
      }, (res) {
        totalPages = res.totalPages;

        final rides =
            res.remappedBookings.where((e) => e.bookingType == 'Ride').toList();
        final parcels = res.remappedBookings
            .where((e) => e.bookingType == 'Parcel')
            .toList();

        if (isFirstLoad) {
          rideHistoryList.assignAll(rides);
          parcelHistoryList.assignAll(parcels);
        } else {
          rideHistoryList.addAll(rides);
          parcelHistoryList.addAll(parcels);
        }

        currentPage++;
      });
    } catch (e) {
      AppLogger.log.e('Ride history exception: $e');
    } finally {
      isLoading.value = false;
      isMoreLoading.value = false;
    }
  }

  @override
  void onClose() {
    scrollController.dispose();
    super.onClose();
  }
}

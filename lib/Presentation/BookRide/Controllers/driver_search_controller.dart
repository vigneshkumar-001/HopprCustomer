import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:hopper/Presentation/BookRide/Models/create_booking_model.dart';
import 'package:hopper/Presentation/BookRide/Models/driver_search_models.dart';
import 'package:hopper/Presentation/BookRide/Models/send_driver_request_models.dart';
import 'package:hopper/Presentation/BookRide/Models/shared_create_booking_response.dart';
import 'package:hopper/Presentation/BookRide/Models/shared_driver_search_response.dart';

import 'package:hopper/Presentation/OnBoarding/Widgets/custom_bottomnavigation.dart';
import 'package:hopper/api/dataSource/shared_api_datasource.dart';

import 'package:hopper/uitls/websocket/socket_io_client.dart';

import '../../../Core/Utility/app_toasts.dart';
import '../../../api/dataSource/apiDataSource.dart';

enum RideType { rideOnly, shared }

class DriverSearchController extends GetxController {
  Rx<RideType> rideType = RideType.rideOnly.obs;
  ApiDataSource apiDataSource = ApiDataSource();
  SharedApiDatasource sharedApiDatasource = SharedApiDatasource();
  Rxn<DriverSearchModels> userProfile = Rxn<DriverSearchModels>();
  Rxn<SharedDriverSearchResponse> sharedDriverSearchResponse =
      Rxn<SharedDriverSearchResponse>();
  RxList<SharedDriverData> sharedServiceType = <SharedDriverData>[].obs;
  RxList<DriverData> serviceType = <DriverData>[].obs;
  Rxn<BookingData> carBooking = Rxn<BookingData>();
  Rxn<BookingDriverData> sendDriverRequestData = Rxn<BookingDriverData>();
  RxString estimatedTime = ''.obs;
  RxString frontImageUrl = ''.obs;
  final socketService = SocketService();
  RxBool markerAdded = false.obs;
  RxBool isLoading = false.obs;
  RxBool isRetryLoading = false.obs;
  RxBool isCancelLoading = false.obs;
  RxBool isGetLoading = false.obs;
  // Used by UI to avoid showing "No drivers" before the first response arrives.
  RxBool hasFetchedRideOnly = false.obs;
  RxBool hasFetchedShared = false.obs;
  RxString selectedCarType = ''.obs;
  Rxn<SharedDriverData> selectedSharedDriver = Rxn<SharedDriverData>();

  Rxn<SharedBookingData> sharedBooking = Rxn<SharedBookingData>();
  @override
  void onInit() {
    super.onInit();
  }

  Future<DriverSearchModels?> getDriverSearch({
    required double pickupLat,
    required double pickupLng,
    required double dropLat,
    required double dropLng,
  }) async {
    isGetLoading.value = true;

    try {
      final results = await apiDataSource.getDriverSearch(
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        dropLat: dropLat,
        dropLng: dropLng,
      );

      return results.fold(
        (failure) {
          isGetLoading.value = false;
          hasFetchedRideOnly.value = true;
          return null;
        },
        (response) {
          isGetLoading.value = false;
          hasFetchedRideOnly.value = true;
          serviceType.value = response.data;
          markerAdded.value = false;
          update();
          AppLogger.log.i(serviceType.length);
          AppLogger.log.i(response.data.toString());
          return response;
        },
      );
    } catch (e) {
      isGetLoading.value = false;
      hasFetchedRideOnly.value = true;
      return null;
    }
  }

  Future<SharedDriverSearchResponse?> getSharedDriverSearch({
    required double pickupLat,
    required double pickupLng,
    required double dropLat,
    required double dropLng,
    int? seatsToShare,
    String? routeId,
  }) async {
    isGetLoading.value = true;

    try {
      final results = await sharedApiDatasource.driverSearchShared(
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        dropLat: dropLat,
        dropLng: dropLng,

        // seatsToShare: seatsToShare,
        // routeId: routeId,
      );

      return results.fold(
        (failure) {
          isGetLoading.value = false;
          hasFetchedShared.value = true;
          return null;
        },
        (response) {
          isGetLoading.value = false;
          hasFetchedShared.value = true;
          // set shared drivers list safely
          sharedServiceType.value = response.data ?? [];
          markerAdded.value = false;
          update();
          AppLogger.log.i(serviceType.length);
          AppLogger.log.i(response.data.toString());
          return response;
        },
      );
    } catch (e) {
      isGetLoading.value = false;
      hasFetchedShared.value = true;
      return null;
    }
  }

  Future<String?> createBookingCar({
    required double fromLatitude,
    required double fromLongitude,
    required double toLatitude,
    required double toLongitude,
    required String customerId,
    required String carType,
    required BuildContext context,
  }) async {
    isLoading.value = true;

    try {
      final results = await apiDataSource.carBookingCar(
        carType: carType,
        fromLatitude: fromLatitude,
        fromLongitude: fromLongitude,
        toLatitude: toLatitude,
        toLongitude: toLongitude,
        customerId: customerId,
      );

      return results.fold(
        (failure) {
          isLoading.value = false;
          AppToasts.showError(context, failure.message);
          return failure.message;
        },
        (response) {
          isLoading.value = false;
          carBooking.value = response.data;

          final bookingData = {
            'bookingId': response.data.bookingId,
            'userId': response.data.customerId,
          };

          // Log the data
          AppLogger.log.i("📤 Join booking data: $bookingData");
          socketService.joinBookingRoom(
            bookingId: response.data.bookingId.toString(),
            payload: bookingData,
          );

          AppLogger.log.i(response.data);
          return null;
        },
      );
    } catch (e) {
      isLoading.value = false;
      return 'An error occurred';
    }
  }

  Future<String?> createSharedBooking({
    required double fromLatitude,
    required double fromLongitude,
    required double toLatitude,
    required double toLongitude,

    required String carType,
    required List<int> seats,
    required BuildContext context,
  }) async {
    isLoading.value = true;

    try {
      final results = await sharedApiDatasource.createSharedBooking(
        carType: carType,
        fromLatitude: fromLatitude,
        fromLongitude: fromLongitude,
        toLatitude: toLatitude,
        toLongitude: toLongitude,

        seats: seats,
      );

      return results.fold(
        (failure) {
          isLoading.value = false;
          AppToasts.showError(context, failure.message);
          return failure.message;
        },
        (response) {
          isLoading.value = false;
          sharedBooking.value = response.data;

          final bookingData = {
            'bookingId': response.data?.bookingId,
            'userId': response.data?.customerId,
          };

          AppLogger.log.i("📤 Join booking data: $bookingData");
          final bookingId = (response.data?.bookingId ?? '').toString().trim();
          if (bookingId.isNotEmpty) {
            socketService.joinBookingRoom(
              bookingId: bookingId,
              payload: bookingData,
            );
          }

          AppLogger.log.i(response.data);
          return null;
        },
      );
    } catch (e) {
      isLoading.value = false;
      return 'An error occurred';
    }
  }

  Future<String?> sendDriverRequest({
    required double pickupLatitude,
    required double pickupLongitude,
    required double dropLatitude,
    required double dropLongitude,

    required String bookingId,
    required String carType,
    required BuildContext context,
  }) async {
    isRetryLoading.value = true;

    try {
      final safeBookingId = bookingId.trim();
      final hasValidCoords =
          pickupLatitude != 0.0 &&
          pickupLongitude != 0.0 &&
          dropLatitude != 0.0 &&
          dropLongitude != 0.0;

      if (safeBookingId.isEmpty || !hasValidCoords) {
        isRetryLoading.value = false;
        AppToasts.showError(
          context,
          'Invalid booking details. Please try again.',
        );
        AppLogger.log.e(
          'sendDriverRequest blocked: bookingId="$safeBookingId", '
          'pickup=($pickupLatitude,$pickupLongitude), drop=($dropLatitude,$dropLongitude), '
          'rideType=${rideType.value}',
        );
        return null;
      }

      final results =
          rideType.value == RideType.shared
              ? await sharedApiDatasource.sendSharedDriverRequest(
                carType: carType,
                pickupLatitude: pickupLatitude,
                pickupLongitude: pickupLongitude,
                dropLatitude: dropLatitude,
                dropLongitude: dropLongitude,
                bookingId: safeBookingId,
              )
              : await apiDataSource.sendDriverRequest(
                carType: carType,
                pickupLatitude: pickupLatitude,
                pickupLongitude: pickupLongitude,
                dropLatitude: dropLatitude,
                dropLongitude: dropLongitude,
                bookingId: safeBookingId,
              );

      return results.fold(
        (failure) {
          isRetryLoading.value = false;
          AppToasts.showError(context, failure.message);
          return null;
        },
        (response) {
          isRetryLoading.value = false;
          sendDriverRequestData.value = response.data;
          AppLogger.log.i(response.data);

          return 'success';
        },
      );
    } catch (e) {
      isRetryLoading.value = false;
      return 'An error occurred';
    }
  }

  Future<String?> cancelRide({
    required String bookingId,
    required String selectedReason,
    required BuildContext context,
  }) async {
    isCancelLoading.value = true;

    try {
      final results = await apiDataSource.cancelRide(
        selectedReason: selectedReason,
        bookingId: bookingId,
      );

      return results.fold(
        (failure) {
          isCancelLoading.value = false;
          AppLogger.log.e(failure.message);
          AppToasts.showError(
            context,
            failure.message,
            title: 'Cancellation Failed',
          );
          return failure.message;
        },
        (response) {
          isCancelLoading.value = false;
          sendDriverRequestData.value = response.data;
          AppLogger.log.i(response.data);
          final msg = response.message.trim();
          AppToasts.showSuccessGlobal(msg.isEmpty ? 'Booking cancelled' : msg);
          return '';
        },
      );
    } catch (e) {
      isCancelLoading.value = false;
      return 'An error occurred';
    }
  }

  Future<String?> rateDriver({
    required String bookingId,
    required String rating,
    required BuildContext context,
  }) async {
    isLoading.value = true;

    try {
      final results = await apiDataSource.starRating(
        selectedReason: rating,
        bookingId: bookingId,
      );

      return results.fold(
        (failure) {
          isLoading.value = false;
          AppLogger.log.e(failure.message);
          AppToasts.showError(context, failure.message);
          // Navigator.pushReplacement(
          //   context,
          //   MaterialPageRoute(
          //     builder: (context) => CommonBottomNavigation(initialIndex: 0),
          //   ),
          // );
          return failure.message;
        },
        (response) {
          isLoading.value = false;
          sendDriverRequestData.value = response.data;
          AppLogger.log.i(response.data);

          return '';
        },
      );
    } catch (e) {
      isLoading.value = false;
      return 'An error occurred';
    }
  }

  Future<bool> noDriverFound({
    required String bookingId,
    required bool status,
    required BuildContext context,
  }) async {
    isLoading.value = true;

    try {
      final results = await apiDataSource.noDriverFound(
        status: status,
        bookingId: bookingId,
      );

      return results.fold(
        (failure) {
          isLoading.value = false;
          return false;
        },
        (response) {
          isLoading.value = false;

          sendDriverRequestData.value = response.data;
          final totalDrivers =
              int.tryParse(
                sendDriverRequestData.value?.driversNotified.toString() ?? '0',
              ) ??
              0;

          AppLogger.log.i("Total Drivers Found: $totalDrivers");

          // ✅ Return TRUE only if there are drivers found
          return totalDrivers > 0;
        },
      );
    } catch (e) {
      isLoading.value = false;
      AppLogger.log.e("NoDriverFound Error: $e");
      return false;
    }
  }

  void clearState() {}
}

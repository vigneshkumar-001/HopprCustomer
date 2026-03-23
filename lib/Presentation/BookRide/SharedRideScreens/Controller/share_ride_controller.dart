import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:hopper/Core/Utility/app_toasts.dart';
import 'package:hopper/Presentation/BookRide/Models/create_booking_model.dart';
import 'package:hopper/Presentation/BookRide/Models/driver_search_models.dart';
import 'package:hopper/Presentation/BookRide/Models/send_driver_request_models.dart';
import 'package:hopper/Presentation/BookRide/Models/shared_create_booking_response.dart';
import 'package:hopper/Presentation/BookRide/Models/shared_driver_search_response.dart';
 
 
import 'package:hopper/Presentation/OnBoarding/Widgets/custom_bottomnavigation.dart';
import 'package:hopper/api/dataSource/shared_api_datasource.dart';
import 'package:hopper/api/repository/api_consents.dart';
import 'package:hopper/uitls/websocket/shared_web_socket.dart';

class ShareRideController extends GetxController {
  final rideShareSocket = RideShareSocketService();
  Rxn<SharedDriverData> selectedSharedDriver = Rxn<SharedDriverData>();
  RxBool isLoading = false.obs;
  Rxn<BookingDriverData> sendDriverRequestData = Rxn<BookingDriverData>();
  Rxn<SharedBookingData> sharedBooking = Rxn<SharedBookingData>();
  @override
  void onInit() {
    super.onInit();
  }

  SharedApiDatasource sharedApiDatasource = SharedApiDatasource();
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
          AppToasts.showError(context,failure.message);
          return failure.message;
        },
        (response) {
          isLoading.value = false;
          sharedBooking.value = response.data;

          final bookingId = response.data?.bookingId;
          final customerId = response.data?.customerId;

          if (bookingId == null || customerId == null) {
            AppLogger.log.e("❌ Missing bookingId/customerId");
            return "Invalid booking data";
          }


          // Socket is expected to be connected from Home; fallback connect if needed.
          if (!rideShareSocket.connected) {
            rideShareSocket.initSocket(ApiConsents.sharedBaseUrl);
          }


          rideShareSocket.registerUser(customerId, bookingId: bookingId);


          rideShareSocket.setBooking(bookingId);

          AppLogger.log.i(
            "✅ Shared Booking setup → user=$customerId, booking=$bookingId",
          );

          return null; // success
        },
      );
    } catch (e, stack) {
      isLoading.value = false;
      AppLogger.log.e("❗ createSharedBooking error: $e");
      AppLogger.log.e(stack.toString());
      return 'An error occurred';
    }
  }

  Future<String?> sendSharedDriverRequest({
    required double pickupLatitude,
    required double pickupLongitude,
    required double dropLatitude,
    required double dropLongitude,

    required String bookingId,
    required String carType,
    required BuildContext context,
  }) async {
    isLoading.value = true;

    try {
      final results = await sharedApiDatasource.sendSharedDriverRequest(
        carType: carType,

        pickupLatitude: pickupLatitude,
        pickupLongitude: pickupLongitude,
        dropLatitude: dropLatitude,
        dropLongitude: dropLongitude,
        bookingId: bookingId,
      );

      return results.fold(
        (failure) {
          isLoading.value = false;
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
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hopper/Core/Consents/app_colors.dart';
import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:get/get.dart';
import 'package:hopper/Core/Utility/app_toasts.dart';
import 'package:hopper/Presentation/OnBoarding/Screens/payment_screen.dart';
import 'package:hopper/Presentation/OnBoarding/models/address_models.dart';
import 'package:hopper/Presentation/OnBoarding/models/confrom_package_response.dart';
import 'package:hopper/Presentation/OnBoarding/models/coupen_response.dart';
import 'package:hopper/Presentation/OnBoarding/models/package_details_response.dart';
import 'package:hopper/api/dataSource/apiDataSource.dart';

import '../../../uitls/websocket/socket_io_client.dart';
import '../../Drawer/controller/ride_history_controller.dart';
import '../Screens/package_map_confrim_screen.dart';

class PackageController extends GetxController {
  final ApiDataSource apiDataSource = ApiDataSource();
  final RxBool isLoading = false.obs;
  final socketService = SocketService();
  final RxBool isConfirmLoading = false.obs;
  RxString frontImageUrl = ''.obs;
  final RxBool isButtonLoading = false.obs;
  var packageDetails = Rxn<PackageDetailsResponse>();
  var confirmPackageDetails = Rxn<ConfirmPackageResponse>();
  RideHistoryController get controller {
    if (Get.isRegistered<RideHistoryController>()) {
      return Get.find<RideHistoryController>();
    }
    return Get.put(RideHistoryController(), permanent: true);
  }

  Future<bool> paymentDetails({
    required String bookingId,
    required String paymentType,
    required BuildContext context,
  }) async {
    isButtonLoading.value = true;

    try {
      final results = await apiDataSource.paymentDetails(
        paymentType: paymentType,
        bookingId: bookingId,
      );

      return results.fold(
        (failure) {
          AppToasts.showErrorGlobal(failure.message, title: "Error");

          isButtonLoading.value = false;
          return false;
        },
        (response) {
          isButtonLoading.value = false;

          return true;
        },
      );
    } catch (e) {
      isButtonLoading.value = false;
      return false;
    }
  }

  Future<String?> packageAddressDetails({
    required AddressModel senderData,
    required AddressModel receiverData,
    required String weight,
    required String selectedParcel,
    required String description,
    required String deliveryInstruction,
  }) async {
    try {
      isLoading.value = true;
      final results = await apiDataSource.packageAddressDetails(
        deliveryInstruction: deliveryInstruction,
        description: description,
        receiverData: receiverData,
        senderData: senderData,
        weight: weight,
        selectedParcel: selectedParcel,
      );
      return results.fold(
        (failure) {
          isLoading.value = false;
          // Surface a clear message instead of silently failing (the server can
          // return a 500 on create-booking). Prefer the server's message when it
          // is meaningful; otherwise a friendly fallback. Return null so the
          // screen does NOT navigate forward on a failed booking.
          final raw = failure.message.trim();
          final friendly =
              (raw.isEmpty || raw == 'Something went wrong')
                  ? 'Could not create your booking right now. Please try again.'
                  : raw;
          AppToasts.showErrorGlobal(friendly, title: 'Booking failed');
          return null;
        },
        (response) {
          isLoading.value = false;
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

           isLoading.value = false;
           packageDetails.value = response;
           AppLogger.log.i("Package Details  == ${packageDetails.value}");
          return response.data.toString();
        },
      );
    } catch (e) {
      isLoading.value = false;
      AppLogger.log.e(e);
      AppToasts.showErrorGlobal(
        'Could not create your booking right now. Please try again.',
        title: 'Booking failed',
      );
    }
    return null;
  }

  Future<String?> confirmPackageAddressDetails({
    required String bookingId,
    required String weight,
    required AddressModel senderData,
    required AddressModel receiverData,
  }) async {
    try {
      isConfirmLoading.value = true;
      final results = await apiDataSource.confirmPackageScreen(
        bookingId: bookingId,
      );
      return results.fold(
        (failure) {
          isConfirmLoading.value = false;
          AppLogger.log.e("Failure: $failure");
          return '';
        },
        (response) {
          isConfirmLoading.value = false;
          confirmPackageDetails.value = response;
          final double amount = response.data.amount;
          final String bookingId = response.data.bookingId;
          AppLogger.log.i(' ${amount},${bookingId}');

          Get.to(
            PaymentScreen(
              amount: amount,
              bookingId: bookingId,
              sender: senderData,
              receiver: receiverData,
            ),
          );
          // Navigator.push(
          //   context,
          //   MaterialPageRoute(builder: (context) => PaymentScreen()),
          // );
          AppLogger.log.i('confirm = ${confirmPackageDetails.value?.toJson()}');

          return response.data.toString();
        },
      );
    } catch (e) {
      isConfirmLoading.value = false;
      AppLogger.log.e(e);
    }
    return null;
  }

  Future<String?> sendPackageDriverRequest({
    required String bookingId,
    required String discountCode,

    required AddressModel senderData,
    required AddressModel receiverData,
  }) async {
    // Guard: without a bookingId the request 500s on the server and the user
    // would otherwise see nothing happen. Fail fast with a clear message.
    if (bookingId.trim().isEmpty) {
      AppToasts.showErrorGlobal(
        'Something went wrong with your booking. Please go back and try again.',
        title: 'Booking failed',
      );
      return null;
    }
    try {
      isConfirmLoading.value = true;
      final results = await apiDataSource.sendPackageDriverRequest(
        discountCode: discountCode,
        bookingId: bookingId,
        receiverData: receiverData,
        senderData: senderData,
      );
      return results.fold(
        (failure) {
          isConfirmLoading.value = false;
          AppLogger.log.e("Failure: $failure");
          // Surface the failure instead of silently doing nothing.
          final raw = failure.message.trim();
          final friendly =
              (raw.isEmpty || raw == 'Something went wrong')
                  ? 'Could not confirm your booking right now. Please try again.'
                  : raw;
          AppToasts.showErrorGlobal(friendly, title: 'Booking failed');
          return null;
        },
        (response) {
          isConfirmLoading.value = false;
          Get.to(
            PackageMapConfirmScreen(
              bookingId: bookingId,
              discountCode: discountCode,
              senderData: senderData,
              receiverData: receiverData,
            ),
          );
          AppLogger.log.i('${response.data}');

          return response.data.toString();
        },
      );
    } catch (e) {
      isConfirmLoading.value = false;
      AppLogger.log.e(e);
      AppToasts.showErrorGlobal(
        'Could not confirm your booking right now. Please try again.',
        title: 'Booking failed',
      );
    }
    return null;
  }

  Future<String?> submitProfileData({
    required String bookingId,

    File? frontImageFile,

    BuildContext? context,
  }) async {
    try {
      isLoading.value = true;
      String? frontImageUrl;

      if (frontImageFile != null) {
        final frontResult = await apiDataSource.userProfileUpload(
          imageFile: frontImageFile,
        );

        frontImageUrl = frontResult.fold((failure) {
          AppLogger.log.e("Front Upload Failed: ${failure.message}");
          if (context != null) {
            AppToasts.customToast(context, failure.message);
          } else {
            AppToasts.showError(context!,failure.message);
          }
          return null;
        }, (success) => success.message);

        if (frontImageUrl == null) {
          isLoading.value = false;
          return null;
        }
      } else {
        frontImageUrl = this.frontImageUrl.value;
      }

      final results = await apiDataSource.customerBookingImage(
        bookingId: bookingId,
        imageUrl: frontImageUrl,
      );

      return results.fold(
        (failure) {
          isLoading.value = false;
          if (context != null) {
            AppToasts.customToast(context, failure.message);
          } else {
            AppToasts.showError(context!,failure.message);
          }
          AppLogger.log.e("Failure: $failure");

          return null;
        },
        (response) {
          isLoading.value = false;
          AppLogger.log.i("Success: ${response.message}");
          return response.message;
        },
      );
    } catch (e) {
      isLoading.value = false;
      AppLogger.log.e(e);
      return null;
    }
  }

  Future<CouponResponse?> applyCoupon({
    required String code,
    required BuildContext context,
    required String bookingId,
    required String actionType,
  }) async {
    isLoading.value = true;

    try {
      final result = await apiDataSource.applyCoupon(
        code: code,
        bookingId: bookingId,
        actionType: actionType,
      );

      return result.fold(
        (failure) {
          isLoading.value = false;
          AppLogger.log.e("Failed: ${failure.message}");
          AppToasts.showError(context,failure.message);
          return null; // <-- always return a consistent type
        },
        (response) {
          isLoading.value = false;
          AppLogger.log.i("Success: ${response.message}");
          AppToasts.showSuccess(context,response.message ?? 'Coupon applied');
          return response; // <-- return proper CouponResponse
        },
      );
    } catch (e, stack) {
      isLoading.value = false;
      AppLogger.log.e("Coupon error: $e\n$stack");
      AppToasts.customToast(
        Get.context!,
        'An error occurred while applying coupon',
      );
      return null;
    }
  }
}






import 'dart:io';

import 'package:flutter/material.dart';
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

/// Centralized UI state for the parcel PAYMENT SCREEN specifically (not the
/// booking flow at large) — single source of truth for what the bottom
/// action button shows/does, replacing 4 independent per-tile loading
/// booleans that used to live on the screen itself.
enum ParcelPaymentUiState {
  idle,
  methodSelected,
  confirmingCash,
  initializingOnlinePayment,
  awaitingPayment,
  verifyingPayment,
  dispatching,
  success,
  failed,
}

class PackageController extends GetxController {
  final ApiDataSource apiDataSource = ApiDataSource();
  final RxBool isLoading = false.obs;
  final socketService = SocketService();
  final RxBool isConfirmLoading = false.obs;
  RxString frontImageUrl = ''.obs;
  final RxBool isButtonLoading = false.obs;
  var packageDetails = Rxn<PackageDetailsResponse>();
  var confirmPackageDetails = Rxn<ConfirmPackageResponse>();

  /// ---- Package delivery trust (Phase 3): sender-only Pickup OTP ----
  /// Held in memory ONLY — never persisted (no SharedPreferences/GetStorage)
  /// and never logged. Cleared as soon as pickup is verified or the tracking
  /// screen is left. Backend (the Phase 1 sender-only endpoint) is the sole
  /// source of truth for the value; nothing here is locally generated.
  final RxString pickupOtp = ''.obs;
  final RxBool pickupOtpLoading = false.obs;
  final RxString pickupOtpError = ''.obs;
  final RxBool pickupOtpAvailable = false.obs;

  /// Fetch the sender's Pickup OTP for [bookingId]. Safe to call repeatedly
  /// (e.g. on resume) — a 409 (already verified / past pre-pickup status) is
  /// treated as "nothing to show", not a user-facing error.
  Future<void> fetchSenderPickupOtp(String bookingId) async {
    if (bookingId.trim().isEmpty || pickupOtpLoading.value) return;
    pickupOtpLoading.value = true;
    pickupOtpError.value = '';
    try {
      final result = await apiDataSource.getParcelPickupOtp(
        bookingId: bookingId,
      );
      result.fold(
        (failure) {
          pickupOtp.value = '';
          pickupOtpAvailable.value = false;
          // A 409 ("not available right now") is expected once pickup moves
          // on — don't surface it as an error the sender needs to act on.
          pickupOtpError.value = '';
        },
        (data) {
          final code = (data['otp'] ?? '').toString().trim();
          pickupOtp.value = code;
          pickupOtpAvailable.value =
              data['otpAvailable'] == true && code.isNotEmpty;
        },
      );
    } catch (_) {
      pickupOtp.value = '';
      pickupOtpAvailable.value = false;
    } finally {
      pickupOtpLoading.value = false;
    }
  }

  /// Clear the raw Pickup OTP from memory — called once pickup is verified
  /// (local or via socket) and whenever the sender leaves the eligible
  /// tracking flow (screen dispose).
  void clearPickupOtpFromMemory() {
    pickupOtp.value = '';
    pickupOtpAvailable.value = false;
    pickupOtpError.value = '';
  }

  /// ---- Receiver Tracking + WhatsApp Share MVP ----
  /// Sender-authorized share payload (tracking link, pre-filled message,
  /// Delivery OTP while eligible). Held in memory only, same treatment as
  /// the Pickup OTP above — never persisted, never logged.
  final Rxn<Map<String, dynamic>> shareDetails = Rxn<Map<String, dynamic>>();
  final RxBool shareDetailsLoading = false.obs;
  final RxString shareDetailsError = ''.obs;

  /// Fetch the sender's share payload for [bookingId]. Safe to call
  /// repeatedly (e.g. on resume/reconnect) — a 409 (pickup not verified yet)
  /// is treated as "nothing to show", not a user-facing error.
  Future<void> fetchParcelShareDetails(String bookingId) async {
    if (bookingId.trim().isEmpty || shareDetailsLoading.value) return;
    shareDetailsLoading.value = true;
    shareDetailsError.value = '';
    try {
      final result = await apiDataSource.getParcelShareDetails(
        bookingId: bookingId,
      );
      result.fold(
        (failure) {
          shareDetails.value = null;
          shareDetailsError.value = failure.message;
        },
        (data) {
          shareDetails.value = data;
          shareDetailsError.value = '';
        },
      );
    } catch (_) {
      shareDetails.value = null;
      shareDetailsError.value = 'Something went wrong';
    } finally {
      shareDetailsLoading.value = false;
    }
  }

  /// Clear the share payload from memory — called on screen dispose and
  /// whenever the sender leaves the eligible tracking flow.
  void clearShareDetailsFromMemory() {
    shareDetails.value = null;
    shareDetailsError.value = '';
    shareDetailsLoading.value = false;
  }

  /// ---- Parcel payment ----
  /// Deliberately separate from paymentDetails() (car-ride) — never touches
  /// driverSearchController or the car-ride payment endpoint.
  final RxBool parcelPaymentLoading = false.obs;
  final RxString parcelPaymentError = ''.obs;

  /// Drives PackagePaymentScreen's single bottom action button + tile
  /// enablement. See [ParcelPaymentUiState] for the full state list.
  final Rx<ParcelPaymentUiState> parcelPaymentUiState =
      ParcelPaymentUiState.idle.obs;
  final Rxn<String> selectedParcelPaymentMethod = Rxn<String>();

  /// Non-toast status/error text for the payment screen — e.g. a failed
  /// dispatch-after-payment message that should stay visible until retried,
  /// not just flash as a toast.
  final RxString parcelPaymentStatusMessage = ''.obs;

  /// Full reset for a fresh entry into the payment screen — called from the
  /// screen's dispose() so a previous booking's selection/error never leaks
  /// into the next one.
  void resetParcelPaymentFlow() {
    parcelPaymentUiState.value = ParcelPaymentUiState.idle;
    selectedParcelPaymentMethod.value = null;
    parcelPaymentStatusMessage.value = '';
    parcelPaymentError.value = '';
  }

  final RxBool parcelOnlinePaymentInitLoading = false.obs;

  /// Starts a Paystack checkout for a parcel booking — call only AFTER
  /// [payParcelBooking] has recorded the PAYSTACK intent. Returns the raw
  /// backend body (`authorization_url`, ...) or null on failure (message in
  /// [parcelPaymentError]).
  Future<Map<String, dynamic>?> initParcelPaystackPayment({
    required String bookingId,
    required String email,
  }) async {
    parcelOnlinePaymentInitLoading.value = true;
    parcelPaymentError.value = '';
    try {
      final result = await apiDataSource.initPaystackPayment(
        bookingId: bookingId,
        email: email,
      );
      return result.fold((failure) {
        parcelPaymentError.value = failure.message;
        return null;
      }, (data) => data);
    } catch (e) {
      AppLogger.log.e(e);
      parcelPaymentError.value = 'Something went wrong';
      return null;
    } finally {
      parcelOnlinePaymentInitLoading.value = false;
    }
  }

  /// Starts a Flutterwave checkout for a parcel booking. See
  /// [initParcelPaystackPayment] for the calling contract.
  Future<Map<String, dynamic>?> initParcelFlutterwavePayment({
    required String bookingId,
    required double amount,
    required String email,
    required String name,
    required String phone,
  }) async {
    parcelOnlinePaymentInitLoading.value = true;
    parcelPaymentError.value = '';
    try {
      final result = await apiDataSource.initFlutterwavePayment(
        bookingId: bookingId,
        amount: amount,
        email: email,
        name: name,
        phone: phone,
      );
      return result.fold((failure) {
        parcelPaymentError.value = failure.message;
        return null;
      }, (data) => data);
    } catch (e) {
      AppLogger.log.e(e);
      parcelPaymentError.value = 'Something went wrong';
      return null;
    } finally {
      parcelOnlinePaymentInitLoading.value = false;
    }
  }

  /// paymentType ∈ {PAYSTACK, FLUTTERWAVE, WALLET, CASH}. Returns the
  /// backend's data map on success (`parcelPaymentStatus` tells the caller
  /// what happened: PAID / CASH_PENDING / PENDING), or null on failure
  /// (error message left in [parcelPaymentError]).
  Future<Map<String, dynamic>?> payParcelBooking({
    required String bookingId,
    required String paymentType,
  }) async {
    parcelPaymentLoading.value = true;
    parcelPaymentError.value = '';
    try {
      final result = await apiDataSource.payParcelBooking(
        bookingId: bookingId,
        paymentType: paymentType,
      );
      return result.fold(
        (failure) {
          parcelPaymentError.value = failure.message;
          parcelPaymentLoading.value = false;
          return null;
        },
        (data) {
          parcelPaymentLoading.value = false;
          return data;
        },
      );
    } catch (e) {
      AppLogger.log.e(e);
      parcelPaymentError.value = 'Something went wrong';
      parcelPaymentLoading.value = false;
      return null;
    }
  }

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

  /// Dispatches the booking to nearby drivers. For Parcel bookings the
  /// backend rejects this (409, dispatchEligible=false) until a payment plan
  /// has been confirmed via payParcelBooking — so callers must only invoke
  /// this AFTER that succeeds. Does NOT navigate — the caller (PaymentScreen
  /// for parcels) owns navigation since it knows the full post-payment flow.
  Future<bool> sendPackageDriverRequest({
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
      return false;
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
                  ? 'Could not request a courier right now. Please try again.'
                  : raw;
          AppToasts.showErrorGlobal(friendly, title: 'Courier request failed');
          return false;
        },
        (response) {
          isConfirmLoading.value = false;
          AppLogger.log.i('${response.data}');
          final state = response.data.dispatchStatus.trim().toUpperCase();
          final acceptedState =
              state == 'SEARCHING' || state == 'OFFERED' || state == 'ASSIGNED';
          if (!response.data.dispatchAccepted || !acceptedState) {
            AppToasts.showErrorGlobal(
              'Courier search could not be started. Please try again.',
              title: 'Courier request failed',
            );
            return false;
          }
          return true;
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
    return false;
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
            AppToasts.showError(context!, failure.message);
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
            AppToasts.showError(context!, failure.message);
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
          AppToasts.showError(context, failure.message);
          return null; // <-- always return a consistent type
        },
        (response) {
          isLoading.value = false;
          AppLogger.log.i("Success: ${response.message}");
          AppToasts.showSuccess(context, response.message ?? 'Coupon applied');
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

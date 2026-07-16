import 'dart:convert';
import 'dart:io';

import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:hopper/Presentation/Authentication/models/login_response.dart';
import 'package:hopper/Presentation/Authentication/models/otp_response.dart';
import 'package:hopper/Presentation/Authentication/models/sos_response.dart';
import 'package:hopper/Presentation/BookRide/Models/create_booking_model.dart';
import 'package:hopper/Presentation/BookRide/Models/driver_search_models.dart';
import 'package:hopper/Presentation/BookRide/Models/payment_response.dart';
import 'package:hopper/Presentation/BookRide/Models/active_booking_response.dart';
import 'package:hopper/Presentation/BookRide/Models/send_driver_request_models.dart';
import 'package:hopper/Presentation/Drawer/models/notification_response.dart';
import 'package:hopper/Presentation/Drawer/models/profile_response.dart';
import 'package:hopper/Presentation/Drawer/models/ride_history_response.dart';
import 'package:hopper/Presentation/Drawer/models/user_submit_response.dart';
import 'package:hopper/Presentation/OnBoarding/models/address_models.dart';
import 'package:hopper/Presentation/OnBoarding/models/chat_history_response.dart';
import 'package:hopper/Presentation/OnBoarding/models/confrom_package_response.dart';
import 'package:hopper/Presentation/OnBoarding/models/coupen_response.dart';
import 'package:hopper/Presentation/OnBoarding/models/package_details_response.dart';
import 'package:hopper/Presentation/OnBoarding/models/ride_receipt_response.dart';
import 'package:hopper/Presentation/CustomerSupport/models/customer_support_models.dart';
import 'package:hopper/Presentation/wallet/model/get_wallet_balance_response.dart';
import 'package:hopper/Presentation/wallet/model/transaction_response.dart';
import 'package:hopper/Presentation/wallet/model/wallet_response.dart';
import 'package:hopper/api/repository/api_consents.dart';
import 'package:hopper/api/repository/request.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../Presentation/OnBoarding/models/send_package_driver_response.dart';
import '../../Presentation/OnBoarding/models/user_image_models.dart';
import '../repository/failure.dart';
import 'package:dio/dio.dart';
import 'package:dartz/dartz.dart';

typedef SupportCommonDetailsResult =
    Either<Failure, SupportCommonDetailsResponse>;
typedef SupportMyTicketsResult = Either<Failure, SupportMyTicketsResponse>;
typedef SupportCreateTicketResult =
    Either<Failure, SupportCreateTicketResponse>;
typedef SupportMyTicketDetailsResult =
    Either<Failure, SupportTicketDetailsResponse>;
typedef SupportSendMessageResult = Either<Failure, SupportSendMessageResponse>;

abstract class BaseApiDataSource {
  Future<Either<Failure, LoginResponse>> mobileNumberLogin(
    String mobileNumber,
    String countryCode,
  );
}

class ApiDataSource extends BaseApiDataSource {
  @override
  Future<Either<Failure, LoginResponse>> mobileNumberLogin(
    String mobileNumber,
    String countryCode,
  ) async {
    try {
      String url = ApiConsents.signIn;
      final String phone = countryCode + mobileNumber;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('phone', mobileNumber);
      dynamic response = await Request.sendRequest(
        url,
        {"phone": mobileNumber, 'countryCode': countryCode},
        'Post',
        false,
      );
      if (response is! DioException && response.statusCode == 200) {
        if (response.data['status'] == 200) {
          return Right(LoginResponse.fromJson(response.data));
        } else {
          return Left(ServerFailure(response.data['message']));
        }
      } else {
        return Left(ServerFailure((response as DioException).message ?? ""));
      }
    } catch (e, st) {
      AppLogger.log.e("ERROR: $e\n$st");
      return Left(ServerFailure("$e"));
    }
  }

  Future<Either<Failure, OtpResponse>> otpVerify(
    String mobileNumber,
    String otp,
  ) async {
    try {
      String url = ApiConsents.verifyOtp;

      dynamic response = await Request.sendRequest(
        url,
        {"phone": mobileNumber, "otp": otp},
        'Post',
        false,
      );
      if (response is! DioException && response.statusCode == 200) {
        if (response.data['status'] == 200) {
          return Right(OtpResponse.fromJson(response.data));
        } else {
          return Left(ServerFailure(response.data['message']));
        }
      } else {
        return Left(ServerFailure((response as DioException).message ?? ""));
      }
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure("$e"));
    }
  }

  Future<Either<Failure, LoginResponse>> resendOtp(
    String mobileNumber,
    String countryCode,
  ) async {
    try {
      String url = ApiConsents.resendOtp;
      final String phone = countryCode + mobileNumber;
      AppLogger.log.i(phone);
      dynamic response = await Request.sendRequest(
        url,
        {"phone": phone},

        'Post',
        false,
      );
      if (response is! DioException && response.statusCode == 200) {
        if (response.data['status'] == 200) {
          return Right(LoginResponse.fromJson(response.data));
        } else {
          return Left(ServerFailure(response.data['message']));
        }
      } else {
        return Left(ServerFailure((response as DioException).message ?? ""));
      }
    } catch (e) {
      return Left(ServerFailure(''));
    }
  }

  Future<Either<Failure, DriverSearchModels>> getDriverSearch({
    required double pickupLat,
    required double pickupLng,
    required double dropLat,
    required double dropLng,
  }) async {
    try {
      final url = ApiConsents.driverSearch(
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        dropLat: dropLat,
        dropLng: dropLng,
      );
      AppLogger.log.i(url);

      dynamic response = await Request.sendGetRequest(url, {}, 'GET', true);

      if (response.statusCode == 200) {
        if (response.data['status'] == 200) {
          return Right(DriverSearchModels.fromJson(response.data));
        } else {
          return Left(
            ServerFailure(response.data['message'] ?? "Login failed"),
          );
        }
      } else if (response is Response) {
        return Left(
          ServerFailure(response.data['message'] ?? "Unexpected error"),
        );
      } else {
        return Left(ServerFailure("Unknown error occurred"));
      }
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Something went wrong'));
    }
  }

  Future<Either<Failure, CreateBookingModel>> carBookingCar({
    required double fromLatitude,
    required double fromLongitude,
    required double toLatitude,
    required double toLongitude,
    required String customerId,
    required String carType,
  }) async {
    try {
      final url = ApiConsents.createBooking;
      AppLogger.log.i(url);

      dynamic response = await Request.sendRequest(
        url,
        {
          "fromLatitude": fromLatitude,
          "fromLongitude": fromLongitude,
          "toLatitude": toLatitude,
          "toLongitude": toLongitude,
          "sharedBooking": false,
          "sharedCount": 1,
          "carType": carType,
        },
        'Post',
        false,
      );
      AppLogger.log.i(response);
      if (response.statusCode == 200) {
        if (response.data['status'] == 200) {
          return Right(CreateBookingModel.fromJson(response.data));
        } else {
          return Left(ServerFailure(response.data['message'] ?? " "));
        }
      } else if (response is Response) {
        return Left(
          ServerFailure(response.data['message'] ?? "Unexpected error"),
        );
      } else {
        return Left(ServerFailure("Unknown error occurred"));
      }
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Something went wrong'));
    }
  }

  /// Customer-initiated resend of the start-trip OTP (Ride/Parcel).
  /// Returns the response body on success (carries `message`, `nextResendInSec`,
  /// `attemptsLeft`); a Left with the server message otherwise (cooldown/limit).
  Future<Either<Failure, Map<String, dynamic>>> resendRideOtp(
    String bookingId,
  ) async {
    try {
      final response = await Request.sendRequest(
        ApiConsents.resendRideOtp,
        {'bookingId': bookingId},
        'POST',
        true,
      );
      final data =
          (response is Response && response.data is Map)
              ? Map<String, dynamic>.from(response.data as Map)
              : <String, dynamic>{};
      if (response is Response && (response.statusCode ?? 0) == 200) {
        return Right(data);
      }
      return Left(
        ServerFailure((data['message'] ?? 'Could not resend OTP').toString()),
      );
    } on DioException catch (e) {
      final d = e.response?.data;
      final msg =
          (d is Map && d['message'] != null)
              ? d['message'].toString()
              : 'Could not resend OTP';
      return Left(ServerFailure(msg));
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Something went wrong'));
    }
  }

  /// Package delivery trust (Phase 1): sender-only Pickup OTP retrieval.
  /// Returns `{otp, otpAvailable, expiresAt, verified}` on 200 — `otp` is
  /// null on a process-local cache miss. A 409 means "not available right
  /// now" (already verified / past pre-pickup status) — not a real error,
  /// callers should treat it as "hide the card", not show an error toast.
  Future<Either<Failure, Map<String, dynamic>>> getParcelPickupOtp({
    required String bookingId,
  }) async {
    try {
      final url = ApiConsents.parcelPickupOtp(bookingId);
      final response = await Request.sendGetRequest(url, {}, 'GET', true);

      if (response is Response && response.statusCode == 200) {
        final body = response.data;
        final data =
            (body is Map && body['data'] is Map)
                ? Map<String, dynamic>.from(body['data'] as Map)
                : <String, dynamic>{};
        return Right(data);
      } else if (response is Response) {
        return Left(
          ServerFailure(
            (response.data is Map ? response.data['message'] : null)
                    ?.toString() ??
                'Pickup OTP is not available right now',
          ),
        );
      }
      return Left(ServerFailure('Unexpected error'));
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Something went wrong'));
    }
  }

  /// Parcel payment — deliberately separate from paymentDetails() (car-ride).
  /// paymentType ∈ {PAYSTACK, FLUTTERWAVE, WALLET, CASH}. Returns the
  /// backend's `data` map on success: WALLET/CASH resolve synchronously
  /// (`parcelPaymentStatus: PAID` / `CASH_PENDING`); PAYSTACK/FLUTTERWAVE only
  /// record intent (`parcelPaymentStatus: PENDING`) — the caller still needs
  /// to open the existing generic gateway-checkout flow (same one car-ride
  /// payment uses) to actually collect the money.
  Future<Either<Failure, Map<String, dynamic>>> payParcelBooking({
    required String bookingId,
    required String paymentType,
  }) async {
    try {
      final url = ApiConsents.parcelPay;
      final response = await Request.sendRequest(
        url,
        {"bookingId": bookingId, "paymentType": paymentType},
        'Post',
        false,
      );
      if (response is Response && response.statusCode == 200) {
        final body = response.data;
        if (body is Map && body['success'] == true) {
          final data =
              (body['data'] is Map)
                  ? Map<String, dynamic>.from(body['data'] as Map)
                  : <String, dynamic>{};
          return Right(data);
        }
        return Left(
          ServerFailure(
            (body is Map ? body['message'] : null)?.toString() ??
                'Payment failed',
          ),
        );
      } else if (response is Response) {
        return Left(
          ServerFailure(
            (response.data is Map ? response.data['message'] : null)
                    ?.toString() ??
                'Payment failed',
          ),
        );
      }
      return Left(ServerFailure('Unexpected error'));
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Something went wrong'));
    }
  }

  /// Starts a Paystack checkout for the given booking (parcel or ride — the
  /// endpoint is generic, keyed on `userBookingId`). Returns the raw backend
  /// body on success (`authorization_url`, `reference`, ...) so the caller
  /// can open it in a WebView. Goes through the shared `Request` helper
  /// (auth header attached automatically) instead of a raw `http.post` with
  /// a hardcoded base URL.
  Future<Either<Failure, Map<String, dynamic>>> initPaystackPayment({
    required String bookingId,
    required String email,
  }) async {
    try {
      final response = await Request.sendRequest(
        ApiConsents.paystackInit,
        {"userBookingId": bookingId, "email": email},
        'Post',
        true,
      );
      if (response is Response) {
        final body = response.data;
        if (response.statusCode == 200 &&
            body is Map &&
            body['authorization_url'] != null) {
          return Right(Map<String, dynamic>.from(body as Map));
        }
        return Left(
          ServerFailure(
            (body is Map ? body['message'] : null)?.toString() ??
                'Failed to initialize payment',
          ),
        );
      }
      return Left(ServerFailure('Unexpected error'));
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Something went wrong'));
    }
  }

  /// Starts a Flutterwave checkout for the given booking. Same shape as
  /// [initPaystackPayment] — see its doc comment.
  Future<Either<Failure, Map<String, dynamic>>> initFlutterwavePayment({
    required String bookingId,
    required double amount,
    required String email,
    required String name,
    required String phone,
  }) async {
    try {
      final response = await Request.sendRequest(
        ApiConsents.flutterwaveInitialize,
        {
          "userBookingId": bookingId,
          "amount": amount.toString(),
          "email": email,
          "name": name,
          "phone": phone,
        },
        'Post',
        true,
      );
      if (response is Response) {
        final body = response.data;
        if (response.statusCode == 200 &&
            body is Map &&
            body['paymentLink'] != null) {
          return Right(Map<String, dynamic>.from(body as Map));
        }
        return Left(
          ServerFailure(
            (body is Map ? body['message'] : null)?.toString() ??
                'Failed to initialize payment',
          ),
        );
      }
      return Left(ServerFailure('Unexpected error'));
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Something went wrong'));
    }
  }

  /// Receiver Tracking + WhatsApp Share MVP: sender-authorized share payload.
  /// Returns `{receiverName, normalizedReceiverPhone, publicPackageId,
  /// trackingUrl, deliveryOtp, message, expiresAt}` on 200. `deliveryOtp` is
  /// null once delivery is verified or the package is delivered. A 409 means
  /// "not available yet" (pickup not verified) — callers should hide the
  /// share card, not show an error toast.
  Future<Either<Failure, Map<String, dynamic>>> getParcelShareDetails({
    required String bookingId,
  }) async {
    try {
      final url = ApiConsents.parcelShareDetails(bookingId);
      final response = await Request.sendGetRequest(url, {}, 'GET', true);

      if (response is Response && response.statusCode == 200) {
        final body = response.data;
        final data =
            (body is Map && body['data'] is Map)
                ? Map<String, dynamic>.from(body['data'] as Map)
                : <String, dynamic>{};
        return Right(data);
      } else if (response is Response) {
        return Left(
          ServerFailure(
            (response.data is Map ? response.data['message'] : null)
                    ?.toString() ??
                'Share details are not available right now',
          ),
        );
      }
      return Left(ServerFailure('Unexpected error'));
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Something went wrong'));
    }
  }

  Future<Either<Failure, ActiveBookingResponse>> getActiveBooking() async {
    try {
      final url = ApiConsents.activeBooking;
      AppLogger.log.i(url);

      final response = await Request.sendGetRequest(url, {}, 'GET', true);

      if (response != null && response.statusCode == 200) {
        return Right(ActiveBookingResponse.fromJson(response.data));
      } else if (response is Response) {
        return Left(
          ServerFailure(response.data['message'] ?? 'Unexpected error'),
        );
      } else {
        return Left(ServerFailure('Unknown error occurred'));
      }
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Something went wrong'));
    }
  }

  Future<Either<Failure, SendDriverRequestModels>> sendDriverRequest({
    required double pickupLatitude,
    required double pickupLongitude,
    required double dropLatitude,
    required double dropLongitude,
    required String bookingId,
    required String carType,
  }) async {
    try {
      final url = ApiConsents.sendDriverRequest;
      AppLogger.log.i(url);
      final carTypes = carType == 'Sedan' ? 'sedan' : 'luxury';

      dynamic response = await Request.sendRequest(
        url,
        {
          "bookingId": bookingId,
          "pickupLatitude": pickupLatitude,
          "pickupLongitude": pickupLongitude,
          "dropLatitude": dropLatitude,
          "dropLongitude": dropLongitude,
          "carType": carTypes,
        },
        'Post',
        false,
      );
      if (response.statusCode == 200) {
        if (response.data['status'] == 200) {
          return Right(SendDriverRequestModels.fromJson(response.data));
        } else {
          return Left(ServerFailure(response.data['message'] ?? " "));
        }
      } else if (response is Response) {
        return Left(
          ServerFailure(response.data['message'] ?? "Unexpected error"),
        );
      } else {
        return Left(ServerFailure("Unknown error occurred"));
      }
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Something went wrong'));
    }
  }

  Future<Either<Failure, SendDriverRequestModels>> cancelRide({
    required String bookingId,
    required String selectedReason,
  }) async {
    try {
      final url = ApiConsents.cancelRide(bookingId: bookingId);
      AppLogger.log.i(url);

      dynamic response = await Request.sendRequest(
        url,
        {"rejectedReason": selectedReason},
        'Post',
        true,
      );
      if (response.statusCode == 200) {
        if (response.data['status'] == 200) {
          return Right(SendDriverRequestModels.fromJson(response.data));
        } else {
          return Left(ServerFailure(response.data['message'] ?? " "));
        }
      } else if (response is Response) {
        return Left(
          ServerFailure(response.data['message'] ?? "Unexpected error"),
        );
      } else {
        return Left(ServerFailure("Unknown error occurred"));
      }
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Something went wrong'));
    }
  }

  Future<Either<Failure, SendDriverRequestModels>> starRating({
    required String bookingId,
    required String selectedReason,
  }) async {
    try {
      final url = ApiConsents.rateDriver(bookingId: bookingId);
      AppLogger.log.i(url);

      dynamic response = await Request.sendRequest(
        url,
        {"rating": selectedReason, "review": ''},
        'Post',
        false,
      );
      if (response.statusCode == 200) {
        if (response.data['status'] == 200) {
          return Right(SendDriverRequestModels.fromJson(response.data));
        } else {
          return Left(ServerFailure(response.data['message'] ?? " "));
        }
      } else if (response is Response) {
        return Left(
          ServerFailure(response.data['message'] ?? "Unexpected error"),
        );
      } else {
        return Left(ServerFailure("Unknown error occurred"));
      }
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Something went wrong'));
    }
  }

  Future<Either<Failure, PackageDetailsResponse>> packageAddressDetails({
    required AddressModel senderData,
    required AddressModel receiverData,
    required String weight,
    required String selectedParcel,
    required String description,
    required String deliveryInstruction,
  }) async {
    try {
      final url = ApiConsents.createBooking;
      AppLogger.log.i(url);
      final data = {
        "fromLatitude": senderData.latitude,
        "fromLongitude": senderData.longitude,
        "pickupAddress": senderData.address,
        "fromContact_name": senderData.name,
        "fromContact_phone": senderData.phone,
        "toLatitude": receiverData.latitude,
        "toLongitude": receiverData.longitude,
        "dropAddress": receiverData.address,
        "toContact_name": receiverData.name,
        "toContact_phone": receiverData.phone,
        "parcel_type": selectedParcel,
        "description": description,
        "delivery_instruction": deliveryInstruction,
        "address_type": "Work",
        "rideType": "Bike",
        "bookingType": "Parcel",
        "maxWeight": weight,
      };

      dynamic response = await Request.sendRequest(url, data, 'Post', false);
      if (response.statusCode == 200) {
        if (response.data['status'] == 200) {
          return Right(PackageDetailsResponse.fromJson(response.data));
        } else {
          return Left(ServerFailure(response.data['message'] ?? " "));
        }
      } else if (response is Response) {
        return Left(
          ServerFailure(response.data['message'] ?? "Unexpected error"),
        );
      } else {
        return Left(ServerFailure("Unknown error occurred"));
      }
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Something went wrong'));
    }
  }

  Future<Either<Failure, ConfirmPackageResponse>> confirmPackageScreen({
    required String bookingId,
  }) async {
    try {
      final url = ApiConsents.confirmBooking;
      AppLogger.log.i(url);

      dynamic response = await Request.sendRequest(
        url,
        {"bookingId": bookingId},
        'Post',
        false,
      );
      if (response.statusCode == 200) {
        if (response.data['success'] == true) {
          return Right(ConfirmPackageResponse.fromJson(response.data));
        } else {
          return Left(ServerFailure(response.data['message'] ?? " "));
        }
      } else if (response is Response) {
        return Left(
          ServerFailure(response.data['message'] ?? "Unexpected error"),
        );
      } else {
        return Left(ServerFailure("Unknown error occurred"));
      }
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Something went wrong'));
    }
  }

  Future<Either<Failure, SendPackageDriverResponse>> sendPackageDriverRequest({
    required String bookingId,
    required String discountCode,
    required AddressModel senderData,
    required AddressModel receiverData,
  }) async {
    try {
      final url = ApiConsents.sendDriverRequest;
      final data = {
        "bookingId": bookingId,
        "pickupLatitude": senderData.latitude,
        "pickupLongitude": senderData.longitude,
        "dropLatitude": receiverData.latitude,
        "dropLongitude": receiverData.longitude,
        "discountcode": discountCode,
      };

      AppLogger.log.i(url);
      AppLogger.log.i(data);
      dynamic response = await Request.sendRequest(url, data, 'Post', false);
      if (response.statusCode == 200) {
        return Right(SendPackageDriverResponse.fromJson(response.data));
        // if (response.data['success'] == 200) {
        //   return Right(SendDriverRequestModels.fromJson(response.data));
        // } else {
        //   return Left(ServerFailure(response.data['message'] ?? " "));
        // }
      } else if (response is Response) {
        return Left(
          ServerFailure(response.data['message'] ?? "Unexpected error"),
        );
      } else {
        return Left(ServerFailure("Unknown error occurred"));
      }
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Something went wrong'));
    }
  }

  Future<Either<Failure, UserImageModels>> userProfileUpload({
    required File imageFile,
  }) async {
    try {
      if (!await imageFile.exists()) {
        return Left(ServerFailure('Image file does not exist.'));
      }

      String url = ApiConsents.userImageUpload;
      // Send an explicit image content-type. Without it the multipart part was
      // uploaded as `application/octet-stream`, which the server's image filter
      // rejected and face-detection could not read.
      final lowerPath = imageFile.path.toLowerCase();
      final imageSubtype =
          lowerPath.endsWith('.png')
              ? 'png'
              : lowerPath.endsWith('.webp')
              ? 'webp'
              : 'jpeg';
      FormData formData = FormData.fromMap({
        'image': await MultipartFile.fromFile(
          imageFile.path,
          filename: imageFile.path.split('/').last,
          contentType: DioMediaType('image', imageSubtype),
        ),
      });

      final response = await Request.formData(url, formData, 'POST', true);

      if (response is! Response) {
        return Left(ServerFailure("Unexpected error"));
      }

      final dynamic raw = response.data;
      final Map<String, dynamic> responseData =
          raw is String
              ? (jsonDecode(raw) as Map<String, dynamic>)
              : (raw is Map<String, dynamic> ? raw : <String, dynamic>{});

      if (response.statusCode == 200) {
        if (responseData['status'] == true) {
          return Right(UserImageModels.fromJson(responseData));
        }
        return Left(ServerFailure((responseData['message'] ?? '').toString()));
      } else if (response.statusCode == 409) {
        return Left(ServerFailure((responseData['message'] ?? '').toString()));
      } else {
        return Left(
          ServerFailure(
            (responseData['message'] ?? "Unknown error").toString(),
          ),
        );
      }
    } catch (e, st) {
      AppLogger.log.e('userProfileUpload error: $e\n$st');
      return Left(ServerFailure('Something went wrong'));
    }
  }

  // ------------------------------------------------------------
  // Support
  // ------------------------------------------------------------

  Future<SupportCommonDetailsResult> getSupportCommonDetails() async {
    try {
      final url = ApiConsents.supportCommonDetails;
      final response = await Request.sendGetRequest(url, {}, 'GET', true);

      if (response is! Response) {
        return Left(ServerFailure('Unexpected response from server'));
      }

      if (response.statusCode != 200) {
        final msg =
            (response.data is Map<String, dynamic>)
                ? (response.data['message'] ?? '').toString()
                : '';
        return Left(
          ServerFailure(msg.isEmpty ? 'Failed to load support details' : msg),
        );
      }

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        return Left(ServerFailure('Invalid response format'));
      }

      final parsed = SupportCommonDetailsResponse.fromJson(data);
      if (!parsed.success || parsed.data == null) {
        return Left(ServerFailure((data['message'] ?? 'Failed').toString()));
      }

      return Right(parsed);
    } catch (e, st) {
      AppLogger.log.e("getSupportCommonDetails error: $e\n$st");
      return Left(ServerFailure('Something went wrong'));
    }
  }

  Future<SupportMyTicketsResult> getMySupportTickets() async {
    try {
      final url = ApiConsents.supportMyTickets;
      final response = await Request.sendGetRequest(url, {}, 'GET', true);

      if (response is! Response) {
        return Left(ServerFailure('Unexpected response from server'));
      }

      if (response.statusCode != 200) {
        final msg =
            (response.data is Map<String, dynamic>)
                ? (response.data['message'] ?? '').toString()
                : '';
        return Left(
          ServerFailure(msg.isEmpty ? 'Failed to load tickets' : msg),
        );
      }

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        return Left(ServerFailure('Invalid response format'));
      }

      final parsed = SupportMyTicketsResponse.fromJson(data);
      if (!parsed.success) {
        return Left(ServerFailure((data['message'] ?? 'Failed').toString()));
      }
      return Right(parsed);
    } catch (e, st) {
      AppLogger.log.e("getMySupportTickets error: $e\n$st");
      return Left(ServerFailure('Something went wrong'));
    }
  }

  Future<SupportMyTicketDetailsResult> getMySupportTicketDetails({
    required String ticketId,
  }) async {
    try {
      final id = ticketId.trim();
      if (id.isEmpty) {
        return Left(ServerFailure('Ticket id is required'));
      }

      final url = '${ApiConsents.supportMyTickets}/$id';
      final response = await Request.sendGetRequest(url, {}, 'GET', true);

      if (response is! Response) {
        return Left(ServerFailure('Unexpected response from server'));
      }

      if (response.statusCode != 200) {
        final msg =
            (response.data is Map<String, dynamic>)
                ? (response.data['message'] ?? '').toString()
                : '';
        return Left(ServerFailure(msg.isEmpty ? 'Failed to load ticket' : msg));
      }

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        return Left(ServerFailure('Invalid response format'));
      }

      final parsed = SupportTicketDetailsResponse.fromJson(data);
      if (!parsed.success) {
        return Left(ServerFailure((data['message'] ?? 'Failed').toString()));
      }
      return Right(parsed);
    } catch (e, st) {
      AppLogger.log.e("getMySupportTicketDetails error: $e\n$st");
      return Left(ServerFailure('Something went wrong'));
    }
  }

  Future<SupportCreateTicketResult> createSupportTicket({
    required String categoryId,
    required String subcategoryId,
    required String priority,
    required String subject,
    required String detailedDescription,
    required List<String> attachments,
  }) async {
    try {
      final url = ApiConsents.supportCustomerTickets;
      final payload = <String, dynamic>{
        "categoryId": categoryId,
        "subcategoryId": subcategoryId,
        "priority": priority,
        "subject": subject,
        "detailedDescription": detailedDescription,
        "attachments": attachments,
      };

      final response = await Request.sendRequest(url, payload, 'Post', true);

      if (response is DioException) {
        return Left(ServerFailure(response.message ?? 'Network error'));
      }

      if (response is! Response) {
        return Left(ServerFailure('Unexpected response from server'));
      }

      final status = response.statusCode ?? 0;
      if (status != 200 && status != 201) {
        final msg =
            (response.data is Map<String, dynamic>)
                ? (response.data['message'] ?? '').toString()
                : '';
        return Left(
          ServerFailure(msg.isEmpty ? 'Failed to create ticket' : msg),
        );
      }

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        return Left(ServerFailure('Invalid response format'));
      }

      final parsed = SupportCreateTicketResponse.fromJson(data);
      if (!parsed.success) {
        return Left(ServerFailure((data['message'] ?? 'Failed').toString()));
      }
      return Right(parsed);
    } catch (e, st) {
      AppLogger.log.e("createSupportTicket error: $e\n$st");
      return Left(ServerFailure('Something went wrong'));
    }
  }

  Future<SupportSendMessageResult> sendSupportTicketMessage({
    required String ticketId,
    required String userType,
    required String message,
    List<String> attachments = const <String>[],
  }) async {
    try {
      final id = ticketId.trim();
      if (id.isEmpty) {
        return Left(ServerFailure('Ticket id is required'));
      }

      final url = '${ApiConsents.supportCustomerTickets}/$id/message';
      final payload = <String, dynamic>{
        'userType': userType.trim(),
        'message': message.trim(),
        'attachments': attachments,
      };

      final response = await Request.sendRequest(url, payload, 'Post', true);

      if (response is DioException) {
        return Left(ServerFailure(response.message ?? 'Network error'));
      }

      if (response is! Response) {
        return Left(ServerFailure('Unexpected response from server'));
      }

      final status = response.statusCode ?? 0;
      if (status != 200 && status != 201) {
        final msg =
            (response.data is Map<String, dynamic>)
                ? (response.data['message'] ?? '').toString()
                : '';
        return Left(
          ServerFailure(msg.isEmpty ? 'Failed to send message' : msg),
        );
      }

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        return Left(ServerFailure('Invalid response format'));
      }

      final parsed = SupportSendMessageResponse.fromJson(data);
      if (!parsed.success) {
        return Left(ServerFailure((data['message'] ?? 'Failed').toString()));
      }
      return Right(parsed);
    } catch (e, st) {
      AppLogger.log.e("sendSupportTicketMessage error: $e\n$st");
      return Left(ServerFailure('Something went wrong'));
    }
  }

  Future<Either<Failure, RideHistoryResponse>> getRideHistory({
    required int page,
  }) async {
    try {
      final url = ApiConsents.rideHistory;
      AppLogger.log.i(url);
      final payload = {"page": page.toString(), "limit": "10"};
      AppLogger.log.i(payload);
      dynamic response = await Request.sendRequest(url, payload, 'Post', true);

      if (response.statusCode == 200) {
        if (response.data['success'] == true) {
          return Right(RideHistoryResponse.fromJson(response.data));
        } else {
          return Left(
            ServerFailure(response.data['message'] ?? "Login failed"),
          );
        }
      } else if (response is Response) {
        return Left(
          ServerFailure(response.data['message'] ?? "Unexpected error"),
        );
      } else {
        return Left(ServerFailure("Unknown error occurred"));
      }
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Something went wrong'));
    }
  }

  Future<Either<Failure, WalletResponse>> addWallet({
    required double amount,
    required String method,
  }) async {
    try {
      final url = ApiConsents.addToWallet;
      AppLogger.log.i(url);

      dynamic response = await Request.sendRequest(
        url,
        {'amount': amount, 'method': method},
        'GET',
        false,
      );

      if (response.statusCode == 200) {
        if (response.data['success'] == true) {
          return Right(WalletResponse.fromJson(response.data));
        } else {
          return Left(
            ServerFailure(response.data['message'] ?? "Login failed"),
          );
        }
      } else if (response is Response) {
        return Left(
          ServerFailure(response.data['message'] ?? "Unexpected error"),
        );
      } else {
        return Left(ServerFailure("Unknown error occurred"));
      }
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Something went wrong'));
    }
  }

  Future<Either<Failure, GetWalletBalanceResponse>> getWalletBalance() async {
    try {
      final url = ApiConsents.getwalletBalance;
      AppLogger.log.i(url);

      dynamic response = await Request.sendGetRequest(url, {}, 'GET', true);

      if (response.statusCode == 200) {
        if (response.data['success'] == true) {
          return Right(GetWalletBalanceResponse.fromJson(response.data));
        } else {
          return Left(
            ServerFailure(response.data['message'] ?? "Login failed"),
          );
        }
      } else if (response is Response) {
        return Left(
          ServerFailure(response.data['message'] ?? "Unexpected error"),
        );
      } else {
        return Left(ServerFailure("Unknown error occurred"));
      }
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Something went wrong'));
    }
  }

  Future<Either<Failure, TransactionResponse>> customerWalletHistory({
    required int page,
  }) async {
    try {
      final url = ApiConsents.customerWalletHistory;
      final payLoad = {"page": page, "limit": 10};
      AppLogger.log.i(url);

      dynamic response = await Request.sendRequest(url, payLoad, 'GET', false);

      if (response.statusCode == 200) {
        if (response.data['success'] == true) {
          return Right(TransactionResponse.fromJson(response.data));
        } else {
          return Left(
            ServerFailure(response.data['message'] ?? "Login failed"),
          );
        }
      } else if (response is Response) {
        return Left(
          ServerFailure(response.data['message'] ?? "Unexpected error"),
        );
      } else {
        return Left(ServerFailure("Unknown error occurred"));
      }
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Something went wrong'));
    }
  }

  Future<Either<Failure, ProfileResponse>> getProfileData() async {
    try {
      final url = ApiConsents.getCustomerDetails;
      AppLogger.log.i(url);

      dynamic response = await Request.sendRequest(url, {}, 'GET', true);

      if (response.statusCode == 200) {
        if (response.data['success'] == true) {
          return Right(ProfileResponse.fromJson(response.data));
        } else {
          return Left(
            ServerFailure(response.data['message'] ?? "Login failed"),
          );
        }
      } else if (response is Response) {
        return Left(
          ServerFailure(response.data['message'] ?? "Unexpected error"),
        );
      } else {
        return Left(ServerFailure("Unknown error occurred"));
      }
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Something went wrong'));
    }
  }

  Future<Either<Failure, UserSubmitResponse>> submitProfileData({
    required String firstName,
    required String lastName,
    required String dateOfBirth,
    required String gender,
    required String email,
    required String profileImage,
    required String emergencyNumber,
    required String countryCode,
  }) async {
    try {
      final url = ApiConsents.postCustomerDetails;
      AppLogger.log.i(url);

      dynamic response = await Request.sendRequest(
        url,
        {
          "firstName": firstName,

          "dateOfBirth": dateOfBirth,
          "gender": gender,
          "email": email,
          "profileImage": profileImage,
          "emergencyContactNumber": emergencyNumber,
          "emergencyCountryCode": countryCode,
        },
        'POST',
        false,
      );

      if (response is DioException) {
        final responseData = response.response?.data;
        final backendMessage =
            responseData is Map<String, dynamic>
                ? (responseData['message'] ?? '').toString()
                : '';
        final fallbackMessage =
            response.response?.statusCode == 500
                ? 'Server error. Please try again.'
                : 'Something went wrong';
        return Left(
          ServerFailure(
            backendMessage.trim().isNotEmpty
                ? backendMessage
                : (response.message?.trim().isNotEmpty ?? false)
                ? response.message!.trim()
                : fallbackMessage,
          ),
        );
      }

      if (response is! Response) {
        return Left(ServerFailure("Unknown error occurred"));
      }

      if (response.statusCode == 200) {
        if (response.data['success'] == true) {
          return Right(UserSubmitResponse.fromJson(response.data));
        } else {
          return Left(
            ServerFailure(response.data['message'] ?? "Profile update failed"),
          );
        }
      } else {
        return Left(
          ServerFailure(response.data['message'] ?? "Unexpected error"),
        );
      }
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Something went wrong'));
    }
  }

  Future<Either<Failure, NotificationResponse>> getNotification({
    required String page,
  }) async {
    try {
      final url = ApiConsents.notification;
      AppLogger.log.i(url);
      final payload = {"page": page, "limit": "10"};
      AppLogger.log.i(payload);
      AppLogger.log.i(page);
      dynamic response = await Request.sendRequest(url, payload, 'GET', false);

      if (response.statusCode == 200) {
        if (response.data['success'] == true) {
          return Right(NotificationResponse.fromJson(response.data));
        } else {
          return Left(
            ServerFailure(response.data['message'] ?? "Login failed"),
          );
        }
      } else if (response is Response) {
        return Left(
          ServerFailure(response.data['message'] ?? "Unexpected error"),
        );
      } else {
        return Left(ServerFailure("Unknown error occurred"));
      }
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Something went wrong'));
    }
  }

  Future<Either<Failure, SendDriverRequestModels>> noDriverFound({
    required String bookingId,
    required bool status,
  }) async {
    try {
      final url = ApiConsents.sendDriverRequestStatus;
      AppLogger.log.i(url);

      dynamic response = await Request.sendRequest(
        url,
        {"bookingId": bookingId, "driverNotAvailableFromCustomer": status},
        'Post',
        true,
      );
      if (response.statusCode == 200) {
        if (response.data['status'] == 200) {
          return Right(SendDriverRequestModels.fromJson(response.data));
        } else {
          return Left(ServerFailure(response.data['message'] ?? " "));
        }
      } else if (response is Response) {
        return Left(
          ServerFailure(response.data['message'] ?? "Unexpected error"),
        );
      } else {
        return Left(ServerFailure("Unknown error occurred"));
      }
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Something went wrong'));
    }
  }

  Future<Either<Failure, PaymentResponse>> paymentDetails({
    required String bookingId,
    required String paymentType,
  }) async {
    try {
      final url = ApiConsents.paymentBooking;
      AppLogger.log.i(url);

      dynamic response = await Request.sendRequest(
        url,
        {
          "userBookingId": bookingId,
          "paymentType": paymentType,
          // "paymentType":"WALLET" // "COD"
        },
        'Post',
        false,
      );
      if (response.statusCode == 200) {
        if (response.data['status'] == 200) {
          return Right(PaymentResponse.fromJson(response.data));
        } else {
          return Left(ServerFailure(response.data['message'] ?? " "));
        }
      } else if (response is Response) {
        return Left(
          ServerFailure(response.data['message'] ?? "Unexpected error"),
        );
      } else {
        return Left(ServerFailure("Unknown error occurred"));
      }
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<Either<Failure, SosResponse>> getAppSettings() async {
    try {
      final url = ApiConsents.appSettings;
      AppLogger.log.i(url);

      dynamic response = await Request.sendGetRequest(url, {}, 'GET', false);

      if (response.statusCode == 200) {
        if (response.data['success'] == true) {
          return Right(SosResponse.fromJson(response.data));
        } else {
          return Left(
            ServerFailure(response.data['message'] ?? "Login failed"),
          );
        }
      } else if (response is Response) {
        return Left(
          ServerFailure(response.data['message'] ?? "Unexpected error"),
        );
      } else {
        return Left(ServerFailure("Unknown error occurred"));
      }
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Something went wrong'));
    }
  }

  /// Universal ride receipt — works for COD / Wallet / Paystack / Flutterwave.
  /// Returns the backend-built receipt (data + html + text) so the amounts shown
  /// exactly match what was charged. On any failure the caller shows a soft
  /// "Receipt not available yet" message — it never throws.
  Future<Either<Failure, RideReceiptResponse>> getRideReceipt({
    required String bookingId,
  }) async {
    try {
      final id = bookingId.trim();
      if (id.isEmpty) {
        return Left(ServerFailure('Booking id missing'));
      }
      final url = ApiConsents.rideReceipt(id);
      AppLogger.log.i(url);

      final response = await Request.sendGetRequest(url, {}, 'GET', true);

      if (response != null && response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          final rawSuccess = data['success'];
          final success =
              rawSuccess == true || rawSuccess?.toString() == 'true';
          if (success) {
            return Right(RideReceiptResponse.fromJson(data));
          }
          return Left(
            ServerFailure(
              data['message']?.toString() ?? 'Receipt not available yet',
            ),
          );
        }
        return Left(ServerFailure('Receipt not available yet'));
      } else {
        return Left(ServerFailure('Receipt not available yet'));
      }
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Receipt not available yet'));
    }
  }

  /// Emails the ride invoice/receipt to the customer's registered email.
  /// Returns the success message on success, a Failure with the server message
  /// otherwise. Works for both single and shared rides.
  Future<Either<Failure, String>> sendRideReceipt({
    required String bookingId,
  }) async {
    try {
      final id = bookingId.trim();
      if (id.isEmpty) {
        return Left(ServerFailure('Booking id missing'));
      }
      final url = ApiConsents.sendRideReceipt(id);
      AppLogger.log.i(url);

      final response = await Request.sendRequest(url, {}, 'POST', true);

      if (response is Response &&
          response.statusCode == 200 &&
          response.data is Map &&
          (response.data['success'] == true ||
              response.data['success']?.toString() == 'true')) {
        return Right(
          response.data['message']?.toString() ?? 'Invoice sent successfully',
        );
      }
      if (response is Response && response.data is Map) {
        return Left(
          ServerFailure(
            response.data['message']?.toString() ?? 'Could not send invoice',
          ),
        );
      }
      return Left(ServerFailure('Could not send invoice'));
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Could not send invoice'));
    }
  }

  Future<Either<Failure, ChatHistoryResponse>> chatHistory({
    required String bookingId,
    required String pickupLatitude,
    required String pickupLongitude,
  }) async {
    try {
      final url = ApiConsents.chatHistory;
      AppLogger.log.i(url);

      final payLoad = {
        "bookingId": bookingId,
        "senderType": "customer",
        "pickupLatitude": pickupLatitude,
        "pickupLongitude": pickupLongitude,
      };
      AppLogger.log.i(payLoad);

      final response = await Request.sendRequest(url, payLoad, 'Post', false);

      // If you're using Dio, response is likely a Dio Response
      final status = response.statusCode as int? ?? 0;

      if (status == 200) {
        final data = response.data as Map<String, dynamic>;
        final rawSuccess = data['success'];

        // accept both bool true and string "true"
        final success = rawSuccess == true || rawSuccess?.toString() == 'true';

        if (success) {
          return Right(ChatHistoryResponse.fromJson(data));
        } else {
          return Left(
            ServerFailure(data['message']?.toString() ?? 'Request failed'),
          );
        }
      } else {
        // Non-200 http
        final msg =
            (response is Response &&
                    response.data is Map &&
                    response.data['message'] != null)
                ? response.data['message'].toString()
                : 'Unexpected error';
        return Left(ServerFailure(msg));
      }
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Something went wrong'));
    }
  }

  Future<Either<Failure, UserSubmitResponse>> customerBookingImage({
    required String bookingId,
    required String imageUrl,
  }) async {
    try {
      final url = ApiConsents.userImageCaputre;
      AppLogger.log.i(url);

      dynamic response = await Request.sendRequest(
        url,
        {"bookingId": bookingId, "imageUrl": imageUrl},
        'POST',
        false,
        // Booking-image confirmation does heavier server-side work (face
        // verification), so the default 15s receiveTimeout was too short and the
        // upload failed with a [receive timeout]. Give it room to finish.
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 60),
      );

      // `sendRequest` returns a `Response` on success OR the caught
      // `DioException` on a timeout/error. Guard `is Response` BEFORE reading
      // `.statusCode` — calling `.statusCode` on a DioException throws
      // NoSuchMethodError and masked the real timeout as "Something went wrong".
      if (response is Response && response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final rawSuccess = data['success'] ?? data['status'];
        final success =
            rawSuccess == true ||
            rawSuccess?.toString().toLowerCase() == 'true';
        if (success) {
          return Right(UserSubmitResponse.fromJson(response.data));
        } else {
          return Left(
            ServerFailure((data['message'] ?? "Login failed").toString()),
          );
        }
      } else if (response is Response) {
        final data = response.data;
        final msg =
            (data is Map && data['message'] != null)
                ? data['message'].toString()
                : "Unexpected error";
        return Left(ServerFailure(msg));
      } else if (response is DioException) {
        final isTimeout =
            response.type == DioExceptionType.receiveTimeout ||
            response.type == DioExceptionType.sendTimeout ||
            response.type == DioExceptionType.connectionTimeout;
        return Left(
          ServerFailure(
            isTimeout
                ? "Upload timed out. Please check your connection and try again."
                : (response.message ?? "Network error"),
          ),
        );
      } else {
        return Left(ServerFailure("Unknown error occurred"));
      }
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Something went wrong'));
    }
  }

  Future<Either<Failure, UserSubmitResponse>> sendFcmToken({
    required String fcmToken,
  }) async {
    try {
      final url = ApiConsents.fcmToken;
      AppLogger.log.i(url);
      AppLogger.log.w('Fcm Token is ==  $fcmToken');

      dynamic response = await Request.sendRequest(
        url,
        {"fcm_token": fcmToken},
        'POST',
        true,
      );

      if (response.statusCode == 200) {
        if (response.data['success'] == true) {
          return Right(UserSubmitResponse.fromJson(response.data));
        } else {
          return Left(
            ServerFailure(response.data['message'] ?? "Login failed"),
          );
        }
      } else if (response is Response) {
        return Left(
          ServerFailure(response.data['message'] ?? "Unexpected error"),
        );
      } else {
        return Left(ServerFailure("Unknown error occurred"));
      }
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Something went wrong'));
    }
  }

  Future<Either<Failure, CouponResponse>> applyCoupon({
    required String code,
    required String bookingId,
    required String actionType,
  }) async {
    try {
      final url = ApiConsents.discountApply;
      AppLogger.log.i(url);
      final payLoad = {
        "code": code,
        "bookingId": bookingId,
        "actionType": actionType,
      };
      AppLogger.log.i(payLoad);
      dynamic response = await Request.sendRequest(url, payLoad, 'Post', false);
      if (response.statusCode == 200) {
        if (response.data['success'] == true) {
          return Right(CouponResponse.fromJson(response.data));
        } else {
          return Left(ServerFailure(response.data['message'] ?? " "));
        }
      } else if (response is Response) {
        return Left(
          ServerFailure(response.data['message'] ?? "Unexpected error"),
        );
      } else {
        return Left(ServerFailure("Unknown error occurred"));
      }
    } catch (e) {
      AppLogger.log.e(e);
      return Left(ServerFailure('Something went wrong'));
    }
  }
}

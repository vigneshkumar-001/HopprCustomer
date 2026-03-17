import 'package:hopper/Core/Consents/app_logger.dart';
import 'package:hopper/Presentation/Authentication/models/login_response.dart';
import 'package:hopper/Presentation/BookRide/Models/driver_search_models.dart';
import 'package:hopper/Presentation/BookRide/Models/send_driver_request_models.dart';
import 'package:hopper/Presentation/BookRide/Models/shared_create_booking_response.dart';
import 'package:hopper/Presentation/BookRide/Models/shared_driver_search_response.dart';
import 'package:hopper/api/repository/api_consents.dart';
import 'package:hopper/api/repository/failure.dart';
import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:hopper/api/repository/request.dart';

class SharedApiDatasource {
  Future<Either<Failure, SharedDriverSearchResponse>> driverSearchShared({
    required double pickupLat,
    required double pickupLng,
    required double dropLat,
    required double dropLng,
  }) async {
    try {
      // TODO: change this to the correct endpoint for driver search
      final String url = ApiConsents.driverSearchSharedBooking(
        pickupLat: pickupLat,
        pickupLng: pickupLng,
        dropLat: dropLat,
        dropLng: dropLng,
      );

      final dynamic response = await Request.sendGetRequest(
        url,
        {},
        'Post',
        true,
      );

      if (response is Response) {
        if (response.statusCode == 200) {
          final data = response.data;

          if (data is Map<String, dynamic>) {
            if (data['status'] == 200) {
              return Right(SharedDriverSearchResponse.fromJson(data));
            } else {
              return Left(
                ServerFailure(data['message']?.toString() ?? 'Unknown error'),
              );
            }
          } else {
            return Left(ServerFailure('Invalid response format from server'));
          }
        } else {
          return Left(
            ServerFailure('Server returned status code ${response.statusCode}'),
          );
        }
      }

      if (response is DioException) {
        return Left(ServerFailure(response.message ?? 'Network error'));
      }

      // Fallback for unexpected response types
      return Left(ServerFailure('Unexpected response from server'));
    } catch (e, stack) {
      AppLogger.log.e('driverSearchShared error: $e');
      AppLogger.log.e(stack.toString());
      return Left(ServerFailure('Something went wrong, please try again'));
    }
  }

  Future<Either<Failure, SharedBookingCreateResponse>> createSharedBooking({
    required double fromLatitude,
    required double fromLongitude,
    required double toLatitude,
    required double toLongitude,

    required String carType,

    required List<int> seats,
  }) async {
    try {
      final url = ApiConsents.createSharedBooking; // adjust

      final body = {
        'fromLatitude': fromLatitude,
        'fromLongitude': fromLongitude,
        'toLatitude': toLatitude,
        'toLongitude': toLongitude,

        'carType': carType,
        "sharedBooking": true,
        'seats': seats,
      };
      AppLogger.log.w(url);
AppLogger.log.w(body);

      final response = await Request.sendRequest(url, body, 'POST', false);

      if (response is Response && response.statusCode == 200) {
        final data = response.data;
        if (data['status'] == 200) {
          return Right(SharedBookingCreateResponse.fromJson(data));
        } else {
          return Left(
            ServerFailure(data['message']?.toString() ?? 'Unknown error'),
          );
        }
      }

      if (response is DioException) {
        return Left(ServerFailure(response.message ?? 'Network error'));
      }

      return Left(ServerFailure('Unexpected response from server'));
    } catch (e,st) {
      AppLogger.log.e('createSharedBooking error: $e\n$st');
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<Either<Failure, SendDriverRequestModels>> sendSharedDriverRequest({
    required double pickupLatitude,
    required double pickupLongitude,
    required double dropLatitude,
    required double dropLongitude,
    required String bookingId,
    required String carType,
  }) async {
    try {
      final url = ApiConsents.sharedSendRequest;
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
          "sharedBooking":true
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
}

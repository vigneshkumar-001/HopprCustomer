class RideHistoryResponse {
  final bool success;
  final int page;
  final int limit;
  final int totalRecords;
  final int totalPages;
  final List<RideHistoryData> remappedBookings;

  RideHistoryResponse({
    required this.success,
    required this.page,
    required this.limit,
    required this.totalRecords,
    required this.totalPages,
    required this.remappedBookings,
  });

  factory RideHistoryResponse.fromJson(Map<String, dynamic> json) {
    return RideHistoryResponse(
      success: json['success'] ?? false,
      page: json['page'] ?? 1,
      limit: json['limit'] ?? 10,
      totalRecords: json['totalRecords'] ?? 0,
      totalPages: json['totalPages'] ?? 0,
      remappedBookings:
          (json['data'] as List? ?? [])
              .map((e) => RideHistoryData.fromJson(e))
              .toList(),
    );
  }
}

class RideHistoryData {
  final String? id;
  final String? bookingType;
  final String? bookingId;

  final double? fromLatitude;
  final double? fromLongitude;
  final double? toLatitude;
  final double? toLongitude;
  final String? parcelType;
  final Customer? customer;
  final Driver? driver;
  final String? ridehistoryColor;
  final bool sharedBooking;
  final int sharedCount;
  final String? rideDurationFormatted;
  final num? amount;
  final String? status;
  final String? fromContactName;
  final bool otpVerified;
  final bool scheduled;
  final bool trackingEnabled;
  final String? toContactName;
  final num? baseFare;
  final num? serviceFare;
  final num? distance;
  final num? duration;
  final num? total;

  final String? pickupAddress;
  final String? dropAddress;

  final String? rideType;
  final String? serviceLocationId;
  final String? serviceLocationName;

  final String? createdAt;
  final String? updatedAt;
  final String? completedAt;
  final String? starRating;

  RideHistoryData({
    this.id,
    this.rideDurationFormatted,
    this.bookingType,
    this.bookingId,
    this.fromLatitude,
    this.fromLongitude,
    this.toLatitude,
    this.toLongitude,
    this.customer,
    this.driver,
    this.sharedBooking = false,
    this.sharedCount = 0,
    this.amount,
    this.parcelType,
    this.status,
    this.fromContactName,
    this.otpVerified = false,
    this.scheduled = false,
    this.trackingEnabled = false,
    this.baseFare,
    this.serviceFare,
    this.toContactName,
    this.distance,
    this.duration,
    this.total,
    this.pickupAddress,
    this.dropAddress,
    this.rideType,
    this.serviceLocationId,
    this.serviceLocationName,
    this.starRating,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
    this.ridehistoryColor,
  });

  factory RideHistoryData.fromJson(Map<String, dynamic> json) {
    return RideHistoryData(
      id: json['_id'],
      bookingType: json['bookingType'],
      bookingId: json['bookingId'],
      ridehistoryColor: json['ridehistoryColor'],
      parcelType: json['parcel_type'],
      toContactName: json['toContact_name'],
      fromContactName: json['fromContact_name'],
      fromLatitude: _toDouble(json['fromLatitude']),
      fromLongitude: _toDouble(json['fromLongitude']),
      toLatitude: _toDouble(json['toLatitude']),
      toLongitude: _toDouble(json['toLongitude']),
      rideDurationFormatted: json['rideDurationFormatted'],
      customer:
          json['customerId'] != null
              ? Customer.fromJson(json['customerId'])
              : null,
      driver:
          json['driverId'] != null ? Driver.fromJson(json['driverId']) : null,

      sharedBooking: json['sharedBooking'] ?? false,
      sharedCount: json['sharedCount'] ?? 0,

      amount: json['amount'],
      status: json['status'],

      otpVerified: json['otpVerified'] ?? false,
      scheduled: json['scheduled'] ?? false,
      trackingEnabled: json['trackingEnabled'] ?? false,

      baseFare: json['baseFare'],
      serviceFare: json['serviceFare'],
      distance: json['distance'],
      duration: json['duration'],
      total: json['total'],

      pickupAddress: json['pickupAddress'],
      dropAddress: json['dropAddress'],
      starRating: json['starRating'],

      rideType: json['rideType'],
      serviceLocationId: json['serviceLocationId'],
      serviceLocationName: json['serviceLocationName'],

      createdAt: json['createdAt'],
      updatedAt: json['updatedAt'],
      completedAt: json['completedAt'],
    );
  }
}

double? _toDouble(dynamic v) {
  if (v == null) return null;
  return double.tryParse(v.toString());
}

class Customer {
  final String? id;
  final String? firstName;
  final String? lastName;
  final String? email;
  final String? phone;

  Customer({this.id, this.firstName, this.lastName, this.email, this.phone});

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['_id'],
      firstName: json['firstName'],
      lastName: json['lastName'],
      email: json['email'],
      phone: json['phone'],
    );
  }
}

class Driver {
  final String? id;
  final String? serviceType;
  final String? firstName;
  final String? lastName;
  final String? profilePic;
  final String? mobileNumber;

  final String? carBrand;
  final String? carModel;
  final String? carType;
  final String? carColor;
  final String? carPlateNumber;
  final String? carRegistrationNumber;

  Driver({
    this.id,
    this.serviceType,
    this.firstName,
    this.lastName,
    this.profilePic,
    this.mobileNumber,
    this.carBrand,
    this.carModel,
    this.carType,
    this.carColor,
    this.carPlateNumber,
    this.carRegistrationNumber,
  });

  factory Driver.fromJson(Map<String, dynamic> json) {
    return Driver(
      id: json['_id'],
      serviceType: json['serviceType'],
      firstName: json['firstName'],
      lastName: json['lastName'],
      profilePic: json['profilePic'],
      mobileNumber: json['mobileNumber'],
      carBrand: json['carBrand'],
      carModel: json['carModel'],
      carType: json['carType'],
      carColor: json['carColor'],
      carPlateNumber: json['carPlateNumber'],
      carRegistrationNumber: json['carRegistrationNumber'],
    );
  }
}

class RideStatus {
  final String? status;
  final String? timestamp;

  RideStatus({this.status, this.timestamp});

  factory RideStatus.fromJson(Map<String, dynamic> json) {
    return RideStatus(status: json['status'], timestamp: json['timestamp']);
  }
}

class Rating {
  final int? rating;
  final String? review;

  Rating({this.rating, this.review});

  factory Rating.fromJson(Map<String, dynamic> json) {
    return Rating(rating: json['rating'], review: json['review']);
  }
}

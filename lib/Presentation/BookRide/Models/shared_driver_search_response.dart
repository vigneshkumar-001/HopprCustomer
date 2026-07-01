import 'package:hopper/Presentation/BookRide/Models/pricing_insights_model.dart';

class SharedDriverSearchResponse {
  final int? status;
  final List<SharedDriverData>? data;
  final int? count;

  SharedDriverSearchResponse({this.status, this.data, this.count});

  factory SharedDriverSearchResponse.fromJson(Map<String, dynamic> json) {
    return SharedDriverSearchResponse(
      status: json['status'] as int?,
      data:
          (json['data'] as List<dynamic>?)
              ?.map((e) => SharedDriverData.fromJson(e as Map<String, dynamic>))
              .toList(),
      count: json['count'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'data': data?.map((e) => e.toJson()).toList(),
      'count': count,
    };
  }
}

class SharedDriverData {
  final SharedDriverId? driverId;
  final bool? sharedBooking;
  final int? occupiedSeats;
  final String? estimatedPrice;
  final String? carType;
  final int? estimatedTime;
  final int? maxSeats;
  final int? maxSeatsPerBooking;
  final List<SharedSeat>? seats;
  final List<SharedFareByLocation> faresByLocation;

  SharedDriverData({
    this.driverId,
    this.sharedBooking,
    this.occupiedSeats,
    this.estimatedPrice,
    this.carType,
    this.estimatedTime,
    this.maxSeats,
    this.maxSeatsPerBooking,
    this.seats,
    this.faresByLocation = const [],
  });

  factory SharedDriverData.fromJson(Map<String, dynamic> json) {
    return SharedDriverData(
      driverId:
          json['driverId'] != null
              ? SharedDriverId.fromJson(
                json['driverId'] as Map<String, dynamic>,
              )
              : null,
      sharedBooking: json['sharedBooking'] as bool?,
      occupiedSeats: json['occupiedSeats'] as int?,
      estimatedPrice: json['estimatedPrice'] as String?,
      carType: json['carType'] as String?,
      estimatedTime: json['estimatedTime'] as int?,
      maxSeats: json['maxSeats'] as int?, // may be null / absent
      maxSeatsPerBooking: json['maxSeatsPerBooking'] as int?,
      seats:
          (json['seats'] as List<dynamic>?)
              ?.map((e) => SharedSeat.fromJson(e as Map<String, dynamic>))
              .toList(),
      faresByLocation:
          (json['faresByLocation'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(SharedFareByLocation.fromJson)
              .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'driverId': driverId?.toJson(),
      'sharedBooking': sharedBooking,
      'occupiedSeats': occupiedSeats,
      'estimatedPrice': estimatedPrice,
      'carType': carType,
      'estimatedTime': estimatedTime,
      'maxSeats': maxSeats,
      'maxSeatsPerBooking': maxSeatsPerBooking,
      'seats': seats?.map((e) => e.toJson()).toList(),
      'faresByLocation': faresByLocation.map((e) => e.toJson()).toList(),
    };
  }
}

class SharedDriverId {
  final String? id;
  final String? serviceType;
  final String? firstName;
  final String? lastName;
  final String? carBrand;
  final String? carModel;
  final String? carType;

  SharedDriverId({
    this.id,
    this.serviceType,
    this.firstName,
    this.lastName,
    this.carBrand,
    this.carModel,
    this.carType,
  });

  factory SharedDriverId.fromJson(Map<String, dynamic> json) {
    return SharedDriverId(
      id: json['_id'] as String?,
      serviceType: json['serviceType'] as String?,
      firstName: json['firstName'] as String?,
      lastName: json['lastName'] as String?,
      carBrand: json['carBrand'] as String?,
      carModel: json['carModel'] as String?,
      carType: json['carType'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'serviceType': serviceType,
      'firstName': firstName,
      'lastName': lastName,
      'carBrand': carBrand,
      'carModel': carModel,
      'carType': carType,
    };
  }
}

class SharedSeat {
  final int? seatNumber;
  final String? passengerId;
  final String? customerId;

  SharedSeat({this.seatNumber, this.passengerId, this.customerId});

  factory SharedSeat.fromJson(Map<String, dynamic> json) {
    return SharedSeat(
      seatNumber: json['seatNumber'] as int?,
      // can be "" or null → treat both as String?
      passengerId: json['passengerId']?.toString(),
      customerId: json['customerId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'seatNumber': seatNumber,
      'passengerId': passengerId,
      'customerId': customerId,
    };
  }
}

class SharedFareByLocation {
  final String locationId;
  final String locationName;
  final double baseFare;
  final double distanceFare;
  final double timeFare;
  final double pickupFare;
  final double bookingFee;
  final double subtotal;
  final double estimatedPrice;
  final PricingInsights? pricingInsights;

  SharedFareByLocation({
    required this.locationId,
    required this.locationName,
    required this.baseFare,
    required this.distanceFare,
    required this.timeFare,
    required this.pickupFare,
    required this.bookingFee,
    required this.subtotal,
    required this.estimatedPrice,
    this.pricingInsights,
  });

  factory SharedFareByLocation.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse((value ?? '').toString()) ?? 0.0;
    }

    return SharedFareByLocation(
      locationId: json['locationId']?.toString() ?? '',
      locationName: json['locationName']?.toString() ?? '',
      baseFare: asDouble(json['baseFare']),
      distanceFare: asDouble(json['distanceFare']),
      timeFare: asDouble(json['timeFare']),
      pickupFare: asDouble(json['pickupFare']),
      bookingFee: asDouble(json['bookingFee']),
      subtotal: asDouble(json['subtotal']),
      estimatedPrice: asDouble(json['estimatedPrice']),
      pricingInsights:
          json['pricingInsights'] is Map<String, dynamic>
              ? PricingInsights.fromJson(json['pricingInsights'])
              : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'locationId': locationId,
      'locationName': locationName,
      'baseFare': baseFare,
      'distanceFare': distanceFare,
      'timeFare': timeFare,
      'pickupFare': pickupFare,
      'bookingFee': bookingFee,
      'subtotal': subtotal,
      'estimatedPrice': estimatedPrice,
      'pricingInsights': pricingInsights?.toJson(),
    };
  }
}

import 'package:hopper/Presentation/BookRide/Models/pricing_insights_model.dart';

class CreateBookingModel {
  final int status;
  final BookingData data;
  final String message;

  CreateBookingModel({
    required this.status,
    required this.data,
    required this.message,
  });

  factory CreateBookingModel.fromJson(Map<String, dynamic> json) {
    return CreateBookingModel(
      status: json['status'] ?? 0,
      data: BookingData.fromJson(json['data'] ?? {}),
      message: json['message']?.toString() ?? "",
    );
  }

  Map<String, dynamic> toJson() {
    return {"status": status, "data": data.toJson(), "message": message};
  }
}

class BookingData {
  final String bookingType;
  final BookingCustomerLocation bookingCustomerlocation;
  final String carType;
  final String bookingId;
  final double fromLatitude;
  final double fromLongitude;
  final double toLatitude;
  final double toLongitude;
  final String customerId;
  final bool sharedBooking;
  final int sharedCount;
  final double amount;
  final String status;
  final bool otpVerified;
  final bool scheduled;
  final bool trackingEnabled;
  final double baseFare;
  final double serviceFare;
  final double distance;
  final int duration;
  final double driverDistance;
  final double total;
  final String pickupAddress;
  final String dropAddress;
  final String rideType;
  final String serviceLocationId;
  final String serviceLocationName;
  final double maxWeight;
  final bool specificLocation;
  final double distanceFareAmount;
  final double timeFareAmount;
  final double surgeMultiplier;
  final double surgeFareAmount;
  final double bookingFeeAmount;
  final double driverReceivedAmount;
  final List<FareBreakdown> fareBreakdown;
  final String id;
  final String otpGeneratedAt;
  final List<dynamic> rideStatusHistory;
  final String createdAt;
  final String updatedAt;
  final int v;
  final double walletAmount;
  final PricingInsights? pricingInsights;

  BookingData({
    required this.bookingType,
    required this.bookingCustomerlocation,
    required this.carType,
    required this.bookingId,
    required this.fromLatitude,
    required this.fromLongitude,
    required this.toLatitude,
    required this.toLongitude,
    required this.customerId,
    required this.sharedBooking,
    required this.sharedCount,
    required this.amount,
    required this.status,
    required this.otpVerified,
    required this.scheduled,
    required this.trackingEnabled,
    required this.baseFare,
    required this.serviceFare,
    required this.distance,
    required this.duration,
    required this.driverDistance,
    required this.total,
    required this.pickupAddress,
    required this.dropAddress,
    required this.rideType,
    required this.serviceLocationId,
    required this.serviceLocationName,
    required this.maxWeight,
    required this.specificLocation,
    required this.distanceFareAmount,
    required this.timeFareAmount,
    required this.surgeMultiplier,
    required this.surgeFareAmount,
    required this.bookingFeeAmount,
    required this.driverReceivedAmount,
    required this.fareBreakdown,
    required this.id,
    required this.otpGeneratedAt,
    required this.rideStatusHistory,
    required this.createdAt,
    required this.updatedAt,
    required this.v,
    required this.walletAmount,
    this.pricingInsights,
  });

  factory BookingData.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> breakdown =
        (json['fareBreakdown'] is List &&
                (json['fareBreakdown'] as List).isNotEmpty &&
                (json['fareBreakdown'] as List).first is Map<String, dynamic>)
            ? ((json['fareBreakdown'] as List).first as Map<String, dynamic>)
            : const <String, dynamic>{};

    return BookingData(
      bookingType: json['bookingType']?.toString() ?? "",
      bookingCustomerlocation: BookingCustomerLocation.fromJson(
        json['bookingCustomerlocation'] ?? {},
      ),
      carType: json['carType']?.toString() ?? "",
      bookingId: json['bookingId']?.toString() ?? "",
      fromLatitude: _asDouble(json['fromLatitude']),
      fromLongitude: _asDouble(json['fromLongitude']),
      toLatitude: _asDouble(json['toLatitude']),
      toLongitude: _asDouble(json['toLongitude']),
      customerId: json['customerId']?.toString() ?? "",
      sharedBooking: json['sharedBooking'] ?? false,
      sharedCount: _asInt(json['sharedCount']),
      amount: _asDouble(json['amount']),
      status: json['status']?.toString() ?? "",
      otpVerified: json['otpVerified'] ?? false,
      scheduled: json['scheduled'] ?? false,
      trackingEnabled: json['trackingEnabled'] ?? false,
      baseFare: _asDouble(json['baseFare']),
      serviceFare: _asDouble(json['serviceFare']),
      distance: _asDouble(json['distance']),
      duration: _asInt(json['duration']),
      driverDistance: _asDouble(json['driverDistance']),
      total: _asDouble(json['total']),
      pickupAddress: json['pickupAddress']?.toString() ?? "",
      dropAddress: json['dropAddress']?.toString() ?? "",
      rideType: json['rideType']?.toString() ?? "",
      serviceLocationId: json['serviceLocationId']?.toString() ?? "",
      serviceLocationName: json['serviceLocationName']?.toString() ?? "",
      maxWeight: _asDouble(json['maxWeight']),
      specificLocation: json['specificLocation'] ?? false,
      distanceFareAmount: _asDouble(json['distanceFareAmount']),
      timeFareAmount: _asDouble(json['timeFareAmount']),
      surgeMultiplier: _asDouble(json['surgeMultiplier']),
      surgeFareAmount: _asDouble(json['surgeFareAmount']),
      bookingFeeAmount: _asDouble(json['bookingFeeAmount']),
      driverReceivedAmount: _asDouble(json['driverReceivedAmount']),
      fareBreakdown:
          (json['fareBreakdown'] as List? ?? [])
              .whereType<Map<String, dynamic>>()
              .map(FareBreakdown.fromJson)
              .toList(),
      id: json['_id']?.toString() ?? "",
      otpGeneratedAt: json['otpGeneratedAt']?.toString() ?? "",
      rideStatusHistory: json['rideStatusHistory'] ?? [],
      createdAt: json['createdAt']?.toString() ?? "",
      updatedAt: json['updatedAt']?.toString() ?? "",
      v: _asInt(json['__v']),
      walletAmount: _asDouble(json['walletAmount']),
      pricingInsights:
          json['pricingInsights'] is Map<String, dynamic>
              ? PricingInsights.fromJson(json['pricingInsights'])
              : (breakdown['pricingInsights'] is Map<String, dynamic>
                  ? PricingInsights.fromJson(breakdown['pricingInsights'])
                  : null),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "bookingType": bookingType,
      "bookingCustomerlocation": bookingCustomerlocation.toJson(),
      "carType": carType,
      "bookingId": bookingId,
      "fromLatitude": fromLatitude,
      "fromLongitude": fromLongitude,
      "toLatitude": toLatitude,
      "toLongitude": toLongitude,
      "customerId": customerId,
      "sharedBooking": sharedBooking,
      "sharedCount": sharedCount,
      "amount": amount,
      "status": status,
      "otpVerified": otpVerified,
      "scheduled": scheduled,
      "trackingEnabled": trackingEnabled,
      "baseFare": baseFare,
      "serviceFare": serviceFare,
      "distance": distance,
      "duration": duration,
      "driverDistance": driverDistance,
      "total": total,
      "pickupAddress": pickupAddress,
      "dropAddress": dropAddress,
      "rideType": rideType,
      "serviceLocationId": serviceLocationId,
      "serviceLocationName": serviceLocationName,
      "maxWeight": maxWeight,
      "specificLocation": specificLocation,
      "distanceFareAmount": distanceFareAmount,
      "timeFareAmount": timeFareAmount,
      "surgeMultiplier": surgeMultiplier,
      "surgeFareAmount": surgeFareAmount,
      "bookingFeeAmount": bookingFeeAmount,
      "driverReceivedAmount": driverReceivedAmount,
      "fareBreakdown": fareBreakdown.map((e) => e.toJson()).toList(),
      "_id": id,
      "otpGeneratedAt": otpGeneratedAt,
      "rideStatusHistory": rideStatusHistory,
      "createdAt": createdAt,
      "updatedAt": updatedAt,
      "__v": v,
      "walletAmount": walletAmount,
      "pricingInsights": pricingInsights?.toJson(),
    };
  }
}

class BookingCustomerLocation {
  final String type;
  final List<double> coordinates;

  BookingCustomerLocation({required this.type, required this.coordinates});

  factory BookingCustomerLocation.fromJson(Map<String, dynamic> json) {
    return BookingCustomerLocation(
      type: json['type']?.toString() ?? "",
      coordinates: List<double>.from(
        (json['coordinates'] ?? []).map((x) => _asDouble(x)),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {"type": type, "coordinates": coordinates};
  }
}

class FareBreakdown {
  final String locationId;
  final String locationName;
  final double baseFare;
  final double rideDistanceInKm;
  final double perKilometerRate;
  final dynamic distanceFare;
  final int rideDuration;
  final double timeFareAmount;
  final double timeFare;
  final double driverDistancePerKm;
  final double pickupFareAmount;
  final double pickupFare;
  final double bookingFee;
  final double subtotal;
  final SurgeFareDetails surgeFareDetails;
  final double commissionPercent;
  final double commissionAmount;
  final double estimatedPrice;
  final double driverEarnings;

  FareBreakdown({
    required this.locationId,
    required this.locationName,
    required this.baseFare,
    required this.rideDistanceInKm,
    required this.perKilometerRate,
    required this.distanceFare,
    required this.rideDuration,
    required this.timeFareAmount,
    required this.timeFare,
    required this.driverDistancePerKm,
    required this.pickupFareAmount,
    required this.pickupFare,
    required this.bookingFee,
    required this.subtotal,
    required this.surgeFareDetails,
    required this.commissionPercent,
    required this.commissionAmount,
    required this.estimatedPrice,
    required this.driverEarnings,
  });

  factory FareBreakdown.fromJson(Map<String, dynamic> json) {
    return FareBreakdown(
      locationId: json['locationId']?.toString() ?? '',
      locationName: json['locationName']?.toString() ?? '',
      baseFare: _asDouble(json['baseFare']),
      rideDistanceInKm: _asDouble(json['RideDistanceInKm']),
      perKilometerRate: _asDouble(json['perKilometerRate']),
      distanceFare: _asDouble(json['distanceFare']),
      rideDuration: _asInt(json['Rideduration']),
      timeFareAmount: _asDouble(json['timeFareAmount']),
      timeFare: _asDouble(json['timeFare']),
      driverDistancePerKm: _asDouble(json['driverDistancePerKm']),
      pickupFareAmount: _asDouble(json['pickupFareAmount']),
      pickupFare: _asDouble(json['pickupFare']),
      bookingFee: _asDouble(json['bookingFee']),
      subtotal: _asDouble(json['subtotal']),
      surgeFareDetails: SurgeFareDetails.fromJson(
        json['surgeFareDetails'] ?? {},
      ),
      commissionPercent: _asDouble(json['commissionPercent']),
      commissionAmount: _asDouble(json['commissionAmount']),
      estimatedPrice: _asDouble(json['estimatedPrice']),
      driverEarnings: _asDouble(json['driverEarnings']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "locationId": locationId,
      "locationName": locationName,
      "baseFare": baseFare,
      "RideDistanceInKm": rideDistanceInKm,
      "perKilometerRate": perKilometerRate,
      "distanceFare": distanceFare,
      "Rideduration": rideDuration,
      "timeFareAmount": timeFareAmount,
      "timeFare": timeFare,
      "driverDistancePerKm": driverDistancePerKm,
      "pickupFareAmount": pickupFareAmount,
      "pickupFare": pickupFare,
      "bookingFee": bookingFee,
      "subtotal": subtotal,
      "surgeFareDetails": surgeFareDetails.toJson(),
      "commissionPercent": commissionPercent,
      "commissionAmount": commissionAmount,
      "estimatedPrice": estimatedPrice,
      "driverEarnings": driverEarnings,
    };
  }
}

class SurgeFareDetails {
  final double customerPays;
  final String demandareaId;
  final double demands;
  final double supplies;
  final double surgeMultiplier;
  final double surgeMultiplierAmount;
  final double surgeFare;

  SurgeFareDetails({
    required this.customerPays,
    required this.demandareaId,
    required this.demands,
    required this.supplies,
    required this.surgeMultiplier,
    required this.surgeMultiplierAmount,
    required this.surgeFare,
  });

  factory SurgeFareDetails.fromJson(Map<String, dynamic> json) {
    return SurgeFareDetails(
      customerPays: _asDouble(json['customerPays']),
      demandareaId: json['demandareaId']?.toString() ?? '',
      demands: _asDouble(json['demands']),
      supplies: _asDouble(json['supplies']),
      surgeMultiplier: _asDouble(json['surgeMultiplier']),
      surgeMultiplierAmount: _asDouble(json['surgeMultiplierAmount']),
      surgeFare: _asDouble(json['surgeFare']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "customerPays": customerPays,
      "demandareaId": demandareaId,
      "demands": demands,
      "supplies": supplies,
      "surgeMultiplier": surgeMultiplier,
      "surgeMultiplierAmount": surgeMultiplierAmount,
      "surgeFare": surgeFare,
    };
  }
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse((value ?? '').toString()) ?? 0.0;
}

int _asInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse((value ?? '').toString()) ?? 0;
}

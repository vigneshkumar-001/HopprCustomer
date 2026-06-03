import 'package:hopper/Presentation/BookRide/Models/pricing_insights_model.dart';

class SharedBookingCreateResponse {
  final int status;
  final SharedBookingData? data;
  final String? message;

  SharedBookingCreateResponse({required this.status, this.data, this.message});

  factory SharedBookingCreateResponse.fromJson(Map<String, dynamic> json) {
    return SharedBookingCreateResponse(
      status: json['status'] ?? 0,
      data:
          json['data'] != null
              ? SharedBookingData.fromJson(json['data'])
              : null,
      message: json['message'],
    );
  }
}

class SharedBookingData {
  final String? customerId;
  final String? carType;
  final String? bookingId;
  final String? sharedCount;
  final double? amount;
  final String? pickupAddress;
  final String? dropAddress;
  final double distance;
  final int duration;
  final List<FareBreakdown> fareBreakdown;
  final PricingInsights? pricingInsights;

  SharedBookingData({
    this.customerId,
    this.carType,
    this.bookingId,
    this.sharedCount,
    this.amount,
    this.pickupAddress,
    this.dropAddress,
    required this.distance,
    required this.duration,
    required this.fareBreakdown,
    this.pricingInsights,
  });

  factory SharedBookingData.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> breakdown =
        (json['fareBreakdown'] is List &&
                (json['fareBreakdown'] as List).isNotEmpty &&
                (json['fareBreakdown'] as List).first is Map<String, dynamic>)
            ? ((json['fareBreakdown'] as List).first as Map<String, dynamic>)
            : const <String, dynamic>{};

    return SharedBookingData(
      customerId: json['customerId'],
      carType: json['carType'],
      bookingId: json['bookingId'],
      sharedCount: json['sharedCount']?.toString(),
      amount: _asDoubleOrNull(json['amount']),
      pickupAddress: json['pickupAddress'],
      dropAddress: json['dropAddress'],
      distance: _asDouble(json['distance']),
      duration: _asInt(json['duration']),
      fareBreakdown:
          (json['fareBreakdown'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .map(FareBreakdown.fromJson)
              .toList(),
      pricingInsights:
          json['pricingInsights'] is Map<String, dynamic>
              ? PricingInsights.fromJson(json['pricingInsights'])
              : (breakdown['pricingInsights'] is Map<String, dynamic>
                  ? PricingInsights.fromJson(breakdown['pricingInsights'])
                  : null),
    );
  }
}

class FareBreakdown {
  final double baseFare;
  final double rideDistanceInKm;
  final double perKilometerRate;
  final double distanceFare;
  final int rideDuration;
  final double timeFareAmount;
  final double timeFare;
  final double driverDistancePerKm;
  final double pickupFareAmount;
  final double pickupFare;
  final double bookingFee;
  final double subtotal;
  final double commissionPercent;
  final double commissionAmount;
  final double estimatedPrice;
  final double driverEarnings;

  FareBreakdown({
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
    required this.commissionPercent,
    required this.commissionAmount,
    required this.estimatedPrice,
    required this.driverEarnings,
  });

  factory FareBreakdown.fromJson(Map<String, dynamic> json) {
    return FareBreakdown(
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
      commissionPercent: _asDouble(json['commissionPercent']),
      commissionAmount: _asDouble(json['commissionAmount']),
      estimatedPrice: _asDouble(json['estimatedPrice']),
      driverEarnings: _asDouble(json['driverEarnings']),
    );
  }
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse((value ?? '').toString()) ?? 0.0;
}

double? _asDoubleOrNull(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int _asInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse((value ?? '').toString()) ?? 0;
}

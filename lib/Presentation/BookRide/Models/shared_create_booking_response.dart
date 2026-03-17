class SharedBookingCreateResponse {
  final int status;
  final SharedBookingData? data;
  final String? message;

  SharedBookingCreateResponse({
    required this.status,
    this.data,
    this.message,
  });

  factory SharedBookingCreateResponse.fromJson(Map<String, dynamic> json) {
    return SharedBookingCreateResponse(
      status: json['status'] ?? 0,
      data: json['data'] != null
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
  });

  factory SharedBookingData.fromJson(Map<String, dynamic> json) {
    return SharedBookingData(
      customerId: json['customerId'],
      carType: json['carType'],
      bookingId: json['bookingId'],
      sharedCount: json['sharedCount']?.toString(),
      amount: (json['amount'] as num?)?.toDouble(),
      pickupAddress: json['pickupAddress'],
      dropAddress: json['dropAddress'],
      distance: (json['distance'] as num?)?.toDouble() ?? 0.0,
      duration: json['duration'] ?? 0,
      fareBreakdown: (json['fareBreakdown'] as List<dynamic>? ?? [])
          .map((e) => FareBreakdown.fromJson(e))
          .toList(),
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
    double parseDouble(dynamic v) =>
        double.tryParse(v?.toString() ?? '0') ?? 0;

    int parseInt(dynamic v) =>
        int.tryParse(v?.toString() ?? '0') ?? 0;

    return FareBreakdown(
      baseFare: parseDouble(json['baseFare']),
      rideDistanceInKm: parseDouble(json['RideDistanceInKm']),
      perKilometerRate: parseDouble(json['perKilometerRate']),
      distanceFare: parseDouble(json['distanceFare']),
      rideDuration: parseInt(json['Rideduration']),
      timeFareAmount: parseDouble(json['timeFareAmount']),
      timeFare: parseDouble(json['timeFare']),
      driverDistancePerKm: parseDouble(json['driverDistancePerKm']),
      pickupFareAmount: parseDouble(json['pickupFareAmount']),
      pickupFare: parseDouble(json['pickupFare']),
      bookingFee: parseDouble(json['bookingFee']),
      subtotal: parseDouble(json['subtotal']),
      commissionPercent: parseDouble(json['commissionPercent']),
      commissionAmount: parseDouble(json['commissionAmount']),
      estimatedPrice: parseDouble(json['estimatedPrice']),
      driverEarnings: parseDouble(json['driverEarnings']),
    );
  }
}

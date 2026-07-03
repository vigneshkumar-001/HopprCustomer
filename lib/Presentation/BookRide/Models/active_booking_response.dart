import 'package:hopper/Presentation/BookRide/Models/pricing_insights_model.dart';

class ActiveBookingResponse {
  final bool success;
  final bool hasActiveBooking;
  final ActiveBookingData? data;

  ActiveBookingResponse({
    required this.success,
    required this.hasActiveBooking,
    this.data,
  });

  factory ActiveBookingResponse.fromJson(Map<String, dynamic> json) {
    return ActiveBookingResponse(
      success: json['success'] == true,
      hasActiveBooking: json['hasActiveBooking'] == true,
      data:
          json['data'] is Map<String, dynamic>
              ? ActiveBookingData.fromJson(json['data'])
              : null,
    );
  }
}

class ActiveBookingData {
  final String bookingId;
  final String status;
  final dynamic paymentStatus;
  final String driverId;
  final String driverName;
  final String driverPhone;
  final String driverProfilePic;
  final String bookingType;
  final String rideType;
  final bool sharedBooking;
  final String driverServiceMode;

  /// Fare breakdown values can arrive as strings ("566.39") or numbers.
  final double? baseFare;
  final double? serviceFare;
  final double? distanceFare;
  final double? timeFare;
  final double? pickupFare;
  final double? bookingFee;
  final double? subtotal;
  final double? total;

  final double amount;
  final String pickupAddress;
  final String dropAddress;
  final double fromLatitude;
  final double fromLongitude;
  final double toLatitude;
  final double toLongitude;
  final ActiveBookingDriverLocation? driverLocation;
  final dynamic otpCode;
  final bool otpVerified;
  final bool customerImageVerified;
  final bool driverAcceptStatus;
  final bool destinationReached;
  final bool rideStarted;
  final bool cancelled;
  final ActiveBookingVehicle? vehicle;
  final PricingInsights? pricingInsights;

  /// Parcel delivery trust (Phase 2): raw courier lifecycle object
  /// (parcelStatus, deliveryOtpVerified, podPhotoUrl, pickedUpAt, deliveredAt,
  /// receiverName, receiverPhoneMasked, ...). Null for rides.
  final Map<String, dynamic>? parcel;

  ActiveBookingData({
    required this.bookingId,
    required this.status,
    this.paymentStatus,
    required this.driverId,
    required this.driverName,
    required this.driverPhone,
    required this.driverProfilePic,
    required this.bookingType,
    required this.rideType,
    required this.sharedBooking,
    required this.driverServiceMode,
    this.baseFare,
    this.serviceFare,
    this.distanceFare,
    this.timeFare,
    this.pickupFare,
    this.bookingFee,
    this.subtotal,
    this.total,
    required this.amount,
    required this.pickupAddress,
    required this.dropAddress,
    required this.fromLatitude,
    required this.fromLongitude,
    required this.toLatitude,
    required this.toLongitude,
    this.driverLocation,
    this.otpCode,
    required this.otpVerified,
    required this.customerImageVerified,
    required this.driverAcceptStatus,
    required this.destinationReached,
    required this.rideStarted,
    required this.cancelled,
    this.vehicle,
    this.pricingInsights,
    this.parcel,
  });

  static double? _parseNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  static double? _pickNum(Map<String, dynamic> json, List<String> keys) {
    for (final k in keys) {
      final val = _parseNum(json[k]);
      if (val != null) return val;
    }
    return null;
  }

  factory ActiveBookingData.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> breakdown =
        (json['fareBreakdown'] is List &&
                (json['fareBreakdown'] as List).isNotEmpty &&
                (json['fareBreakdown'] as List).first is Map<String, dynamic>)
            ? ((json['fareBreakdown'] as List).first as Map<String, dynamic>)
            : const <String, dynamic>{};

    return ActiveBookingData(
      bookingId: (json['bookingId'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      paymentStatus: json['paymentStatus'],
      driverId: (json['driverId'] ?? '').toString(),
      driverName: (json['driverName'] ?? '').toString(),
      driverPhone: (json['driverPhone'] ?? '').toString(),
      driverProfilePic: (json['driverProfilePic'] ?? '').toString(),
      bookingType: (json['bookingType'] ?? '').toString(),
      rideType: (json['rideType'] ?? '').toString(),
      sharedBooking: json['sharedBooking'] == true,
      driverServiceMode: (json['driverServiceMode'] ?? '').toString(),
      baseFare:
          _pickNum(json, const ['baseFare']) ??
          _pickNum(breakdown, const ['baseFare']),
      serviceFare:
          _pickNum(json, const ['serviceFare']) ??
          _pickNum(breakdown, const ['perKilometerRate']),
      distanceFare:
          _pickNum(json, const ['distanceFareAmount', 'distanceFare']) ??
          _pickNum(breakdown, const ['distanceFare', 'distanceFareAmount']),
      timeFare:
          _pickNum(json, const ['timeFareAmount', 'timeFare']) ??
          _pickNum(breakdown, const ['timeFareAmount', 'timeFare']),
      pickupFare:
          _pickNum(json, const ['pickupFareAmount', 'pickupFare']) ??
          _pickNum(breakdown, const ['pickupFareAmount', 'pickupFare']),
      bookingFee:
          _pickNum(json, const ['bookingFeeAmount', 'bookingFee']) ??
          _pickNum(breakdown, const ['bookingFeeAmount', 'bookingFee']),
      subtotal:
          _pickNum(json, const ['subtotal']) ??
          _pickNum(breakdown, const ['subtotal']),
      total:
          _pickNum(json, const ['total']) ??
          _pickNum(breakdown, const ['estimatedPrice']),
      amount:
          (json['amount'] is num)
              ? (json['amount'] as num).toDouble()
              : double.tryParse((json['amount'] ?? '').toString()) ?? 0.0,
      pickupAddress: (json['pickupAddress'] ?? '').toString(),
      dropAddress: (json['dropAddress'] ?? '').toString(),
      fromLatitude:
          (json['fromLatitude'] is num)
              ? (json['fromLatitude'] as num).toDouble()
              : double.tryParse((json['fromLatitude'] ?? '').toString()) ?? 0.0,
      fromLongitude:
          (json['fromLongitude'] is num)
              ? (json['fromLongitude'] as num).toDouble()
              : double.tryParse((json['fromLongitude'] ?? '').toString()) ??
                  0.0,
      toLatitude:
          (json['toLatitude'] is num)
              ? (json['toLatitude'] as num).toDouble()
              : double.tryParse((json['toLatitude'] ?? '').toString()) ?? 0.0,
      toLongitude:
          (json['toLongitude'] is num)
              ? (json['toLongitude'] as num).toDouble()
              : double.tryParse((json['toLongitude'] ?? '').toString()) ?? 0.0,
      driverLocation:
          json['driverLocation'] is Map<String, dynamic>
              ? ActiveBookingDriverLocation.fromJson(json['driverLocation'])
              : null,
      otpCode: json['otpCode'],
      otpVerified: json['otpVerified'] == true,
      parcel:
          json['parcel'] is Map
              ? Map<String, dynamic>.from(json['parcel'] as Map)
              : null,
      customerImageVerified: json['customerImageVerified'] == true,
      driverAcceptStatus: json['driverAcceptStatus'] == true,
      destinationReached: json['destinationReached'] == true,
      rideStarted: json['rideStarted'] == true,
      cancelled: json['cancelled'] == true,
      vehicle:
          json['vehicle'] is Map<String, dynamic>
              ? ActiveBookingVehicle.fromJson(json['vehicle'])
              : null,
      pricingInsights:
          json['pricingInsights'] is Map<String, dynamic>
              ? PricingInsights.fromJson(json['pricingInsights'])
              : (breakdown['pricingInsights'] is Map<String, dynamic>
                  ? PricingInsights.fromJson(breakdown['pricingInsights'])
                  : null),
    );
  }
}

class ActiveBookingDriverLocation {
  final double latitude;
  final double longitude;

  ActiveBookingDriverLocation({
    required this.latitude,
    required this.longitude,
  });

  factory ActiveBookingDriverLocation.fromJson(Map<String, dynamic> json) {
    return ActiveBookingDriverLocation(
      latitude:
          (json['latitude'] is num)
              ? (json['latitude'] as num).toDouble()
              : double.tryParse((json['latitude'] ?? '').toString()) ?? 0.0,
      longitude:
          (json['longitude'] is num)
              ? (json['longitude'] as num).toDouble()
              : double.tryParse((json['longitude'] ?? '').toString()) ?? 0.0,
    );
  }
}

class ActiveBookingVehicle {
  final String plateNumber;
  final String brand;
  final String model;
  final String color;
  final String type;
  final String carType;
  final List<String> carExteriorPhotos;

  ActiveBookingVehicle({
    required this.plateNumber,
    required this.brand,
    required this.model,
    required this.color,
    required this.type,
    required this.carType,
    required this.carExteriorPhotos,
  });

  factory ActiveBookingVehicle.fromJson(Map<String, dynamic> json) {
    return ActiveBookingVehicle(
      plateNumber: (json['plateNumber'] ?? '').toString(),
      brand: (json['brand'] ?? '').toString(),
      model: (json['model'] ?? '').toString(),
      color: (json['color'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      carType: (json['carType'] ?? '').toString(),
      carExteriorPhotos:
          (json['carExteriorPhotos'] as List<dynamic>? ?? const [])
              .map((item) => item.toString())
              .toList(),
    );
  }
}

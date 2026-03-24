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
      data: json['data'] is Map<String, dynamic>
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
  });

  factory ActiveBookingData.fromJson(Map<String, dynamic> json) {
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
      amount: (json['amount'] is num)
          ? (json['amount'] as num).toDouble()
          : double.tryParse((json['amount'] ?? '').toString()) ?? 0.0,
      pickupAddress: (json['pickupAddress'] ?? '').toString(),
      dropAddress: (json['dropAddress'] ?? '').toString(),
      fromLatitude: (json['fromLatitude'] is num)
          ? (json['fromLatitude'] as num).toDouble()
          : double.tryParse((json['fromLatitude'] ?? '').toString()) ?? 0.0,
      fromLongitude: (json['fromLongitude'] is num)
          ? (json['fromLongitude'] as num).toDouble()
          : double.tryParse((json['fromLongitude'] ?? '').toString()) ?? 0.0,
      toLatitude: (json['toLatitude'] is num)
          ? (json['toLatitude'] as num).toDouble()
          : double.tryParse((json['toLatitude'] ?? '').toString()) ?? 0.0,
      toLongitude: (json['toLongitude'] is num)
          ? (json['toLongitude'] as num).toDouble()
          : double.tryParse((json['toLongitude'] ?? '').toString()) ?? 0.0,
      driverLocation: json['driverLocation'] is Map<String, dynamic>
          ? ActiveBookingDriverLocation.fromJson(json['driverLocation'])
          : null,
      otpCode: json['otpCode'],
      otpVerified: json['otpVerified'] == true,
      customerImageVerified: json['customerImageVerified'] == true,
      driverAcceptStatus: json['driverAcceptStatus'] == true,
      destinationReached: json['destinationReached'] == true,
      rideStarted: json['rideStarted'] == true,
      cancelled: json['cancelled'] == true,
      vehicle: json['vehicle'] is Map<String, dynamic>
          ? ActiveBookingVehicle.fromJson(json['vehicle'])
          : null,
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
      latitude: (json['latitude'] is num)
          ? (json['latitude'] as num).toDouble()
          : double.tryParse((json['latitude'] ?? '').toString()) ?? 0.0,
      longitude: (json['longitude'] is num)
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
      carExteriorPhotos: (json['carExteriorPhotos'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
    );
  }
}

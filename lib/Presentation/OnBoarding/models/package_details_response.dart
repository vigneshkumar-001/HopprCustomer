class PackageDetailsResponse {
  final int status;
  final PackageBookingData data;
  final String message;

  PackageDetailsResponse({
    required this.status,
    required this.data,
    required this.message,
  });

  factory PackageDetailsResponse.fromJson(Map<String, dynamic> json) {
    return PackageDetailsResponse(
      status: json['status'],
      data: PackageBookingData.fromJson(json['data']),
      message: json['message'],
    );
  }

  Map<String, dynamic> toJson() {
    return {"status": status, "data": data.toJson(), "message": message};
  }
}

class PackageBookingData {
  final String bookingType;
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
  final String fromContactName;
  final String fromContactPhone;
  final String toContactName;
  final String toContactPhone;
  final String parcelType;
  final String description;
  final String deliveryInstruction;
  final String addressType;
  final String pickupAddress;
  final String dropAddress;
  final String rideType;
  final String serviceLocationId;
  final String serviceLocationName;
  final String id;
  final String otpGeneratedAt;
  final List<dynamic> rideStatusHistory;
  final String createdAt;
  final String updatedAt;
  final int v;

  PackageBookingData({
    required this.bookingType,
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
    required this.fromContactName,
    required this.fromContactPhone,
    required this.toContactName,
    required this.toContactPhone,
    required this.parcelType,
    required this.description,
    required this.deliveryInstruction,
    required this.addressType,
    required this.pickupAddress,
    required this.dropAddress,
    required this.rideType,
    required this.serviceLocationId,
    required this.serviceLocationName,
    required this.id,
    required this.otpGeneratedAt,
    required this.rideStatusHistory,
    required this.createdAt,
    required this.updatedAt,
    required this.v,
  });

  factory PackageBookingData.fromJson(Map<String, dynamic> json) {
    return PackageBookingData(
      bookingType: json['bookingType'] ?? "",
      bookingId: json['bookingId'] ?? "",
      fromLatitude: (json['fromLatitude'] ?? 0).toDouble(),
      fromLongitude: (json['fromLongitude'] ?? 0).toDouble(),
      toLatitude: (json['toLatitude'] ?? 0).toDouble(),
      toLongitude: (json['toLongitude'] ?? 0).toDouble(),
      customerId: json['customerId'] ?? "",
      sharedBooking: json['sharedBooking'] ?? false,
      sharedCount: json['sharedCount'] ?? 0,
      amount: (json['amount'] ?? 0).toDouble(),
      status: json['status'] ?? "",
      otpVerified: json['otpVerified'] ?? false,
      scheduled: json['scheduled'] ?? false,
      trackingEnabled: json['trackingEnabled'] ?? false,
      baseFare: (json['baseFare'] ?? 0).toDouble(),
      serviceFare: (json['serviceFare'] ?? 0).toDouble(),
      distance: (json['distance'] ?? 0).toDouble(),
      duration: json['duration'] ?? 0,
      fromContactName: json['fromContact_name'] ?? "",
      fromContactPhone: json['fromContact_phone'] ?? "",
      toContactName: json['toContact_name'] ?? "",
      toContactPhone: json['toContact_phone'] ?? "",
      parcelType: json['parcel_type'] ?? "",
      description: json['description'] ?? "",
      deliveryInstruction: json['delivery_instruction'] ?? "",
      addressType: json['address_type'] ?? "",
      pickupAddress: json['pickupAddress'] ?? "",
      dropAddress: json['dropAddress'] ?? "",
      rideType: json['rideType'] ?? "",
      serviceLocationId: json['serviceLocationId'] ?? "",
      serviceLocationName: json['serviceLocationName'] ?? "",
      id: json['_id'] ?? "",
      otpGeneratedAt: json['otpGeneratedAt'] ?? "",
      rideStatusHistory: json['rideStatusHistory'] ?? [],
      createdAt: json['createdAt'] ?? "",
      updatedAt: json['updatedAt'] ?? "",
      v: json['__v'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "bookingType": bookingType,
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
      "fromContact_name": fromContactName,
      "fromContact_phone": fromContactPhone,
      "toContact_name": toContactName,
      "toContact_phone": toContactPhone,
      "parcel_type": parcelType,
      "description": description,
      "delivery_instruction": deliveryInstruction,
      "address_type": addressType,
      "pickupAddress": pickupAddress,
      "dropAddress": dropAddress,
      "rideType": rideType,
      "serviceLocationId": serviceLocationId,
      "serviceLocationName": serviceLocationName,
      "_id": id,
      "otpGeneratedAt": otpGeneratedAt,
      "rideStatusHistory": rideStatusHistory,
      "createdAt": createdAt,
      "updatedAt": updatedAt,
      "__v": v,
    };
  }
}

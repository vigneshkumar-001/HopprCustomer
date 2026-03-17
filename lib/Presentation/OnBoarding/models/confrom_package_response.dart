class ConfirmPackageResponse {
  final bool success;
  final String message;
  final ConfirmBookingData data;

  ConfirmPackageResponse({
    required this.success,
    required this.message,
    required this.data,
  });

  factory ConfirmPackageResponse.fromJson(Map<String, dynamic> json) {
    return ConfirmPackageResponse(
      success: json['success'] ?? false,
      message: json['message'] ?? "",
      data: ConfirmBookingData.fromJson(json['data']),
    );
  }

  Map<String, dynamic> toJson() {
    return {"success": success, "message": message, "data": data.toJson()};
  }
}

class ConfirmBookingData {
  final String id;
  final String bookingType;
  late final String bookingId;
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
  final double total;
  final String pickupAddress;
  final String dropAddress;
  final String rideType;
  final String serviceLocationId;
  final String serviceLocationName;
  final String otpGeneratedAt;
  final List<RideStatusHistory> rideStatusHistory;
  final String createdAt;
  final String updatedAt;
  final int v;
  final String? couponAt;
  final String couponCode;
  final double discountAmount;

  ConfirmBookingData({
    required this.id,
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
    required this.total,
    required this.pickupAddress,
    required this.dropAddress,
    required this.rideType,
    required this.serviceLocationId,
    required this.serviceLocationName,
    required this.otpGeneratedAt,
    required this.rideStatusHistory,
    required this.createdAt,
    required this.updatedAt,
    required this.v,
    this.couponAt,
    required this.couponCode,
    required this.discountAmount,
  });

  factory ConfirmBookingData.fromJson(Map<String, dynamic> json) {
    return ConfirmBookingData(
      id: json['_id'] ?? "",
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
      total: (json['total'] ?? 0).toDouble(),
      pickupAddress: json['pickupAddress'] ?? "",
      dropAddress: json['dropAddress'] ?? "",
      rideType: json['rideType'] ?? "",
      serviceLocationId: json['serviceLocationId'] ?? "",
      serviceLocationName: json['serviceLocationName'] ?? "",
      otpGeneratedAt: json['otpGeneratedAt'] ?? "",
      rideStatusHistory:
          (json['rideStatusHistory'] as List<dynamic>?)
              ?.map((e) => RideStatusHistory.fromJson(e))
              .toList() ??
          [],
      createdAt: json['createdAt'] ?? "",
      updatedAt: json['updatedAt'] ?? "",
      v: json['__v'] ?? 0,
      couponAt: json['couponAt'],
      couponCode: json['couponCode'] ?? "",
      discountAmount: (json['discountAmount'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      "_id": id,
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
      "total": total,
      "pickupAddress": pickupAddress,
      "dropAddress": dropAddress,
      "rideType": rideType,
      "serviceLocationId": serviceLocationId,
      "serviceLocationName": serviceLocationName,
      "otpGeneratedAt": otpGeneratedAt,
      "rideStatusHistory": rideStatusHistory.map((e) => e.toJson()).toList(),
      "createdAt": createdAt,
      "updatedAt": updatedAt,
      "__v": v,
      "couponAt": couponAt,
      "couponCode": couponCode,
      "discountAmount": discountAmount,
    };
  }
}

class RideStatusHistory {
  final String status;
  final String timestamp;

  RideStatusHistory({required this.status, required this.timestamp});

  factory RideStatusHistory.fromJson(Map<String, dynamic> json) {
    return RideStatusHistory(
      status: json['status'] ?? "",
      timestamp: json['timestamp'] ?? "",
    );
  }

  Map<String, dynamic> toJson() {
    return {"status": status, "timestamp": timestamp};
  }
}

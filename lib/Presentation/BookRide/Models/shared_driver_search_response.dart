class SharedDriverSearchResponse {
  final int? status;
  final List<SharedDriverData>? data;
  final int? count;

  SharedDriverSearchResponse({
    this.status,
    this.data,
    this.count,
  });

  factory SharedDriverSearchResponse.fromJson(Map<String, dynamic> json) {
    return SharedDriverSearchResponse(
      status: json['status'] as int?,
      data: (json['data'] as List<dynamic>?)
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
  final List<SharedSeat>? seats;

  SharedDriverData({
    this.driverId,
    this.sharedBooking,
    this.occupiedSeats,
    this.estimatedPrice,
    this.carType,
    this.estimatedTime,
    this.maxSeats,
    this.seats,
  });

  factory SharedDriverData.fromJson(Map<String, dynamic> json) {
    return SharedDriverData(
      driverId: json['driverId'] != null
          ? SharedDriverId.fromJson(json['driverId'] as Map<String, dynamic>)
          : null,
      sharedBooking: json['sharedBooking'] as bool?,
      occupiedSeats: json['occupiedSeats'] as int?,
      estimatedPrice: json['estimatedPrice'] as String?,
      carType: json['carType'] as String?,
      estimatedTime: json['estimatedTime'] as int?,
      maxSeats: json['maxSeats'] as int?, // may be null / absent
      seats: (json['seats'] as List<dynamic>?)
          ?.map((e) => SharedSeat.fromJson(e as Map<String, dynamic>))
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
      'seats': seats?.map((e) => e.toJson()).toList(),
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

  SharedSeat({
    this.seatNumber,
    this.passengerId,
    this.customerId,
  });

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

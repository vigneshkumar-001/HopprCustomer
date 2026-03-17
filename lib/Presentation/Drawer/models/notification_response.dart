class NotificationResponse {
  final bool? success;
  final int? count;
  final int? total;
  final int? page;
  final int? totalPages;
  final List<NotificationData> data;

  NotificationResponse({
    this.success,
    this.count,
    this.total,
    this.page,
    this.totalPages,
    required this.data,
  });

  factory NotificationResponse.fromJson(Map<String, dynamic> json) {
    return NotificationResponse(
      success: json['success'],
      count: json['count'],
      total: json['total'],
      page: json['page'],
      totalPages: json['totalPages'],
      data: json['data'] != null
          ? List<NotificationData>.from(
          json['data'].map((x) => NotificationData.fromJson(x)))
          : [],
    );
  }

  Map<String, dynamic> toJson() => {
    "success": success,
    "count": count,
    "total": total,
    "page": page,
    "totalPages": totalPages,
    "data": List<dynamic>.from(data.map((x) => x.toJson())),
  };
}

class NotificationData {
  final String? id;
  final String? userType;
  final String? customerId;
  final String? driverId;
  final String? bookingId;
  final String? type;
  final String? title;
  final String? message;
  final NotificationInnerData? data;
  final String? status;
  final String? createdAt;
  final String? updatedAt;
  final int? v;
  final String? imageType;
  final String? bookingType;
  final bool? sharedBooking;

  NotificationData({
    this.id,
    this.userType,
    this.customerId,
    this.driverId,
    this.bookingId,
    this.type,
    this.title,
    this.message,
    this.data,
    this.status,
    this.createdAt,
    this.updatedAt,
    this.v,
    this.imageType,
    this.bookingType,
    this.sharedBooking,
  });

  factory NotificationData.fromJson(Map<String, dynamic> json) {
    return NotificationData(
      id: json['_id'],
      userType: json['userType'],
      customerId: json['customerId'],
      driverId: json['driverId'],
      bookingId: json['bookingId'],
      type: json['type'],
      title: json['title'],
      message: json['message'],
      data: json['data'] != null
          ? NotificationInnerData.fromJson(json['data'])
          : null,
      status: json['status'],
      createdAt: json['createdAt'],
      updatedAt: json['updatedAt'],
      v: json['__v'],
      imageType: json['imageType'],
      bookingType: json['bookingType'],
      sharedBooking: json['sharedBooking'],
    );
  }

  Map<String, dynamic> toJson() => {
    "_id": id,
    "userType": userType,
    "customerId": customerId,
    "driverId": driverId,
    "bookingId": bookingId,
    "type": type,
    "title": title,
    "message": message,
    "data": data?.toJson(),
    "status": status,
    "createdAt": createdAt,
    "updatedAt": updatedAt,
    "__v": v,
    "imageType": imageType,
    "bookingType": bookingType,
    "sharedBooking": sharedBooking,
  };
}


class NotificationInnerData {
  final String? bookingId;
  final String? driverId;
  final String? status;
  final String? time;

  NotificationInnerData({
    this.bookingId,
    this.driverId,
    this.status,
    this.time,
  });

  factory NotificationInnerData.fromJson(Map<String, dynamic> json) {
    return NotificationInnerData(
      bookingId: json['bookingId'],
      driverId: json['driverId'],
      status: json['status'],
      time: json['time'],
    );
  }

  Map<String, dynamic> toJson() => {
    "bookingId": bookingId,
    "driverId": driverId,
    "status": status,
    "time": time,
  };
}


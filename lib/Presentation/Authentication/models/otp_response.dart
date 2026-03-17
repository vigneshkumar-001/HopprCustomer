class OtpResponse {
  final int status;
  final Data data;

  OtpResponse({required this.status, required this.data});

  factory OtpResponse.fromJson(Map<String, dynamic> json) {
    return OtpResponse(
      status: json['status'],
      data: Data.fromJson(json['data']),
    );
  }

  Map<String, dynamic> toJson() => {"status": status, "data": data.toJson()};
}

class Data {
  final String token;
  final Customer customer;

  Data({required this.token, required this.customer});

  factory Data.fromJson(Map<String, dynamic> json) {
    return Data(
      token: json['token'],
      customer: Customer.fromJson(json['customer']),
    );
  }

  Map<String, dynamic> toJson() => {
    "token": token,
    "customer": customer.toJson(),
  };
}

class Customer {
  final String id;
  final String firstName;
  final String lastName;

  final String phone;

  final String countryCode;

  Customer({
    required this.id,
    required this.firstName,
    required this.lastName,

    required this.phone,

    required this.countryCode,
  });

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['_id'],
      firstName: json['firstName'],
      lastName: json['lastName'],

      phone: json['phone'],

      countryCode: json['countryCode'],
    );
  }

  Map<String, dynamic> toJson() => {
    "_id": id,
    "firstName": firstName,
    "lastName": lastName,

    "phone": phone,

    "countryCode": countryCode,
  };
}

class Preferences {
  final Notifications notifications;
  final Privacy privacy;
  final Ride ride;
  final String language;
  final String currency;
  final String id;

  Preferences({
    required this.notifications,
    required this.privacy,
    required this.ride,
    required this.language,
    required this.currency,
    required this.id,
  });

  factory Preferences.fromJson(Map<String, dynamic> json) {
    return Preferences(
      notifications: Notifications.fromJson(json['notifications']),
      privacy: Privacy.fromJson(json['privacy']),
      ride: Ride.fromJson(json['ride']),
      language: json['language'],
      currency: json['currency'],
      id: json['_id'],
    );
  }

  Map<String, dynamic> toJson() => {
    "notifications": notifications.toJson(),
    "privacy": privacy.toJson(),
    "ride": ride.toJson(),
    "language": language,
    "currency": currency,
    "_id": id,
  };
}

class Notifications {
  final String email;
  final String sms;
  final String push;
  final String bookingUpdates;
  final String promotions;
  final String rideReminders;

  Notifications({
    required this.email,
    required this.sms,
    required this.push,
    required this.bookingUpdates,
    required this.promotions,
    required this.rideReminders,
  });

  factory Notifications.fromJson(Map<String, dynamic> json) {
    return Notifications(
      email: json['email'],
      sms: json['sms'],
      push: json['push'],
      bookingUpdates: json['bookingUpdates'],
      promotions: json['promotions'],
      rideReminders: json['rideReminders'],
    );
  }

  Map<String, dynamic> toJson() => {
    "email": email,
    "sms": sms,
    "push": push,
    "bookingUpdates": bookingUpdates,
    "promotions": promotions,
    "rideReminders": rideReminders,
  };
}

class Privacy {
  final String shareLocation;
  final String showOnlineStatus;
  final String allowDataCollection;

  Privacy({
    required this.shareLocation,
    required this.showOnlineStatus,
    required this.allowDataCollection,
  });

  factory Privacy.fromJson(Map<String, dynamic> json) {
    return Privacy(
      shareLocation: json['shareLocation'],
      showOnlineStatus: json['showOnlineStatus'],
      allowDataCollection: json['allowDataCollection'],
    );
  }

  Map<String, dynamic> toJson() => {
    "shareLocation": shareLocation,
    "showOnlineStatus": showOnlineStatus,
    "allowDataCollection": allowDataCollection,
  };
}

class Ride {
  final List<dynamic> preferredVehicleType;
  final String maxWaitTime;
  final String autoConfirmBooking;
  final String allowSharedRides;

  Ride({
    required this.preferredVehicleType,
    required this.maxWaitTime,
    required this.autoConfirmBooking,
    required this.allowSharedRides,
  });

  factory Ride.fromJson(Map<String, dynamic> json) {
    return Ride(
      preferredVehicleType: List<dynamic>.from(json['preferredVehicleType']),
      maxWaitTime: json['maxWaitTime'],
      autoConfirmBooking: json['autoConfirmBooking'],
      allowSharedRides: json['allowSharedRides'],
    );
  }

  Map<String, dynamic> toJson() => {
    "preferredVehicleType": preferredVehicleType,
    "maxWaitTime": maxWaitTime,
    "autoConfirmBooking": autoConfirmBooking,
    "allowSharedRides": allowSharedRides,
  };
}

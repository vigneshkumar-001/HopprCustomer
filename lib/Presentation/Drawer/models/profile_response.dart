import 'dart:convert';

class ProfileResponse {
  final String message;
  final bool success;
  final UserModel data;

  ProfileResponse({
    required this.message,
    required this.success,
    required this.data,
  });

  factory ProfileResponse.fromJson(Map<String, dynamic> json) =>
      ProfileResponse(
        message: json["message"] ?? "",
        success: json["success"] ?? false,
        data: UserModel.fromJson(json["data"] ?? {}),
      );

  Map<String, dynamic> toJson() => {
    "message": message,
    "success": success,
    "data": data.toJson(),
  };
}

class UserModel {
  final String id;
  final String firstName;
  final String countryCode;
  final String email;
  final String phone;
  final double walletBalance;
  final DateTime? dateOfBirth;
  final String gender;
  final String profileImage;
  final double customerWalletAmount;
  final CustomerRating? customerRating;

  UserModel({
    required this.id,
    required this.firstName,
    required this.countryCode,
    required this.email,
    required this.phone,
    required this.walletBalance,
    required this.dateOfBirth,
    required this.gender,
    required this.profileImage,
    required this.customerWalletAmount,
    this.customerRating,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    id: json["_id"] ?? "",
    firstName: json["firstName"] ?? "",
    countryCode: json["countryCode"] ?? "",
    email: json["email"] ?? "",
    phone: json["phone"] ?? "",
    walletBalance: (json["walletBalance"] ?? 0).toDouble(),
    dateOfBirth: json["dateOfBirth"] != null
        ? DateTime.tryParse(json["dateOfBirth"])
        : null,
    gender: json["gender"] ?? "",
    profileImage: json["profileImage"] ?? "",
    customerWalletAmount:
    (json["customerWalletAmount"] ?? 0).toDouble(),
    customerRating: json["customerRating"] != null
        ? CustomerRating.fromJson(json["customerRating"])
        : null,
  );

  Map<String, dynamic> toJson() => {
    "_id": id,
    "firstName": firstName,
    "countryCode": countryCode,
    "email": email,
    "phone": phone,
    "walletBalance": walletBalance,
    "dateOfBirth": dateOfBirth?.toIso8601String(),
    "gender": gender,
    "profileImage": profileImage,
    "customerWalletAmount": customerWalletAmount,
    "customerRating": customerRating?.toJson(),
  };
}

class CustomerRating {
  final double averageRating;
  final int totalRatings;

  CustomerRating({
    required this.averageRating,
    required this.totalRatings,
  });

  factory CustomerRating.fromJson(Map<String, dynamic> json) =>
      CustomerRating(
        averageRating: (json["averageRating"] ?? 0).toDouble(),
        totalRatings: json["totalRatings"] ?? 0,
      );

  Map<String, dynamic> toJson() => {
    "averageRating": averageRating,
    "totalRatings": totalRatings,
  };
}

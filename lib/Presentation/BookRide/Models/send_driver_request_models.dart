// class SendDriverRequestModels {
//   final int status;
//   final String message;
//   final BookingDriverData data;
//
//   SendDriverRequestModels({
//     required this.status,
//     required this.message,
//     required this.data,
//   });
//
//   factory SendDriverRequestModels.fromJson(Map<String, dynamic> json) {
//     return SendDriverRequestModels(
//       status: json['status'],
//       message: json['message'],
//       data: BookingDriverData.fromJson(json['data']),
//     );
//   }
// }
//
// class BookingDriverData {
//   final String driversNotified;
//
//   BookingDriverData({required this.driversNotified});
//
//   factory BookingDriverData.fromJson(Map<String, dynamic> json) {
//     return BookingDriverData(driversNotified: json['totalDrivers']);
//   }
// }

class SendDriverRequestModels {
  final int status;
  final String message;
  final BookingDriverData? data; // nullable

  SendDriverRequestModels({
    required this.status,
    required this.message,
    this.data,
  });

  factory SendDriverRequestModels.fromJson(Map<String, dynamic> json) {
    return SendDriverRequestModels(
      status: json['status'] ?? 0,
      message: json['message'] ?? '',
      data:
          json['data'] != null
              ? BookingDriverData.fromJson(json['data'])
              : null,
    );
  }
}

class BookingDriverData {
  final String driversNotified;

  BookingDriverData({required this.driversNotified});

  factory BookingDriverData.fromJson(Map<String, dynamic> json) {
    // handle if key is missing or null
    return BookingDriverData(
      driversNotified: json['totalDrivers']?.toString() ?? '0',
    );
  }
}

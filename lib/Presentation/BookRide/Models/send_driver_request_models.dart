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
  final String dispatchStatus;
  final bool dispatchInProgress;
  final bool driverAssigned;
  final bool noDriverFound;
  final DateTime? deadlineAt;

  BookingDriverData({
    required this.driversNotified,
    required this.dispatchStatus,
    required this.dispatchInProgress,
    required this.driverAssigned,
    required this.noDriverFound,
    this.deadlineAt,
  });

  factory BookingDriverData.fromJson(Map<String, dynamic> json) {
    // handle if key is missing or null
    return BookingDriverData(
      driversNotified: json['totalDrivers']?.toString() ?? '0',
      dispatchStatus: (json['dispatchStatus'] ?? '').toString(),
      dispatchInProgress: json['dispatchInProgress'] == true,
      driverAssigned: json['driverAssigned'] == true,
      noDriverFound: json['noDriverFound'] == true,
      deadlineAt: DateTime.tryParse((json['deadlineAt'] ?? '').toString()),
    );
  }
}

class SendPackageDriverResponse {
  final int status;
  final String message;
  final BookingPackageDriverData data;

  SendPackageDriverResponse({
    required this.status,
    required this.message,
    required this.data,
  });

  factory SendPackageDriverResponse.fromJson(Map<String, dynamic> json) {
    return SendPackageDriverResponse(
      status: json['status'],
      message: json['message'],
      data: BookingPackageDriverData.fromJson(json['data']),
    );
  }
}

class BookingPackageDriverData {
  final String totalDrivers;

  BookingPackageDriverData({required this.totalDrivers});

  factory BookingPackageDriverData.fromJson(Map<String, dynamic> json) {
    return BookingPackageDriverData(totalDrivers: json['totalDrivers']);
  }
}

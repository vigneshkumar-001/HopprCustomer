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
  final bool dispatchAccepted;
  final String dispatchStatus;
  final bool dispatchInProgress;
  final String? attemptId;
  final DateTime? deadlineAt;
  final int? timeoutSeconds;
  final List<int> radiusStepsMeters;

  BookingPackageDriverData({
    required this.totalDrivers,
    required this.dispatchAccepted,
    required this.dispatchStatus,
    required this.dispatchInProgress,
    this.attemptId,
    this.deadlineAt,
    this.timeoutSeconds,
    this.radiusStepsMeters = const [],
  });

  factory BookingPackageDriverData.fromJson(Map<String, dynamic> json) {
    return BookingPackageDriverData(
      totalDrivers: json['totalDrivers']?.toString() ?? '0',
      dispatchAccepted: json['dispatchAccepted'] == true,
      dispatchStatus: (json['dispatchStatus'] ?? '').toString(),
      dispatchInProgress: json['dispatchInProgress'] == true,
      attemptId: json['attemptId']?.toString(),
      deadlineAt: DateTime.tryParse((json['deadlineAt'] ?? '').toString()),
      timeoutSeconds: int.tryParse((json['timeoutSeconds'] ?? '').toString()),
      radiusStepsMeters:
          (json['radiusStepsMeters'] as List?)
              ?.map((value) => int.tryParse(value.toString()))
              .whereType<int>()
              .toList() ??
          const [],
    );
  }
}

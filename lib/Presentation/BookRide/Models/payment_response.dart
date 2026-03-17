class PaymentResponse {
  final int status;
  final String message;
  final String bookingStatus;
  final double paidAmount;
  final String paymentId;

  PaymentResponse({
    required this.status,
    required this.message,
    required this.bookingStatus,
    required this.paidAmount,
    required this.paymentId,
  });

  factory PaymentResponse.fromJson(Map<String, dynamic> json) {
    return PaymentResponse(
      status: json['status'] ?? 0,
      message: json['message'] ?? '',
      bookingStatus: json['bookingStatus'] ?? '',
      paidAmount: (json['paidAmount'] != null)
          ? double.tryParse(json['paidAmount'].toString()) ?? 0.0
          : 0.0,
      paymentId: json['paymentId'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'message': message,
      'bookingStatus': bookingStatus,
      'paidAmount': paidAmount,
      'paymentId': paymentId,
    };
  }
}

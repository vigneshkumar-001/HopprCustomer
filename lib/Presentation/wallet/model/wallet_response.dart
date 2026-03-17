class WalletResponse {
  final bool success;
  final String message;
  final String clientSecret;
  final String ephemeralKey;
  final String customer;
  final String transactionId;
  final String publishableKey;

  WalletResponse({
    required this.success,
    required this.message,
    required this.clientSecret,
    required this.ephemeralKey,
    required this.customer,
    required this.transactionId,
    required this.publishableKey,
  });

  factory WalletResponse.fromJson(Map<String, dynamic> json) {
    return WalletResponse(
      success: json['success'],
      message: json['message'] ?? '',
      clientSecret: json['clientSecret'] ?? '',
      ephemeralKey: json['ephemeralKey'] ?? '',
      customer: json['customer'] ?? '',
      transactionId: json['transactionId'] ?? '',
      publishableKey: json['publishableKey'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'message': message,
      'clientSecret': clientSecret,
      'ephemeralKey': ephemeralKey,
      'customer': customer,
      'transactionId': transactionId,
      'publishableKey': publishableKey,
    };
  }
}

class CouponResponse {
  final bool success;
  final String message;
  final String? discountCode;
  final double? discountAmount;
  final double? amount;
  final double? amountBeforeDiscount;

  const CouponResponse({
    required this.success,
    required this.message,
    this.discountCode,
    this.discountAmount,
    this.amount,
    this.amountBeforeDiscount,
  });

  factory CouponResponse.fromJson(Map<String, dynamic> json) {
    return CouponResponse(
      success: json['success'] ?? false,
      message: json['message'] ?? '',
      discountCode: json['discountCode'] as String?,
      discountAmount: _parseDouble(json['discountAmount']),
      amount: _parseDouble(json['amount']),
      amountBeforeDiscount: _parseDouble(json['discountAmountAgo']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'message': message,
      'discountCode': discountCode,
      'discountAmount': discountAmount,
      'amount': amount,
      'discountAmountAgo': amountBeforeDiscount,
    };
  }

  static double? _parseDouble(dynamic value) =>
      value == null ? null : double.tryParse(value.toString());

  @override
  String toString() {
    return 'CouponResponse(success: $success, message: $message, '
        'discountCode: $discountCode, discountAmount: $discountAmount, '
        'amount: $amount, amountBeforeDiscount: $amountBeforeDiscount)';
  }
}

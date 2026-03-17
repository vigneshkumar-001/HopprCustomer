class GetWalletBalanceResponse {
  final String message;
  final bool success;
  final WalletBalance data;

  GetWalletBalanceResponse({
    required this.message,
    required this.data,
    required this.success,
  });

  factory GetWalletBalanceResponse.fromJson(Map<String, dynamic> json) {
    return GetWalletBalanceResponse(
      message: json['message'],
      success: json['success'],
      data: WalletBalance.fromJson(json['data']),
    );
  }
  Map<String, dynamic> toJson() => {
    'message': message,
    'success': success,
    'data': data.toJson(),
  };
}

class WalletBalance {
  final String customerWalletBalance;
  final String minimumWalletAddBalance;

  WalletBalance({
    required this.customerWalletBalance,
    required this.minimumWalletAddBalance,
  });

  factory WalletBalance.fromJson(Map<String, dynamic> json) {
    return WalletBalance(
      customerWalletBalance: json['customerWalletBalance'] ?? '0',
      minimumWalletAddBalance: json['minimumWalletAddBalance'] ?? '0',
    );
  }

  Map<String, dynamic> toJson() => {
    'customerWalletBalance': customerWalletBalance,
    'minimumWalletAddBalance': minimumWalletAddBalance,
  };
}

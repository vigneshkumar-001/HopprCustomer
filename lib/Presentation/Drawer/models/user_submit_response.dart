class UserSubmitResponse {
  final bool success;
  final String message;
  UserSubmitResponse({required this.message, required this.success});

  factory UserSubmitResponse.fromJson(Map<String, dynamic> json) {
    return UserSubmitResponse(
      success: json['success'],
      message: json['message'] ?? '',
    );
  }
  Map<String, dynamic> toJson() => {"message": message, "success": success};
}

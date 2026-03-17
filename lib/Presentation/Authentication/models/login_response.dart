class LoginResponse {
  final int status;

  final String message;

  LoginResponse({required this.status, required this.message});

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      message: json['message'] ?? '',
      status: json['status'] ?? 0,
    );
  }
  Map<String, dynamic> toJson() {
    return {'status': status, 'message': message};
  }
}

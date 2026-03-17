class SosResponse {
  final bool success;
  final String sosNumber;
  final String gMapKey;

  SosResponse({
    required this.success,
    required this.sosNumber,
    required this.gMapKey,
  });

  factory SosResponse.fromJson(Map<String, dynamic> json) {
    return SosResponse(
      success: json['success'] ?? false,
      sosNumber: json['sosNumber'] ?? '',
      gMapKey: json['gMapKey'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'success': success, 'sosNumber': sosNumber, 'gMapKey': gMapKey};
  }
}

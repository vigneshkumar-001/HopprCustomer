/// Backend ride receipt (single source of truth for the amounts shown on the
/// "Payment Successful" sheet). Same shape is returned by:
///   - POST /api/customer/paymentBooking  (COD, inline `receipt`)
///   - GET  /api/customer/ride-receipt/{bookingId}  (universal, all methods)
///
/// Parsing is fully defensive — every field tolerates null / wrong types so the
/// success sheet can never crash on a partial payload.
class RideReceiptResponse {
  final bool success;
  final ReceiptData? data;
  final String html; // styled invoice HTML -> used to build the PDF
  final String text; // plain text -> used for Copy / Share

  const RideReceiptResponse({
    required this.success,
    required this.data,
    required this.html,
    required this.text,
  });

  factory RideReceiptResponse.fromJson(Map<String, dynamic> json) {
    final dynamic d = json['data'];
    final bool ok =
        json['success'] == true || json['success']?.toString() == 'true';
    return RideReceiptResponse(
      success: ok,
      data: d is Map<String, dynamic> ? ReceiptData.fromJson(d) : null,
      html: (json['html'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
    );
  }

  bool get hasText => text.trim().isNotEmpty;
  bool get hasHtml => html.trim().isNotEmpty;
}

class ReceiptData {
  final String currency;
  final String bookingId;
  final String rideType;
  final String status;
  final String rideDate;
  final String paymentMethod;
  final String paymentStatus;
  final String driverName;
  final double driverRating;
  final double total;
  final double discount;
  final String downloadPath;

  const ReceiptData({
    required this.currency,
    required this.bookingId,
    required this.rideType,
    required this.status,
    required this.rideDate,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.driverName,
    required this.driverRating,
    required this.total,
    required this.discount,
    required this.downloadPath,
  });

  factory ReceiptData.fromJson(Map<String, dynamic> json) {
    final dynamic payment = json['payment'];
    final dynamic driver = json['driver'];
    final dynamic fare = json['fare'];

    String pick(dynamic map, String key) =>
        (map is Map && map[key] != null) ? map[key].toString() : '';

    return ReceiptData(
      currency: (json['currency'] ?? '').toString(),
      bookingId: (json['bookingId'] ?? '').toString(),
      rideType: (json['rideType'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      // Prefer rideDate, fall back to completedAt.
      rideDate:
          (json['rideDate'] ?? json['completedAt'] ?? '').toString(),
      paymentMethod: pick(payment, 'method'),
      paymentStatus: pick(payment, 'status'),
      driverName: pick(driver, 'name'),
      driverRating: _toDouble(driver is Map ? driver['rating'] : null),
      total: _toDouble(fare is Map ? fare['total'] : null),
      discount: _toDouble(fare is Map ? fare['discount'] : null),
      downloadPath: (json['downloadPath'] ?? '').toString(),
    );
  }

  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  /// "₦816.05" — currency + total, safe when currency is empty.
  String get formattedTotal => '$currency${total.toStringAsFixed(2)}';

  /// "vignesh kumar ⭐ 4.14" — only appends rating when we actually have one.
  String get driverWithRating {
    final name = driverName.trim();
    if (name.isEmpty) return '-';
    if (driverRating <= 0) return name;
    return '$name ⭐ ${driverRating.toStringAsFixed(2)}';
  }
}

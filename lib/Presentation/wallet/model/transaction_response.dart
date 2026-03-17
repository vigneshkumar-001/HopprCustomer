// Updated transaction models with pagination fields and robust JSON parsing.
// Use these to parse the API payload you posted (includes page, limit, totalPages, etc).

class TransactionResponse {
  final bool success;
  final String balance;
  final int? page;
  final int? limit;
  final int? totalPages;
  final int? totalTransactions;
  final List<Transaction> transactions;

  TransactionResponse({
    required this.success,
    required this.balance,
    this.page,
    this.limit,
    this.totalPages,
    this.totalTransactions,
    this.transactions = const [],
  });

  factory TransactionResponse.fromJson(Map<String, dynamic> json) {
    return TransactionResponse(
      success: json['success'] ?? false,
      balance: json['balance']?.toString() ?? '0',
      page: _toInt(json['page']),
      limit: _toInt(json['limit']),
      totalPages: _toInt(json['totalPages']),
      totalTransactions: _toInt(json['totalTransactions']) ?? _toInt(json['totalTransactions']),
      transactions: (json['transactions'] as List<dynamic>?)
          ?.map((e) => Transaction.fromJson(e as Map<String, dynamic>))
          .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
    'success': success,
    'balance': balance,
    'page': page,
    'limit': limit,
    'totalPages': totalPages,
    'totalTransactions': totalTransactions,
    'transactions': transactions.map((t) => t.toJson()).toList(),
  };
}

/* ---------------- Transaction ---------------- */

class Transaction {
  final String id;
  final double amount;
  final String type;
  final String paymentMode;
  final String status;
  final String? paymentId;
  final String? bookingId;
  final String? bookingType;
  final String createdAt; // the API returns formatted string e.g. "Oct 29 • 11:52 AM"
  final String displayText;
  final String walletDescription;
  final String imageType;
  final String color;
  final Booking? booking;
  final Payment? payment;

  Transaction({
    required this.id,
    required this.amount,
    required this.type,
    required this.paymentMode,
    required this.status,
    this.paymentId,
    this.bookingId,
    this.bookingType,
    required this.createdAt,
    required this.displayText,
    required this.walletDescription,
    required this.imageType,
    required this.color,
    this.booking,
    this.payment,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: (json['_id'] ?? '').toString(),
      amount: _toDouble(json['amount']) ?? 0.0,
      type: (json['type'] ?? '').toString(),
      paymentMode: (json['paymentMode'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      paymentId: json['paymentId']?.toString(),
      bookingId: json['bookingId']?.toString(),
      bookingType: json['bookingType']?.toString(),
      createdAt: (json['createdAt'] ?? '').toString(),
      displayText: (json['displayText'] ?? '').toString(),
      walletDescription: (json['walletDescription'] ?? '').toString(),
      imageType: (json['imageType'] ?? '').toString(),
      color: (json['color'] ?? '').toString(),
      booking: (json['booking'] is Map) ? Booking.fromJson(Map<String, dynamic>.from(json['booking'])) : null,
      payment: (json['payment'] is Map) ? Payment.fromJson(Map<String, dynamic>.from(json['payment'])) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    '_id': id,
    'amount': amount,
    'type': type,
    'paymentMode': paymentMode,
    'status': status,
    'paymentId': paymentId,
    'bookingId': bookingId,
    'bookingType': bookingType,
    'createdAt': createdAt,
    'displayText': displayText,
    'walletDescription': walletDescription,
    'imageType': imageType,
    'color': color,
    'booking': booking?.toJson(),
    'payment': payment?.toJson(),
  };
}

/* ---------------- Booking ----------------
   NOTE: some API responses return empty object for booking -> keep fields optional.
*/
class Booking {
  final String? status;
  final String? pickupAddress;
  final String? dropAddress;
  final String? createdAt; // keep as string because API sometimes sends formatted string

  Booking({
    this.status,
    this.pickupAddress,
    this.dropAddress,
    this.createdAt,
  });

  factory Booking.fromJson(Map<String, dynamic> json) {
    if (json.isEmpty) return Booking();
    return Booking(
      status: json['status']?.toString(),
      pickupAddress: json['pickupAddress']?.toString(),
      dropAddress: json['dropAddress']?.toString(),
      createdAt: json['createdAt']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'status': status,
    'pickupAddress': pickupAddress,
    'dropAddress': dropAddress,
    'createdAt': createdAt,
  };
}

/* ---------------- Payment ----------------
   Payment fields are optional and parsed defensively.
*/
class Payment {
  final String? id;
  final String? userBookingId;
  final String? status;
  final String? type;
  final String? paymentId;
  final String? createdAt; // keep as string / iso depending on API

  Payment({
    this.id,
    this.userBookingId,
    this.status,
    this.type,
    this.paymentId,
    this.createdAt,
  });

  factory Payment.fromJson(Map<String, dynamic> json) {
    if (json.isEmpty) return Payment();
    return Payment(
      id: json['_id']?.toString(),
      userBookingId: json['userBookingId']?.toString(),
      status: json['status']?.toString(),
      type: json['type']?.toString(),
      paymentId: json['paymentId']?.toString(),
      createdAt: json['createdAt']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    '_id': id,
    'userBookingId': userBookingId,
    'status': status,
    'type': type,
    'paymentId': paymentId,
    'createdAt': createdAt,
  };
}

/* ---------------- Helpers ---------------- */

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is String) return int.tryParse(v);
  if (v is double) return v.toInt();
  return null;
}

double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}


// class TransactionResponse {
//   final bool success;
//   final String balance;
//   final String totalTransactions;
//   final List<Transaction> transactions;
//
//   TransactionResponse({
//     required this.success,
//     required this.balance,
//     required this.totalTransactions,
//     required this.transactions,
//   });
//
//   factory TransactionResponse.fromJson(Map<String, dynamic> json) {
//     return TransactionResponse(
//       success: json['success'] ?? false,
//       balance: json['balance'] ?? '0',
//       totalTransactions: json['totalTransactions'] ?? '0',
//       transactions:
//           (json['transactions'] as List<dynamic>?)
//               ?.map((e) => Transaction.fromJson(e))
//               .toList() ??
//           [],
//     );
//   }
// }
//
// class Transaction {
//   final String id;
//   final double amount;
//   final String type;
//   final String paymentMode;
//   final String status;
//   final String? paymentId;
//   final String? bookingId;
//   final String? bookingType;
//   final String createdAt; // formatted date string like "Sep 25 • 7:39 PM"
//   final String displayText;
//   final String walletDescription;
//   final String imageType;
//   final String color;
//   final Booking? booking;
//   final Payment? payment;
//
//   Transaction({
//     required this.id,
//     required this.amount,
//     required this.type,
//     required this.paymentMode,
//     required this.status,
//     this.paymentId,
//     this.bookingId,
//     this.bookingType,
//     required this.createdAt,
//     required this.displayText,
//     required this.walletDescription,
//     required this.imageType,
//     required this.color,
//     this.booking,
//     this.payment,
//   });
//
//   factory Transaction.fromJson(Map<String, dynamic> json) {
//     return Transaction(
//       id: json['_id'] ?? '',
//       amount: (json['amount'] ?? 0).toDouble(),
//       type: json['type'] ?? '',
//       paymentMode: json['paymentMode'] ?? '',
//       status: json['status'] ?? '',
//       paymentId: json['paymentId'],
//       bookingId: json['bookingId'],
//       bookingType: json['bookingType'],
//       createdAt: json['createdAt'] ?? '',
//       displayText: json['displayText'] ?? '',
//       imageType: json['imageType'] ?? '',
//       walletDescription: json['walletDescription'] ?? '',
//       color: json['color'] ?? '',
//       booking:
//           json['booking'] != null ? Booking.fromJson(json['booking']) : null,
//       payment:
//           json['payment'] != null ? Payment.fromJson(json['payment']) : null,
//     );
//   }
// }
//
// class Booking {
//   final String status;
//   final String pickupAddress;
//   final String dropAddress;
//   final DateTime createdAt;
//
//   Booking({
//     required this.status,
//     required this.pickupAddress,
//     required this.dropAddress,
//     required this.createdAt,
//   });
//
//   factory Booking.fromJson(Map<String, dynamic> json) {
//     return Booking(
//       status: json['status'] ?? '',
//       pickupAddress: json['pickupAddress'] ?? '',
//       dropAddress: json['dropAddress'] ?? '',
//       createdAt: DateTime.parse(json['createdAt']),
//     );
//   }
// }
//
// class Payment {
//   final String id;
//   final String userBookingId;
//   final String status;
//   final String type;
//   final String paymentId;
//   final DateTime createdAt;
//
//   Payment({
//     required this.id,
//     required this.userBookingId,
//     required this.status,
//     required this.type,
//     required this.paymentId,
//     required this.createdAt,
//   });
//
//   factory Payment.fromJson(Map<String, dynamic> json) {
//     return Payment(
//       id: json['_id'] ?? '',
//       userBookingId: json['userBookingId'] ?? '',
//       status: json['status'] ?? '',
//       type: json['type'] ?? '',
//       paymentId: json['paymentId'] ?? '',
//       createdAt: DateTime.parse(json['createdAt']),
//     );
//   }
// }

/// A Paystack saved card returned by GET /api/customer/cards.
///
/// The full card number is NEVER stored or returned — only the safe display
/// fields (last 4, brand, bank, label). Parsing is fully defensive so the
/// payment screen can never crash on a partial payload.
class SavedCard {
  final String id;
  final String last4;
  final String cardType; // e.g. "visa", "mastercard"
  final String bank;
  final String label; // optional server-formatted label

  const SavedCard({
    required this.id,
    required this.last4,
    required this.cardType,
    required this.bank,
    required this.label,
  });

  factory SavedCard.fromJson(Map<String, dynamic> json) {
    return SavedCard(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      last4: (json['last4'] ?? json['last_4'] ?? '').toString(),
      cardType: (json['cardType'] ?? json['brand'] ?? '').toString(),
      bank: (json['bank'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
    );
  }

  /// "Visa •••• 1234" — brand + last4, with safe fallbacks.
  String get display {
    final brand = cardType.trim().isNotEmpty
        ? _capitalize(cardType.trim())
        : (label.trim().isNotEmpty ? label.trim() : 'Card');
    final l4 = last4.trim();
    return l4.isEmpty ? brand : '$brand •••• $l4';
  }

  bool get isValid => id.trim().isNotEmpty;

  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

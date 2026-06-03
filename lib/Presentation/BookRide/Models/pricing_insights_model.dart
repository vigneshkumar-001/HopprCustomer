class PricingInsights {
  final bool hasDynamicPricing;
  final double totalIncreaseAmount;
  final int reasonCount;
  final List<String> labels;
  final String summary;
  final List<PricingReason> activeReasons;

  const PricingInsights({
    required this.hasDynamicPricing,
    required this.totalIncreaseAmount,
    required this.reasonCount,
    required this.labels,
    required this.summary,
    required this.activeReasons,
  });

  factory PricingInsights.fromJson(Map<String, dynamic> json) {
    return PricingInsights(
      hasDynamicPricing: json['hasDynamicPricing'] == true,
      totalIncreaseAmount: _asDouble(json['totalIncreaseAmount']),
      reasonCount: _asInt(json['reasonCount']),
      labels:
          (json['labels'] as List<dynamic>? ?? const [])
              .map((item) => item.toString())
              .toList(),
      summary: (json['summary'] ?? '').toString(),
      activeReasons:
          (json['activeReasons'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(PricingReason.fromJson)
              .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'hasDynamicPricing': hasDynamicPricing,
      'totalIncreaseAmount': totalIncreaseAmount,
      'reasonCount': reasonCount,
      'labels': labels,
      'summary': summary,
      'activeReasons': activeReasons.map((item) => item.toJson()).toList(),
    };
  }
}

class PricingReason {
  final String code;
  final String label;
  final double amount;
  final double percentage;
  final Map<String, dynamic>? details;

  const PricingReason({
    required this.code,
    required this.label,
    required this.amount,
    required this.percentage,
    this.details,
  });

  factory PricingReason.fromJson(Map<String, dynamic> json) {
    return PricingReason(
      code: (json['code'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      amount: _asDouble(json['amount']),
      percentage: _asDouble(json['percentage']),
      details:
          json['details'] is Map<String, dynamic>
              ? json['details'] as Map<String, dynamic>
              : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'label': label,
      'amount': amount,
      'percentage': percentage,
      'details': details,
    };
  }
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse((value ?? '').toString()) ?? 0.0;
}

int _asInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse((value ?? '').toString()) ?? 0;
}

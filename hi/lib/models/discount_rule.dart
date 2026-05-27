class DiscountRule {
  final int id;
  final String paymentSoftware;
  final String paymentMethod;
  final String userLevel;
  final double discountAmount;
  final double minSpend;
  final double equivalentRate;
  final bool isSpecial;
  final String startDate;
  final String endDate;
  final double availableDays;
  final String ruleDesc;

  const DiscountRule({
    required this.id,
    required this.paymentSoftware,
    required this.paymentMethod,
    required this.userLevel,
    required this.discountAmount,
    required this.minSpend,
    required this.equivalentRate,
    required this.isSpecial,
    required this.startDate,
    required this.endDate,
    required this.availableDays,
    required this.ruleDesc,
  });

  factory DiscountRule.fromMap(Map<String, dynamic> m) => DiscountRule(
        id: (m['id'] as num).toInt(),
        paymentSoftware: m['payment_software'] as String,
        paymentMethod: m['payment_method'] as String,
        userLevel: m['user_level'] as String,
        discountAmount: (m['discount_amount'] as num).toDouble(),
        minSpend: (m['min_spend'] as num).toDouble(),
        equivalentRate: (m['equivalent_rate'] as num).toDouble(),
        isSpecial: (m['is_special'] as num) == 1,
        startDate: m['start_date'] as String,
        endDate: m['end_date'] as String,
        availableDays: (m['available_days'] as num).toDouble(),
        ruleDesc: m['rule_desc'] as String,
      );
}

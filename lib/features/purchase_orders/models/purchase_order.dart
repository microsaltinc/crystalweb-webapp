class PurchaseOrder {
  PurchaseOrder({
    required this.id,
    required this.code,
    required this.createdAt,
  });

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    return PurchaseOrder(
      id: json['id'] as String,
      code: json['code'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String code;
  final DateTime createdAt;
}

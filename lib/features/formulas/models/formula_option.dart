class FormulaOption {
  FormulaOption({
    required this.id,
    required this.category,
    required this.code,
    required this.label,
    required this.active,
    required this.sortOrder,
  });

  factory FormulaOption.fromJson(Map<String, dynamic> json) {
    return FormulaOption(
      id: json['id'] as String,
      category: json['category'] as String,
      code: json['code'] as String,
      label: json['label'] as String,
      active: json['active'] as bool? ?? true,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }

  final String id;
  final String category;
  final String code;
  final String label;
  final bool active;
  final int sortOrder;
}

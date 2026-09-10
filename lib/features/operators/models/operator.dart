class OperatorRole {
  const OperatorRole({required this.id, required this.name});

  factory OperatorRole.fromJson(Map<String, dynamic> json) {
    return OperatorRole(id: json['id'] as String, name: json['name'] as String);
  }

  final String id;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

class Operator {
  Operator({
    required this.id,
    required this.name,
    required this.active,
    required this.hasPin,
    required this.createdAt,
    required this.email,
    this.sessionEmail,
    this.phone,
    required this.managedBy,
    this.roles = const [],
  });

  factory Operator.fromJson(Map<String, dynamic> json) {
    final rolesList = json['roles'] as List?;
    return Operator(
      id: json['id'] as String,
      name: json['name'] as String,
      active: json['active'] as bool,
      hasPin: json['has_pin'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      email: json['email'] as String? ?? '',
      sessionEmail: json['session_email'] as String?,
      phone: json['phone'] as String?,
      managedBy: json['managed_by'] as String? ?? '',
      roles:
          rolesList
              ?.map((r) => OperatorRole.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  final String id;
  final String name;
  final bool active;
  final bool hasPin;
  final DateTime createdAt;
  final String email;
  final String? sessionEmail;
  final String? phone;
  final String managedBy;
  final List<OperatorRole> roles;

  List<String> get roleNames => roles.map((r) => r.name).toList();
  bool get isResearcher => roleNames.contains('researcher');
  bool get isProduction => roleNames.contains('production');
  bool get isDualRole => isResearcher && isProduction;

  String get responsibleSessionEmail {
    final explicitSessionEmail = sessionEmail?.trim() ?? '';
    if (explicitSessionEmail.isNotEmpty) return explicitSessionEmail;
    if (managedBy.isNotEmpty) return managedBy;
    return email;
  }

  String get ownershipLabel {
    final operatorEmail = email.trim();
    const domain = '@microsaltinc.com';
    final account = operatorEmail.toLowerCase().endsWith(domain)
        ? operatorEmail.substring(0, operatorEmail.length - domain.length)
        : operatorEmail;
    if (account.isEmpty) return name;
    return '$name — $account';
  }

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'active': active,
    'has_pin': hasPin,
    'created_at': createdAt.toIso8601String(),
    'email': email,
    'session_email': sessionEmail,
    'phone': phone,
    'managed_by': managedBy,
    'roles': roles.map((r) => r.toJson()).toList(),
  };
}

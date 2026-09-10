class CampaignAssignmentCandidate {
  const CampaignAssignmentCandidate({
    required this.id,
    required this.name,
    this.email,
  });

  factory CampaignAssignmentCandidate.fromJson(Map<String, dynamic> json) =>
      CampaignAssignmentCandidate(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String?,
      );

  final String id;
  final String name;
  final String? email;

  String get accountLocalPart {
    final value = email?.trim() ?? '';
    const domain = '@microsaltinc.com';
    if (value.toLowerCase().endsWith(domain)) {
      return value.substring(0, value.length - domain.length);
    }
    return value;
  }

  String get accountLabel =>
      accountLocalPart.isEmpty ? '(account unavailable)' : '($accountLocalPart)';
}

class CampaignComment {
  const CampaignComment({
    required this.id,
    required this.batchId,
    required this.authorOperatorId,
    required this.authorOperatorName,
    required this.authorOperatorActive,
    required this.authorSessionEmail,
    this.authorRequiresOperatorName = false,
    required this.text,
    required this.createdAt,
  });

  factory CampaignComment.fromJson(Map<String, dynamic> json) {
    return CampaignComment(
      id: json['id'] as String,
      batchId: json['batch_id'] as String,
      authorOperatorId: json['author_operator_id'] as String,
      authorOperatorName: json['author_operator_name'] as String? ?? '',
      authorOperatorActive: json['author_operator_active'] as bool? ?? false,
      authorSessionEmail: json['author_session_email'] as String? ?? '',
      authorRequiresOperatorName:
          json['author_requires_operator_name'] as bool? ?? false,
      text: json['text'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String batchId;
  final String authorOperatorId;
  final String authorOperatorName;
  final bool authorOperatorActive;
  final String authorSessionEmail;
  final bool authorRequiresOperatorName;
  final String text;
  final DateTime createdAt;

  String get authorDisplayLabel {
    if (authorRequiresOperatorName &&
        authorSessionEmail.isNotEmpty &&
        authorOperatorName.isNotEmpty) {
      return '$authorSessionEmail — $authorOperatorName';
    }
    if (authorSessionEmail.isNotEmpty) return authorSessionEmail;
    return authorOperatorName.isNotEmpty
        ? authorOperatorName
        : 'Unknown author';
  }

  String get authorDisplayWithStatus => authorOperatorActive
      ? authorDisplayLabel
      : '$authorDisplayLabel (inactive)';

  Map<String, dynamic> toJson() => {
    'id': id,
    'batch_id': batchId,
    'author_operator_id': authorOperatorId,
    'author_operator_name': authorOperatorName,
    'author_operator_active': authorOperatorActive,
    'author_session_email': authorSessionEmail,
    'author_requires_operator_name': authorRequiresOperatorName,
    'text': text,
    'created_at': createdAt.toIso8601String(),
  };
}

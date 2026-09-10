enum CampaignQualificationStatus {
  pendingReview('pending_review', 'Pending Review'),
  accepted('accepted', 'Accepted'),
  acceptedWithExclusions(
    'accepted_with_exclusions',
    'Accepted with Exclusions',
  ),
  rejected('rejected', 'Rejected');

  const CampaignQualificationStatus(this.key, this.label);
  final String key;
  final String label;

  static CampaignQualificationStatus fromJson(Object? value) =>
      values.firstWhere(
        (status) => status.key == value,
        orElse: () => throw FormatException(
          'Unknown campaign qualification status: $value',
        ),
      );
}

enum BagQualificationStatus {
  pendingReview('pending_review', 'Pending Review'),
  accepted('accepted', 'Accepted'),
  rejected('rejected', 'Rejected');

  const BagQualificationStatus(this.key, this.label);
  final String key;
  final String label;

  static BagQualificationStatus fromJson(Object? value) => values.firstWhere(
    (status) => status.key == value,
    orElse: () =>
        throw FormatException('Unknown Bag qualification status: $value'),
  );
}

class QualificationReason {
  const QualificationReason(this.key, this.label);
  final String key;
  final String label;

  static const values = <QualificationReason>[
    QualificationReason(
      'crystal_size_above_specification',
      'Crystal size above specification',
    ),
    QualificationReason(
      'crystal_size_or_distribution_out_of_specification',
      'Crystal size or distribution otherwise out of specification',
    ),
    QualificationReason(
      'crystal_morphology_out_of_specification',
      'Crystal morphology out of specification',
    ),
    QualificationReason(
      'contamination_or_foreign_material',
      'Contamination or foreign material',
    ),
    QualificationReason(
      'insufficient_or_invalid_sample',
      'Insufficient or invalid sample',
    ),
    QualificationReason(
      'measurement_or_image_quality_issue',
      'Measurement or image-quality issue',
    ),
    QualificationReason('other', 'Other'),
  ];

  static QualificationReason? byKey(Object? key) {
    if (key == null) return null;
    return values.firstWhere(
      (reason) => reason.key == key,
      orElse: () => throw FormatException('Unknown rejection reason: $key'),
    );
  }
}

class BagQualification {
  const BagQualification({
    required this.id,
    required this.sublotId,
    required this.sublotIdentifier,
    required this.number,
    required this.status,
    required this.imageCount,
    required this.operatorReviewed,
    this.reason,
    this.notes,
    this.decidedAt,
    this.decidedByOperatorId,
  });

  factory BagQualification.fromJson(Map<String, dynamic> json) =>
      BagQualification(
        id: json['id'] as String,
        sublotId: json['sublot_id'] as String,
        sublotIdentifier: json['sublot_identifier'] as String,
        number: (json['number'] as num).toInt(),
        status: BagQualificationStatus.fromJson(json['status']),
        imageCount: (json['image_count'] as num?)?.toInt() ?? 0,
        operatorReviewed: json['operator_reviewed'] == true,
        reason: QualificationReason.byKey(json['reason_code']),
        notes: json['notes'] as String?,
        decidedAt: json['decided_at'] is String
            ? DateTime.parse(json['decided_at'] as String)
            : null,
        decidedByOperatorId: json['decided_by_operator_id'] as String?,
      );

  final String id;
  final String sublotId;
  final String sublotIdentifier;
  final int number;
  final BagQualificationStatus status;
  final int imageCount;
  final bool operatorReviewed;
  final QualificationReason? reason;
  final String? notes;
  final DateTime? decidedAt;
  final String? decidedByOperatorId;
}

class CampaignQualificationCurrent {
  const CampaignQualificationCurrent({
    required this.status,
    this.reason,
    this.notes,
    this.decidedAt,
    this.decidedByOperatorId,
  });
  factory CampaignQualificationCurrent.fromJson(Map<String, dynamic> json) =>
      CampaignQualificationCurrent(
        status: CampaignQualificationStatus.fromJson(json['status']),
        reason: QualificationReason.byKey(json['reason_code']),
        notes: json['notes'] as String?,
        decidedAt: json['decided_at'] is String
            ? DateTime.parse(json['decided_at'] as String)
            : null,
        decidedByOperatorId: json['decided_by_operator_id'] as String?,
      );
  final CampaignQualificationStatus status;
  final QualificationReason? reason;
  final String? notes;
  final DateTime? decidedAt;
  final String? decidedByOperatorId;
}

class CampaignQualification {
  const CampaignQualification({
    required this.batchId,
    required this.mode,
    required this.editState,
    required this.editStateVersion,
    required this.contentRevision,
    required this.campaign,
    required this.includedBags,
    required this.excludedBags,
    required this.pendingBagIds,
    required this.canFinalizeAs,
    required this.finalizationBlockers,
  });

  factory CampaignQualification.fromJson(Map<String, dynamic> json) {
    List<BagQualification> bags(String key) => (json[key] as List? ?? const [])
        .map(
          (item) =>
              BagQualification.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
    return CampaignQualification(
      batchId: json['batch_id'] as String,
      mode: json['mode'] as String,
      editState: json['edit_state'] as String,
      editStateVersion: (json['edit_state_version'] as num).toInt(),
      contentRevision: (json['content_revision'] as num).toInt(),
      campaign: CampaignQualificationCurrent.fromJson(
        Map<String, dynamic>.from(json['campaign'] as Map),
      ),
      includedBags: bags('included_bags'),
      excludedBags: bags('excluded_bags'),
      pendingBagIds: (json['pending_bag_ids'] as List? ?? const [])
          .cast<String>(),
      canFinalizeAs: (json['can_finalize_as'] as List? ?? const [])
          .map(CampaignQualificationStatus.fromJson)
          .toList(growable: false),
      finalizationBlockers: (json['finalization_blockers'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false),
    );
  }

  final String batchId;
  final String mode;
  final String editState;
  final int editStateVersion;
  final int contentRevision;
  final CampaignQualificationCurrent campaign;
  final List<BagQualification> includedBags;
  final List<BagQualification> excludedBags;
  final List<String> pendingBagIds;
  final List<CampaignQualificationStatus> canFinalizeAs;
  final List<Map<String, dynamic>> finalizationBlockers;
  bool get isLocked => editState == 'locked';
  List<BagQualification> get allBags => [...includedBags, ...excludedBags];
}

class QualificationMutationResult {
  const QualificationMutationResult({
    required this.changed,
    required this.batchId,
    required this.editStateVersion,
    required this.contentRevision,
    required this.data,
  });
  factory QualificationMutationResult.fromJson(Map<String, dynamic> json) =>
      QualificationMutationResult(
        changed: json['changed'] == true,
        batchId: json['batch_id'] as String,
        editStateVersion: (json['edit_state_version'] as num).toInt(),
        contentRevision: (json['content_revision'] as num).toInt(),
        data: Map.unmodifiable(json),
      );
  final bool changed;
  final String batchId;
  final int editStateVersion;
  final int contentRevision;
  final Map<String, dynamic> data;
}

class QualificationHistoryPage {
  const QualificationHistoryPage({required this.items, this.nextCursor});
  factory QualificationHistoryPage.fromJson(Map<String, dynamic> json) =>
      QualificationHistoryPage(
        items: (json['items'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false),
        nextCursor: json['next_cursor'] as String?,
      );
  final List<Map<String, dynamic>> items;
  final String? nextCursor;
}

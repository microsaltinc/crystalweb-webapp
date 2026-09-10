class Batch {
  Batch({
    required this.id,
    required this.lotCode,
    required this.formulaCode,
    required this.dryerCode,
    required this.campaignNum,
    required this.sublotCount,
    required this.imageCount,
    this.processedCount = 0,
    this.crystalCount = 0,
    this.autoCrystalCount = 0,
    this.operatorCrystalCount = 0,
    this.acceptedImageCount = 0,
    this.acceptedCrystalCount = 0,
    this.acceptedAutoCrystalCount = 0,
    this.acceptedOperatorCrystalCount = 0,
    required this.status,
    required this.createdAt,
    this.purchaseOrderId,
    this.purchaseOrderCode,
    this.projectId,
    this.projectName,
    this.ownerOperatorId,
    this.ownerOperatorName,
    this.ownerOperatorActive,
    this.ownerEmail,
    this.ownerSessionEmail,
    this.ownerRequiresOperatorName = false,
    this.ownershipVersion = 1,
    this.mode = 'production',
    this.workflowStatusId,
    this.workflowStatusKey = '',
    this.workflowStatusLabel = 'Unknown',
    this.workflowStatusColor = 'gray',
    this.workflowStatusDisplayOrder = 0,
    this.workflowStatusIsDefault = false,
    this.editState = 'editable',
    this.editStateVersion = 1,
    this.contentRevision = 1,
    this.editStateChangedAt,
    this.editStateChangedByUserId,
    this.editStateChangedByOperatorId,
    this.editStateChangedByOperatorName,
    this.editStateChangedBySessionEmail,
    this.editStateChangeReason,
    this.unresolvedRegistrationConflictCount = 0,
    this.sourceLotCode,
    this.qualificationStatus = 'pending_review',
    this.qualificationReasonCode,
    this.qualificationNotes,
    this.qualificationDecidedAt,
    this.qualificationDecidedByOperatorId,
    this.activeSublotCount = 0,
    this.activeBagCount = 0,
    this.excludedBagCount = 0,
    this.archivedSublotCount = 0,
    this.archivedBagCount = 0,
  });

  factory Batch.fromJson(Map<String, dynamic> json) {
    return Batch(
      id: json['id'] as String,
      lotCode: json['lot_code'] as String,
      formulaCode: json['formula_code'] as String? ?? '',
      dryerCode: json['dryer_code'] as String? ?? '',
      campaignNum: json['campaign_num'] as int? ?? 0,
      sublotCount: json['sublot_count'] as int? ?? 0,
      imageCount: json['image_count'] as int? ?? 0,
      processedCount: json['processed_count'] as int? ?? 0,
      crystalCount: json['crystal_count'] as int? ?? 0,
      autoCrystalCount: json['auto_crystal_count'] as int? ?? 0,
      operatorCrystalCount: json['operator_crystal_count'] as int? ?? 0,
      acceptedImageCount: (json['accepted_image_count'] as num?)?.toInt() ?? 0,
      acceptedCrystalCount:
          (json['accepted_crystal_count'] as num?)?.toInt() ?? 0,
      acceptedAutoCrystalCount:
          (json['accepted_auto_crystal_count'] as num?)?.toInt() ?? 0,
      acceptedOperatorCrystalCount:
          (json['accepted_operator_crystal_count'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'pending',
      createdAt: DateTime.parse(json['created_at'] as String),
      purchaseOrderId: json['purchase_order_id'] as String?,
      purchaseOrderCode: json['purchase_order_code'] as String?,
      projectId: json['project_id'] as String?,
      projectName: json['project_name'] as String?,
      ownerOperatorId: json['owner_operator_id'] as String?,
      ownerOperatorName: json['owner_operator_name'] as String?,
      ownerOperatorActive: json['owner_operator_active'] as bool?,
      ownerEmail: json['owner_email'] as String?,
      ownerSessionEmail: json['owner_session_email'] as String?,
      ownerRequiresOperatorName:
          json['owner_requires_operator_name'] as bool? ?? false,
      ownershipVersion: (json['ownership_version'] as num?)?.toInt() ?? 1,
      mode: json['mode'] as String? ?? 'production',
      workflowStatusId: json['workflow_status_id'] as String?,
      workflowStatusKey: json['workflow_status_key'] as String? ?? '',
      workflowStatusLabel:
          json['workflow_status_label'] as String? ?? 'Unknown',
      workflowStatusColor: json['workflow_status_color'] as String? ?? 'gray',
      workflowStatusDisplayOrder:
          json['workflow_status_display_order'] as int? ?? 0,
      workflowStatusIsDefault:
          json['workflow_status_is_default'] as bool? ?? false,
      editState: json['edit_state'] is String
          ? json['edit_state'] as String
          : 'editable',
      editStateVersion: json['edit_state_version'] is num
          ? (json['edit_state_version'] as num).toInt()
          : 1,
      contentRevision: json['content_revision'] is num
          ? (json['content_revision'] as num).toInt()
          : 1,
      editStateChangedAt: json['edit_state_changed_at'] is String
          ? DateTime.tryParse(json['edit_state_changed_at'] as String)
          : null,
      editStateChangedByUserId: json['edit_state_changed_by_user_id'] is String
          ? json['edit_state_changed_by_user_id'] as String
          : null,
      editStateChangedByOperatorId:
          json['edit_state_changed_by_operator_id'] is String
          ? json['edit_state_changed_by_operator_id'] as String
          : null,
      editStateChangedByOperatorName:
          json['edit_state_changed_by_operator_name'] is String
          ? json['edit_state_changed_by_operator_name'] as String
          : null,
      editStateChangedBySessionEmail:
          json['edit_state_changed_by_session_email'] is String
          ? json['edit_state_changed_by_session_email'] as String
          : null,
      editStateChangeReason: json['edit_state_change_reason'] is String
          ? json['edit_state_change_reason'] as String
          : null,
      unresolvedRegistrationConflictCount:
          json['unresolved_registration_conflict_count'] is num
          ? (json['unresolved_registration_conflict_count'] as num).toInt()
          : 0,
      sourceLotCode: json['source_lot_code'] as String?,
      qualificationStatus:
          json['qualification_status'] as String? ?? 'pending_review',
      qualificationReasonCode: json['qualification_reason_code'] as String?,
      qualificationNotes: json['qualification_notes'] as String?,
      qualificationDecidedAt: json['qualification_decided_at'] is String
          ? DateTime.tryParse(json['qualification_decided_at'] as String)
          : null,
      qualificationDecidedByOperatorId:
          json['qualification_decided_by_operator_id'] as String?,
      activeSublotCount: (json['active_sublot_count'] as num?)?.toInt() ?? 0,
      activeBagCount: (json['active_bag_count'] as num?)?.toInt() ?? 0,
      excludedBagCount: (json['excluded_bag_count'] as num?)?.toInt() ?? 0,
      archivedSublotCount:
          (json['archived_sublot_count'] as num?)?.toInt() ?? 0,
      archivedBagCount: (json['archived_bag_count'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String lotCode;
  final String formulaCode;
  final String dryerCode;
  final int campaignNum;
  final int sublotCount;
  final int imageCount;
  final int processedCount;
  final int crystalCount;
  final int autoCrystalCount;
  final int operatorCrystalCount;
  final int acceptedImageCount;
  final int acceptedCrystalCount;
  final int acceptedAutoCrystalCount;
  final int acceptedOperatorCrystalCount;
  final String status;
  final DateTime createdAt;
  final String? purchaseOrderId;
  final String? purchaseOrderCode;
  final String? projectId;
  final String? projectName;
  final String? ownerOperatorId;
  final String? ownerOperatorName;
  final bool? ownerOperatorActive;
  final String? ownerEmail;
  final String? ownerSessionEmail;
  final bool ownerRequiresOperatorName;
  final int ownershipVersion;
  final String mode;
  final String? workflowStatusId;
  final String workflowStatusKey;
  final String workflowStatusLabel;
  final String workflowStatusColor;
  final int workflowStatusDisplayOrder;
  final bool workflowStatusIsDefault;
  final String editState;
  final int editStateVersion;
  final int contentRevision;
  final DateTime? editStateChangedAt;
  final String? editStateChangedByUserId;
  final String? editStateChangedByOperatorId;
  final String? editStateChangedByOperatorName;
  final String? editStateChangedBySessionEmail;
  final String? editStateChangeReason;
  final int unresolvedRegistrationConflictCount;
  final String? sourceLotCode;
  final String qualificationStatus;
  final String? qualificationReasonCode;
  final String? qualificationNotes;
  final DateTime? qualificationDecidedAt;
  final String? qualificationDecidedByOperatorId;
  final int activeSublotCount;
  final int activeBagCount;
  final int excludedBagCount;
  final int archivedSublotCount;
  final int archivedBagCount;

  bool get isLocked => editState == 'locked';

  bool get workflowStatusIsDone => workflowStatusKey == 'done';

  String get displayName => '$lotCode $formulaCode';

  bool get hasOwner => ownerOperatorId != null;

  bool get ownerInactive => hasOwner && ownerOperatorActive == false;

  String get ownerDisplayLabel {
    if (!hasOwner) return 'Unassigned';
    final name = ownerOperatorName?.trim() ?? '';
    final email = ownerEmail?.trim() ?? ownerSessionEmail?.trim() ?? '';
    const domain = '@microsaltinc.com';
    final account = email.toLowerCase().endsWith(domain)
        ? email.substring(0, email.length - domain.length)
        : email;
    if (name.isNotEmpty && account.isNotEmpty) {
      return '$name — $account';
    }
    return name.isNotEmpty
        ? name
        : (account.isNotEmpty ? account : 'Unknown owner');
  }

  String get ownerDisplayWithStatus =>
      ownerInactive ? '$ownerDisplayLabel (inactive)' : ownerDisplayLabel;

  double get processingProgress =>
      imageCount > 0 ? processedCount / imageCount : 0.0;

  Map<String, dynamic> toJson() => {
    'id': id,
    'lot_code': lotCode,
    'formula_code': formulaCode,
    'dryer_code': dryerCode,
    'campaign_num': campaignNum,
    'sublot_count': sublotCount,
    'image_count': imageCount,
    'processed_count': processedCount,
    'crystal_count': crystalCount,
    'auto_crystal_count': autoCrystalCount,
    'operator_crystal_count': operatorCrystalCount,
    'accepted_image_count': acceptedImageCount,
    'accepted_crystal_count': acceptedCrystalCount,
    'accepted_auto_crystal_count': acceptedAutoCrystalCount,
    'accepted_operator_crystal_count': acceptedOperatorCrystalCount,
    'status': status,
    'created_at': createdAt.toIso8601String(),
    'purchase_order_id': purchaseOrderId,
    'purchase_order_code': purchaseOrderCode,
    'project_id': projectId,
    'project_name': projectName,
    'owner_operator_id': ownerOperatorId,
    'owner_operator_name': ownerOperatorName,
    'owner_operator_active': ownerOperatorActive,
    'owner_email': ownerEmail,
    'owner_session_email': ownerSessionEmail,
    'owner_requires_operator_name': ownerRequiresOperatorName,
    'ownership_version': ownershipVersion,
    'mode': mode,
    'workflow_status_id': workflowStatusId,
    'workflow_status_key': workflowStatusKey,
    'workflow_status_label': workflowStatusLabel,
    'workflow_status_color': workflowStatusColor,
    'workflow_status_display_order': workflowStatusDisplayOrder,
    'workflow_status_is_default': workflowStatusIsDefault,
    'edit_state': editState,
    'edit_state_version': editStateVersion,
    'content_revision': contentRevision,
    'edit_state_changed_at': editStateChangedAt?.toIso8601String(),
    'edit_state_changed_by_user_id': editStateChangedByUserId,
    'edit_state_changed_by_operator_id': editStateChangedByOperatorId,
    'edit_state_changed_by_operator_name': editStateChangedByOperatorName,
    'edit_state_changed_by_session_email': editStateChangedBySessionEmail,
    'edit_state_change_reason': editStateChangeReason,
    'unresolved_registration_conflict_count':
        unresolvedRegistrationConflictCount,
    'source_lot_code': sourceLotCode,
    'qualification_status': qualificationStatus,
    'qualification_reason_code': qualificationReasonCode,
    'qualification_notes': qualificationNotes,
    'qualification_decided_at': qualificationDecidedAt?.toIso8601String(),
    'qualification_decided_by_operator_id': qualificationDecidedByOperatorId,
    'active_sublot_count': activeSublotCount,
    'active_bag_count': activeBagCount,
    'excluded_bag_count': excludedBagCount,
    'archived_sublot_count': archivedSublotCount,
    'archived_bag_count': archivedBagCount,
    'workflow_status_is_done': workflowStatusIsDone,
  };
}

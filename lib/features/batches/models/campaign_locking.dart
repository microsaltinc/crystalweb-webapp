enum CampaignEditState {
  editable,
  locked;

  static CampaignEditState fromJson(Object? value) =>
      value == 'locked' ? CampaignEditState.locked : CampaignEditState.editable;
}

DateTime? _dateTime(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;
int _int(Object? value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;
String? _string(Object? value) => value is String ? value : null;

class ReadinessImageReference {
  const ReadinessImageReference({
    required this.id,
    required this.sublotLetter,
    required this.bagNumber,
    required this.imageNumber,
    required this.processingStatus,
  });

  factory ReadinessImageReference.fromJson(Map<String, dynamic> json) =>
      ReadinessImageReference(
        id: _string(json['id']) ?? '',
        sublotLetter: _string(json['sublot_letter']) ?? '',
        bagNumber: _int(json['bag_number']),
        imageNumber: _int(json['image_number']),
        processingStatus: _string(json['processing_status']) ?? 'pending',
      );

  final String id;
  final String sublotLetter;
  final int bagNumber;
  final int imageNumber;
  final String processingStatus;
}

class ReadinessBlocker {
  const ReadinessBlocker({
    required this.category,
    required this.message,
    required this.count,
    this.images = const [],
    this.sublots = const [],
  });

  factory ReadinessBlocker.fromJson(Map<String, dynamic> json) {
    final rawImages = json['images'];
    final rawSublots = json['sublots'];
    return ReadinessBlocker(
      category: _string(json['category']) ?? 'unknown',
      message: _string(json['message']) ?? '',
      count: _int(json['count']),
      images: rawImages is List
          ? rawImages
                .whereType<Map>()
                .map(
                  (item) => ReadinessImageReference.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const [],
      sublots: rawSublots is List
          ? rawSublots.whereType<String>().toList(growable: false)
          : const [],
    );
  }

  final String category;
  final String message;
  final int count;
  final List<ReadinessImageReference> images;
  final List<String> sublots;
}

class CampaignLockReadiness {
  const CampaignLockReadiness({
    this.batchId,
    this.editState = CampaignEditState.editable,
    this.editStateVersion = 1,
    required this.contentRevision,
    required this.ready,
    this.evaluatedAt,
    this.blockers = const [],
  });

  factory CampaignLockReadiness.fromJson(Map<String, dynamic> json) {
    final rawBlockers = json['blockers'];
    final blockers = rawBlockers is List
        ? rawBlockers
              .whereType<Map>()
              .map(
                (item) =>
                    ReadinessBlocker.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList(growable: false)
        : <ReadinessBlocker>[];
    return CampaignLockReadiness(
      batchId: _string(json['batch_id']),
      editState: CampaignEditState.fromJson(json['edit_state']),
      editStateVersion: _int(json['edit_state_version'], 1),
      contentRevision: _int(json['content_revision'], 1),
      // Blockers are authoritative when a malformed/legacy ready value disagrees.
      ready: json['ready'] is bool
          ? json['ready'] as bool && blockers.isEmpty
          : blockers.isEmpty,
      evaluatedAt: _dateTime(json['evaluated_at']),
      blockers: blockers,
    );
  }

  final String? batchId;
  final CampaignEditState editState;
  final int editStateVersion;
  final int contentRevision;
  final bool ready;
  final DateTime? evaluatedAt;
  final List<ReadinessBlocker> blockers;
}

class CampaignTransition {
  const CampaignTransition({
    required this.batchId,
    required this.editState,
    required this.editStateVersion,
    required this.contentRevision,
    required this.changed,
    this.changedAt,
    this.changedByUserId,
    this.changedByOperatorId,
    this.changedByOperatorName,
    this.reason,
  });

  factory CampaignTransition.fromJson(Map<String, dynamic> json) =>
      CampaignTransition(
        batchId: _string(json['batch_id']) ?? '',
        editState: CampaignEditState.fromJson(json['edit_state']),
        editStateVersion: _int(json['edit_state_version'], 1),
        contentRevision: _int(json['content_revision'], 1),
        changed: json['changed'] == true,
        changedAt: _dateTime(json['changed_at']),
        changedByUserId: _string(json['changed_by_user_id']),
        changedByOperatorId: _string(json['changed_by_operator_id']),
        changedByOperatorName: _string(json['changed_by_operator_name']),
        reason: _string(json['reason']),
      );

  final String batchId;
  final CampaignEditState editState;
  final int editStateVersion;
  final int contentRevision;
  final bool changed;
  final DateTime? changedAt;
  final String? changedByUserId;
  final String? changedByOperatorId;
  final String? changedByOperatorName;
  final String? reason;
}

class RegistrationObjectReference {
  const RegistrationObjectReference({
    required this.bucket,
    required this.key,
    this.versionOrEtag,
  });

  factory RegistrationObjectReference.fromJson(Map<String, dynamic> json) =>
      RegistrationObjectReference(
        bucket: _string(json['bucket']) ?? '',
        key: _string(json['key']) ?? '',
        versionOrEtag: _string(json['version_or_etag']),
      );

  final String bucket;
  final String key;
  final String? versionOrEtag;
}

class RegistrationConflict {
  const RegistrationConflict({
    required this.id,
    required this.batchId,
    required this.operationKind,
    required this.source,
    required this.object,
    required this.safeReason,
    this.reasonCode = 'campaign_locked',
    this.structureCandidates = const [],
    this.firstDetectedAt,
    this.lastSeenAt,
    required this.occurrenceCount,
    this.resolvedAt,
    this.resultImageId,
    required this.canRetry,
  });

  factory RegistrationConflict.fromJson(Map<String, dynamic> json) {
    final object = json['object'];
    return RegistrationConflict(
      id: _string(json['id']) ?? '',
      batchId: _string(json['batch_id']) ?? '',
      operationKind: _string(json['operation_kind']) ?? 'register_image',
      source: _string(json['source']) ?? 'lambda',
      object: RegistrationObjectReference.fromJson(
        object is Map ? Map<String, dynamic>.from(object) : const {},
      ),
      safeReason: _string(json['safe_reason']) ?? '',
      reasonCode: _string(json['reason_code']) ?? 'campaign_locked',
      structureCandidates: (json['structure_candidates'] as List? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false),
      firstDetectedAt: _dateTime(json['first_detected_at']),
      lastSeenAt: _dateTime(json['last_seen_at']),
      occurrenceCount: _int(json['occurrence_count'], 1),
      resolvedAt: _dateTime(json['resolved_at']),
      resultImageId: _string(json['result_image_id']),
      canRetry: json['can_retry'] == true,
    );
  }

  final String id;
  final String batchId;
  final String operationKind;
  final String source;
  final RegistrationObjectReference object;
  final String safeReason;
  final String reasonCode;
  final List<Map<String, dynamic>> structureCandidates;
  final DateTime? firstDetectedAt;
  final DateTime? lastSeenAt;
  final int occurrenceCount;
  final DateTime? resolvedAt;
  final String? resultImageId;
  final bool canRetry;
  bool get isResolved => resolvedAt != null;
}

class RegistrationConflictRetry {
  const RegistrationConflictRetry({
    required this.conflictId,
    required this.resolved,
    required this.contentRevision,
    this.resolvedAt,
    this.resultImageId,
    this.registrationAction,
  });

  factory RegistrationConflictRetry.fromJson(Map<String, dynamic> json) =>
      RegistrationConflictRetry(
        conflictId: _string(json['conflict_id']) ?? '',
        resolved: json['resolved'] == true,
        resolvedAt: _dateTime(json['resolved_at']),
        resultImageId: _string(json['result_image_id']),
        registrationAction: _string(json['registration_action']),
        contentRevision: _int(json['content_revision'], 1),
      );

  final String conflictId;
  final bool resolved;
  final DateTime? resolvedAt;
  final String? resultImageId;
  final String? registrationAction;
  final int contentRevision;
}

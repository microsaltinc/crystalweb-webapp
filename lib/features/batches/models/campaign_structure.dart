class StructureCapabilities {
  const StructureCapabilities({
    required this.canDelete,
    required this.canArchive,
    required this.canRestore,
    this.blockers = const [],
  });
  factory StructureCapabilities.fromJson(Map<String, dynamic> json) =>
      StructureCapabilities(
        canDelete: json['can_delete'] == true,
        canArchive: json['can_archive'] == true,
        canRestore: json['can_restore'] == true,
        blockers: (json['blockers'] as List? ?? const []).cast<String>(),
      );
  final bool canDelete;
  final bool canArchive;
  final bool canRestore;
  final List<String> blockers;
}

class CampaignBag {
  const CampaignBag({
    required this.id,
    required this.sublotId,
    required this.number,
    required this.sourceSublotId,
    required this.sourceNumber,
    required this.qualificationStatus,
    required this.imageCount,
    required this.archived,
    required this.effectivelyArchived,
    required this.capabilities,
    this.notes,
    this.reasonCode,
  });
  factory CampaignBag.fromJson(Map<String, dynamic> json) => CampaignBag(
    id: json['id'] as String,
    sublotId: json['sublot_id'] as String,
    number: (json['number'] as num).toInt(),
    sourceSublotId: json['source_sublot_id'] as String,
    sourceNumber: (json['source_number'] as num).toInt(),
    notes: json['notes'] as String?,
    qualificationStatus: json['qualification_status'] as String,
    reasonCode: json['reason_code'] as String?,
    imageCount: (json['image_count'] as num?)?.toInt() ?? 0,
    archived: json['archived'] == true,
    effectivelyArchived: json['effectively_archived'] == true,
    capabilities: StructureCapabilities.fromJson(json),
  );
  final String id;
  final String sublotId;
  final int number;
  final String sourceSublotId;
  final int sourceNumber;
  final String? notes;
  final String qualificationStatus;
  final String? reasonCode;
  final int imageCount;
  final bool archived;
  final bool effectivelyArchived;
  final StructureCapabilities capabilities;
  bool get isExcluded => qualificationStatus == 'rejected';
}

class CampaignSublot {
  const CampaignSublot({
    required this.id,
    required this.identifier,
    required this.sourceIdentifier,
    required this.archived,
    required this.bags,
    required this.capabilities,
    this.label,
    this.notes,
  });
  factory CampaignSublot.fromJson(Map<String, dynamic> json) => CampaignSublot(
    id: json['id'] as String,
    identifier: json['identifier'] as String,
    sourceIdentifier: json['source_identifier'] as String,
    label: json['label'] as String?,
    notes: json['notes'] as String?,
    archived: json['archived'] == true,
    bags:
        (json['bags'] as List? ?? const [])
            .map(
              (item) =>
                  CampaignBag.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList(growable: false)
          ..sort((a, b) => a.number.compareTo(b.number)),
    capabilities: StructureCapabilities.fromJson(json),
  );
  final String id;
  final String identifier;
  final String sourceIdentifier;
  final String? label;
  final String? notes;
  final bool archived;
  final List<CampaignBag> bags;
  final StructureCapabilities capabilities;
}

class CampaignStructure {
  const CampaignStructure({
    required this.batchId,
    this.customName,
    required this.lotCode,
    required this.sourceLotCode,
    required this.mode,
    required this.editState,
    required this.editStateVersion,
    required this.contentRevision,
    required this.activeSublots,
    required this.excludedBags,
    required this.archivedSublots,
    required this.archivedBags,
  });
  factory CampaignStructure.fromJson(Map<String, dynamic> json) {
    List<CampaignSublot> sublots(String key) =>
        (json[key] as List? ?? const [])
            .map(
              (item) => CampaignSublot.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false)
          ..sort((a, b) => a.identifier.compareTo(b.identifier));
    List<CampaignBag> bags(String key) => (json[key] as List? ?? const [])
        .map(
          (item) =>
              CampaignBag.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false);
    return CampaignStructure(
      batchId: json['batch_id'] as String,
      customName: json['custom_name'] as String?,
      lotCode: json['lot_code'] as String? ?? '',
      sourceLotCode: json['source_lot_code'] as String? ?? '',
      mode: json['mode'] as String,
      editState: json['edit_state'] as String,
      editStateVersion: (json['edit_state_version'] as num).toInt(),
      contentRevision: (json['content_revision'] as num).toInt(),
      activeSublots: sublots('active_sublots'),
      excludedBags: bags('excluded_bags'),
      archivedSublots: sublots('archived_sublots'),
      archivedBags: bags('archived_bags'),
    );
  }
  final String batchId;
  final String? customName;
  final String lotCode;
  final String sourceLotCode;
  final String mode;
  final String editState;
  final int editStateVersion;
  final int contentRevision;
  final List<CampaignSublot> activeSublots;
  final List<CampaignBag> excludedBags;
  final List<CampaignSublot> archivedSublots;
  final List<CampaignBag> archivedBags;
  bool get isLocked => editState == 'locked';
  List<CampaignBagDestination> get activeBagDestinations => [
    for (final sublot in activeSublots)
      for (final bag in sublot.bags)
        if (!bag.archived && !bag.effectivelyArchived)
          CampaignBagDestination(
            bag: bag,
            sublotIdentifier: sublot.identifier,
            sublotLabel: sublot.label,
          ),
  ];
}

class CampaignBagDestination {
  const CampaignBagDestination({
    required this.bag,
    required this.sublotIdentifier,
    this.sublotLabel,
  });

  final CampaignBag bag;
  final String sublotIdentifier;
  final String? sublotLabel;

  String get label => 'Sublot $sublotIdentifier · Bag ${bag.number}';
}

class StructureMutationResult {
  const StructureMutationResult({
    required this.changed,
    required this.batchId,
    required this.action,
    required this.campaignReset,
    required this.editStateVersion,
    required this.contentRevision,
    this.entityId,
    this.entity,
  });
  factory StructureMutationResult.fromJson(Map<String, dynamic> json) =>
      StructureMutationResult(
        changed: json['changed'] == true,
        batchId: json['batch_id'] as String,
        action: json['action'] as String,
        campaignReset: json['campaign_reset'] == true,
        editStateVersion: (json['edit_state_version'] as num).toInt(),
        contentRevision: (json['content_revision'] as num).toInt(),
        entityId: json['entity_id'] as String?,
        entity: json['entity'] is Map
            ? Map<String, dynamic>.from(json['entity'] as Map)
            : null,
      );
  final bool changed;
  final String batchId;
  final String action;
  final bool campaignReset;
  final int editStateVersion;
  final int contentRevision;
  final String? entityId;
  final Map<String, dynamic>? entity;
}

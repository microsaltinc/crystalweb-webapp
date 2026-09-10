class CampaignWorkflowStatus {
  const CampaignWorkflowStatus({
    required this.id,
    required this.key,
    required this.label,
    required this.color,
    required this.displayOrder,
    required this.isDefault,
    required this.isSystem,
    required this.isDone,
    required this.usageCount,
    required this.canDelete,
    this.deleteBlocker,
  });

  factory CampaignWorkflowStatus.fromJson(Map<String, dynamic> json) =>
      CampaignWorkflowStatus(
        id: json['id'] as String,
        key: json['key'] as String? ?? '',
        label: json['label'] as String? ?? 'Unknown',
        color: allowedColors.contains(json['color'])
            ? json['color'] as String
            : 'gray',
        displayOrder: json['display_order'] as int? ?? 0,
        isDefault: json['is_default'] as bool? ?? false,
        isSystem: json['is_system'] as bool? ?? false,
        isDone: json['is_done'] as bool? ?? json['key'] == 'done',
        usageCount: json['usage_count'] as int? ?? 0,
        canDelete: json['can_delete'] as bool? ?? false,
        deleteBlocker: json['delete_blocker'] as String?,
      );

  static const allowedColors = {
    'blue',
    'teal',
    'green',
    'amber',
    'orange',
    'purple',
    'gray',
    'red',
  };

  final String id;
  final String key;
  final String label;
  final String color;
  final int displayOrder;
  final bool isDefault;
  final bool isSystem;
  final bool isDone;
  final int usageCount;
  final bool canDelete;
  final String? deleteBlocker;
}

class CampaignWorkflowCatalog {
  const CampaignWorkflowCatalog({
    required this.version,
    required this.statuses,
  });

  factory CampaignWorkflowCatalog.fromJson(Map<String, dynamic> json) =>
      CampaignWorkflowCatalog(
        version: json['catalog_version'] as int? ?? 1,
        statuses: (json['statuses'] as List? ?? const [])
            .map(
              (item) =>
                  CampaignWorkflowStatus.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
      );

  final int version;
  final List<CampaignWorkflowStatus> statuses;
}

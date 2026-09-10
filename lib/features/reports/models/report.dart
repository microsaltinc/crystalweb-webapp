enum ReportStatus {
  pending,
  generating,
  complete,
  failed,
  error,
  blocked;

  static ReportStatus fromString(String value) {
    return ReportStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => ReportStatus.pending,
    );
  }
}

class Report {
  Report({
    required this.id,
    required this.batchId,
    required this.status,
    this.reportType = 'sublot',
    this.pdfUrl,
    this.csvUrl,
    this.sublotLetter,
    this.sublotName,
    this.bagNumber,
    this.bagLabel,
    this.sublotId,
    this.bagId,
    this.qualificationStatusSnapshot,
    this.qualificationEventId,
    this.qualificationSummary,
    this.dispositionLabel,
    this.isExcludedScope = false,
    this.serverLegacy = false,
    required this.createdAt,
    this.sourceContentRevision = 0,
    this.authorizedEditStateVersion = 0,
    this.jobToken,
    this.startedAt,
    this.finishedAt,
    this.terminalCode,
    this.isCurrent = false,
    this.isStale = true,
    this.supersededAt,
    this.supersededByReportId,
  });

  factory Report.fromJson(Map<String, dynamic> json) {
    return Report(
      id: json['id'] as String,
      batchId: json['batch_id'] as String,
      status: ReportStatus.fromString(json['status'] as String),
      reportType: json['report_type'] as String? ?? 'sublot',
      pdfUrl: json['pdf_url'] as String?,
      csvUrl: json['csv_url'] as String?,
      sublotLetter: json['sublot_letter'] as String?,
      sublotName: json['sublot_name'] as String?,
      bagNumber: json['bag_number'] as int?,
      bagLabel: json['bag_label'] as String?,
      sublotId: json['sublot_id'] as String?,
      bagId: json['bag_id'] as String?,
      qualificationStatusSnapshot:
          json['qualification_status_snapshot'] as String?,
      qualificationEventId: json['qualification_event_id'] as String?,
      qualificationSummary: json['qualification_summary'] is Map
          ? Map<String, dynamic>.from(json['qualification_summary'] as Map)
          : null,
      dispositionLabel: json['disposition_label'] as String?,
      isExcludedScope: json['is_excluded_scope'] == true,
      serverLegacy: json['is_legacy'] == true,
      createdAt: DateTime.parse(json['created_at'] as String),
      sourceContentRevision: json['source_content_revision'] is num
          ? (json['source_content_revision'] as num).toInt()
          : 0,
      authorizedEditStateVersion: json['authorized_edit_state_version'] is num
          ? (json['authorized_edit_state_version'] as num).toInt()
          : 0,
      jobToken: json['job_token'] is String
          ? json['job_token'] as String
          : null,
      startedAt: json['started_at'] is String
          ? DateTime.tryParse(json['started_at'] as String)
          : null,
      finishedAt: json['finished_at'] is String
          ? DateTime.tryParse(json['finished_at'] as String)
          : null,
      terminalCode: json['terminal_code'] is String
          ? json['terminal_code'] as String
          : null,
      isCurrent: json['is_current'] == true,
      isStale: json['is_stale'] is bool ? json['is_stale'] as bool : true,
      supersededAt: json['superseded_at'] is String
          ? DateTime.tryParse(json['superseded_at'] as String)
          : null,
      supersededByReportId: json['superseded_by_report_id'] is String
          ? json['superseded_by_report_id'] as String
          : null,
    );
  }

  final String id;
  final String batchId;
  final ReportStatus status;
  final String reportType;
  final String? pdfUrl;
  final String? csvUrl;
  final String? sublotLetter;
  final String? sublotName;
  final int? bagNumber;
  final String? bagLabel;
  final String? sublotId;
  final String? bagId;
  final String? qualificationStatusSnapshot;
  final String? qualificationEventId;
  final Map<String, dynamic>? qualificationSummary;
  final String? dispositionLabel;
  final bool isExcludedScope;
  final bool serverLegacy;
  final DateTime createdAt;
  final int sourceContentRevision;
  final int authorizedEditStateVersion;
  final String? jobToken;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final String? terminalCode;
  final bool isCurrent;
  final bool isStale;
  final DateTime? supersededAt;
  final String? supersededByReportId;

  bool get isSuperseded => supersededAt != null || supersededByReportId != null;

  bool get isLegacy => serverLegacy || sourceContentRevision == 0;

  String get currencyLabel {
    if (isSuperseded) return 'Superseded';
    if (isLegacy) return 'Legacy';
    if (isCurrent && !isStale) return 'Current';
    return 'Stale';
  }

  bool get isDownloadable =>
      status == ReportStatus.complete && (pdfUrl != null || csvUrl != null);

  bool get isPending =>
      status == ReportStatus.pending || status == ReportStatus.generating;

  bool get hasError =>
      status == ReportStatus.failed || status == ReportStatus.error;

  Map<String, dynamic> toJson() => {
    'id': id,
    'batch_id': batchId,
    'status': status.name,
    'report_type': reportType,
    'pdf_url': pdfUrl,
    'csv_url': csvUrl,
    'sublot_letter': sublotLetter,
    'sublot_name': sublotName,
    'bag_number': bagNumber,
    'bag_label': bagLabel,
    'sublot_id': sublotId,
    'bag_id': bagId,
    'qualification_status_snapshot': qualificationStatusSnapshot,
    'qualification_event_id': qualificationEventId,
    'qualification_summary': qualificationSummary,
    'disposition_label': dispositionLabel,
    'is_excluded_scope': isExcludedScope,
    'is_legacy': serverLegacy,
    'created_at': createdAt.toIso8601String(),
    'source_content_revision': sourceContentRevision,
    'authorized_edit_state_version': authorizedEditStateVersion,
    'job_token': jobToken,
    'started_at': startedAt?.toIso8601String(),
    'finished_at': finishedAt?.toIso8601String(),
    'terminal_code': terminalCode,
    'is_current': isCurrent,
    'is_stale': isStale,
    'superseded_at': supersededAt?.toIso8601String(),
    'superseded_by_report_id': supersededByReportId,
  };
}

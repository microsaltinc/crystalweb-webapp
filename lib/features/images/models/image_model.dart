class ImageSourceIdentity {
  const ImageSourceIdentity({
    required this.s3Key,
    required this.sublotIdentifier,
    required this.bagNumber,
    required this.imageNumber,
    this.lotCode,
  });
  factory ImageSourceIdentity.fromJson(Map<String, dynamic> json) =>
      ImageSourceIdentity(
        s3Key: json['s3_key'] as String,
        lotCode: json['lot_code'] as String?,
        sublotIdentifier: json['sublot_identifier'] as String,
        bagNumber: (json['bag_number'] as num).toInt(),
        imageNumber: (json['image_number'] as num).toInt(),
      );
  final String s3Key;
  final String? lotCode;
  final String sublotIdentifier;
  final int bagNumber;
  final int imageNumber;
}

class ImageModel {
  ImageModel({
    required this.id,
    required this.batchId,
    required this.sublotLetter,
    required this.bagNumber,
    required this.imageNumber,
    required this.s3Key,
    required this.widthPx,
    required this.heightPx,
    required this.processingStatus,
    required this.crystalCount,
    required this.createdAt,
    this.imageUrl,
    this.croppedImageKey,
    this.croppedImageUrl,
    this.cropBottom,
    this.magnification,
    this.voltageKv,
    this.workingDistanceMm,
    this.nmPerPixel,
    this.umPerPixel,
    this.pixelsPerUm,
    this.fieldOfViewWidthUm,
    this.fieldOfViewHeightUm,
    this.detector,
    this.vacuumMode,
    this.scanTimeS,
    this.dwellTimeNs,
    this.contrast,
    this.brightness,
    this.scanDatetime,
    this.instrument,
    this.barHeightPx,
    this.metadataSource,
    this.thumbnailKey,
    this.thumbnailUrl,
    this.analyzedAt,
    this.analysisTriggeredBy,
    this.invalidatedAt,
    this.reviewComplete = false,
    this.reviewCompletedAt,
    this.reviewedByUserId,
    this.reviewedByOperatorId,
    this.reviewedByOperatorName,
    this.reviewedBySessionEmail,
    this.reviewedContentRevision,
    this.campaignEditState = 'editable',
    this.campaignEditStateVersion = 1,
    this.bagId,
    this.sublotId,
    this.sourceIdentity,
  });

  factory ImageModel.fromJson(Map<String, dynamic> json) {
    return ImageModel(
      id: json['id'] as String,
      batchId: json['batch_id'] as String,
      sublotLetter: json['sublot_letter'] as String? ?? '',
      bagNumber: json['bag_number'] as int? ?? 0,
      imageNumber: json['image_number'] as int? ?? 1,
      s3Key: json['s3_key'] as String? ?? '',
      widthPx: json['width_px'] as int? ?? 0,
      heightPx: json['height_px'] as int? ?? 0,
      processingStatus: json['processing_status'] as String? ?? 'pending',
      crystalCount: json['crystal_count'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      imageUrl: json['image_url'] as String?,
      croppedImageKey: json['cropped_image_key'] as String?,
      croppedImageUrl: json['cropped_image_url'] as String?,
      cropBottom: json['crop_bottom'] as int?,
      magnification: json['magnification'] as int?,
      voltageKv: json['voltage_kv'] != null
          ? (json['voltage_kv'] as num).toDouble()
          : null,
      workingDistanceMm: json['working_distance_mm'] != null
          ? (json['working_distance_mm'] as num).toDouble()
          : null,
      nmPerPixel: json['nm_per_pixel'] != null
          ? (json['nm_per_pixel'] as num).toDouble()
          : null,
      umPerPixel: json['um_per_pixel'] != null
          ? (json['um_per_pixel'] as num).toDouble()
          : null,
      pixelsPerUm: json['pixels_per_um'] != null
          ? (json['pixels_per_um'] as num).toDouble()
          : null,
      fieldOfViewWidthUm: json['field_of_view_width_um'] != null
          ? (json['field_of_view_width_um'] as num).toDouble()
          : null,
      fieldOfViewHeightUm: json['field_of_view_height_um'] != null
          ? (json['field_of_view_height_um'] as num).toDouble()
          : null,
      detector: json['detector'] as String?,
      vacuumMode: json['vacuum_mode'] as String?,
      scanTimeS: json['scan_time_s'] as int?,
      dwellTimeNs: json['dwell_time_ns'] as int?,
      contrast: json['contrast'] as int?,
      brightness: json['brightness'] as int?,
      scanDatetime: json['scan_datetime'] as String?,
      instrument: json['instrument'] as String?,
      barHeightPx: json['bar_height_px'] as int?,
      metadataSource: json['metadata_source'] as String?,
      thumbnailKey: json['thumbnail_key'] as String?,
      thumbnailUrl: json['thumbnail_url'] as String?,
      analyzedAt: json['analyzed_at'] != null
          ? DateTime.parse(json['analyzed_at'] as String)
          : null,
      analysisTriggeredBy: json['analysis_triggered_by'] as String?,
      invalidatedAt: json['invalidated_at'] is String
          ? DateTime.tryParse(json['invalidated_at'] as String)
          : null,
      reviewComplete: json['review_complete'] == true,
      reviewCompletedAt: json['review_completed_at'] is String
          ? DateTime.tryParse(json['review_completed_at'] as String)
          : null,
      reviewedByUserId: json['reviewed_by_user_id'] is String
          ? json['reviewed_by_user_id'] as String
          : null,
      reviewedByOperatorId: json['reviewed_by_operator_id'] is String
          ? json['reviewed_by_operator_id'] as String
          : null,
      reviewedByOperatorName: json['reviewed_by_operator_name'] is String
          ? json['reviewed_by_operator_name'] as String
          : null,
      reviewedBySessionEmail: json['reviewed_by_session_email'] is String
          ? json['reviewed_by_session_email'] as String
          : null,
      reviewedContentRevision: json['reviewed_content_revision'] is num
          ? (json['reviewed_content_revision'] as num).toInt()
          : null,
      campaignEditState: json['campaign_edit_state'] is String
          ? json['campaign_edit_state'] as String
          : 'editable',
      campaignEditStateVersion: json['campaign_edit_state_version'] is num
          ? (json['campaign_edit_state_version'] as num).toInt()
          : 1,
      bagId: json['bag_id'] as String?,
      sublotId: json['sublot_id'] as String?,
      sourceIdentity: json['source_identity'] is Map
          ? ImageSourceIdentity.fromJson(
              Map<String, dynamic>.from(json['source_identity'] as Map),
            )
          : null,
    );
  }

  final String id;
  final String batchId;
  final String sublotLetter;
  final int bagNumber;
  final int imageNumber;
  final String s3Key;
  final int widthPx;
  final int heightPx;
  final String processingStatus;
  final int crystalCount;
  final DateTime createdAt;
  final String? imageUrl;
  final String? croppedImageKey;
  final String? croppedImageUrl;
  final int? cropBottom;
  final int? magnification;
  final double? voltageKv;
  final double? workingDistanceMm;
  final double? nmPerPixel;
  final double? umPerPixel;
  final double? pixelsPerUm;
  final double? fieldOfViewWidthUm;
  final double? fieldOfViewHeightUm;
  final String? detector;
  final String? vacuumMode;
  final int? scanTimeS;
  final int? dwellTimeNs;
  final int? contrast;
  final int? brightness;
  final String? scanDatetime;
  final String? instrument;
  final int? barHeightPx;
  final String? metadataSource;
  final String? thumbnailKey;
  final String? thumbnailUrl;
  final DateTime? analyzedAt;
  final String? analysisTriggeredBy;
  final DateTime? invalidatedAt;
  final bool reviewComplete;
  final DateTime? reviewCompletedAt;
  final String? reviewedByUserId;
  final String? reviewedByOperatorId;
  final String? reviewedByOperatorName;
  final String? reviewedBySessionEmail;
  final int? reviewedContentRevision;
  final String campaignEditState;
  final int campaignEditStateVersion;
  final String? bagId;
  final String? sublotId;
  final ImageSourceIdentity? sourceIdentity;

  bool get campaignIsLocked => campaignEditState == 'locked';

  /// Whether this image has been invalidated (soft-discarded).
  bool get isInvalidated => invalidatedAt != null;

  /// Whether a thumbnail is available for fast grid loading.
  bool get hasThumbnail => thumbnailUrl != null && thumbnailUrl!.isNotEmpty;

  String get displayLabel => 'Bag $bagNumber / Image $imageNumber';

  bool get isComplete => processingStatus == 'complete';
  bool get isProcessing => processingStatus == 'processing';
  bool get isFailed => processingStatus == 'failed';
  bool get isPending => processingStatus == 'pending';

  /// Whether a displayable image is available.
  bool get hasCroppedImage =>
      croppedImageUrl != null && croppedImageUrl!.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'id': id,
    'batch_id': batchId,
    'sublot_letter': sublotLetter,
    'bag_number': bagNumber,
    'image_number': imageNumber,
    's3_key': s3Key,
    'width_px': widthPx,
    'height_px': heightPx,
    'processing_status': processingStatus,
    'crystal_count': crystalCount,
    'created_at': createdAt.toIso8601String(),
    'image_url': imageUrl,
    'cropped_image_key': croppedImageKey,
    'cropped_image_url': croppedImageUrl,
    'crop_bottom': cropBottom,
    'magnification': magnification,
    'voltage_kv': voltageKv,
    'working_distance_mm': workingDistanceMm,
    'nm_per_pixel': nmPerPixel,
    'um_per_pixel': umPerPixel,
    'pixels_per_um': pixelsPerUm,
    'field_of_view_width_um': fieldOfViewWidthUm,
    'field_of_view_height_um': fieldOfViewHeightUm,
    'detector': detector,
    'vacuum_mode': vacuumMode,
    'scan_time_s': scanTimeS,
    'dwell_time_ns': dwellTimeNs,
    'contrast': contrast,
    'brightness': brightness,
    'scan_datetime': scanDatetime,
    'instrument': instrument,
    'bar_height_px': barHeightPx,
    'metadata_source': metadataSource,
    'thumbnail_key': thumbnailKey,
    'thumbnail_url': thumbnailUrl,
    'analyzed_at': analyzedAt?.toIso8601String(),
    'analysis_triggered_by': analysisTriggeredBy,
    'invalidated_at': invalidatedAt?.toIso8601String(),
    'review_complete': reviewComplete,
    'review_completed_at': reviewCompletedAt?.toIso8601String(),
    'reviewed_by_user_id': reviewedByUserId,
    'reviewed_by_operator_id': reviewedByOperatorId,
    'reviewed_by_operator_name': reviewedByOperatorName,
    'reviewed_by_session_email': reviewedBySessionEmail,
    'reviewed_content_revision': reviewedContentRevision,
    'campaign_edit_state': campaignEditState,
    'campaign_edit_state_version': campaignEditStateVersion,
    'bag_id': bagId,
    'sublot_id': sublotId,
    'source_identity': sourceIdentity == null
        ? null
        : {
            's3_key': sourceIdentity!.s3Key,
            'lot_code': sourceIdentity!.lotCode,
            'sublot_identifier': sourceIdentity!.sublotIdentifier,
            'bag_number': sourceIdentity!.bagNumber,
            'image_number': sourceIdentity!.imageNumber,
          },
  };
}

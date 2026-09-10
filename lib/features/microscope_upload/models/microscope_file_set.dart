import 'microscope_upload_feedback.dart';

enum MicroscopeFileRole { tiff, txt }

enum MicroscopeSetSelectionStatus { ready, incomplete, ambiguous }

enum MicroscopeUploadPhase {
  idle,
  waiting,
  preparing,
  reserving,
  recovering,
  uploading,
  retrying,
  verifying,
  registering,
  queued,
  paused,
}

class MicroscopeUploadActivity {
  const MicroscopeUploadActivity({
    this.phase = MicroscopeUploadPhase.idle,
    this.role,
    this.completedBytes = 0,
    this.totalBytes = 0,
    this.currentPart,
    this.totalParts,
    this.savedParts = 0,
    this.retryNumber,
    this.maxRetries,
  });

  final MicroscopeUploadPhase phase;
  final MicroscopeFileRole? role;
  final int completedBytes;
  final int totalBytes;
  final int? currentPart;
  final int? totalParts;
  final int savedParts;
  final int? retryNumber;
  final int? maxRetries;

  MicroscopeUploadActivity copyWith({
    MicroscopeUploadPhase? phase,
    MicroscopeFileRole? role,
    int? completedBytes,
    int? totalBytes,
    int? currentPart,
    int? totalParts,
    int? savedParts,
    int? retryNumber,
    int? maxRetries,
    bool clearRetry = false,
  }) => MicroscopeUploadActivity(
    phase: phase ?? this.phase,
    role: role ?? this.role,
    completedBytes: completedBytes ?? this.completedBytes,
    totalBytes: totalBytes ?? this.totalBytes,
    currentPart: currentPart ?? this.currentPart,
    totalParts: totalParts ?? this.totalParts,
    savedParts: savedParts ?? this.savedParts,
    retryNumber: clearRetry ? null : retryNumber ?? this.retryNumber,
    maxRetries: clearRetry ? null : maxRetries ?? this.maxRetries,
  );

  double get progress =>
      totalBytes <= 0 ? 0 : (completedBytes / totalBytes).clamp(0.0, 1.0);

  String get headline => switch (phase) {
    MicroscopeUploadPhase.idle => 'Ready to upload',
    MicroscopeUploadPhase.waiting => 'Queued for the next upload batch',
    MicroscopeUploadPhase.preparing =>
      role == null
          ? 'Preparing files'
          : 'Checking ${microscopeRoleLabel(role!)} before upload',
    MicroscopeUploadPhase.reserving =>
      'Reserving this Image in the selected Bag',
    MicroscopeUploadPhase.recovering => 'Checking safely stored upload parts',
    MicroscopeUploadPhase.uploading =>
      role == null
          ? 'Uploading files'
          : 'Uploading ${microscopeRoleLabel(role!)}',
    MicroscopeUploadPhase.retrying =>
      role == null
          ? 'Connection interrupted — retrying'
          : 'Connection interrupted — retrying ${microscopeRoleLabel(role!)}',
    MicroscopeUploadPhase.verifying =>
      role == null
          ? 'Verifying files in secure storage'
          : 'Verifying ${microscopeRoleLabel(role!)} in secure storage',
    MicroscopeUploadPhase.registering =>
      'Registering the Image with the selected Bag',
    MicroscopeUploadPhase.queued => 'Image registered',
    MicroscopeUploadPhase.paused => 'Upload paused',
  };

  String get detail => switch (phase) {
    MicroscopeUploadPhase.idle =>
      'TIFF and TXT are paired and ready. Nothing has uploaded yet.',
    MicroscopeUploadPhase.waiting =>
      'This set is ready and will start after the current bounded batch finishes.',
    MicroscopeUploadPhase.preparing =>
      'Reading the selected file and calculating checksums. No network transfer is happening yet.',
    MicroscopeUploadPhase.reserving =>
      'The server is checking the Campaign, Bag, image number, and other active uploads.',
    MicroscopeUploadPhase.recovering =>
      savedParts > 0
          ? '$savedParts previously verified ${_parts(savedParts)} will be reused.'
          : 'The server is checking for verified work from an earlier attempt.',
    MicroscopeUploadPhase.uploading => _uploadDetail(),
    MicroscopeUploadPhase.retrying => _retryDetail(),
    MicroscopeUploadPhase.verifying =>
      'All declared parts were sent. Storage is assembling them and checking the exact checksum.',
    MicroscopeUploadPhase.registering =>
      'The verified TIFF and TXT are being registered as one Image. Do not select another destination.',
    MicroscopeUploadPhase.queued =>
      'The Image is safely registered and queued for analysis.',
    MicroscopeUploadPhase.paused =>
      'Completed parts remain stored. Review the message below before resuming.',
  };

  String _uploadDetail() {
    final values = <String>[];
    if (totalBytes > 0) {
      values.add(
        '${_formatBytes(completedBytes)} of ${_formatBytes(totalBytes)}',
      );
    }
    if (currentPart != null && totalParts != null) {
      values.add('part $currentPart of $totalParts');
    }
    if (savedParts > 0) {
      values.add('$savedParts ${_parts(savedParts)} safely stored');
    }
    return values.isEmpty
        ? 'Sending the selected file to secure storage.'
        : values.join(' • ');
  }

  String _retryDetail() {
    final retry = retryNumber;
    final maximum = maxRetries;
    final prefix = retry == null || maximum == null
        ? 'Waiting briefly before another automatic attempt.'
        : 'Retry $retry of $maximum.';
    if (savedParts == 0) return '$prefix No completed part will be resent.';
    return '$prefix $savedParts completed ${_parts(savedParts)} remain safely stored.';
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kib = bytes / 1024;
  if (kib < 1024) return '${kib.toStringAsFixed(1)} KiB';
  return '${(kib / 1024).toStringAsFixed(1)} MiB';
}

String _parts(int count) => count == 1 ? 'part' : 'parts';

class MicroscopeLocalFile {
  const MicroscopeLocalFile({
    required this.path,
    required this.name,
    required this.sizeBytes,
    this.sha256,
    this.multipartChecksums,
  });

  final String path;
  final String name;
  final int sizeBytes;
  final String? sha256;
  final List<String>? multipartChecksums;

  MicroscopeLocalFile copyWith({
    String? sha256,
    List<String>? multipartChecksums,
  }) => MicroscopeLocalFile(
    path: path,
    name: name,
    sizeBytes: sizeBytes,
    sha256: sha256 ?? this.sha256,
    multipartChecksums: multipartChecksums ?? this.multipartChecksums,
  );
}

class MicroscopeFileSet {
  const MicroscopeFileSet({
    required this.clientSetId,
    required this.logicalBaseName,
    required this.canonicalBaseName,
    required this.normalizedMatchKey,
    required this.files,
    this.conflictingFiles = const [],
    this.issues = const [],
    this.serverSetId,
    this.imageId,
    this.uploadProgress = 0,
    this.uploaded = false,
    this.uploadError,
    this.issue,
    this.activity = const MicroscopeUploadActivity(),
  });

  final String clientSetId;
  final String logicalBaseName;
  final String canonicalBaseName;
  final String normalizedMatchKey;
  final Map<MicroscopeFileRole, MicroscopeLocalFile> files;
  final List<MicroscopeLocalFile> conflictingFiles;
  final List<String> issues;
  final String? serverSetId;
  final String? imageId;
  final double uploadProgress;
  final bool uploaded;
  final String? uploadError;
  final MicroscopeUploadIssue? issue;
  final MicroscopeUploadActivity activity;

  MicroscopeSetSelectionStatus get selectionStatus {
    if (issues.isNotEmpty || conflictingFiles.isNotEmpty) {
      return MicroscopeSetSelectionStatus.ambiguous;
    }
    return files.length == MicroscopeFileRole.values.length
        ? MicroscopeSetSelectionStatus.ready
        : MicroscopeSetSelectionStatus.incomplete;
  }

  bool get canUpload =>
      selectionStatus == MicroscopeSetSelectionStatus.ready && !uploaded;

  List<MicroscopeFileRole> get missingRoles => [
    for (final role in MicroscopeFileRole.values)
      if (!files.containsKey(role)) role,
  ];

  List<MicroscopeLocalFile> get allFiles => [
    ...files.values,
    ...conflictingFiles,
  ];

  MicroscopeFileSet copyWith({
    Map<MicroscopeFileRole, MicroscopeLocalFile>? files,
    List<MicroscopeLocalFile>? conflictingFiles,
    List<String>? issues,
    String? serverSetId,
    String? imageId,
    double? uploadProgress,
    bool? uploaded,
    String? uploadError,
    MicroscopeUploadIssue? issue,
    MicroscopeUploadActivity? activity,
    bool clearUploadError = false,
  }) => MicroscopeFileSet(
    clientSetId: clientSetId,
    logicalBaseName: logicalBaseName,
    canonicalBaseName: canonicalBaseName,
    normalizedMatchKey: normalizedMatchKey,
    files: files ?? this.files,
    conflictingFiles: conflictingFiles ?? this.conflictingFiles,
    issues: issues ?? this.issues,
    serverSetId: serverSetId ?? this.serverSetId,
    imageId: imageId ?? this.imageId,
    uploadProgress: uploadProgress ?? this.uploadProgress,
    uploaded: uploaded ?? this.uploaded,
    uploadError: clearUploadError ? null : uploadError ?? this.uploadError,
    issue: clearUploadError ? null : issue ?? this.issue,
    activity: activity ?? this.activity,
  );
}

String microscopeRoleLabel(MicroscopeFileRole role) => switch (role) {
  MicroscopeFileRole.tiff => 'TIFF',
  MicroscopeFileRole.txt => 'TXT',
};

String microscopeRoleKey(MicroscopeFileRole role) => switch (role) {
  MicroscopeFileRole.tiff => 'tiff',
  MicroscopeFileRole.txt => 'txt',
};

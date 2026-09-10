import 'package:dio/dio.dart';

import '../../../core/api/api_error.dart';

enum MicroscopeUploadMessageSeverity { info, warning, error }

enum MicroscopeUploadIssueSource {
  file,
  connection,
  storage,
  server,
  concurrency,
  destination,
  session,
}

class MicroscopeUploadIssue {
  const MicroscopeUploadIssue({
    required this.title,
    required this.message,
    required this.recommendedAction,
    required this.source,
    required this.severity,
    required this.retryable,
    this.code,
    this.reference,
  });

  final String title;
  final String message;
  final String recommendedAction;
  final MicroscopeUploadIssueSource source;
  final MicroscopeUploadMessageSeverity severity;
  final bool retryable;
  final String? code;
  final String? reference;

  @override
  String toString() => '$title. $message $recommendedAction';
}

MicroscopeUploadIssue microscopeUploadIssue(
  Object error, {
  required String operation,
  String? logicalName,
  String? sessionId,
}) {
  final reference = _reference(logicalName, sessionId);
  final parsed = ApiError.tryParse(error);
  if (parsed != null) {
    final canonicalCode = _canonicalUploadCode(parsed.code);
    final structured = canonicalCode == parsed.code
        ? parsed
        : ApiError(
            code: canonicalCode,
            message: parsed.message,
            statusCode: parsed.statusCode,
            details: parsed.details,
          );
    final source = _source(structured.details['source'], structured.code);
    final retryable = structured.details['retryable'] is bool
        ? structured.details['retryable'] == true
        : _legacyRetryable(structured.code);
    return MicroscopeUploadIssue(
      title: _structuredTitle(structured.code, source),
      message:
          _safeText(structured.message) ??
          'The server could not confirm the requested upload step.',
      recommendedAction: _structuredAction(structured, source, retryable),
      source: source,
      severity: _severity(structured.details['severity']),
      retryable: retryable,
      code: structured.code,
      reference: reference,
    );
  }

  if (error is DioException) {
    if (error.response?.statusCode == 403) {
      return MicroscopeUploadIssue(
        title: 'Secure upload permission was rejected',
        message:
            'Storage did not accept the current secure target while trying to $operation.',
        recommendedAction:
            'Resume the upload so CrystalApp can request a fresh secure target. Completed parts are safely retained.',
        source: MicroscopeUploadIssueSource.storage,
        severity: MicroscopeUploadMessageSeverity.warning,
        retryable: true,
        code: 'microscope_upload_target_rejected',
        reference: reference,
      );
    }
    if (_isConnectionFailure(error.type)) {
      return MicroscopeUploadIssue(
        title: 'Connection interrupted',
        message:
            'CrystalApp could not finish the request to $operation because the connection was slow or unavailable.',
        recommendedAction:
            'Check the connection and choose Resume. Any completed parts are safely retained and will not be uploaded again.',
        source: MicroscopeUploadIssueSource.connection,
        severity: MicroscopeUploadMessageSeverity.warning,
        retryable: true,
        code: 'microscope_upload_connection_interrupted',
        reference: reference,
      );
    }
    if (error.type == DioExceptionType.cancel) {
      return MicroscopeUploadIssue(
        title: 'Upload request cancelled',
        message: 'CrystalApp stopped before it could $operation.',
        recommendedAction: 'Choose Resume when you are ready to continue.',
        source: MicroscopeUploadIssueSource.session,
        severity: MicroscopeUploadMessageSeverity.info,
        retryable: true,
        code: 'microscope_upload_request_cancelled',
        reference: reference,
      );
    }
    if ((error.response?.statusCode ?? 0) >= 500) {
      return MicroscopeUploadIssue(
        title: 'Server temporarily unavailable',
        message: 'The server could not $operation at this time.',
        recommendedAction:
            'Wait a moment, then choose Resume. CrystalApp will reconcile the server state before sending more data.',
        source: MicroscopeUploadIssueSource.server,
        severity: MicroscopeUploadMessageSeverity.error,
        retryable: true,
        code: 'microscope_upload_server_unavailable',
        reference: reference,
      );
    }
  }

  final localMessage = error.toString().toLowerCase();
  if (localMessage.contains('selected file changed') ||
      localMessage.contains('does not match the selected file')) {
    return MicroscopeUploadIssue(
      title: 'Selected file changed',
      message:
          'The file on this computer no longer matches the file CrystalApp verified before uploading.',
      recommendedAction:
          'Remove this image set, then reselect the current TIFF and TXT files together.',
      source: MicroscopeUploadIssueSource.file,
      severity: MicroscopeUploadMessageSeverity.warning,
      retryable: false,
      code: 'microscope_upload_local_file_changed',
      reference: reference,
    );
  }
  if (localMessage.contains('read the requested multipart byte range')) {
    return MicroscopeUploadIssue(
      title: 'Could not read the selected file',
      message:
          'CrystalApp could not read the next part of the file from this computer.',
      recommendedAction:
          'Confirm the file is still available and readable, then reselect the TIFF and TXT pair.',
      source: MicroscopeUploadIssueSource.file,
      severity: MicroscopeUploadMessageSeverity.warning,
      retryable: false,
      code: 'microscope_upload_local_file_unreadable',
      reference: reference,
    );
  }

  final registering = operation.toLowerCase().contains('register');
  return MicroscopeUploadIssue(
    title: registering
        ? 'Image registration did not finish'
        : 'Upload could not continue',
    message: registering
        ? 'The files may already be stored, but CrystalApp could not confirm that the Image was registered.'
        : 'CrystalApp could not confirm the next safe upload step.',
    recommendedAction:
        'Choose Resume. CrystalApp will check the server and storage state before continuing.',
    source: MicroscopeUploadIssueSource.server,
    severity: MicroscopeUploadMessageSeverity.error,
    retryable: true,
    code: 'microscope_upload_unconfirmed_state',
    reference: reference,
  );
}

bool _isConnectionFailure(DioExceptionType type) => switch (type) {
  DioExceptionType.connectionTimeout ||
  DioExceptionType.sendTimeout ||
  DioExceptionType.receiveTimeout ||
  DioExceptionType.connectionError ||
  DioExceptionType.unknown => true,
  _ => false,
};

String? _canonicalUploadCode(String? code) {
  if (code == null || code.startsWith('microscope_upload_')) return code;
  const legacyCodes = {
    'file_invalid',
    'manifest_invalid',
    'ambiguous_name',
    'storage_conflict',
    'object_missing',
    'checksum_mismatch',
    'size_mismatch',
    'expired',
    'destination_inactive',
    'locked',
    'precondition_required',
    'stale',
    'in_progress',
    'handoff_in_progress',
    'handoff_incomplete',
    'recovery_required',
    'duplicate',
  };
  return legacyCodes.contains(code) ? 'microscope_upload_$code' : code;
}

MicroscopeUploadIssueSource _source(Object? raw, String? code) {
  final structured = switch (raw) {
    'file' => MicroscopeUploadIssueSource.file,
    'storage' => MicroscopeUploadIssueSource.storage,
    'concurrency' => MicroscopeUploadIssueSource.concurrency,
    'destination' => MicroscopeUploadIssueSource.destination,
    'session' => MicroscopeUploadIssueSource.session,
    _ => null,
  };
  if (structured != null) return structured;
  if ({
    'microscope_upload_file_invalid',
    'microscope_upload_manifest_invalid',
    'microscope_upload_ambiguous_name',
  }.contains(code)) {
    return MicroscopeUploadIssueSource.file;
  }
  if ({
    'microscope_upload_storage_conflict',
    'microscope_upload_object_missing',
    'microscope_upload_checksum_mismatch',
    'microscope_upload_size_mismatch',
  }.contains(code)) {
    return MicroscopeUploadIssueSource.storage;
  }
  if ({
    'microscope_upload_precondition_required',
    'microscope_upload_stale',
    'microscope_upload_in_progress',
    'microscope_upload_handoff_in_progress',
    'microscope_upload_handoff_incomplete',
    'microscope_upload_recovery_required',
    'microscope_upload_duplicate',
  }.contains(code)) {
    return MicroscopeUploadIssueSource.concurrency;
  }
  if ({
    'microscope_upload_locked',
    'microscope_upload_destination_inactive',
  }.contains(code)) {
    return MicroscopeUploadIssueSource.destination;
  }
  if (code == 'microscope_upload_expired') {
    return MicroscopeUploadIssueSource.session;
  }
  return MicroscopeUploadIssueSource.server;
}

bool _legacyRetryable(String? code) => {
  'microscope_upload_storage_conflict',
  'microscope_upload_object_missing',
  'microscope_upload_precondition_required',
  'microscope_upload_stale',
  'microscope_upload_in_progress',
  'microscope_upload_handoff_in_progress',
  'microscope_upload_expired',
}.contains(code);

MicroscopeUploadMessageSeverity _severity(Object? raw) => switch (raw) {
  'info' => MicroscopeUploadMessageSeverity.info,
  'warning' => MicroscopeUploadMessageSeverity.warning,
  _ => MicroscopeUploadMessageSeverity.error,
};

String _structuredTitle(String? code, MicroscopeUploadIssueSource source) {
  if (code == 'microscope_upload_handoff_in_progress') {
    return 'Another operator changed this upload';
  }
  if (code == 'microscope_upload_recovery_required') {
    return 'Unfinished matching upload found';
  }
  if (code == 'microscope_upload_duplicate') {
    return 'Image set already exists or is reserved';
  }
  if (code == 'microscope_upload_locked') return 'Campaign is locked';
  if (code == 'microscope_upload_stale' ||
      code == 'microscope_upload_precondition_required') {
    return 'Campaign changed on another client';
  }
  if (code == 'microscope_upload_destination_inactive') {
    return 'Selected Bag is not active';
  }
  if (code == 'microscope_upload_expired') {
    return 'Upload session expired';
  }
  return switch (source) {
    MicroscopeUploadIssueSource.file => 'Selected files need attention',
    MicroscopeUploadIssueSource.storage =>
      'Storage verification needs attention',
    MicroscopeUploadIssueSource.concurrency => 'Another upload needs attention',
    MicroscopeUploadIssueSource.destination =>
      'Selected destination needs attention',
    MicroscopeUploadIssueSource.session => 'Upload session needs attention',
    MicroscopeUploadIssueSource.connection => 'Connection interrupted',
    MicroscopeUploadIssueSource.server =>
      'Server could not continue the upload',
  };
}

String _defaultAction(MicroscopeUploadIssueSource source, bool retryable) {
  if (retryable) {
    return 'Choose Resume. CrystalApp will reconcile completed work before continuing.';
  }
  return switch (source) {
    MicroscopeUploadIssueSource.file =>
      'Review and reselect the affected TIFF and TXT pair.',
    MicroscopeUploadIssueSource.destination =>
      'Refresh the Campaign and confirm the selected Bag is active.',
    MicroscopeUploadIssueSource.concurrency =>
      'Refresh the Campaign and review the affected image sets.',
    _ => 'Review the reported issue before trying again.',
  };
}

String _structuredAction(
  ApiError error,
  MicroscopeUploadIssueSource source,
  bool retryable,
) {
  if (error.code == 'microscope_upload_handoff_incomplete') {
    final identities = (error.details['identities'] as List? ?? const [])
        .map(_safeText)
        .whereType<String>()
        .take(5)
        .map(
          (value) => value.length > 60 ? '${value.substring(0, 57)}…' : value,
        )
        .toList();
    final count =
        (error.details['identities'] as List?)?.length ?? identities.length;
    if (identities.isNotEmpty) {
      return 'Add all $count remaining original TIFF/TXT pairs: ${identities.join(', ')}.';
    }
  }
  if (error.code == 'microscope_upload_handoff_in_progress') {
    final retryAfter = _safeText(error.details['retry_after']);
    if (retryAfter != null) {
      return 'Keep these exact files selected and resume after $retryAfter.';
    }
  }
  final serverAction = _safeText(error.details['recommended_action']);
  if (serverAction != null) return serverAction;
  return switch (error.code) {
    'microscope_upload_locked' =>
      'Unlock the Campaign, then reopen this Bag before resuming.',
    'microscope_upload_destination_inactive' =>
      'Restore the selected Bag and Sublot, then refresh the Campaign.',
    'microscope_upload_stale' || 'microscope_upload_precondition_required' =>
      'Choose Resume. CrystalApp will adopt the current Campaign revision and rebind the exact unfinished upload.',
    'microscope_upload_expired' =>
      'Start a new upload with the same exact files so CrystalApp can reconcile safe retained work.',
    _ => _defaultAction(source, retryable),
  };
}

String? _safeText(Object? raw) {
  if (raw is! String) return null;
  final value = raw.trim();
  if (value.isEmpty || value.length > 500) return null;
  final lower = value.toLowerCase();
  const unsafeMarkers = [
    'http://',
    'https://',
    'uploadid',
    'credential=',
    'signature=',
    'traceback',
    'stack trace',
    'sqlalchemy',
    '[sql:',
  ];
  if (unsafeMarkers.any(lower.contains)) return null;
  return value;
}

String? _reference(String? logicalName, String? sessionId) {
  final parts = <String>[];
  if (logicalName != null && logicalName.trim().isNotEmpty) {
    parts.add('Image set ${logicalName.trim()}');
  }
  if (sessionId != null && sessionId.trim().isNotEmpty) {
    final normalized = sessionId.trim();
    parts.add(
      'Session ${normalized.substring(0, normalized.length < 8 ? normalized.length : 8)}',
    );
  }
  return parts.isEmpty ? null : parts.join(' • ');
}

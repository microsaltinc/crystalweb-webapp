import 'package:crystalapp/core/api/api_error.dart';
import 'package:crystalapp/features/microscope_upload/models/microscope_upload_feedback.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preserves structured server guidance and safe upload reference', () {
    const error = ApiError(
      code: 'microscope_upload_handoff_in_progress',
      message: 'Another operator recently continued this upload.',
      statusCode: 409,
      details: {
        'source': 'concurrency',
        'severity': 'warning',
        'retryable': true,
        'recommended_action':
            'Refresh the Campaign to load the latest operator changes, then resume this upload.',
      },
    );

    final issue = microscopeUploadIssue(
      error,
      operation: 'reserve microscope files',
      logicalName: '002',
      sessionId: '665a5cad-dc73-4d3a-a3cd-63231b1d2a0e',
    );

    expect(issue.title, 'Another operator changed this upload');
    expect(issue.message, 'Another operator recently continued this upload.');
    expect(issue.recommendedAction, startsWith('Refresh the Campaign'));
    expect(issue.retryable, isTrue);
    expect(issue.reference, 'Image set 002 • Session 665a5cad');
    expect(issue.toString(), isNot(contains('DioException')));
  });

  test('lists the bounded exact files required for operator handoff', () {
    const error = ApiError(
      code: 'microscope_upload_handoff_incomplete',
      message: 'Select every unfinished original set.',
      statusCode: 409,
      details: {
        'source': 'concurrency',
        'severity': 'warning',
        'retryable': false,
        'identities': ['sample-001', 'sample-002'],
      },
    );

    final issue = microscopeUploadIssue(
      error,
      operation: 'continue another operator upload',
    );

    expect(issue.recommendedAction, contains('all 2 remaining'));
    expect(issue.recommendedAction, contains('sample-001, sample-002'));
  });

  test('uses the server handoff window without exposing unsafe targets', () {
    const error = ApiError(
      code: 'microscope_upload_handoff_in_progress',
      message: 'Another operator recently continued this upload.',
      statusCode: 409,
      details: {
        'source': 'concurrency',
        'severity': 'warning',
        'retryable': true,
        'retry_after': '2026-08-20T12:30:00+00:00',
        'recommended_action': 'Open https://presigned.invalid/secret',
      },
    );

    final issue = microscopeUploadIssue(
      error,
      operation: 'continue another operator upload',
    );

    expect(issue.recommendedAction, contains('2026-08-20T12:30:00+00:00'));
    expect(issue.recommendedAction, isNot(contains('https://')));
  });

  test('classifies legacy structured errors without presentation metadata', () {
    const stale = ApiError(
      code: 'microscope_upload_stale',
      message: 'The Campaign changed.',
      statusCode: 409,
    );
    const expired = ApiError(
      code: 'microscope_upload_expired',
      message: 'The upload expired.',
      statusCode: 409,
    );
    const locked = ApiError(
      code: 'microscope_upload_locked',
      message: 'The Campaign is locked.',
      statusCode: 423,
    );
    const legacyFinalize = ApiError(
      code: 'storage_conflict',
      message: 'Storage verification is temporarily unavailable.',
      statusCode: 409,
    );

    final staleIssue = microscopeUploadIssue(stale, operation: 'refresh');
    final expiredIssue = microscopeUploadIssue(expired, operation: 'resume');
    final lockedIssue = microscopeUploadIssue(locked, operation: 'reserve');
    final finalizeIssue = microscopeUploadIssue(
      legacyFinalize,
      operation: 'register the image',
    );

    expect(staleIssue.source, MicroscopeUploadIssueSource.concurrency);
    expect(staleIssue.retryable, isTrue);
    expect(staleIssue.recommendedAction, contains('Resume'));
    expect(expiredIssue.source, MicroscopeUploadIssueSource.session);
    expect(expiredIssue.retryable, isTrue);
    expect(lockedIssue.source, MicroscopeUploadIssueSource.destination);
    expect(lockedIssue.retryable, isFalse);
    expect(lockedIssue.recommendedAction, contains('Unlock'));
    expect(finalizeIssue.source, MicroscopeUploadIssueSource.storage);
    expect(finalizeIssue.retryable, isTrue);
    expect(finalizeIssue.code, 'microscope_upload_storage_conflict');
    expect(finalizeIssue.recommendedAction, contains('Resume'));
  });

  test('maps known server failures to distinct safe operator guidance', () {
    const cases = [
      (
        'microscope_upload_locked',
        'destination',
        MicroscopeUploadIssueSource.destination,
        'Campaign is locked',
      ),
      (
        'microscope_upload_stale',
        'concurrency',
        MicroscopeUploadIssueSource.concurrency,
        'Campaign changed on another client',
      ),
      (
        'microscope_upload_destination_inactive',
        'destination',
        MicroscopeUploadIssueSource.destination,
        'Selected Bag is not active',
      ),
      (
        'microscope_upload_expired',
        'session',
        MicroscopeUploadIssueSource.session,
        'Upload session expired',
      ),
      (
        'microscope_upload_duplicate',
        'concurrency',
        MicroscopeUploadIssueSource.concurrency,
        'Image set already exists or is reserved',
      ),
      (
        'microscope_upload_recovery_required',
        'concurrency',
        MicroscopeUploadIssueSource.concurrency,
        'Unfinished matching upload found',
      ),
      (
        'microscope_upload_checksum_mismatch',
        'storage',
        MicroscopeUploadIssueSource.storage,
        'Storage verification needs attention',
      ),
      (
        'microscope_upload_size_mismatch',
        'storage',
        MicroscopeUploadIssueSource.storage,
        'Storage verification needs attention',
      ),
    ];

    for (final (code, source, expectedSource, title) in cases) {
      final issue = microscopeUploadIssue(
        ApiError(
          code: code,
          message: 'Safe server explanation for $code.',
          statusCode: 409,
          details: {
            'source': source,
            'severity': 'warning',
            'retryable': false,
            'recommended_action': 'Follow the safe action for this set.',
          },
        ),
        operation: 'continue upload',
        logicalName: '002',
      );

      expect(issue.source, expectedSource, reason: code);
      expect(issue.title, title, reason: code);
      expect(issue.message, isNot(contains('Something went wrong')));
      expect(issue.recommendedAction, contains('safe action'));
    }
  });

  test('explains a slow or interrupted direct-to-storage transfer', () {
    final issue = microscopeUploadIssue(
      DioException(
        requestOptions: RequestOptions(path: 'https://storage.invalid'),
        type: DioExceptionType.sendTimeout,
      ),
      operation: 'upload TIFF',
      logicalName: '002',
      sessionId: '12345678-abcd',
    );

    expect(issue.title, 'Connection interrupted');
    expect(issue.message, contains('TIFF'));
    expect(
      issue.recommendedAction,
      contains('completed parts are safely retained'),
    );
    expect(issue.retryable, isTrue);
    expect(issue.reference, 'Image set 002 • Session 12345678');
  });

  test('distinguishes changed local files from network failures', () {
    final issue = microscopeUploadIssue(
      StateError('The selected file changed after it was verified.'),
      operation: 'upload TIFF',
      logicalName: '002',
    );

    expect(issue.title, 'Selected file changed');
    expect(issue.message, contains('no longer matches'));
    expect(issue.recommendedAction, contains('reselect'));
    expect(issue.retryable, isFalse);
    expect(issue.message, isNot(contains('Something went wrong')));
  });

  test('unknown failures still provide a specific safe next step', () {
    final issue = microscopeUploadIssue(
      Exception('presigned-secret-value'),
      operation: 'register the image',
      logicalName: '002',
    );

    expect(issue.title, 'Image registration did not finish');
    expect(issue.message, isNot(contains('presigned-secret-value')));
    expect(issue.message, isNot(contains('Something went wrong')));
    expect(issue.recommendedAction, contains('Resume'));
  });
}

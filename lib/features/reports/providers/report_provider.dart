import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/user_facing_error.dart';
import '../models/report.dart';

/// Fetches all reports for a given batch.
final reportsForBatchProvider = FutureProvider.autoDispose
    .family<List<Report>, String>((ref, batchId) async {
      final client = ref.watch(apiClientProvider);
      final response = await client.dio.get(
        '/api/v1/reports',
        queryParameters: {'batch_id': batchId},
      );
      final data = response.data as List;
      return data
          .map((j) => Report.fromJson(j as Map<String, dynamic>))
          .toList();
    });

/// Fetches a single report by ID.
final reportDetailProvider = FutureProvider.autoDispose.family<Report, String>((
  ref,
  reportId,
) async {
  final client = ref.watch(apiClientProvider);
  final response = await client.dio.get('/api/v1/reports/$reportId');
  return Report.fromJson(response.data as Map<String, dynamic>);
});

/// Triggers report generation for a batch. Returns a list of reports (one per sublot).
final generateReportProvider = FutureProvider.autoDispose
    .family<List<Report>, String>((ref, batchId) async {
      final client = ref.watch(apiClientProvider);
      final response = await client.dio.post('/api/v1/reports/batch/$batchId');
      final data = response.data as List;
      return data
          .map((j) => Report.fromJson(j as Map<String, dynamic>))
          .toList();
    });

// ---------------------------------------------------------------------------
// Error handling utilities
// ---------------------------------------------------------------------------

/// Translates raw exceptions into user-friendly messages.
String userFriendlyError(Object error) {
  if (error is ReportPollingTimeoutException) {
    return 'Report is taking longer than expected. It will appear when ready.';
  }
  return userFacingError(error);
}

// ---------------------------------------------------------------------------
// Polling
// ---------------------------------------------------------------------------

/// Exception thrown when polling exceeds the maximum number of attempts.
class ReportPollingTimeoutException implements Exception {
  const ReportPollingTimeoutException(this.reportId, this.maxAttempts);

  final String reportId;
  final int maxAttempts;

  @override
  String toString() =>
      'Report is taking longer than expected. It will appear when ready.';
}

/// Thrown internally when a polled report was deleted (superseded by regeneration).
/// This is NOT an error — the caller should refresh the list silently.
class ReportSupersededException implements Exception {
  const ReportSupersededException();
}

/// Notifier that manages polling for report completion.
/// State holds the latest polled [Report], or null if not polling.
final reportPollingProvider =
    StateNotifierProvider<ReportPollingNotifier, Report?>(
      (ref) => ReportPollingNotifier(ref),
    );

class ReportPollingNotifier extends StateNotifier<Report?> {
  ReportPollingNotifier(this._ref) : super(null);

  final Ref _ref;

  /// Polls [GET /api/v1/reports/{reportId}] until the report reaches
  /// a terminal status (complete, failed, or error), or until
  /// [maxAttempts] is exceeded.
  ///
  /// Returns the final [Report].
  /// Throws [ReportSupersededException] if report was deleted (regenerated).
  /// Throws [ReportPollingTimeoutException] if max attempts reached.
  Future<Report> pollUntilComplete(
    String reportId, {
    Duration pollInterval = const Duration(seconds: 3),
    int maxAttempts = 60,
  }) async {
    final client = _ref.read(apiClientProvider);
    var consecutiveErrors = 0;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final response = await client.dio.get('/api/v1/reports/$reportId');
        final report = Report.fromJson(response.data as Map<String, dynamic>);
        state = report;
        consecutiveErrors = 0;

        if (report.status == ReportStatus.complete || report.hasError) {
          return report;
        }
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          // Report was deleted — it was superseded by a regeneration.
          // This is expected; the caller should just refresh the list.
          throw const ReportSupersededException();
        }
        // Transient network errors: retry up to 3 times before giving up.
        consecutiveErrors++;
        if (consecutiveErrors >= 3) {
          rethrow;
        }
      }

      await Future<void>.delayed(pollInterval);
    }

    throw ReportPollingTimeoutException(reportId, maxAttempts);
  }

  /// Reset polling state.
  void reset() {
    state = null;
  }
}

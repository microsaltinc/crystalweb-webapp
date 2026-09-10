import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crystalapp/core/api/api_client.dart';
import 'package:crystalapp/features/reports/models/report.dart';
import 'package:crystalapp/features/reports/providers/report_provider.dart';

class MockDio extends Mock implements Dio {
  @override
  BaseOptions get options => BaseOptions(baseUrl: 'http://localhost:8000');
}

void main() {
  late MockDio mockDio;
  late ApiClient apiClient;

  setUp(() {
    mockDio = MockDio();
    apiClient = ApiClient.withDio(mockDio);
  });

  group('report user-facing errors', () {
    test('delegates server errors to the shared safe policy', () {
      final request = RequestOptions(path: '/api/v1/reports');
      final error = DioException(
        requestOptions: request,
        response: Response(
          requestOptions: request,
          statusCode: 500,
          data: {'detail': 'Traceback: SQLAlchemy IntegrityError'},
        ),
        type: DioExceptionType.badResponse,
      );

      final message = userFriendlyError(error);
      expect(message, contains('service could not complete'));
      expect(message, isNot(contains('Traceback')));
    });

    test('preserves report polling timeout guidance', () {
      expect(
        userFriendlyError(const ReportPollingTimeoutException('report-1', 3)),
        'Report is taking longer than expected. It will appear when ready.',
      );
    });
  });

  group('reportsForBatchProvider', () {
    test('fetches reports for a batch', () async {
      when(
        () => mockDio.get(
          '/api/v1/reports',
          queryParameters: {'batch_id': 'batch-1'},
        ),
      ).thenAnswer(
        (_) async => Response(
          data: [
            {
              'id': 'r1',
              'batch_id': 'batch-1',
              'status': 'complete',
              'pdf_url': 'https://example.com/r1.pdf',
              'csv_url': 'https://example.com/r1.csv',
              'created_at': '2026-04-06T12:00:00Z',
            },
          ],
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/v1/reports'),
        ),
      );

      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(apiClient)],
      );
      addTearDown(container.dispose);

      final result = await container.read(
        reportsForBatchProvider('batch-1').future,
      );
      expect(result.length, 1);
      expect(result.first.id, 'r1');
      expect(result.first.status, ReportStatus.complete);
    });

    test('returns empty list when no reports', () async {
      when(
        () => mockDio.get(
          '/api/v1/reports',
          queryParameters: {'batch_id': 'batch-2'},
        ),
      ).thenAnswer(
        (_) async => Response(
          data: [],
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/v1/reports'),
        ),
      );

      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(apiClient)],
      );
      addTearDown(container.dispose);

      final result = await container.read(
        reportsForBatchProvider('batch-2').future,
      );
      expect(result, isEmpty);
    });
  });

  group('reportDetailProvider', () {
    test('fetches a single report', () async {
      when(() => mockDio.get('/api/v1/reports/r1')).thenAnswer(
        (_) async => Response(
          data: {
            'id': 'r1',
            'batch_id': 'batch-1',
            'status': 'complete',
            'pdf_url': 'https://example.com/r1.pdf',
            'csv_url': null,
            'created_at': '2026-04-06T12:00:00Z',
          },
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/v1/reports/r1'),
        ),
      );

      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(apiClient)],
      );
      addTearDown(container.dispose);

      final result = await container.read(reportDetailProvider('r1').future);
      expect(result.id, 'r1');
      expect(result.status, ReportStatus.complete);
    });
  });

  group('generateReportProvider', () {
    test('triggers report generation and returns pending reports', () async {
      when(() => mockDio.post('/api/v1/reports/batch/batch-1')).thenAnswer(
        (_) async => Response(
          data: [
            {
              'id': 'r-new',
              'batch_id': 'batch-1',
              'status': 'pending',
              'sublot_letter': 'A',
              'sublot_name': 'LOT-1A',
              'pdf_url': null,
              'csv_url': null,
              'created_at': '2026-04-20T10:00:00Z',
            },
          ],
          statusCode: 202,
          requestOptions: RequestOptions(path: '/api/v1/reports/batch/batch-1'),
        ),
      );

      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(apiClient)],
      );
      addTearDown(container.dispose);

      final result = await container.read(
        generateReportProvider('batch-1').future,
      );
      expect(result.length, 1);
      expect(result.first.id, 'r-new');
      expect(result.first.status, ReportStatus.pending);
      expect(result.first.sublotLetter, 'A');
    });
  });

  group('ReportPollingNotifier', () {
    test('polls until report is complete', () async {
      var callCount = 0;
      when(() => mockDio.get('/api/v1/reports/r-poll')).thenAnswer((_) async {
        callCount++;
        final isComplete = callCount >= 2;
        return Response(
          data: {
            'id': 'r-poll',
            'batch_id': 'batch-1',
            'status': isComplete ? 'complete' : 'pending',
            'pdf_url': isComplete ? 'https://example.com/r.pdf' : null,
            'csv_url': isComplete ? 'https://example.com/r.csv' : null,
            'created_at': '2026-04-20T10:00:00Z',
          },
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/v1/reports/r-poll'),
        );
      });

      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(apiClient)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(reportPollingProvider.notifier);
      final report = await notifier.pollUntilComplete(
        'r-poll',
        pollInterval: const Duration(milliseconds: 50),
        maxAttempts: 10,
      );

      expect(report.status, ReportStatus.complete);
      expect(report.pdfUrl, isNotNull);
      expect(callCount, 2);
    });

    test('stops polling on error status', () async {
      when(() => mockDio.get('/api/v1/reports/r-err')).thenAnswer(
        (_) async => Response(
          data: {
            'id': 'r-err',
            'batch_id': 'batch-1',
            'status': 'error',
            'pdf_url': null,
            'csv_url': null,
            'created_at': '2026-04-20T10:00:00Z',
          },
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/v1/reports/r-err'),
        ),
      );

      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(apiClient)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(reportPollingProvider.notifier);
      final report = await notifier.pollUntilComplete(
        'r-err',
        pollInterval: const Duration(milliseconds: 50),
        maxAttempts: 10,
      );

      expect(report.hasError, true);
    });

    test('throws after max attempts', () async {
      when(() => mockDio.get('/api/v1/reports/r-timeout')).thenAnswer(
        (_) async => Response(
          data: {
            'id': 'r-timeout',
            'batch_id': 'batch-1',
            'status': 'pending',
            'pdf_url': null,
            'csv_url': null,
            'created_at': '2026-04-20T10:00:00Z',
          },
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/v1/reports/r-timeout'),
        ),
      );

      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(apiClient)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(reportPollingProvider.notifier);
      expect(
        () => notifier.pollUntilComplete(
          'r-timeout',
          pollInterval: const Duration(milliseconds: 10),
          maxAttempts: 3,
        ),
        throwsA(isA<ReportPollingTimeoutException>()),
      );
    });
  });
}

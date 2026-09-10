import 'package:flutter_test/flutter_test.dart';

import 'package:crystalapp/features/reports/models/report.dart';

void main() {
  group('Report model', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': '123',
        'batch_id': '456',
        'status': 'complete',
        'pdf_url': 'https://files.invalid/report.pdf',
        'csv_url': 'https://files.invalid/report.csv',
        'created_at': '2026-04-06T12:00:00Z',
      };
      final report = Report.fromJson(json);
      expect(report.status, ReportStatus.complete);
      expect(report.pdfUrl, isNotNull);
      expect(report.id, '123');
      expect(report.batchId, '456');
    });

    test('pending report has no URLs', () {
      final json = {
        'id': '123',
        'batch_id': '456',
        'status': 'pending',
        'pdf_url': null,
        'csv_url': null,
        'created_at': '2026-04-06T12:00:00Z',
      };
      final report = Report.fromJson(json);
      expect(report.status, ReportStatus.pending);
      expect(report.isDownloadable, false);
    });

    test('complete report is downloadable', () {
      final report = Report(
        id: '1',
        batchId: '2',
        status: ReportStatus.complete,
        pdfUrl: 'https://example.com/report.pdf',
        csvUrl: 'https://example.com/report.csv',
        createdAt: DateTime.now(),
      );
      expect(report.isDownloadable, true);
    });

    test('complete report without urls is not downloadable', () {
      final report = Report(
        id: '1',
        batchId: '2',
        status: ReportStatus.complete,
        createdAt: DateTime.now(),
      );
      expect(report.isDownloadable, false);
    });

    test('error report is not downloadable', () {
      final report = Report(
        id: '1',
        batchId: '2',
        status: ReportStatus.error,
        createdAt: DateTime.now(),
      );
      expect(report.isDownloadable, false);
    });

    test('status parsing', () {
      expect(ReportStatus.fromString('pending'), ReportStatus.pending);
      expect(ReportStatus.fromString('generating'), ReportStatus.generating);
      expect(ReportStatus.fromString('complete'), ReportStatus.complete);
      expect(ReportStatus.fromString('failed'), ReportStatus.failed);
      expect(ReportStatus.fromString('error'), ReportStatus.error);
    });

    test('unknown status defaults to pending', () {
      expect(ReportStatus.fromString('xyz'), ReportStatus.pending);
    });

    test('toJson roundtrip', () {
      final report = Report(
        id: 'abc',
        batchId: 'def',
        status: ReportStatus.complete,
        pdfUrl: 'https://example.com/report.pdf',
        csvUrl: 'https://example.com/report.csv',
        createdAt: DateTime.parse('2026-04-06T12:00:00Z'),
      );
      final json = report.toJson();
      final restored = Report.fromJson(json);
      expect(restored.id, report.id);
      expect(restored.batchId, report.batchId);
      expect(restored.status, report.status);
      expect(restored.pdfUrl, report.pdfUrl);
      expect(restored.csvUrl, report.csvUrl);
    });

    test('isPending returns true for pending status', () {
      final report = Report(
        id: '1',
        batchId: '2',
        status: ReportStatus.pending,
        createdAt: DateTime.now(),
      );
      expect(report.isPending, true);
    });

    test('isPending returns true for generating status', () {
      final report = Report(
        id: '1',
        batchId: '2',
        status: ReportStatus.generating,
        createdAt: DateTime.now(),
      );
      expect(report.isPending, true);
    });

    test('hasError returns true for failed and error status', () {
      expect(
        Report(
          id: '1',
          batchId: '2',
          status: ReportStatus.failed,
          createdAt: DateTime.now(),
        ).hasError,
        true,
      );
      expect(
        Report(
          id: '1',
          batchId: '2',
          status: ReportStatus.error,
          createdAt: DateTime.now(),
        ).hasError,
        true,
      );
    });
  });

  test('parses publication lineage and history with legacy defaults', () {
    final report = Report.fromJson({
      'id': 'r',
      'batch_id': 'b',
      'status': 'complete',
      'created_at': '2026-08-12T00:00:00Z',
      'source_content_revision': 8,
      'authorized_edit_state_version': 3,
      'is_current': true,
      'is_stale': false,
      'superseded_at': '2026-08-13T00:00:00Z',
    });
    expect(report.sourceContentRevision, 8);
    expect(report.isCurrent, isTrue);
    expect(report.isStale, isFalse);
    expect(report.isSuperseded, isTrue);
    final legacy = Report.fromJson({
      'id': 'r',
      'batch_id': 'b',
      'status': 'complete',
      'created_at': '2026-08-12T00:00:00Z',
    });
    expect(legacy.sourceContentRevision, 0);
    expect(legacy.isStale, isTrue);
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:crystalapp/features/reports/services/report_download_service.dart';

void main() {
  group('ReportDownloadService', () {
    test('fileNameFromUrl extracts filename from signed URL', () {
      const url =
          'https://crystal.example/local-files/reports/abc-123/report.pdf?token=signed';
      expect(
        ReportDownloadService.fileNameFromUrl(url, fallback: 'report.pdf'),
        'report.pdf',
      );
    });

    test('fileNameFromUrl uses fallback for bad URL', () {
      expect(
        ReportDownloadService.fileNameFromUrl('', fallback: 'report.pdf'),
        'report.pdf',
      );
    });

    test('fileNameFromUrl handles URL with no query params', () {
      const url = 'https://example.com/path/to/my-report.csv';
      expect(
        ReportDownloadService.fileNameFromUrl(url, fallback: 'report.csv'),
        'my-report.csv',
      );
    });

    test('fileNameFromUrl handles URL ending in slash', () {
      const url = 'https://example.com/path/';
      expect(
        ReportDownloadService.fileNameFromUrl(url, fallback: 'default.pdf'),
        'default.pdf',
      );
    });
  });
}

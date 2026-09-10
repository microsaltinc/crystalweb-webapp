import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crystalapp/features/reports/models/report.dart';
import 'package:crystalapp/features/reports/providers/report_provider.dart';
import 'package:crystalapp/features/reports/widgets/report_section.dart';

void main() {
  group('ReportSection', () {
    testWidgets(
      'shows campaign and bag generation actions when no reports exist',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              reportsForBatchProvider(
                'batch-1',
              ).overrideWith((_) async => <Report>[]),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: ReportSection(
                  batchId: 'batch-1',
                  batchStatus: 'complete',
                  lotCode: 'N26024A-1',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Generate Campaign Report'), findsOneWidget);
        expect(find.text('Generate Bag Reports'), findsOneWidget);
      },
    );

    testWidgets('shows per-sublot rows when reports are complete', (
      tester,
    ) async {
      final completeReport = Report(
        id: 'r1',
        batchId: 'batch-1',
        status: ReportStatus.complete,
        sublotLetter: 'A',
        sublotName: 'N26024A-1A',
        pdfUrl: 'https://example.com/report.pdf',
        csvUrl: 'https://example.com/report.csv',
        createdAt: DateTime.parse('2026-04-20T10:00:00Z'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reportsForBatchProvider(
              'batch-1',
            ).overrideWith((_) async => [completeReport]),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ReportSection(
                batchId: 'batch-1',
                batchStatus: 'complete',
                lotCode: 'N26024A-1',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('N26024A-1A'), findsOneWidget);
      expect(find.text('Complete'), findsOneWidget);
      expect(find.text('View'), findsOneWidget);
      expect(find.byTooltip('Download PDF'), findsOneWidget);
      expect(find.byTooltip('Download CSV'), findsOneWidget);
    });

    testWidgets('shows spinner when report is pending', (tester) async {
      final pendingReport = Report(
        id: 'r1',
        batchId: 'batch-1',
        status: ReportStatus.pending,
        sublotLetter: 'A',
        sublotName: 'N26024A-1A',
        createdAt: DateTime.parse('2026-04-20T10:00:00Z'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reportsForBatchProvider(
              'batch-1',
            ).overrideWith((_) async => [pendingReport]),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ReportSection(
                batchId: 'batch-1',
                batchStatus: 'complete',
                lotCode: 'N26024A-1',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('N26024A-1A'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('shows Retry when report has failed', (tester) async {
      final failedReport = Report(
        id: 'r1',
        batchId: 'batch-1',
        status: ReportStatus.error,
        sublotLetter: 'A',
        sublotName: 'N26024A-1A',
        createdAt: DateTime.parse('2026-04-20T10:00:00Z'),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reportsForBatchProvider(
              'batch-1',
            ).overrideWith((_) async => [failedReport]),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ReportSection(
                batchId: 'batch-1',
                batchStatus: 'complete',
                lotCode: 'N26024A-1',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('N26024A-1A'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('shows message when batch is not complete', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reportsForBatchProvider(
              'batch-1',
            ).overrideWith((_) async => <Report>[]),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ReportSection(
                batchId: 'batch-1',
                batchStatus: 'processing',
                lotCode: 'N26024A-1',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Generate Campaign Report'), findsNothing);
      expect(find.text('Generate Bag Reports'), findsNothing);
      expect(
        find.text('Reports are available after all images are processed'),
        findsOneWidget,
      );
    });
  });
}

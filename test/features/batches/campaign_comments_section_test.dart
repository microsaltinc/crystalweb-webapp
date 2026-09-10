import 'package:crystalapp/features/batches/models/campaign_comment.dart';
import 'package:crystalapp/features/batches/providers/campaign_collaboration_provider.dart';
import 'package:crystalapp/features/batches/widgets/campaign_comments_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows comments in provider order with author display', (
    tester,
  ) async {
    final comments = [
      CampaignComment(
        id: 'c1',
        batchId: 'batch-1',
        authorOperatorId: 'op-1',
        authorOperatorName: 'Maria',
        authorOperatorActive: true,
        authorSessionEmail: 'lab@microsaltinc.com',
        authorRequiresOperatorName: true,
        text: 'First note',
        createdAt: DateTime.utc(2026, 8, 11, 12),
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          campaignCommentsProvider(
            'batch-1',
          ).overrideWith((ref) async => comments),
        ],
        child: const MaterialApp(
          home: Scaffold(body: CampaignCommentsSection(batchId: 'batch-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('lab@microsaltinc.com — Maria'), findsOneWidget);
    expect(find.text('First note'), findsOneWidget);
    expect(find.text('Post comment'), findsOneWidget);
  });

  testWidgets('validates blank drafts locally and keeps composer visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          campaignCommentsProvider('batch-1').overrideWith((ref) async => []),
        ],
        child: const MaterialApp(
          home: Scaffold(body: CampaignCommentsSection(batchId: 'batch-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Post comment'));
    await tester.pump();

    expect(find.text('Enter a comment before posting.'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}

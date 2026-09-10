import 'package:crystalapp/features/batches/models/campaign_assignment_candidate.dart';
import 'package:crystalapp/features/batches/providers/campaign_collaboration_provider.dart';
import 'package:crystalapp/features/batches/widgets/transfer_owner_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows sorted two-column candidates and marks current owner', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          campaignAssignmentCandidatesProvider.overrideWith(
            (ref, batchId) async => const [
              CampaignAssignmentCandidate(
                id: 'op-2',
                name: 'Rodrigo',
                email: 'rodrigo@microsaltinc.com',
              ),
              CampaignAssignmentCandidate(
                id: 'op-1',
                name: 'Ahmad',
                email: 'lab1@microsaltinc.com',
              ),
            ],
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: CampaignAssignmentDialog(
              batchId: 'batch-1',
              currentOwnerId: 'op-2',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Operator'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('(lab1)'), findsOneWidget);
    expect(find.text('(rodrigo)'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Ahmad')).dy,
      lessThan(tester.getTopLeft(find.text('Rodrigo')).dy),
    );
  });
}

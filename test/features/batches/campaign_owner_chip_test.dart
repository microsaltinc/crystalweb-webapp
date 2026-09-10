import 'package:crystalapp/features/batches/models/batch.dart';
import 'package:crystalapp/features/batches/widgets/campaign_owner_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Batch _batch({
  String? ownerId,
  String? ownerName,
  bool? active,
  String? sessionEmail,
  String? ownerEmail,
  bool requiresName = false,
}) => Batch(
  id: 'batch-1',
  lotCode: 'LOT',
  formulaCode: 'F',
  dryerCode: 'D',
  campaignNum: 1,
  sublotCount: 1,
  imageCount: 1,
  status: 'pending',
  createdAt: DateTime.utc(2026),
  ownerOperatorId: ownerId,
  ownerOperatorName: ownerName,
  ownerOperatorActive: active,
  ownerEmail: ownerEmail,
  ownerSessionEmail: sessionEmail,
  ownerRequiresOperatorName: requiresName,
);

void main() {
  testWidgets('shows unassigned label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CampaignOwnerChip(batch: _batch())),
      ),
    );
    expect(find.text('Unassigned'), findsOneWidget);
  });

  testWidgets('shows operator name and shortened operator account', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CampaignOwnerChip(
            batch: _batch(
              ownerId: 'op-1',
              ownerName: 'Maria',
              active: true,
              sessionEmail: 'lab@microsaltinc.com',
              ownerEmail: 'maria@microsaltinc.com',
              requiresName: true,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Maria — maria'), findsOneWidget);
  });

  testWidgets('marks inactive owners', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CampaignOwnerChip(
            batch: _batch(
              ownerId: 'op-1',
              ownerName: 'Maria',
              active: false,
              sessionEmail: 'lab@microsaltinc.com',
              ownerEmail: 'maria@microsaltinc.com',
            ),
          ),
        ),
      ),
    );
    expect(find.text('Maria — maria (inactive)'), findsOneWidget);
  });
}

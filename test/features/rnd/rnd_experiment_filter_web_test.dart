import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crystalapp/features/batches/models/batch.dart';
import 'package:crystalapp/features/batches/models/campaign_workflow_status.dart';
import 'package:crystalapp/features/batches/providers/campaign_workflow_provider.dart';
import 'package:crystalapp/features/operators/providers/operator_provider.dart';
import 'package:crystalapp/features/projects/providers/project_provider.dart';
import 'package:crystalapp/features/rnd/providers/rnd_batch_provider.dart';
import 'package:crystalapp/features/rnd/screens/rnd_batch_list_screen.dart';

void main() {
  testWidgets(
    'Web exposes additive experiment filters without PO or Lot Code',
    (tester) async {
      final experiment = Batch(
        id: 'web-rnd',
        lotCode: 'EXP-WEB',
        formulaCode: 'F-WEB',
        dryerCode: 'D',
        campaignNum: 1,
        sublotCount: 1,
        imageCount: 1,
        status: 'complete',
        createdAt: DateTime.utc(2026, 8, 21),
        mode: 'rnd',
      );
      const catalog = CampaignWorkflowCatalog(version: 1, statuses: []);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            rndBatchListProvider.overrideWith((_) async => [experiment]),
            projectListProvider.overrideWith((_) async => []),
            operatorListProvider.overrideWith((_) async => []),
            campaignWorkflowCatalogProvider.overrideWith((_) async => catalog),
          ],
          child: const MaterialApp(home: RndBatchListScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ChoiceChip, 'All'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Mine'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Unassigned'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Owner'), findsOneWidget);
      expect(find.byKey(const Key('workflow-status-filter')), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'From'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'To'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Formula'), findsOneWidget);
      expect(find.text('Filter by Project'), findsOneWidget);
      expect(find.text('Lot Code'), findsNothing);
      expect(find.text('PO'), findsNothing);

      await tester.tap(find.widgetWithText(InputChip, 'Formula'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('F-WEB').last);
      await tester.pumpAndSettle();
      expect(find.text('1 of 1 experiments'), findsOneWidget);
    },
  );
}

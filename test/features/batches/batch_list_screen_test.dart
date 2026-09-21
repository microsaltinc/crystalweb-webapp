import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crystalapp/features/batches/models/batch.dart';
import 'package:crystalapp/features/batches/providers/batch_provider.dart';
import 'package:crystalapp/features/batches/models/campaign_workflow_status.dart';
import 'package:crystalapp/features/batches/providers/campaign_workflow_provider.dart';
import 'package:crystalapp/features/batches/providers/campaign_workflow_filter_provider.dart';
import 'package:crystalapp/features/batches/screens/batch_list_screen.dart';

void main() {
  testWidgets('offers direct Campaign creation', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [batchListProvider.overrideWith((_) async => [])],
        child: const MaterialApp(home: BatchListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Create a direct-upload destination to begin'),
      findsOneWidget,
    );
    expect(find.byTooltip('New Campaign'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byKey(const Key('create-batches-header')),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'Project fields do not affect production Purchase Order grouping',
    (tester) async {
      final batch = Batch(
        id: 'batch-1',
        lotCode: 'LOT-PO',
        formulaCode: 'FORMULA',
        dryerCode: 'D1',
        campaignNum: 1,
        sublotCount: 1,
        imageCount: 1,
        status: 'complete',
        createdAt: DateTime.utc(2026, 8, 6),
        purchaseOrderId: 'po-1',
        purchaseOrderCode: 'PO-100',
        projectId: 'project-1',
        projectName: 'Must Not Group Production',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            batchListProvider.overrideWith((_) async => [batch]),
          ],
          child: const MaterialApp(home: BatchListScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('PO: PO-100'), findsOneWidget);
      expect(find.textContaining('Must Not Group Production'), findsNothing);
      expect(find.text('PO-100'), findsOneWidget);
    },
  );

  testWidgets('shows workflow and technical chips with accessible filter', (
    tester,
  ) async {
    final batch = Batch(
      id: 'batch-wf',
      lotCode: 'LOT-WF',
      formulaCode: 'F',
      dryerCode: 'D',
      campaignNum: 1,
      sublotCount: 1,
      imageCount: 1,
      status: 'processing',
      createdAt: DateTime.utc(2026, 8, 12),
      workflowStatusId: 'done',
      workflowStatusKey: 'done',
      workflowStatusLabel: 'Shipped',
      workflowStatusColor: 'green',
    );
    const catalog = CampaignWorkflowCatalog(
      version: 1,
      statuses: [
        CampaignWorkflowStatus(
          id: 'done',
          key: 'done',
          label: 'Shipped',
          color: 'green',
          displayOrder: 0,
          isDefault: false,
          isSystem: true,
          isDone: true,
          usageCount: 1,
          canDelete: false,
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          batchListProvider.overrideWith((_) async => [batch]),
          campaignWorkflowCatalogProvider.overrideWith((_) async => catalog),
        ],
        child: const MaterialApp(home: BatchListScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Shipped'), findsOneWidget);
    expect(find.text('processing'), findsOneWidget);
    expect(find.byKey(const Key('workflow-status-filter')), findsOneWidget);
  });

  testWidgets(
    'workflow-filtered empty response shows specific state and can clear',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            batchListProvider.overrideWith((_) async => []),
            campaignWorkflowFilterProvider.overrideWith((_) => 'done'),
          ],
          child: const MaterialApp(home: BatchListScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('No campaigns match the workflow status filter'),
        findsOneWidget,
      );
      expect(find.byTooltip('Clear filters'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear filters'));
      await tester.pump();
    },
  );

  testWidgets(
    'workflow filter exposes keyboard-focusable accessible semantics',
    (tester) async {
      final batch = Batch(
        id: 'a11y',
        lotCode: 'A11Y',
        formulaCode: 'F',
        dryerCode: 'D',
        campaignNum: 1,
        sublotCount: 1,
        imageCount: 1,
        status: 'pending',
        createdAt: DateTime.utc(2026, 8, 12),
        workflowStatusId: 'review',
        workflowStatusKey: 'in_review',
        workflowStatusLabel: 'In Review',
        workflowStatusColor: 'teal',
      );
      const catalog = CampaignWorkflowCatalog(
        version: 1,
        statuses: [
          CampaignWorkflowStatus(
            id: 'review',
            key: 'in_review',
            label: 'In Review',
            color: 'teal',
            displayOrder: 0,
            isDefault: false,
            isSystem: true,
            isDone: false,
            usageCount: 1,
            canDelete: false,
          ),
        ],
      );
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            batchListProvider.overrideWith((_) async => [batch]),
            campaignWorkflowCatalogProvider.overrideWith((_) async => catalog),
          ],
          child: const MaterialApp(home: BatchListScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Workflow status filter, all statuses'),
        findsOneWidget,
      );
      expect(find.byTooltip('Filter by workflow status'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, isNotNull);
      semantics.dispose();
    },
  );
}

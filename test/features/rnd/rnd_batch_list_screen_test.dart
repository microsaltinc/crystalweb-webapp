import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crystalapp/features/batches/models/batch.dart';
import 'package:crystalapp/features/batches/models/campaign_workflow_status.dart';
import 'package:crystalapp/features/batches/providers/campaign_workflow_provider.dart';
import 'package:crystalapp/features/batches/providers/campaign_workflow_filter_provider.dart';
import 'package:crystalapp/features/projects/models/project.dart';
import 'package:crystalapp/features/projects/providers/project_provider.dart';
import 'package:crystalapp/features/rnd/providers/rnd_batch_provider.dart';
import 'package:crystalapp/features/rnd/rnd_batch_filters.dart';
import 'package:crystalapp/features/rnd/screens/rnd_batch_list_screen.dart';

Batch batch(
  String id,
  String lot, {
  String? projectId,
  String? projectName,
  String formulaCode = 'F',
  DateTime? createdAt,
}) => Batch(
  id: id,
  lotCode: lot,
  formulaCode: formulaCode,
  dryerCode: 'D',
  campaignNum: 1,
  sublotCount: 1,
  imageCount: 1,
  status: 'complete',
  createdAt: createdAt ?? DateTime.utc(2026, 8, 6),
  mode: 'rnd',
  projectId: projectId,
  projectName: projectName,
);

void main() {
  testWidgets('offers direct R&D destination creation', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rndBatchListProvider.overrideWith((_) async => []),
          projectListProvider.overrideWith((_) async => []),
        ],
        child: const MaterialApp(home: RndBatchListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Create a direct-upload destination to begin'),
      findsOneWidget,
    );
    expect(find.byTooltip('New R&D experiment'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byKey(const Key('create-rnd-header')),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'shows Campaign-parity filters plus Project without PO or Lot Code',
    (tester) async {
      const catalog = CampaignWorkflowCatalog(version: 1, statuses: []);
      final projects = [
        Project(
          id: 'alpha',
          name: 'Alpha Project',
          createdAt: DateTime.utc(2026),
        ),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            rndBatchListProvider.overrideWith(
              (_) async => [batch('1', 'EXP-1')],
            ),
            projectListProvider.overrideWith((_) async => projects),
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
      expect(find.text('From'), findsOneWidget);
      expect(find.text('To'), findsOneWidget);
      expect(find.text('Formula'), findsOneWidget);
      expect(find.text('Filter by Project'), findsOneWidget);
      expect(find.text('Lot Code'), findsNothing);
      expect(find.text('PO'), findsNothing);
    },
  );

  test('date, Formula, and Project filters compose with inclusive bounds', () {
    final batches = [
      batch(
        'match',
        'EXP-MATCH',
        projectId: 'alpha',
        projectName: 'Alpha',
        formulaCode: 'F-A',
        createdAt: DateTime(2026, 8, 6, 23, 59),
      ),
      batch(
        'wrong-formula',
        'EXP-FORMULA',
        projectId: 'alpha',
        formulaCode: 'F-B',
        createdAt: DateTime(2026, 8, 6, 12),
      ),
      batch(
        'wrong-project',
        'EXP-PROJECT',
        projectId: 'beta',
        formulaCode: 'F-A',
        createdAt: DateTime(2026, 8, 6, 12),
      ),
      batch(
        'too-early',
        'EXP-EARLY',
        projectId: 'alpha',
        formulaCode: 'F-A',
        createdAt: DateTime(2026, 8, 4, 23, 59),
      ),
      batch(
        'too-late',
        'EXP-LATE',
        projectId: 'alpha',
        formulaCode: 'F-A',
        createdAt: DateTime(2026, 8, 7),
      ),
    ];

    final filtered = filterRndBatches(
      batches,
      fromDate: DateTime(2026, 8, 5),
      toDate: DateTime(2026, 8, 6),
      formulaCode: 'F-A',
      projectId: 'alpha',
    );

    expect(filtered.map((item) => item.id), ['match']);
  });

  testWidgets('Formula filter is additive and unified clear restores results', (
    tester,
  ) async {
    const catalog = CampaignWorkflowCatalog(version: 1, statuses: []);
    final batches = [
      batch('a', 'EXP-A', formulaCode: 'F-A'),
      batch('b', 'EXP-B', formulaCode: 'F-B'),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rndBatchListProvider.overrideWith((_) async => batches),
          projectListProvider.overrideWith((_) async => []),
          campaignWorkflowCatalogProvider.overrideWith((_) async => catalog),
        ],
        child: const MaterialApp(home: RndBatchListScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(InputChip, 'Formula'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('F-A').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('EXP-A'), findsOneWidget);
    expect(find.textContaining('EXP-B'), findsNothing);
    expect(find.text('1 of 2 experiments'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.textContaining('EXP-A'), findsOneWidget);
    expect(find.text('No Project (2)'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'Formula'), findsOneWidget);
  });

  testWidgets('experiment filters remain usable at 200 percent text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const catalog = CampaignWorkflowCatalog(version: 1, statuses: []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rndBatchListProvider.overrideWith((_) async => [batch('1', 'EXP-1')]),
          projectListProvider.overrideWith((_) async => []),
          campaignWorkflowCatalogProvider.overrideWith((_) async => catalog),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const RndBatchListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(InputChip, 'Formula'), findsOneWidget);
    expect(find.text('Filter by Project'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('groups named Projects alphabetically with No Project last', (
    tester,
  ) async {
    final batches = [
      batch('3', 'LOT-3'),
      batch('2', 'LOT-2', projectId: 'z', projectName: 'Zebra'),
      batch('1', 'LOT-1', projectId: 'a', projectName: 'Alpha'),
    ];
    final projects = [
      Project(id: 'z', name: 'Zebra', createdAt: DateTime.utc(2026)),
      Project(id: 'a', name: 'Alpha', createdAt: DateTime.utc(2026)),
      Project(id: 'e', name: 'Empty', createdAt: DateTime.utc(2026)),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rndBatchListProvider.overrideWith((_) async => batches),
          projectListProvider.overrideWith((_) async => projects),
        ],
        child: const MaterialApp(home: RndBatchListScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Alpha (1)'), findsOneWidget);
    expect(find.text('Zebra (1)'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('No Project (1)'), findsOneWidget);
    expect(find.text('Empty (0)'), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Assign Project for LOT-1'), findsOneWidget);
  });

  testWidgets('filters by Project and clears back to all results', (
    tester,
  ) async {
    final batches = [
      batch('1', 'LOT-A', projectId: 'a', projectName: 'Alpha'),
      batch('2', 'LOT-NONE'),
    ];
    final projects = [
      Project(id: 'a', name: 'Alpha', createdAt: DateTime.utc(2026)),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rndBatchListProvider.overrideWith((_) async => batches),
          projectListProvider.overrideWith((_) async => projects),
        ],
        child: const MaterialApp(home: RndBatchListScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('project-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alpha').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('LOT-A'), findsOneWidget);
    expect(find.textContaining('LOT-NONE'), findsNothing);
    await tester.tap(find.text('Clear filter'));
    await tester.pumpAndSettle();
    expect(find.textContaining('LOT-NONE'), findsOneWidget);
  });

  testWidgets('R&D shows workflow and technical status parity', (tester) async {
    final item = Batch(
      id: 'rnd-wf',
      lotCode: 'RND-WF',
      formulaCode: 'F',
      dryerCode: 'D',
      campaignNum: 1,
      sublotCount: 1,
      imageCount: 1,
      status: 'complete',
      createdAt: DateTime.utc(2026, 8, 12),
      mode: 'rnd',
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
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rndBatchListProvider.overrideWith((_) async => [item]),
          projectListProvider.overrideWith((_) async => []),
          campaignWorkflowCatalogProvider.overrideWith((_) async => catalog),
        ],
        child: const MaterialApp(home: RndBatchListScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('In Review'), findsOneWidget);
    expect(find.text('complete'), findsOneWidget);
    expect(find.byKey(const Key('workflow-status-filter')), findsOneWidget);
  });

  testWidgets('R&D workflow-filtered empty state is specific', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          rndBatchListProvider.overrideWith((_) async => []),
          projectListProvider.overrideWith((_) async => []),
          campaignWorkflowFilterProvider.overrideWith((_) => 'done'),
        ],
        child: const MaterialApp(home: RndBatchListScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('No experiments match the workflow status filter'),
      findsOneWidget,
    );
  });
}

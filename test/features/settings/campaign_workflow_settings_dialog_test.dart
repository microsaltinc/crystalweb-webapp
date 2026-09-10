import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:crystalapp/features/batches/models/campaign_workflow_status.dart';
import 'package:crystalapp/features/batches/providers/campaign_workflow_provider.dart';
import 'package:crystalapp/features/settings/widgets/campaign_workflow_settings_dialog.dart';

const validationCatalog = CampaignWorkflowCatalog(
  version: 4,
  statuses: [
    CampaignWorkflowStatus(
      id: 'hold',
      key: 'custom_hold',
      label: 'Hold',
      color: 'amber',
      displayOrder: 0,
      isDefault: false,
      isSystem: false,
      isDone: false,
      usageCount: 0,
      canDelete: true,
    ),
  ],
);

void main() {
  test('unknown color degrades to accessible gray', () {
    final item = CampaignWorkflowStatus.fromJson({
      'id': '1',
      'label': 'Hold',
      'color': '#fff',
    });
    expect(item.color, 'gray');
  });

  testWidgets(
    'renders responsive catalog usage, disabled reasons, and semantics',
    (tester) async {
      const catalog = CampaignWorkflowCatalog(
        version: 4,
        statuses: [
          CampaignWorkflowStatus(
            id: 'progress',
            key: 'in_progress',
            label: 'In Progress',
            color: 'blue',
            displayOrder: 0,
            isDefault: true,
            isSystem: true,
            isDone: false,
            usageCount: 12,
            canDelete: false,
            deleteBlocker: 'System statuses cannot be deleted',
          ),
          CampaignWorkflowStatus(
            id: 'hold',
            key: 'custom_hold',
            label: 'Hold',
            color: 'amber',
            displayOrder: 1,
            isDefault: false,
            isSystem: false,
            isDone: false,
            usageCount: 0,
            canDelete: true,
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            campaignWorkflowCatalogProvider.overrideWith((_) async => catalog),
          ],
          child: const MaterialApp(
            home: Scaffold(body: CampaignWorkflowSettingsDialog()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('12 campaigns • Default'), findsOneWidget);
      expect(find.text('0 campaigns'), findsOneWidget);
      expect(
        find.byTooltip('System statuses cannot be deleted'),
        findsOneWidget,
      );
      expect(find.byTooltip('Move up'), findsNWidgets(2));
      expect(find.byTooltip('Move down'), findsNWidgets(2));
      expect(find.text('Add status'), findsOneWidget);
    },
  );

  testWidgets('shows loading and sanitized server error states', (
    tester,
  ) async {
    final pending = Completer<CampaignWorkflowCatalog>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          campaignWorkflowCatalogProvider.overrideWith((_) => pending.future),
        ],
        child: const MaterialApp(
          home: Scaffold(body: CampaignWorkflowSettingsDialog()),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pending.complete(const CampaignWorkflowCatalog(version: 1, statuses: []));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          campaignWorkflowCatalogProvider.overrideWith((_) async {
            throw DioException(
              requestOptions: RequestOptions(
                path: 'https://secret.invalid/workflow',
              ),
              message: 'RequestOptions stack trace',
            );
          }),
        ],
        child: const MaterialApp(
          home: Scaffold(body: CampaignWorkflowSettingsDialog()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('secret.invalid'), findsNothing);
    expect(find.textContaining('Dio'), findsNothing);
    expect(find.textContaining('RequestOptions'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('add dialog validates blank label', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          campaignWorkflowCatalogProvider.overrideWith(
            (_) async => validationCatalog,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: CampaignWorkflowSettingsDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pump();
    expect(find.text('Workflow status label is required.'), findsOneWidget);
  });

  testWidgets('add dialog validates case-insensitive duplicate label', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          campaignWorkflowCatalogProvider.overrideWith(
            (_) async => validationCatalog,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: CampaignWorkflowSettingsDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add status'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '  hOLD  ');
    await tester.tap(find.text('Add'));
    await tester.pump();
    expect(
      find.text('A workflow status with this label already exists.'),
      findsOneWidget,
    );
  });

  testWidgets('catalog rows expose edit, reorder, and delete controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          campaignWorkflowCatalogProvider.overrideWith(
            (_) async => validationCatalog,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: CampaignWorkflowSettingsDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hold'), findsOneWidget);
    expect(find.byTooltip('Move up'), findsOneWidget);
    expect(find.byTooltip('Move down'), findsOneWidget);
    expect(find.byTooltip('Delete Hold'), findsOneWidget);
    await tester.tap(find.text('Hold'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Hold'), findsOneWidget);
    expect(find.text('Default for new campaigns'), findsOneWidget);
    expect(find.text('Color'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });
}

import 'dart:typed_data';

import 'package:crystalapp/core/api/api_client.dart';
import 'package:crystalapp/features/batches/models/batch.dart';
import 'package:crystalapp/features/batches/models/campaign_workflow_status.dart';
import 'package:crystalapp/features/batches/providers/campaign_lock_coordinator.dart';
import 'package:crystalapp/features/batches/providers/campaign_workflow_provider.dart';
import 'package:crystalapp/features/batches/widgets/campaign_workflow_section.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class SectionAdapter implements HttpClientAdapter {
  SectionAdapter({this.statusCode = 200, this.responseKey = 'done'});
  final int statusCode;
  final String responseKey;
  final paths = <String>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    final body = statusCode >= 400
        ? '{"detail":"That workflow status is no longer available. Refresh and try again."}'
        : '{"id":"batch","lot_code":"LOT","created_at":"2026-08-12T00:00:00Z",'
              '"workflow_status_id":"$responseKey","workflow_status_key":"$responseKey",'
              '"workflow_status_label":"Updated","workflow_status_color":"green"}';
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class RecordingLockCoordinator implements CampaignLockCoordinator {
  RecordingLockCoordinator(this.result);
  final CampaignLockResult result;
  int calls = 0;

  @override
  Future<CampaignLockResult> lockCampaignIfReady(String batchId) async {
    calls++;
    return result;
  }
}

Batch testBatch() => Batch(
  id: 'batch',
  lotCode: 'LOT',
  formulaCode: 'F',
  dryerCode: 'D',
  campaignNum: 1,
  sublotCount: 1,
  imageCount: 1,
  status: 'complete',
  createdAt: DateTime.utc(2026, 8, 12),
  workflowStatusId: 'progress',
  workflowStatusKey: 'in_progress',
  workflowStatusLabel: 'In Progress',
  workflowStatusColor: 'blue',
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
      usageCount: 0,
      canDelete: false,
    ),
  ],
);

void main() {
  test('unavailable coordinator safely reports dependency', () async {
    expect(
      await UnavailableCampaignLockCoordinator().lockCampaignIfReady('batch'),
      isA<CampaignLockUnavailable>(),
    );
  });

  testWidgets('Done identity after rename shows exact prompt and Not Now saves', (
    tester,
  ) async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
    final adapter = SectionAdapter();
    dio.httpClientAdapter = adapter;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(ApiClient.withDio(dio)),
          campaignWorkflowCatalogProvider.overrideWith((_) async => catalog),
        ],
        child: MaterialApp(
          home: Scaffold(body: CampaignWorkflowSection(batch: testBatch())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shipped'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Since you are done with this campaign, do you want to lock it so it cannot be edited?',
      ),
      findsOneWidget,
    );
    expect(adapter.paths, isEmpty);
    await tester.tap(find.text('Not Now'));
    await tester.pumpAndSettle();
    expect(adapter.paths, contains('/api/v1/batches/batch/workflow-status'));
  });

  testWidgets(
    'stale transition conflict refreshes safely and never invokes lock',
    (tester) async {
      final dio = Dio(BaseOptions(baseUrl: 'https://secret.invalid'));
      dio.httpClientAdapter = SectionAdapter(statusCode: 409);
      final coordinator = RecordingLockCoordinator(const CampaignLockSuccess());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(ApiClient.withDio(dio)),
            campaignWorkflowCatalogProvider.overrideWith((_) async => catalog),
            campaignLockCoordinatorProvider.overrideWithValue(coordinator),
          ],
          child: MaterialApp(
            home: Scaffold(body: CampaignWorkflowSection(batch: testBatch())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shipped'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Since you are done'), findsOneWidget);
      expect(coordinator.calls, 0);
      await tester.tap(find.text('Lock'));
      await tester.pumpAndSettle();
      expect(find.textContaining('no longer available'), findsOneWidget);
      expect(find.textContaining('Since you are done'), findsNothing);
      expect(coordinator.calls, 0);
      expect(find.textContaining('secret.invalid'), findsNothing);
      expect(find.textContaining('Dio'), findsNothing);
    },
  );

  testWidgets('non-Done immutable key never shows Done prompt', (tester) async {
    const reviewCatalog = CampaignWorkflowCatalog(
      version: 1,
      statuses: [
        CampaignWorkflowStatus(
          id: 'review',
          key: 'in_review',
          label: 'Ready',
          color: 'teal',
          displayOrder: 0,
          isDefault: false,
          isSystem: true,
          isDone: false,
          usageCount: 0,
          canDelete: false,
        ),
      ],
    );
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
    dio.httpClientAdapter = SectionAdapter(responseKey: 'in_review');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(ApiClient.withDio(dio)),
          campaignWorkflowCatalogProvider.overrideWith(
            (_) async => reviewCatalog,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: CampaignWorkflowSection(batch: testBatch())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ready'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Since you are done'), findsNothing);
  });

  testWidgets('blocked Lock preserves Done and reports friendly blockers', (
    tester,
  ) async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
    dio.httpClientAdapter = SectionAdapter();
    final coordinator = RecordingLockCoordinator(
      const CampaignLockBlocked(['report is still generating']),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(ApiClient.withDio(dio)),
          campaignWorkflowCatalogProvider.overrideWith((_) async => catalog),
          campaignLockCoordinatorProvider.overrideWithValue(coordinator),
        ],
        child: MaterialApp(
          home: Scaffold(body: CampaignWorkflowSection(batch: testBatch())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shipped'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lock'));
    await tester.pumpAndSettle();
    expect(coordinator.calls, 1);
    expect(
      find.text('Done saved. Cannot lock: report is still generating'),
      findsOneWidget,
    );
  });
}

import 'dart:async';
import 'dart:typed_data';

import 'package:crystalapp/core/api/api_client.dart';
import 'package:crystalapp/core/providers/role_scope_provider.dart';
import 'package:crystalapp/features/batches/models/campaign_workflow_status.dart';
import 'package:crystalapp/features/batches/providers/batch_provider.dart';
import 'package:crystalapp/features/batches/providers/campaign_ownership_filter_provider.dart';
import 'package:crystalapp/features/batches/providers/campaign_workflow_filter_provider.dart';
import 'package:crystalapp/features/rnd/providers/rnd_batch_provider.dart';
import 'package:crystalapp/features/batches/providers/campaign_workflow_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingAdapter implements HttpClientAdapter {
  RecordingAdapter(this.handler);
  final ResponseBody Function(RequestOptions options) handler;
  RequestOptions? last;
  final history = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    history.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(String body, {int status = 200}) =>
    ResponseBody.fromString(
      body,
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

void main() {
  test('catalog model preserves version and Done identity after rename', () {
    final catalog = CampaignWorkflowCatalog.fromJson({
      'catalog_version': 2,
      'statuses': [
        {
          'id': '1',
          'key': 'done',
          'label': 'Complete',
          'color': 'green',
          'is_done': true,
        },
      ],
    });
    expect(catalog.version, 2);
    expect(catalog.statuses.single.isDone, isTrue);
  });

  test(
    'production campaign requests stay production-scoped for all-mode users',
    () async {
      const allModeScopes = <RoleScope>[
        RoleScope.admin(),
        RoleScope(
          canSeeRnd: true,
          canSeeProduction: true,
          canSeeAll: true,
          availableModes: ['rnd', 'production'],
          isAdmin: false,
        ),
      ];

      for (final scope in allModeScopes) {
        final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
        final adapter = RecordingAdapter((_) => jsonResponse('[]'));
        dio.httpClientAdapter = adapter;
        final container = ProviderContainer(
          overrides: [
            apiClientProvider.overrideWithValue(ApiClient.withDio(dio)),
            roleScopeProvider.overrideWithValue(scope),
          ],
        );

        await container.read(batchListProvider.future);

        expect(adapter.last?.path, '/api/v1/batches');
        expect(
          adapter.last?.queryParameters['mode'],
          'production',
          reason:
              'Campaigns must stay production-only for every all-mode scope',
        );
        container.dispose();
      }
    },
  );

  test('catalog fetch and production/R&D workflow query composition', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
    final adapter = RecordingAdapter((options) {
      if (options.path == '/api/v1/campaign-workflow-statuses') {
        return jsonResponse(
          '{"catalog_version":7,"statuses":[{"id":"review","key":"in_review",'
          '"label":"In Review","color":"teal","usage_count":2,"can_delete":false}]}',
        );
      }
      return jsonResponse('[]');
    });
    dio.httpClientAdapter = adapter;
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(ApiClient.withDio(dio)),
        roleScopeProvider.overrideWithValue(
          const RoleScope(
            canSeeRnd: false,
            canSeeProduction: true,
            canSeeAll: false,
            availableModes: ['production'],
            isAdmin: false,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final catalog = await container.read(
      campaignWorkflowCatalogProvider.future,
    );
    expect(catalog.version, 7);
    expect(catalog.statuses.single.usageCount, 2);
    container.read(campaignWorkflowFilterProvider.notifier).state = 'review';
    container.read(campaignOwnershipFilterProvider.notifier).state =
        const OwnershipFilter.unassigned();
    await container.read(batchListProvider.future);
    expect(adapter.last?.queryParameters, {
      'workflow_status_id': 'review',
      'mode': 'production',
      'owner': 'unassigned',
    });
    container.read(campaignOwnershipFilterProvider.notifier).state =
        const OwnershipFilter.unassigned();
    await container.read(rndBatchListProvider.future);
    expect(adapter.last?.queryParameters, {
      'mode': 'rnd',
      'workflow_status_id': 'review',
      'owner': 'unassigned',
    });
  });

  test('transition sends exact payload and returns projection', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
    final adapter = RecordingAdapter(
      (_) => jsonResponse(
        '{"id":"batch-1","lot_code":"LOT","created_at":"2026-08-12T00:00:00Z",'
        '"workflow_status_id":"done-id","workflow_status_key":"done",'
        '"workflow_status_label":"Done","workflow_status_color":"green"}',
      ),
    );
    dio.httpClientAdapter = adapter;
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(ApiClient.withDio(dio))],
    );
    addTearDown(container.dispose);
    final result = await container
        .read(campaignWorkflowControllerProvider)
        .transition(batchId: 'batch-1', workflowStatusId: 'done-id');
    expect(adapter.last?.path, '/api/v1/batches/batch-1/workflow-status');
    expect(adapter.last?.data, {'workflow_status_id': 'done-id'});
    expect(result.workflowStatusIsDone, isTrue);
  });

  test(
    'catalog mutations include optimistic version and complete reorder',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
      final adapter = RecordingAdapter(
        (_) => jsonResponse('{"catalog_version":4,"statuses":[]}'),
      );
      dio.httpClientAdapter = adapter;
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(ApiClient.withDio(dio)),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(campaignWorkflowControllerProvider);
      await controller.create(
        label: 'QA Hold',
        color: 'purple',
        expectedCatalogVersion: 3,
        displayOrder: 1,
        isDefault: true,
      );
      expect(adapter.last?.data['expected_catalog_version'], 3);
      expect(adapter.last?.data['display_order'], 1);
      await controller.reorder(
        orderedStatusIds: ['b', 'a'],
        expectedCatalogVersion: 4,
      );
      expect(adapter.last?.data, {
        'ordered_status_ids': ['b', 'a'],
        'expected_catalog_version': 4,
      });
      await controller.delete(statusId: 'a', expectedCatalogVersion: 4);
      expect(adapter.last?.queryParameters['expected_catalog_version'], 4);
    },
  );

  test(
    'safe conflict detail is mapped without Dio or URL diagnostics',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://secret.invalid'));
      dio.httpClientAdapter = RecordingAdapter(
        (_) => jsonResponse(
          '{"detail":"Workflow statuses changed. Refresh and try again."}',
          status: 409,
        ),
      );
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(ApiClient.withDio(dio)),
        ],
      );
      addTearDown(container.dispose);
      try {
        await container
            .read(campaignWorkflowControllerProvider)
            .delete(statusId: 'a', expectedCatalogVersion: 1);
        fail('expected conflict');
      } on CampaignWorkflowException catch (error) {
        expect(error.message, contains('Refresh and try again'));
        expect(error.message, isNot(contains('Dio')));
        expect(error.message, isNot(contains('secret.invalid')));
        expect(error.message, isNot(contains('RequestOptions')));
      }
    },
  );

  test(
    'update sends only requested fields with expected catalog version',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
      final adapter = RecordingAdapter(
        (_) => jsonResponse('{"catalog_version":9,"statuses":[]}'),
      );
      dio.httpClientAdapter = adapter;
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(ApiClient.withDio(dio)),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(campaignWorkflowControllerProvider)
          .update(
            statusId: 'review',
            expectedCatalogVersion: 8,
            label: 'Ready',
            color: 'teal',
            isDefault: true,
          );
      expect(adapter.last?.path, '/api/v1/campaign-workflow-statuses/review');
      expect(adapter.last?.data, {
        'label': 'Ready',
        'color': 'teal',
        'is_default': true,
        'expected_catalog_version': 8,
      });
    },
  );

  test('non-JSON 5xx and network failures map to sanitized messages', () async {
    for (final failure in <ResponseBody Function(RequestOptions)>[
      (_) => ResponseBody.fromString(
        '<html>https://secret.invalid RequestOptions DioException</html>',
        503,
        headers: {
          Headers.contentTypeHeader: ['text/html'],
        },
      ),
      (_) => throw DioException(
        requestOptions: RequestOptions(path: 'https://secret.invalid/private'),
        message: 'socket RequestOptions',
      ),
    ]) {
      final dio = Dio(BaseOptions(baseUrl: 'https://secret.invalid'));
      dio.httpClientAdapter = RecordingAdapter(failure);
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(ApiClient.withDio(dio)),
        ],
      );
      try {
        await container
            .read(campaignWorkflowControllerProvider)
            .transition(batchId: 'batch', workflowStatusId: 'done');
        fail('expected safe failure');
      } on CampaignWorkflowException catch (error) {
        expect(error.message, isNot(contains('Dio')));
        expect(error.message, isNot(contains('RequestOptions')));
        expect(error.message, isNot(contains('secret.invalid')));
        expect(error.message, isNot(contains('<html>')));
      } finally {
        container.dispose();
      }
    }
  });
}

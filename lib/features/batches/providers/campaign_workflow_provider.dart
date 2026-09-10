import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/user_facing_error.dart';
import '../../rnd/providers/rnd_batch_provider.dart';
import '../models/batch.dart';
import '../models/campaign_workflow_status.dart';
import 'batch_provider.dart';
import 'campaign_locking_provider.dart';

final campaignWorkflowCatalogProvider =
    FutureProvider.autoDispose<CampaignWorkflowCatalog>((ref) async {
      final client = ref.watch(apiClientProvider);
      final response = await client.dio.get(
        '/api/v1/campaign-workflow-statuses',
      );
      return CampaignWorkflowCatalog.fromJson(
        response.data as Map<String, dynamic>,
      );
    });

/// Invalidated after persisted catalog changes so Settings-local draft state
/// cannot silently survive a server-side mutation.
final campaignWorkflowSettingsRefreshProvider = StateProvider<int>((ref) => 0);

class CampaignWorkflowException implements Exception {
  const CampaignWorkflowException(this.message);
  final String message;

  @override
  String toString() => message;
}

String campaignWorkflowErrorMessage(Object error) =>
    error is CampaignWorkflowException
    ? error.message
    : userFacingError(error, action: 'update campaign workflow');

class CampaignWorkflowController {
  CampaignWorkflowController(this.ref);
  final Ref ref;

  ApiClient get _client => ref.read(apiClientProvider);

  Never _safe(Object error, String action) =>
      throw CampaignWorkflowException(userFacingError(error, action: action));

  void _invalidate({String? batchId, bool catalog = false}) {
    ref.invalidate(batchListProvider);
    ref.invalidate(rndBatchListProvider);
    if (batchId != null) ref.invalidate(batchDetailProvider(batchId));
    if (catalog) {
      ref.invalidate(campaignWorkflowCatalogProvider);
      ref.invalidate(batchDetailProvider);
      ref.invalidate(campaignWorkflowSettingsRefreshProvider);
    }
  }

  Future<Batch> transition({
    required String batchId,
    required String workflowStatusId,
    int? expectedEditStateVersion,
  }) async {
    try {
      final response = await _client.dio.patch(
        '/api/v1/batches/$batchId/workflow-status',
        data: {'workflow_status_id': workflowStatusId},
        options: expectedEditStateVersion == null
            ? null
            : Options(
                headers: {
                  'If-Match': campaignEditETag(expectedEditStateVersion),
                },
              ),
      );
      final batch = Batch.fromJson(response.data as Map<String, dynamic>);
      _invalidate(batchId: batchId);
      return batch;
    } catch (error) {
      _invalidate(batchId: batchId, catalog: true);
      _safe(error, 'change workflow status');
    }
  }

  Future<CampaignWorkflowCatalog> create({
    required String label,
    required String color,
    required int expectedCatalogVersion,
    int? displayOrder,
    bool isDefault = false,
  }) async {
    try {
      final response = await _client.dio.post(
        '/api/v1/campaign-workflow-statuses',
        data: {
          'label': label,
          'color': color,
          'display_order': ?displayOrder,
          'is_default': isDefault,
          'expected_catalog_version': expectedCatalogVersion,
        },
      );
      final catalog = CampaignWorkflowCatalog.fromJson(
        response.data as Map<String, dynamic>,
      );
      _invalidate(catalog: true);
      return catalog;
    } catch (error) {
      _safe(error, 'add workflow status');
    }
  }

  Future<CampaignWorkflowCatalog> update({
    required String statusId,
    required int expectedCatalogVersion,
    String? label,
    String? color,
    bool? isDefault,
  }) async {
    try {
      final response = await _client.dio.patch(
        '/api/v1/campaign-workflow-statuses/$statusId',
        data: {
          'label': ?label,
          'color': ?color,
          'is_default': ?isDefault,
          'expected_catalog_version': expectedCatalogVersion,
        },
      );
      final catalog = CampaignWorkflowCatalog.fromJson(
        response.data as Map<String, dynamic>,
      );
      _invalidate(catalog: true);
      return catalog;
    } catch (error) {
      _safe(error, 'update workflow status');
    }
  }

  Future<CampaignWorkflowCatalog> reorder({
    required List<String> orderedStatusIds,
    required int expectedCatalogVersion,
  }) async {
    try {
      final response = await _client.dio.put(
        '/api/v1/campaign-workflow-statuses/order',
        data: {
          'ordered_status_ids': orderedStatusIds,
          'expected_catalog_version': expectedCatalogVersion,
        },
      );
      final catalog = CampaignWorkflowCatalog.fromJson(
        response.data as Map<String, dynamic>,
      );
      _invalidate(catalog: true);
      return catalog;
    } catch (error) {
      _safe(error, 'reorder workflow statuses');
    }
  }

  Future<CampaignWorkflowCatalog> delete({
    required String statusId,
    required int expectedCatalogVersion,
  }) async {
    try {
      final response = await _client.dio.delete(
        '/api/v1/campaign-workflow-statuses/$statusId',
        queryParameters: {'expected_catalog_version': expectedCatalogVersion},
      );
      final catalog = CampaignWorkflowCatalog.fromJson(
        response.data as Map<String, dynamic>,
      );
      _invalidate(catalog: true);
      return catalog;
    } catch (error) {
      _safe(error, 'delete workflow status');
    }
  }
}

final campaignWorkflowControllerProvider = Provider<CampaignWorkflowController>(
  CampaignWorkflowController.new,
);

Future<Batch> transitionCampaignWorkflowStatus(
  WidgetRef ref, {
  required String batchId,
  required String workflowStatusId,
  int? expectedEditStateVersion,
}) => ref
    .read(campaignWorkflowControllerProvider)
    .transition(
      batchId: batchId,
      workflowStatusId: workflowStatusId,
      expectedEditStateVersion: expectedEditStateVersion,
    );

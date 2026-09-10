import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../models/campaign_structure.dart';
import 'campaign_qualification_provider.dart';

final campaignStructureProvider = FutureProvider.autoDispose
    .family<CampaignStructure, String>((ref, batchId) async {
      final response = await ref
          .watch(apiClientProvider)
          .dio
          .get(
            '/api/v1/batches/$batchId/structure',
            queryParameters: {'include_archived': true},
          );
      return CampaignStructure.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    });

final campaignStructureActionsProvider = Provider<CampaignStructureActions>(
  CampaignStructureActions.new,
);

class CampaignStructureActions {
  CampaignStructureActions(this._ref);
  final Ref _ref;

  Future<StructureMutationResult> updateLot(
    String batchId,
    String lotCode, {
    required int editStateVersion,
    required int contentRevision,
  }) => _request(
    batchId,
    'PATCH',
    '/api/v1/batches/$batchId/structure',
    {'lot_code': lotCode},
    editStateVersion,
    contentRevision,
  );
  Future<StructureMutationResult> addSublot(
    String batchId,
    String identifier, {
    String? label,
    String? notes,
    required int editStateVersion,
    required int contentRevision,
  }) => _request(
    batchId,
    'POST',
    '/api/v1/batches/$batchId/sublots',
    {
      'identifier': identifier,
      // ignore: use_null_aware_elements
      if (label != null) 'label': label,
      // ignore: use_null_aware_elements
      if (notes != null) 'notes': notes,
    },
    editStateVersion,
    contentRevision,
  );
  Future<StructureMutationResult> updateSublot(
    String batchId,
    String sublotId,
    Map<String, dynamic> changes, {
    required int editStateVersion,
    required int contentRevision,
  }) => _request(
    batchId,
    'PATCH',
    '/api/v1/sublots/$sublotId',
    changes,
    editStateVersion,
    contentRevision,
  );
  Future<StructureMutationResult> addBag(
    String batchId,
    String sublotId,
    int number, {
    String? notes,
    required int editStateVersion,
    required int contentRevision,
  }) => _request(
    batchId,
    'POST',
    '/api/v1/sublots/$sublotId/bags',
    // ignore: use_null_aware_elements
    {'number': number, if (notes != null) 'notes': notes},
    editStateVersion,
    contentRevision,
  );
  Future<StructureMutationResult> updateBag(
    String batchId,
    String bagId,
    Map<String, dynamic> changes, {
    required int editStateVersion,
    required int contentRevision,
  }) => _request(
    batchId,
    'PATCH',
    '/api/v1/bags/$bagId',
    changes,
    editStateVersion,
    contentRevision,
  );
  Future<StructureMutationResult> archiveBag(
    String batchId,
    String bagId, {
    required int editStateVersion,
    required int contentRevision,
  }) => _request(
    batchId,
    'POST',
    '/api/v1/bags/$bagId/archive',
    null,
    editStateVersion,
    contentRevision,
  );
  Future<StructureMutationResult> restoreBag(
    String batchId,
    String bagId, {
    required int editStateVersion,
    required int contentRevision,
  }) => _request(
    batchId,
    'POST',
    '/api/v1/bags/$bagId/restore',
    null,
    editStateVersion,
    contentRevision,
  );
  Future<StructureMutationResult> deleteBag(
    String batchId,
    String bagId, {
    required int editStateVersion,
    required int contentRevision,
  }) => _request(
    batchId,
    'DELETE',
    '/api/v1/bags/$bagId',
    null,
    editStateVersion,
    contentRevision,
  );
  Future<StructureMutationResult> archiveSublot(
    String batchId,
    String id, {
    required int editStateVersion,
    required int contentRevision,
  }) => _request(
    batchId,
    'POST',
    '/api/v1/sublots/$id/archive',
    null,
    editStateVersion,
    contentRevision,
  );
  Future<StructureMutationResult> restoreSublot(
    String batchId,
    String id, {
    required int editStateVersion,
    required int contentRevision,
  }) => _request(
    batchId,
    'POST',
    '/api/v1/sublots/$id/restore',
    null,
    editStateVersion,
    contentRevision,
  );
  Future<StructureMutationResult> deleteSublot(
    String batchId,
    String id, {
    required int editStateVersion,
    required int contentRevision,
  }) => _request(
    batchId,
    'DELETE',
    '/api/v1/sublots/$id',
    null,
    editStateVersion,
    contentRevision,
  );

  Future<StructureMutationResult> _request(
    String batchId,
    String method,
    String path,
    Map<String, dynamic>? data,
    int editVersion,
    int contentRevision,
  ) async {
    try {
      final response = await _ref
          .read(apiClientProvider)
          .dio
          .request(
            path,
            data: data,
            options: Options(
              method: method,
              headers: {
                'If-Match': campaignCompositeETag(editVersion, contentRevision),
              },
            ),
          );
      return StructureMutationResult.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } finally {
      _ref.invalidate(campaignStructureProvider(batchId));
      refreshCampaignDetail(_ref, batchId);
    }
  }
}

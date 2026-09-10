import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../images/providers/image_provider.dart';
import '../../reports/providers/report_provider.dart';
import '../../rnd/providers/rnd_batch_provider.dart';
import '../models/campaign_qualification.dart';
import 'batch_provider.dart';
import 'campaign_locking_provider.dart';

String campaignCompositeETag(int editVersion, int contentRevision) =>
    '"campaign-edit-$editVersion-content-$contentRevision"';

final campaignQualificationProvider = FutureProvider.autoDispose
    .family<CampaignQualification, String>((ref, batchId) async {
      final response = await ref
          .watch(apiClientProvider)
          .dio
          .get('/api/v1/batches/$batchId/qualification');
      return CampaignQualification.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    });

final campaignQualificationHistoryProvider = FutureProvider.autoDispose
    .family<QualificationHistoryPage, String>((ref, batchId) async {
      final response = await ref
          .watch(apiClientProvider)
          .dio
          .get('/api/v1/batches/$batchId/qualification-history');
      return QualificationHistoryPage.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    });

final campaignQualificationActionsProvider =
    Provider<CampaignQualificationActions>(CampaignQualificationActions.new);

class CampaignQualificationActions {
  CampaignQualificationActions(this._ref);
  final Ref _ref;

  Future<QualificationMutationResult> decideBag(
    String batchId,
    String bagId, {
    required BagQualificationStatus status,
    required int editStateVersion,
    required int contentRevision,
    String? reasonCode,
    String? notes,
  }) => _mutate(
    batchId,
    '/api/v1/bags/$bagId/qualification',
    {
      'status': status.key,
      // ignore: use_null_aware_elements
      if (reasonCode != null) 'reason_code': reasonCode,
      // ignore: use_null_aware_elements
      if (notes?.trim().isNotEmpty == true) 'notes': notes!.trim(),
    },
    editStateVersion,
    contentRevision,
  );

  Future<QualificationMutationResult> acceptOperatorReviewedBags(
    String batchId,
    String sublotId, {
    required int editStateVersion,
    required int contentRevision,
  }) => _mutate(
    batchId,
    '/api/v1/sublots/$sublotId/qualification/accept-operator-reviewed',
    const {},
    editStateVersion,
    contentRevision,
  );

  Future<QualificationMutationResult> finalizeCampaign(
    String batchId, {
    required CampaignQualificationStatus status,
    required int editStateVersion,
    required int contentRevision,
    String? reasonCode,
    String? notes,
  }) => _mutate(
    batchId,
    '/api/v1/batches/$batchId/qualification',
    {
      'status': status.key,
      // ignore: use_null_aware_elements
      if (reasonCode != null) 'reason_code': reasonCode,
      // ignore: use_null_aware_elements
      if (notes?.trim().isNotEmpty == true) 'notes': notes!.trim(),
    },
    editStateVersion,
    contentRevision,
  );

  Future<QualificationMutationResult> _mutate(
    String batchId,
    String path,
    Map<String, dynamic> data,
    int editVersion,
    int contentRevision,
  ) async {
    try {
      final response = await _ref
          .read(apiClientProvider)
          .dio
          .put(
            path,
            data: data,
            options: Options(
              headers: {
                'If-Match': campaignCompositeETag(editVersion, contentRevision),
              },
            ),
          );
      return QualificationMutationResult.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } finally {
      refreshCampaignDetail(_ref, batchId);
    }
  }
}

void refreshCampaignDetail(Ref ref, String batchId) {
  ref.invalidate(campaignQualificationProvider(batchId));
  ref.invalidate(campaignQualificationHistoryProvider(batchId));
  ref.invalidate(batchDetailProvider(batchId));
  ref.invalidate(batchListProvider);
  ref.invalidate(rndBatchListProvider);
  ref.invalidate(imagesForBatchProvider(batchId));
  ref.invalidate(reportsForBatchProvider(batchId));
  ref.invalidate(campaignLockReadinessProvider(batchId));
}

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../images/providers/image_provider.dart';
import '../../reports/providers/report_provider.dart';
import '../../rnd/providers/rnd_batch_provider.dart';
import '../models/campaign_locking.dart';
import 'batch_provider.dart';

String campaignEditETag(int version) => '"campaign-edit-$version"';

final campaignLockReadinessProvider = FutureProvider.autoDispose
    .family<CampaignLockReadiness, String>((ref, batchId) async {
      final response = await ref
          .watch(apiClientProvider)
          .dio
          .get('/api/v1/batches/$batchId/lock-readiness');
      return CampaignLockReadiness.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    });

final registrationConflictsProvider = FutureProvider.autoDispose
    .family<List<RegistrationConflict>, String>((ref, batchId) async {
      final response = await ref
          .watch(apiClientProvider)
          .dio
          .get(
            '/api/v1/batches/$batchId/registration-conflicts',
            queryParameters: {'resolved': false},
          );
      final data = response.data as List;
      return data
          .whereType<Map>()
          .map(
            (value) =>
                RegistrationConflict.fromJson(Map<String, dynamic>.from(value)),
          )
          .toList(growable: false);
    });

final campaignLockingActionsProvider = Provider<CampaignLockingActions>(
  CampaignLockingActions.new,
);

class CampaignLockingActions {
  CampaignLockingActions(this._ref);
  final Ref _ref;

  Future<CampaignTransition> lock(
    String batchId, {
    required int expectedEditStateVersion,
    String? reason,
  }) => _transition(
    batchId,
    'lock',
    expectedEditStateVersion: expectedEditStateVersion,
    reason: reason,
  );

  Future<CampaignTransition> unlock(
    String batchId, {
    required int expectedEditStateVersion,
    String? reason,
  }) => _transition(
    batchId,
    'unlock',
    expectedEditStateVersion: expectedEditStateVersion,
    reason: reason,
  );

  Future<CampaignTransition> _transition(
    String batchId,
    String action, {
    required int expectedEditStateVersion,
    String? reason,
  }) async {
    final data = <String, dynamic>{
      'expected_edit_state_version': expectedEditStateVersion,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    };
    try {
      final response = await _ref
          .read(apiClientProvider)
          .dio
          .post('/api/v1/batches/$batchId/$action', data: data);
      return CampaignTransition.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } finally {
      _refreshCampaign(batchId);
    }
  }

  Future<RegistrationConflictRetry> retryConflict(
    String batchId,
    String conflictId, {
    required int expectedEditStateVersion,
    int? expectedContentRevision,
    String? selectedBagId,
  }) async {
    try {
      final response = await _ref
          .read(apiClientProvider)
          .dio
          .post(
            '/api/v1/batches/$batchId/registration-conflicts/$conflictId/retry',
            queryParameters: {
              // ignore: use_null_aware_elements
              if (selectedBagId != null) 'bag_id': selectedBagId,
            },
            options: Options(
              headers: {
                'If-Match': expectedContentRevision == null
                    ? campaignEditETag(expectedEditStateVersion)
                    : '"campaign-edit-$expectedEditStateVersion-content-$expectedContentRevision"',
              },
            ),
          );
      return RegistrationConflictRetry.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } finally {
      _ref.invalidate(registrationConflictsProvider(batchId));
      _refreshCampaign(batchId);
    }
  }

  void _refreshCampaign(String batchId) {
    _ref.invalidate(campaignLockReadinessProvider(batchId));
    _ref.invalidate(registrationConflictsProvider(batchId));
    _ref.invalidate(batchDetailProvider(batchId));
    _ref.invalidate(batchListProvider);
    _ref.invalidate(rndBatchListProvider);
    _ref.invalidate(imagesForBatchProvider(batchId));
    _ref.invalidate(reportsForBatchProvider(batchId));
  }
}

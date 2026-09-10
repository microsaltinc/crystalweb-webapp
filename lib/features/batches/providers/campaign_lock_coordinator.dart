import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_error.dart';
import '../models/campaign_locking.dart';
import 'campaign_locking_provider.dart';

sealed class CampaignLockResult {
  const CampaignLockResult();
}

class CampaignLockSuccess extends CampaignLockResult {
  const CampaignLockSuccess();
}

class CampaignLockBlocked extends CampaignLockResult {
  const CampaignLockBlocked(this.blockers);
  final List<String> blockers;
}

class CampaignLockUnavailable extends CampaignLockResult {
  const CampaignLockUnavailable();
}

abstract class CampaignLockCoordinator {
  Future<CampaignLockResult> lockCampaignIfReady(String batchId);
}

class UnavailableCampaignLockCoordinator implements CampaignLockCoordinator {
  @override
  Future<CampaignLockResult> lockCampaignIfReady(String batchId) async =>
      const CampaignLockUnavailable();
}

class ApiCampaignLockCoordinator implements CampaignLockCoordinator {
  ApiCampaignLockCoordinator(this._ref);
  final Ref _ref;

  @override
  Future<CampaignLockResult> lockCampaignIfReady(String batchId) async {
    try {
      final readiness = await _ref.read(
        campaignLockReadinessProvider(batchId).future,
      );
      if (!readiness.ready) {
        return CampaignLockBlocked(
          readiness.blockers.map((blocker) => blocker.message).toList(),
        );
      }
      await _ref
          .read(campaignLockingActionsProvider)
          .lock(batchId, expectedEditStateVersion: readiness.editStateVersion);
      return const CampaignLockSuccess();
    } catch (error) {
      final structured = ApiError.tryParse(error);
      if (structured?.code == 'campaign_not_ready') {
        final rawReadiness = structured!.details['readiness'];
        if (rawReadiness is Map) {
          final readiness = CampaignLockReadiness.fromJson(
            Map<String, dynamic>.from(rawReadiness),
          );
          return CampaignLockBlocked(
            readiness.blockers.map((blocker) => blocker.message).toList(),
          );
        }
      }
      return const CampaignLockUnavailable();
    }
  }
}

final campaignLockCoordinatorProvider = Provider<CampaignLockCoordinator>(
  (ref) => ApiCampaignLockCoordinator(ref),
);

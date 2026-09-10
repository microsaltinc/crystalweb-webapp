import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_provider.dart';
import '../models/batch.dart';
import '../models/campaign_assignment_candidate.dart';
import '../models/campaign_comment.dart';
import '../../rnd/providers/rnd_batch_provider.dart';
import 'batch_provider.dart';
import 'campaign_locking_provider.dart';

export 'campaign_ownership_filter_provider.dart';

final campaignAssignmentCandidatesProvider = FutureProvider.autoDispose
    .family<List<CampaignAssignmentCandidate>, String>((ref, batchId) async {
      final client = ref.watch(apiClientProvider);
      final response = await client.dio.get(
        '/api/v1/batches/$batchId/assignment-candidates',
        options: _authOptions(ref),
      );
      return (response.data as List)
          .map(
            (item) => CampaignAssignmentCandidate.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList();
    });

final campaignCommentsProvider = FutureProvider.autoDispose
    .family<List<CampaignComment>, String>((ref, batchId) async {
      final client = ref.watch(apiClientProvider);
      final response = await client.dio.get(
        '/api/v1/batches/$batchId/comments',
      );
      final data = response.data as List;
      return data
          .map((item) => CampaignComment.fromJson(item as Map<String, dynamic>))
          .toList();
    });

Options _authOptions(dynamic ref, {int? expectedEditStateVersion}) {
  final token = ref.read(authStateProvider).token;
  return Options(
    headers: {
      if (token != null) 'Authorization': 'Bearer $token',
      if (expectedEditStateVersion != null)
        'If-Match': campaignEditETag(expectedEditStateVersion),
    },
  );
}

void _invalidateBatchViews(dynamic ref, String batchId) {
  ref.invalidate(batchDetailProvider(batchId));
  ref.invalidate(batchListProvider);
  ref.invalidate(rndBatchListProvider);
  ref.invalidate(campaignAssignmentCandidatesProvider(batchId));
}

Future<Batch> assignCampaign(
  dynamic ref,
  String batchId, {
  required String targetOperatorId,
  required int expectedOwnershipVersion,
}) async {
  final client = ref.read(apiClientProvider);
  try {
    final response = await client.dio.post(
      '/api/v1/batches/$batchId/assign',
      data: {
        'target_operator_id': targetOperatorId,
        'expected_ownership_version': expectedOwnershipVersion,
      },
      options: _authOptions(ref),
    );
    _invalidateBatchViews(ref, batchId);
    return Batch.fromJson(response.data as Map<String, dynamic>);
  } on DioException catch (error) {
    if (error.response?.statusCode == 409) {
      _invalidateBatchViews(ref, batchId);
    }
    rethrow;
  }
}

Future<Batch> claimCampaign(
  dynamic ref,
  String batchId, {
  int? expectedEditStateVersion,
}) async {
  final client = ref.read(apiClientProvider);
  final response = await client.dio.post(
    '/api/v1/batches/$batchId/claim',
    options: _authOptions(
      ref,
      expectedEditStateVersion: expectedEditStateVersion,
    ),
  );
  _invalidateBatchViews(ref, batchId);
  return Batch.fromJson(response.data as Map<String, dynamic>);
}

Future<Batch> releaseCampaign(
  dynamic ref,
  String batchId, {
  int? expectedEditStateVersion,
}) async {
  final client = ref.read(apiClientProvider);
  final response = await client.dio.post(
    '/api/v1/batches/$batchId/release',
    options: _authOptions(
      ref,
      expectedEditStateVersion: expectedEditStateVersion,
    ),
  );
  _invalidateBatchViews(ref, batchId);
  return Batch.fromJson(response.data as Map<String, dynamic>);
}

Future<Batch> transferCampaign(
  dynamic ref,
  String batchId, {
  required String targetOperatorId,
  int? expectedEditStateVersion,
}) async {
  final client = ref.read(apiClientProvider);
  final response = await client.dio.post(
    '/api/v1/batches/$batchId/transfer',
    data: {'target_operator_id': targetOperatorId},
    options: _authOptions(
      ref,
      expectedEditStateVersion: expectedEditStateVersion,
    ),
  );
  _invalidateBatchViews(ref, batchId);
  return Batch.fromJson(response.data as Map<String, dynamic>);
}

Future<CampaignComment> createCampaignComment(
  dynamic ref,
  String batchId, {
  required String text,
}) async {
  final client = ref.read(apiClientProvider);
  final response = await client.dio.post(
    '/api/v1/batches/$batchId/comments',
    data: {'text': text},
    options: _authOptions(ref),
  );
  ref.invalidate(campaignCommentsProvider(batchId));
  return CampaignComment.fromJson(response.data as Map<String, dynamic>);
}

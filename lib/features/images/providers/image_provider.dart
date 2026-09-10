import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../batches/providers/batch_provider.dart';
import '../../batches/providers/campaign_locking_provider.dart';
import '../../batches/providers/campaign_qualification_provider.dart';
import '../../batches/providers/campaign_structure_provider.dart';
import '../../reports/providers/report_provider.dart';
import '../../rnd/providers/rnd_batch_provider.dart';
import '../models/crystal.dart';
import '../models/image_model.dart';

/// Fetches all images for a batch.
final imagesForBatchProvider = FutureProvider.autoDispose
    .family<List<ImageModel>, String>((ref, batchId) async {
      final client = ref.watch(apiClientProvider);
      final response = await client.dio.get(
        '/api/v1/images',
        queryParameters: {'batch_id': batchId},
      );
      final data = response.data as List;
      return data
          .map((j) => ImageModel.fromJson(j as Map<String, dynamic>))
          .toList();
    });

/// Fetches a single image detail.
final imageDetailProvider = FutureProvider.autoDispose
    .family<ImageModel, String>((ref, imageId) async {
      final client = ref.watch(apiClientProvider);
      final response = await client.dio.get('/api/v1/images/$imageId');
      return ImageModel.fromJson(response.data as Map<String, dynamic>);
    });

/// Fetches crystals for an image.
final crystalsForImageProvider = FutureProvider.autoDispose
    .family<List<Crystal>, String>((ref, imageId) async {
      final client = ref.watch(apiClientProvider);
      final response = await client.dio.get('/api/v1/crystals/image/$imageId');
      final data = response.data as List;
      return data
          .map((j) => Crystal.fromJson(j as Map<String, dynamic>))
          .toList();
    });

Options? _campaignPrecondition(int? version) => version == null
    ? null
    : Options(headers: {'If-Match': campaignEditETag(version)});

/// Invalidate an image (soft-discard). CRY-36 callers pass the parent state
/// version observed with the image; the optional form preserves legacy callers
/// until their projection has loaded.
Future<ImageModel> invalidateImage(
  WidgetRef ref,
  String imageId, {
  int? expectedEditStateVersion,
}) async {
  final observed = await ref.read(imageDetailProvider(imageId).future);
  final version = expectedEditStateVersion ?? observed.campaignEditStateVersion;
  try {
    final response = await ref
        .read(apiClientProvider)
        .dio
        .post(
          '/api/v1/images/$imageId/invalidate',
          options: _campaignPrecondition(version),
        );
    return ImageModel.fromJson(response.data as Map<String, dynamic>);
  } finally {
    refreshImageState(ref, imageId, observed.batchId);
  }
}

/// Revalidate a previously invalidated image.
Future<ImageModel> revalidateImage(
  WidgetRef ref,
  String imageId, {
  int? expectedEditStateVersion,
}) async {
  final observed = await ref.read(imageDetailProvider(imageId).future);
  final version = expectedEditStateVersion ?? observed.campaignEditStateVersion;
  try {
    final response = await ref
        .read(apiClientProvider)
        .dio
        .post(
          '/api/v1/images/$imageId/revalidate',
          options: _campaignPrecondition(version),
        );
    return ImageModel.fromJson(response.data as Map<String, dynamic>);
  } finally {
    refreshImageState(ref, imageId, observed.batchId);
  }
}

void refreshImageState(WidgetRef ref, String imageId, String batchId) {
  ref.invalidate(imageDetailProvider(imageId));
  ref.invalidate(imagesForBatchProvider(batchId));
  ref.invalidate(batchDetailProvider(batchId));
  ref.invalidate(batchListProvider);
  ref.invalidate(rndBatchListProvider);
  ref.invalidate(campaignLockReadinessProvider(batchId));
  ref.invalidate(reportsForBatchProvider(batchId));
}

void refreshImageStateFromProvider(Ref ref, String imageId, String batchId) {
  ref.invalidate(imageDetailProvider(imageId));
  ref.invalidate(imagesForBatchProvider(batchId));
  ref.invalidate(batchDetailProvider(batchId));
  ref.invalidate(batchListProvider);
  ref.invalidate(rndBatchListProvider);
  ref.invalidate(campaignLockReadinessProvider(batchId));
  ref.invalidate(reportsForBatchProvider(batchId));
}

class ImageRelocationResult {
  const ImageRelocationResult({
    required this.image,
    required this.campaignReset,
    required this.editStateVersion,
    required this.contentRevision,
  });

  factory ImageRelocationResult.fromJson(Map<String, dynamic> json) =>
      ImageRelocationResult(
        image: ImageModel.fromJson(
          Map<String, dynamic>.from(json['image'] as Map),
        ),
        campaignReset: json['campaign_reset'] == true,
        editStateVersion: (json['edit_state_version'] as num).toInt(),
        contentRevision: (json['content_revision'] as num).toInt(),
      );

  final ImageModel image;
  final bool campaignReset;
  final int editStateVersion;
  final int contentRevision;
}

final imageRelocationActionsProvider = Provider<ImageRelocationActions>(
  ImageRelocationActions.new,
);

class ImageRelocationActions {
  ImageRelocationActions(this._ref);
  final Ref _ref;

  Future<ImageRelocationResult> relocate(
    String imageId, {
    required String batchId,
    required String destinationBagId,
    required int expectedEditStateVersion,
    required int expectedContentRevision,
  }) async {
    try {
      final response = await _ref
          .read(apiClientProvider)
          .dio
          .post(
            '/api/v1/images/$imageId/relocate',
            data: {'destination_bag_id': destinationBagId},
            options: Options(
              headers: {
                'If-Match': campaignCompositeETag(
                  expectedEditStateVersion,
                  expectedContentRevision,
                ),
              },
            ),
          );
      return ImageRelocationResult.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } finally {
      _ref.invalidate(imageDetailProvider(imageId));
      _ref.invalidate(imagesForBatchProvider(batchId));
      _ref.invalidate(batchDetailProvider(batchId));
      _ref.invalidate(batchListProvider);
      _ref.invalidate(rndBatchListProvider);
      _ref.invalidate(campaignStructureProvider(batchId));
      _ref.invalidate(campaignQualificationProvider(batchId));
      _ref.invalidate(campaignLockReadinessProvider(batchId));
      _ref.invalidate(reportsForBatchProvider(batchId));
    }
  }
}

final imageReviewActionsProvider = Provider<ImageReviewActions>(
  ImageReviewActions.new,
);

class ImageReviewActions {
  ImageReviewActions(this._ref);
  final Ref _ref;

  Future<ImageModel> complete(
    String imageId, {
    required String batchId,
    required int expectedEditStateVersion,
  }) => _review(
    imageId,
    batchId: batchId,
    action: 'review-complete',
    expectedEditStateVersion: expectedEditStateVersion,
  );

  Future<ImageModel> clear(
    String imageId, {
    required String batchId,
    required int expectedEditStateVersion,
  }) => _review(
    imageId,
    batchId: batchId,
    action: 'review-clear',
    expectedEditStateVersion: expectedEditStateVersion,
    data: const {'reason': 'operator_correction'},
  );

  Future<ImageModel> _review(
    String imageId, {
    required String batchId,
    required String action,
    required int expectedEditStateVersion,
    Map<String, dynamic>? data,
  }) async {
    try {
      final response = await _ref
          .read(apiClientProvider)
          .dio
          .post(
            '/api/v1/images/$imageId/$action',
            data: data,
            options: _campaignPrecondition(expectedEditStateVersion),
          );
      return ImageModel.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } finally {
      _ref.invalidate(imageDetailProvider(imageId));
      _ref.invalidate(imagesForBatchProvider(batchId));
      _ref.invalidate(batchDetailProvider(batchId));
      _ref.invalidate(batchListProvider);
      _ref.invalidate(rndBatchListProvider);
      _ref.invalidate(campaignLockReadinessProvider(batchId));
      _ref.invalidate(reportsForBatchProvider(batchId));
    }
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:crystalapp/core/api/api_client.dart';
import 'package:crystalapp/features/batches/providers/campaign_qualification_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _QualificationAdapter implements HttpClientAdapter {
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.endsWith('/accept-operator-reviewed')) {
      request = options;
      return ResponseBody.fromString(
        jsonEncode({
          'changed': true,
          'batch_id': 'batch-1',
          'sublot_id': 'sublot-a',
          'accepted_bag_ids': ['bag-1'],
          'already_accepted_bag_ids': <String>[],
          'skipped_bag_ids': ['bag-2'],
          'campaign_status': 'pending_review',
          'campaign_reset': false,
          'edit_state_version': 3,
          'content_revision': 9,
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    return ResponseBody.fromString('{}', 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'accept operator-reviewed Bags uses Sublot endpoint and composite version',
    () async {
      final adapter = _QualificationAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://private.invalid'));
      dio.httpClientAdapter = adapter;
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(ApiClient.withDio(dio)),
        ],
      );
      addTearDown(container.dispose);

      final result = await container
          .read(campaignQualificationActionsProvider)
          .acceptOperatorReviewedBags(
            'batch-1',
            'sublot-a',
            editStateVersion: 3,
            contentRevision: 8,
          );

      expect(
        adapter.request?.path,
        '/api/v1/sublots/sublot-a/qualification/accept-operator-reviewed',
      );
      expect(adapter.request?.method, 'PUT');
      expect(
        adapter.request?.headers['If-Match'],
        '"campaign-edit-3-content-8"',
      );
      expect(result.contentRevision, 9);
    },
  );
}

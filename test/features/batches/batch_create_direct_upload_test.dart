import 'dart:convert';
import 'dart:typed_data';

import 'package:crystalapp/core/api/api_client.dart';
import 'package:crystalapp/features/batches/providers/batch_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _CreateBatchAdapter implements HttpClientAdapter {
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      jsonEncode({
        'id': 'batch-web',
        'lot_code': 'L26232A-1',
        'formula_code': 'PROD',
        'dryer_code': 'L',
        'campaign_num': 1,
        'sublot_count': 0,
        'image_count': 0,
        'status': 'pending',
        'created_at': '2026-08-20T00:00:00Z',
      }),
      201,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'direct-upload Campaign creation suppresses legacy placeholder Images',
    () async {
      final adapter = _CreateBatchAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://private.invalid'));
      dio.httpClientAdapter = adapter;

      final created = await createBatch(
        ApiClient.withDio(dio),
        formulaId: 'formula',
        dryerId: 'dryer',
        lotCode: 'L26232A-1',
        campaignNum: 1,
        julianDate: 232,
        year: 2026,
        sublotLetters: const ['A'],
        createPlaceholderImages: false,
        creationRequestId: '00000000-0000-4000-8000-000000000001',
      );

      expect(created.id, 'batch-web');
      expect(adapter.request?.method, 'POST');
      expect(adapter.request?.path, '/api/v1/batches');
      final payload = adapter.request?.data as Map<String, dynamic>;
      expect(payload['create_placeholder_images'], isFalse);
      expect(
        payload['creation_request_id'],
        '00000000-0000-4000-8000-000000000001',
      );
      expect(payload['sublot_letters'], ['A']);
    },
  );
}

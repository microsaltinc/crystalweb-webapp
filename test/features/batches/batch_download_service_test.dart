import 'dart:typed_data';

import 'package:crystalapp/features/batches/services/batch_download_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _ZipAdapter implements HttpClientAdapter {
  _ZipAdapter({this.fileName, this.statusCode = 200});

  final String? fileName;
  final int statusCode;
  RequestOptions? request;
  final bytes = Uint8List.fromList(<int>[80, 75, 3, 4, 1, 2, 3]);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromBytes(
      bytes,
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/zip'],
        if (fileName != null)
          'content-disposition': ['attachment; filename="$fileName"'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(_ZipAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
    ..httpClientAdapter = adapter;
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        options.headers['Authorization'] = 'Bearer web-jwt';
        handler.next(options);
      },
    ),
  );
  return dio;
}

void main() {
  test('Web ZIP uses authenticated Dio bytes and server filename', () async {
    final adapter = _ZipAdapter(fileName: 'LOT_campaign1_cropped.zip');
    Uint8List? savedBytes;
    String? savedName;
    final service = BatchDownloadService(
      dio: _dio(adapter),
      saveWebFile: (bytes, fileName) {
        savedBytes = bytes;
        savedName = fileName;
      },
    );

    final result = await service.downloadBatchImages(
      batchId: 'batch-1',
      format: 'cropped',
      lotCode: 'LOT',
      campaignNum: 1,
    );

    expect(result, isNull);
    expect(adapter.request?.path, '/api/v1/batches/batch-1/download-images');
    expect(adapter.request?.queryParameters, {'format': 'cropped'});
    expect(adapter.request?.headers['Authorization'], 'Bearer web-jwt');
    expect(adapter.request?.responseType, ResponseType.bytes);
    expect(savedBytes, adapter.bytes);
    expect(savedName, 'LOT_campaign1_cropped.zip');
  });

  test(
    'Web ZIP sanitizes a server path and otherwise uses campaign fallback',
    () async {
      for (final value in <String?>['../../unsafe.zip', null]) {
        final adapter = _ZipAdapter(fileName: value);
        String? savedName;
        final service = BatchDownloadService(
          dio: _dio(adapter),
          saveWebFile: (_, fileName) => savedName = fileName,
        );

        await service.downloadBatchImages(
          batchId: 'batch-1',
          format: 'original',
          lotCode: 'N26100A',
          campaignNum: 2,
        );

        expect(
          savedName,
          value == null ? 'N26100A_campaign2_original.zip' : 'unsafe.zip',
        );
      }
    },
  );

  test('Web ZIP propagates authorization and generation failures', () async {
    final service = BatchDownloadService(
      dio: _dio(_ZipAdapter(statusCode: 403)),
      saveWebFile: (_, _) {},
    );

    expect(
      () => service.downloadBatchImages(
        batchId: 'batch-1',
        format: 'cropped',
        lotCode: 'LOT',
        campaignNum: 1,
      ),
      throwsA(isA<DioException>()),
    );
  });
}

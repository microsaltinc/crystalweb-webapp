import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'batch_download_web_stub.dart'
    if (dart.library.js_interop) 'batch_download_web.dart'
    as web_download;

typedef WebFileSaver = void Function(Uint8List bytes, String fileName);

/// Downloads an authenticated Campaign ZIP and saves it through the browser.
class BatchDownloadService {
  BatchDownloadService({required Dio dio, WebFileSaver? saveWebFile})
    : _dio = dio,
      _saveWebFile = saveWebFile ?? web_download.saveWebFile;

  final Dio _dio;
  final WebFileSaver _saveWebFile;

  Future<String?> downloadBatchImages({
    required String batchId,
    required String format,
    required String lotCode,
    required int campaignNum,
    ValueChanged<double>? onProgress,
  }) async {
    final endpoint = '/api/v1/batches/$batchId/download-images';
    final queryParams = {'format': format};
    final defaultFileName = '${lotCode}_campaign${campaignNum}_$format.zip';
    final response = await _dio.get<List<int>>(
      endpoint,
      queryParameters: queryParams,
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(minutes: 3),
        sendTimeout: const Duration(seconds: 30),
      ),
      onReceiveProgress: (received, total) {
        if (total > 0 && onProgress != null) {
          onProgress(received / total);
        }
      },
    );
    final data = response.data ?? const <int>[];
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    final fileName = _responseFileName(
      response.headers.value('content-disposition'),
      defaultFileName,
    );
    _saveWebFile(bytes, fileName);
    return null;
  }

  static String _responseFileName(String? contentDisposition, String fallback) {
    if (contentDisposition == null) return fallback;
    final encoded = RegExp(
      r"filename\*=UTF-8''([^;]+)",
      caseSensitive: false,
    ).firstMatch(contentDisposition);
    final quoted = RegExp(
      r'filename="?([^";]+)"?',
      caseSensitive: false,
    ).firstMatch(contentDisposition);
    var candidate = encoded?.group(1) ?? quoted?.group(1);
    if (candidate == null) return fallback;
    try {
      candidate = Uri.decodeComponent(candidate);
    } on FormatException {
      return fallback;
    }
    candidate = candidate.replaceAll('\\', '/').split('/').last.trim();
    return candidate.isEmpty || candidate == '.' || candidate == '..'
        ? fallback
        : candidate;
  }
}

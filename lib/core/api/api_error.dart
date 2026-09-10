import 'package:dio/dio.dart';

/// Safe, structured API failure. Raw request/response diagnostics are never
/// included in [toString].
class ApiError implements Exception {
  const ApiError({
    this.code,
    required this.message,
    this.statusCode,
    this.details = const {},
  });

  final String? code;
  final String message;
  final int? statusCode;
  final Map<String, dynamic> details;

  static ApiError? tryParse(Object error) {
    if (error is ApiError) return error;
    if (error is DioException) {
      if (error.error is ApiError) return error.error as ApiError;
      return fromResponse(error.response);
    }
    return null;
  }

  static ApiError? fromResponse(Response<dynamic>? response) {
    final statusCode = response?.statusCode;
    if (statusCode == null || statusCode < 400 || statusCode >= 600) {
      return null;
    }
    final data = response?.data;
    if (data is! Map) return null;
    final detail = data['detail'];
    if (detail is! Map) return null;
    final map = Map<String, dynamic>.from(detail);
    final code = map['code'];
    final message = map['message'];
    if (code is! String ||
        code.trim().isEmpty ||
        message is! String ||
        !_isSafe(message)) {
      return null;
    }
    return ApiError(
      code: code.trim(),
      message: message.trim(),
      statusCode: response?.statusCode,
      details: Map.unmodifiable(map),
    );
  }

  static bool _isSafe(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 500) return false;
    final lower = normalized.toLowerCase();
    const markers = [
      'dioexception',
      'requestoptions',
      'traceback',
      'stack trace',
      'sqlalchemy',
      'asyncpg',
      '[sql:',
      '<html',
      '<!doctype',
    ];
    return !markers.any(lower.contains);
  }

  @override
  String toString() => message;
}

/// Attaches parsed structured errors without changing Dio's transport API.
class ApiErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final parsed = ApiError.fromResponse(err.response);
    handler.next(parsed == null ? err : err.copyWith(error: parsed));
  }
}

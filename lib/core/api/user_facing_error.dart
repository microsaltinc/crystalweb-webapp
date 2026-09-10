import 'package:dio/dio.dart';

import 'api_error.dart';

/// Converts application and transport failures into concise messages suitable
/// for display to an end user.
String userFacingError(Object error, {String? action}) {
  final message = _baseMessage(error);
  final normalizedAction = action?.trim();

  if (normalizedAction == null || normalizedAction.isEmpty) {
    return message;
  }

  return 'Could not $normalizedAction. $message';
}

String _baseMessage(Object error) {
  final structured = ApiError.tryParse(error);
  if (structured != null) {
    final rawIdentities = structured.details['identities'];
    final identities = rawIdentities is List
        ? rawIdentities
              .whereType<String>()
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty && value.length <= 255)
              .take(20)
              .toList(growable: false)
        : const <String>[];
    if (identities.isNotEmpty) {
      return '${structured.message} Affected sets: ${identities.join(', ')}.';
    }
    return structured.message;
  }

  if (error is! DioException) {
    return 'Something went wrong. Please try again.';
  }

  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return 'The request took too long. Please try again.';
    case DioExceptionType.connectionError:
      return 'Unable to reach the service. '
          'Check your internet connection and try again.';
    case DioExceptionType.cancel:
      return 'The action was cancelled.';
    case DioExceptionType.badCertificate:
      return 'A secure connection could not be established. Please try again.';
    case DioExceptionType.badResponse:
      return _responseMessage(error.response);
    case DioExceptionType.unknown:
      return 'Something went wrong. Please try again.';
  }
}

String _responseMessage(Response<dynamic>? response) {
  final statusCode = response?.statusCode;
  final safeDetail = _safeDetail(response?.data);

  if ((statusCode == 400 ||
          statusCode == 403 ||
          statusCode == 409 ||
          statusCode == 422) &&
      safeDetail != null) {
    return safeDetail;
  }

  switch (statusCode) {
    case 400:
    case 422:
      return 'Some information is invalid. '
          'Check your entries and try again.';
    case 401:
      return 'Your session has expired. Please sign in again.';
    case 403:
      return 'You do not have permission to do that.';
    case 404:
      return 'The requested item is no longer available. '
          'Please refresh and try again.';
    case 409:
      return 'The request conflicts with existing information. '
          'Update it and try again.';
    case 429:
      return 'Too many attempts. Please wait a moment and try again.';
    default:
      if (statusCode != null && statusCode >= 500) {
        return 'The service could not complete your request. '
            'Please try again in a moment.';
      }
      return 'The request could not be completed. Please try again.';
  }
}

String? _safeDetail(dynamic data) {
  if (data is! Map) {
    return null;
  }

  final detail = data['detail'];
  if (detail is! String) {
    return null;
  }

  final normalized = detail.trim();
  if (normalized.isEmpty || normalized.length > 500) {
    return null;
  }

  final lower = normalized.toLowerCase();
  const technicalMarkers = <String>[
    'dioexception',
    'exception:',
    'traceback',
    'stack trace',
    'sqlalchemy',
    'asyncpg',
    '[sql:',
    'requestoptions',
    '<html',
    '<!doctype',
  ];

  if (technicalMarkers.any(lower.contains)) {
    return null;
  }

  return normalized;
}

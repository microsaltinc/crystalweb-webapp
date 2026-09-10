import 'package:crystalapp/core/api/user_facing_error.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _responseError(int statusCode, dynamic data) {
  final request = RequestOptions(path: '/api/v1/test');
  return DioException(
    requestOptions: request,
    response: Response<dynamic>(
      requestOptions: request,
      statusCode: statusCode,
      data: data,
    ),
    type: DioExceptionType.badResponse,
  );
}

DioException _transportError(DioExceptionType type) {
  return DioException(
    requestOptions: RequestOptions(path: '/api/v1/test'),
    type: type,
  );
}

void main() {
  group('userFacingError', () {
    test('propagates safe actionable detail for expected 400 responses', () {
      final message = userFacingError(
        _responseError(400, {'detail': 'Choose a valid formula option.'}),
      );

      expect(message, 'Choose a valid formula option.');
    });

    test('propagates safe actionable detail for 409 conflicts', () {
      final message = userFacingError(
        _responseError(409, {
          'detail':
              'A formula with this code already exists. Change the formula selections and try again.',
        }),
      );

      expect(
        message,
        'A formula with this code already exists. '
        'Change the formula selections and try again.',
      );
    });

    test('propagates safe actionable detail for 422 validation', () {
      final message = userFacingError(
        _responseError(422, {
          'detail': 'Salt percentage must be between 0 and 100.',
        }),
      );

      expect(message, 'Salt percentage must be between 0 and 100.');
    });

    test('includes affected identities from structured upload conflicts', () {
      final message = userFacingError(
        _responseError(409, {
          'detail': {
            'code': 'microscope_upload_duplicate',
            'message':
                'The selected files do not exactly match an unfinished upload.',
            'identities': ['001', '002', '008'],
            'can_discard': false,
          },
        }),
        action: 'upload microscope files',
      );

      expect(
        message,
        'Could not upload microscope files. '
        'The selected files do not exactly match an unfinished upload. '
        'Affected sets: 001, 002, 008.',
      );
    });

    test('uses validation fallback for structured 422 details', () {
      final message = userFacingError(
        _responseError(422, {
          'detail': [
            {
              'loc': ['body', 'salt_pct'],
              'msg': 'Input should be less than 100',
            },
          ],
        }),
      );

      expect(
        message,
        'Some information is invalid. Check your entries and try again.',
      );
      expect(message, isNot(contains('salt_pct')));
    });

    test('rejects technical server detail', () {
      final technicalDetails = [
        'DioException [bad response]: status code 500',
        'Traceback (most recent call last):',
        'sqlalchemy.exc.IntegrityError: duplicate key',
        r'[SQL: UPDATE formulas SET code=$1]',
        '<html><body>Proxy error</body></html>',
      ];

      for (final detail in technicalDetails) {
        final message = userFacingError(
          _responseError(409, {'detail': detail}),
        );
        expect(
          message,
          'The request conflicts with existing information. Update it and try again.',
        );
        expect(message, isNot(contains(detail)));
      }
    });

    test('maps authentication failure', () {
      expect(
        userFacingError(_responseError(401, {'detail': 'raw'})),
        'Your session has expired. Please sign in again.',
      );
    });

    test('propagates safe actionable detail for expected 403 responses', () {
      expect(
        userFacingError(
          _responseError(403, {
            'detail': 'Only the current owner can transfer.',
          }),
        ),
        'Only the current owner can transfer.',
      );
    });

    test('maps missing resource', () {
      expect(
        userFacingError(_responseError(404, {'detail': 'Formula not found'})),
        'The requested item is no longer available. Please refresh and try again.',
      );
    });

    test('maps rate limit', () {
      expect(
        userFacingError(_responseError(429, {'detail': 'raw'})),
        'Too many attempts. Please wait a moment and try again.',
      );
    });

    test('preserves safe structured server guidance for 503 responses', () {
      final message = userFacingError(
        _responseError(503, {
          'detail': {
            'code': 'microscope_upload_storage_unavailable',
            'message':
                'Storage verification is temporarily unavailable. Completed parts are retained.',
            'retryable': true,
          },
        }),
      );

      expect(
        message,
        'Storage verification is temporarily unavailable. Completed parts are retained.',
      );
    });

    test('maps server and malformed response failures', () {
      expect(
        userFacingError(_responseError(500, '<html>internal failure</html>')),
        'The service could not complete your request. Please try again in a moment.',
      );
    });

    test('maps timeout failures', () {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        expect(
          userFacingError(_transportError(type)),
          'The request took too long. Please try again.',
        );
      }
    });

    test('maps connection failures', () {
      expect(
        userFacingError(_transportError(DioExceptionType.connectionError)),
        'Unable to reach the service. Check your internet connection and try again.',
      );
    });

    test('maps cancellation', () {
      expect(
        userFacingError(_transportError(DioExceptionType.cancel)),
        'The action was cancelled.',
      );
    });

    test('maps unknown exceptions without serializing them', () {
      final message = userFacingError(StateError('database password leaked'));

      expect(message, 'Something went wrong. Please try again.');
      expect(message, isNot(contains('database password leaked')));
      expect(message, isNot(contains('Bad state')));
    });

    test('adds concise action context', () {
      final message = userFacingError(
        _responseError(409, {
          'detail': 'Choose different formula selections and try again.',
        }),
        action: 'save formula',
      );

      expect(
        message,
        'Could not save formula. Choose different formula selections and try again.',
      );
    });
  });
}

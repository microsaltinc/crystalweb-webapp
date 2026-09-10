import 'package:crystalapp/core/api/api_error.dart';
import 'package:crystalapp/core/api/user_facing_error.dart';
import 'package:crystalapp/features/batches/models/campaign_locking.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

DioException responseError(dynamic data) {
  final request = RequestOptions(path: '/lock');
  return DioException(
    requestOptions: request,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: request, statusCode: 409, data: data),
  );
}

void main() {
  test('readiness decodes blockers and malformed collections safely', () {
    final readiness = CampaignLockReadiness.fromJson({
      'ready': false,
      'content_revision': 4,
      'evaluated_at': 'bad',
      'blockers': [
        {
          'category': 'image_review_incomplete',
          'message': 'Review images',
          'count': 2,
          'images': [
            {'id': 'i', 'bag_number': 1},
          ],
          'sublots': ['A', 2],
        },
      ],
    });
    expect(readiness.ready, isFalse);
    expect(readiness.blockers.single.count, 2);
    expect(readiness.blockers.single.images.single.id, 'i');
    expect(readiness.blockers.single.sublots, ['A']);
    expect(readiness.evaluatedAt, isNull);
  });

  test('transition and conflict projections decode', () {
    expect(
      CampaignTransition.fromJson({
        'batch_id': 'b',
        'edit_state': 'locked',
        'edit_state_version': 2,
        'content_revision': 3,
        'changed': true,
      }).editState,
      CampaignEditState.locked,
    );
    final conflict = RegistrationConflict.fromJson({
      'id': 'c',
      'batch_id': 'b',
      'object': {'bucket': 'bucket', 'key': 'key'},
      'occurrence_count': 3,
      'can_retry': true,
    });
    expect(conflict.object.key, 'key');
    expect(conflict.canRetry, isTrue);
  });

  test('structured errors expose stable code and only safe message', () {
    final dio = responseError({
      'detail': {
        'code': 'campaign_locked',
        'message': 'Unlock this campaign.',
        'batch_id': 'b',
      },
    });
    final parsed = ApiError.tryParse(dio)!;
    expect(parsed.code, 'campaign_locked');
    expect(userFacingError(dio), 'Unlock this campaign.');
    expect(parsed.toString(), isNot(contains('/lock')));
  });

  test('malformed structured errors use safe response fallback', () {
    final dio = responseError({
      'detail': {
        'code': 'campaign_locked',
        'message': '<html>DioException RequestOptions</html>',
      },
    });
    expect(ApiError.tryParse(dio), isNull);
    final message = userFacingError(dio);
    expect(message, isNot(contains('Dio')));
    expect(message, isNot(contains('/lock')));
  });

  test('retry projection decodes safe typed values', () {
    final retry = RegistrationConflictRetry.fromJson({
      'conflict_id': 'c',
      'resolved': true,
      'resolved_at': 'bad',
      'registration_action': 'created',
      'content_revision': 9,
    });
    expect(retry.registrationAction, 'created');
    expect(retry.resolvedAt, isNull);
  });

  test('legacy HTML, 5xx, and network failures never leak diagnostics', () {
    final request = RequestOptions(
      path: '/private',
      baseUrl: 'https://secret.invalid',
    );
    final failures = <DioException>[
      DioException(
        requestOptions: request,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: request,
          statusCode: 400,
          data: {'detail': '<html>DioException RequestOptions</html>'},
        ),
      ),
      DioException(
        requestOptions: request,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: request,
          statusCode: 503,
          data: '<html>upstream private diagnostics</html>',
        ),
      ),
      DioException(
        requestOptions: request,
        type: DioExceptionType.connectionError,
        error: 'socket secret.invalid',
      ),
    ];
    for (final failure in failures) {
      final message = userFacingError(failure);
      expect(message, isNot(contains('Dio')));
      expect(message, isNot(contains('secret.invalid')));
      expect(message.toLowerCase(), isNot(contains('<html')));
      expect(message, isNot(contains('/private')));
    }
  });
}

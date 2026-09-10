import 'package:flutter_test/flutter_test.dart';

import 'package:crystalapp/core/auth/auth_callback_parameters.dart';

void main() {
  group('authCallbackParameters', () {
    test('reads the browser token from the URL fragment', () {
      final values = authCallbackParameters(
        Uri.parse('/auth-callback#token=jwt-value&role=user&expires_in=60'),
      );

      expect(values['token'], 'jwt-value');
      expect(values['role'], 'user');
      expect(values['expires_in'], '60');
    });

    test('keeps legacy query callback compatibility', () {
      final values = authCallbackParameters(
        Uri.parse('/auth-callback?token=legacy-jwt&role=user'),
      );

      expect(values['token'], 'legacy-jwt');
    });

    test('fragment takes precedence over a stale query token', () {
      final values = authCallbackParameters(
        Uri.parse('/auth-callback?token=old#token=new'),
      );

      expect(values['token'], 'new');
    });

    test('malformed fragment returns no token', () {
      final values = authCallbackParameters(
        Uri.parse('/auth-callback#not-a-query'),
      );

      expect(values['token'], isNull);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:crystalapp/core/api/api_client.dart';
import 'package:crystalapp/core/config/app_config.dart';
import 'package:crystalapp/core/config/env.dart';

void main() {
  group('AppConfig', () {
    test('uses the configured API URL and removes trailing slashes', () {
      final config = AppConfig(
        env: AppEnv.local,
        apiUrl: 'https://api.example.com///',
      );
      expect(config.apiBaseUrl, 'https://api.example.com');
      expect(
        ApiClient(baseUrl: config.apiBaseUrl).dio.options.baseUrl,
        config.apiBaseUrl,
      );
    });

    test('blank API URL fails closed instead of using production', () {
      final config = AppConfig(env: AppEnv.local, apiUrl: '   ');

      expect(
        () => config.apiBaseUrl,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('API_URL'),
          ),
        ),
      );
    });

    test('missing production API URL also fails closed', () {
      final config = AppConfig(env: AppEnv.production, apiUrl: '');

      expect(() => config.apiBaseUrl, throwsStateError);
    });

    test('production requires an HTTPS API URL', () {
      final config = AppConfig(
        env: AppEnv.production,
        apiUrl: 'http://api.example.com',
      );

      expect(() => config.apiBaseUrl, throwsStateError);
    });

    test('local auth requires local environment and an explicit flag', () {
      expect(
        AppConfig(
          env: AppEnv.local,
          apiUrl: 'http://localhost:8080',
          localAuthEnabled: true,
        ).localAuthEnabled,
        isTrue,
      );
      expect(
        AppConfig(
          env: AppEnv.local,
          apiUrl: 'http://localhost:8080',
          localAuthEnabled: false,
        ).localAuthEnabled,
        isFalse,
      );
    });

    test('production rejects local auth even when explicitly enabled', () {
      final config = AppConfig(
        env: AppEnv.production,
        apiUrl: 'https://api.example.com',
        localAuthEnabled: true,
      );

      expect(() => config.localAuthEnabled, throwsStateError);
    });
  });

  group('AppEnv', () {
    test('fromString parses valid env', () {
      expect(AppEnv.fromString('local'), AppEnv.local);
      expect(AppEnv.fromString('production'), AppEnv.production);
    });

    test('fromString rejects unknown values instead of assuming local', () {
      expect(() => AppEnv.fromString('unknown'), throwsArgumentError);
    });
  });
}

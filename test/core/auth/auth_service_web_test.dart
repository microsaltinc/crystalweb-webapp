import 'dart:convert';
import 'dart:typed_data';

import 'package:crystalapp/core/auth/auth_service.dart';
import 'package:crystalapp/core/config/app_config.dart';
import 'package:crystalapp/core/config/env.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockStorage extends Mock implements FlutterSecureStorage {}

class _LocalBootstrapAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final data = options.path.endsWith('/api/v1/auth/local/login')
        ? {
            'access_token': 'local-jwt',
            'token_type': 'bearer',
            'role': 'user',
            'expires_in': 3600,
          }
        : {
            'id': 'local-user-1',
            'email': 'local@microsaltinc.com',
            'name': 'Local CrystalApp User',
            'role': 'user',
            'groups': <String>[],
            'created_at': '2026-08-31T00:00:00Z',
          };
    return ResponseBody.fromString(
      jsonEncode(data),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _MeAdapter implements HttpClientAdapter {
  _MeAdapter({this.statusCode = 200});

  final int statusCode;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(
        statusCode >= 400
            ? {'detail': 'expired'}
            : {
                'id': 'user-1',
                'email': 'user@microsaltinc.com',
                'name': 'Web User',
                'role': 'user',
                'groups': <String>[],
                'created_at': '2026-08-18T00:00:00Z',
              },
      ),
      statusCode,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

AuthService _service(_MockStorage storage, _MeAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com'))
    ..httpClientAdapter = adapter;
  return AuthService(
    dio: dio,
    config: AppConfig(env: AppEnv.local),
    storage: storage,
  );
}

void main() {
  test('Web SAML login sends an absolute local callback separately', () {
    final url = samlLoginUrl(
      apiBaseUrl: 'https://api.example.com',
      currentUri: Uri.parse('http://localhost:3000/login'),
    );

    expect(url.path, '/api/v1/auth/saml/login');
    expect(
      url.queryParameters['web_return_url'],
      'http://localhost:3000/auth-callback',
    );
    expect(url.queryParameters['redirect'], isNull);
  });

  late _MockStorage storage;

  setUp(() {
    storage = _MockStorage();
    when(
      () => storage.read(key: any(named: 'key')),
    ).thenAnswer((_) async => null);
    when(
      () => storage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((_) async {});
    when(() => storage.delete(key: any(named: 'key'))).thenAnswer((_) async {});
  });

  test(
    'local bootstrap signs in automatically only when explicitly enabled',
    () async {
      final adapter = _LocalBootstrapAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:8080'))
        ..httpClientAdapter = adapter;
      final service = AuthService(
        dio: dio,
        config: AppConfig(
          env: AppEnv.local,
          apiUrl: 'http://localhost:8080',
          localAuthEnabled: true,
        ),
        storage: storage,
      );

      final result = await service.restoreSession();

      expect(result.isSessionOnly, isTrue);
      expect(result.user?.email, 'local@microsaltinc.com');
      expect(adapter.requests.map((request) => request.path), [
        '/api/v1/auth/local/login',
        '/api/v1/auth/me',
      ]);
      verify(
        () => storage.write(key: 'jwt_token', value: 'local-jwt'),
      ).called(1);
      verify(
        () => storage.write(key: 'jwt_sso_token', value: 'local-jwt'),
      ).called(1);
    },
  );

  test('SAML completion persists the active and original SSO token', () async {
    final adapter = _MeAdapter();
    final result = await _service(storage, adapter).completeSamlAuth('sso-jwt');

    expect(result.user?.email, 'user@microsaltinc.com');
    verify(() => storage.write(key: 'jwt_token', value: 'sso-jwt')).called(1);
    verify(
      () => storage.write(key: 'jwt_sso_token', value: 'sso-jwt'),
    ).called(1);
    expect(adapter.requests.single.headers['Authorization'], 'Bearer sso-jwt');
  });

  test(
    'reload restores the original SSO token instead of delegated token',
    () async {
      when(
        () => storage.read(key: 'jwt_sso_token'),
      ).thenAnswer((_) async => 'sso-jwt');
      when(
        () => storage.read(key: 'jwt_token'),
      ).thenAnswer((_) async => 'operator-jwt');
      final adapter = _MeAdapter();

      final result = await _service(storage, adapter).restoreSession();

      expect(result.isSessionOnly, isTrue);
      expect(result.token, 'sso-jwt');
      expect(
        adapter.requests.single.headers['Authorization'],
        'Bearer sso-jwt',
      );
    },
  );

  test(
    'expired stored SSO session is cleared and becomes unauthenticated',
    () async {
      when(
        () => storage.read(key: 'jwt_sso_token'),
      ).thenAnswer((_) async => 'expired-jwt');
      final result = await _service(
        storage,
        _MeAdapter(statusCode: 401),
      ).restoreSession();

      expect(result.token, isNull);
      verify(() => storage.delete(key: 'jwt_token')).called(1);
      verify(() => storage.delete(key: 'jwt_sso_token')).called(1);
    },
  );
}

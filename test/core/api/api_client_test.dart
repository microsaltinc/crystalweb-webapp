import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crystalapp/core/api/api_client.dart';
import 'package:crystalapp/core/api/auth_interceptor.dart';

class MockDio extends Mock implements Dio {}

void main() {
  group('ApiClient', () {
    test('creates Dio instance with base URL', () {
      final client = ApiClient(baseUrl: 'https://api.example.com');
      expect(client.dio.options.baseUrl, 'https://api.example.com');
    });

    test('sets JSON content type', () {
      final client = ApiClient(baseUrl: 'https://api.example.com');
      expect(
        client.dio.options.headers['Content-Type'],
        'application/json',
      );
    });

    test('sets timeout values', () {
      final client = ApiClient(baseUrl: 'https://api.example.com');
      expect(
        client.dio.options.connectTimeout,
        const Duration(seconds: 10),
      );
      expect(
        client.dio.options.receiveTimeout,
        const Duration(seconds: 30),
      );
    });
  });

  group('AuthInterceptor', () {
    test('adds Authorization header when token exists', () async {
      final interceptor = AuthInterceptor(
        getToken: () async => 'test-jwt-token',
      );
      final options = RequestOptions(path: '/test');
      final handler = MockRequestInterceptorHandler();

      await interceptor.onRequest(options, handler);

      expect(options.headers['Authorization'], 'Bearer test-jwt-token');
    });

    test('skips header when no token', () async {
      final interceptor = AuthInterceptor(
        getToken: () async => null,
      );
      final options = RequestOptions(path: '/test');
      final handler = MockRequestInterceptorHandler();

      await interceptor.onRequest(options, handler);

      expect(options.headers.containsKey('Authorization'), false);
    });
  });
}

class MockRequestInterceptorHandler extends Mock
    implements RequestInterceptorHandler {
  @override
  void next(RequestOptions requestOptions) {}
}

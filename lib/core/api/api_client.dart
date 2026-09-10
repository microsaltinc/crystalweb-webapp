import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
import '../config/app_config.dart';
import 'api_error.dart';
import 'auth_interceptor.dart';

class ApiClient {
  ApiClient({
    required String baseUrl,
    Future<String?> Function()? getToken,
    void Function()? onSessionExpired,
  }) : dio = Dio(
         BaseOptions(
           baseUrl: baseUrl,
           connectTimeout: const Duration(seconds: 10),
           receiveTimeout: const Duration(seconds: 30),
           headers: {'Content-Type': 'application/json'},
         ),
       ) {
    dio.interceptors.add(ApiErrorInterceptor());
    if (getToken != null) {
      dio.interceptors.add(
        AuthInterceptor(getToken: getToken, onSessionExpired: onSessionExpired),
      );
    }
  }

  /// Constructor for injecting a mock Dio instance in tests.
  ApiClient.withDio(this.dio);

  final Dio dio;
}

/// Provides an ApiClient wired to config and auth state.
final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(appConfigProvider);
  final authState = ref.watch(authStateProvider);
  return ApiClient(
    baseUrl: config.apiBaseUrl,
    getToken: () async => authState.token,
    onSessionExpired: () {
      // Clear auth state — GoRouter redirect will send user to login.
      ref.read(authStateProvider.notifier).setUnauthenticated();
    },
  );
});

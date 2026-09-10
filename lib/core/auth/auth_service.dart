import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import 'auth_state.dart';

Uri samlLoginUrl({required String apiBaseUrl, required Uri currentUri}) {
  final endpoint = Uri.parse('$apiBaseUrl/api/v1/auth/saml/login');
  return endpoint.replace(
    queryParameters: {
      'web_return_url': currentUri.resolve('/auth-callback').toString(),
    },
  );
}

/// Web authentication using Google Workspace SAML and optional local bootstrap.
///
/// The backend returns the JWT in the `/auth-callback` URL fragment. The app
/// captures and removes that fragment before storing the SSO token and loading
/// the authenticated profile.
class AuthService {
  AuthService({
    required Dio dio,
    required AppConfig config,
    bool? localAuthEnabled,
    FlutterSecureStorage? storage,
  }) : _dio = dio,
       _config = config,
       _localAuthEnabled = localAuthEnabled ?? config.localAuthEnabled,
       _storage = storage ?? const FlutterSecureStorage();

  final Dio _dio;
  final AppConfig _config;
  final bool _localAuthEnabled;
  final FlutterSecureStorage _storage;

  static const _tokenKey = 'jwt_token';
  static const _ssoTokenKey = 'jwt_sso_token';

  /// Initiate SAML SSO with a same-window browser redirect.
  Future<AuthState> signInWithSaml() async {
    if (_localAuthEnabled) {
      return _signInWithLocalBootstrap();
    }

    final loginUrl = samlLoginUrl(
      apiBaseUrl: _config.apiBaseUrl,
      currentUri: Uri.base,
    );
    return _samlWebFlow(loginUrl);
  }

  /// SAML flow for web — redirect in same window, handle callback
  Future<AuthState> _samlWebFlow(Uri loginUrl) async {
    // For web, the SAML ACS returns an HTML page that posts a message
    // or redirects to the app. We'll use the redirect approach.
    final launched = await launchUrl(loginUrl, webOnlyWindowName: '_self');
    if (!launched) return const AuthState.unauthenticated();

    // Keep the current page in its loading state until same-window navigation
    // replaces it. The new page captures the fragment token before routing.
    return Completer<AuthState>().future;
  }

  /// Complete SAML auth from a token received in the browser callback URL.
  /// This is called after the app receives the callback.
  Future<AuthState> completeSamlAuth(String token) async {
    await _storeSsoToken(token);
    return _fetchUserProfile(token);
  }

  /// Delegate auth to an operator via PIN verification.
  /// [currentToken] is the SSO JWT to authenticate the delegation request.
  Future<AuthState> delegateToOperator({
    required String operatorId,
    required String pin,
    String? currentToken,
  }) async {
    final response = await _dio.post(
      '/api/v1/auth/delegate',
      data: {'operator_id': operatorId, 'pin': pin},
      options: currentToken != null
          ? Options(headers: {'Authorization': 'Bearer $currentToken'})
          : null,
    );

    final jwt = response.data['access_token'] as String;
    final role = response.data['role'] as String?;
    await _storage.write(key: _tokenKey, value: jwt);

    return _fetchUserProfile(jwt, roleOverride: role);
  }

  /// Restore the original SSO authority before routing. Delegated operator
  /// context deliberately requires operator selection/PIN again after reload.
  Future<AuthState> restoreSession() async {
    try {
      final storedSsoToken = await _storage
          .read(key: _ssoTokenKey)
          .timeout(const Duration(seconds: 5));
      final token =
          storedSsoToken ??
          await _storage
              .read(key: _tokenKey)
              .timeout(const Duration(seconds: 5));
      if (token == null) {
        if (_localAuthEnabled) {
          return _signInWithLocalBootstrap();
        }
        return const AuthState.unauthenticated();
      }

      final restored = await _fetchUserProfile(token);
      if (restored.user?.role == UserRole.operator) {
        await signOut();
        return const AuthState.unauthenticated();
      }
      return restored;
    } on TimeoutException {
      return const AuthState.unauthenticated();
    } on DioException {
      await signOut();
      if (_localAuthEnabled) {
        try {
          return await _signInWithLocalBootstrap();
        } on DioException {
          return const AuthState.unauthenticated();
        }
      }
      return const AuthState.unauthenticated();
    }
  }

  Future<AuthState> _signInWithLocalBootstrap() async {
    final response = await _dio.post('/api/v1/auth/local/login');
    final jwt = response.data['access_token'] as String;
    final role = response.data['role'] as String?;
    if (role != 'user') {
      throw StateError('Local bootstrap must return a user token.');
    }
    await _storeSsoToken(jwt);
    return _fetchUserProfile(jwt);
  }

  Future<void> signOut() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _ssoTokenKey);
  }

  Future<void> _storeSsoToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _ssoTokenKey, value: token);
  }

  Future<String?> getStoredToken() async {
    return _storage.read(key: _tokenKey);
  }

  /// Fetch user profile from /api/v1/auth/me using the given token.
  Future<AuthState> _fetchUserProfile(
    String token, {
    String? roleOverride,
  }) async {
    final meResponse = await _dio.get(
      '/api/v1/auth/me',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );

    final userData = meResponse.data as Map<String, dynamic>;
    final roleStr = roleOverride ?? userData['role'] as String? ?? 'user';
    final rawGroups = userData['groups'] as List<dynamic>? ?? [];

    return AuthState.sessionOnly(
      token: token,
      user: AuthUser(
        id: userData['id'] as String,
        email: userData['email'] as String? ?? '',
        name: userData['name'] as String? ?? '',
        role: roleStr == 'operator' ? UserRole.operator : UserRole.user,
        groups: rawGroups.map((g) => g.toString()).toList(),
      ),
    );
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'env.dart';

class AppConfig {
  AppConfig({required this.env, String? apiUrl, bool? localAuthEnabled})
    : _apiUrl = apiUrl,
      _localAuthEnabled = localAuthEnabled;

  static const _definedApiUrl = String.fromEnvironment('API_URL');
  static const _definedLocalAuthEnabled = bool.fromEnvironment(
    'LOCAL_AUTH_ENABLED',
  );

  final AppEnv env;
  final String? _apiUrl;
  final bool? _localAuthEnabled;

  /// The API endpoint must be supplied explicitly for every environment.
  /// This intentionally has no production fallback: a local build with a
  /// missing define must never send operator traffic to lab.microsalt.in.
  String get apiBaseUrl {
    final configured = (_apiUrl ?? _definedApiUrl).trim();
    if (configured.isEmpty) {
      throw StateError(
        'API_URL is required; refusing to select a default API endpoint.',
      );
    }

    final uri = Uri.tryParse(configured);
    final isHttp = uri?.scheme == 'http' || uri?.scheme == 'https';
    if (uri == null ||
        !isHttp ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw StateError('API_URL must be an absolute HTTP(S) URL.');
    }
    if (env == AppEnv.production && uri.scheme != 'https') {
      throw StateError('Production API_URL must use HTTPS.');
    }

    return configured.replaceFirst(RegExp(r'/+$'), '');
  }

  /// Local bootstrap login has two independent gates: the local environment
  /// and an explicit compile-time enable flag.
  bool get localAuthEnabled {
    final enabled = _localAuthEnabled ?? _definedLocalAuthEnabled;
    if (enabled && env != AppEnv.local) {
      throw StateError('LOCAL_AUTH_ENABLED is only valid when APP_ENV=local.');
    }
    return enabled;
  }
}

final appConfigProvider = Provider<AppConfig>((ref) {
  const envStr = String.fromEnvironment('APP_ENV', defaultValue: 'production');
  return AppConfig(env: AppEnv.fromString(envStr));
});

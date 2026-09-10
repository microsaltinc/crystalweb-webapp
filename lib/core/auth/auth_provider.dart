import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/operators/models/operator.dart';
import '../config/app_config.dart';
import 'auth_service.dart';
import 'auth_state.dart';

/// Global auth state -- starts unauthenticated.
/// Real screens call notifier methods to update.
final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState.unauthenticated());

  /// Set session-only state (token + user, no operator yet).
  /// Used after SSO login, before operator selection.
  void setSessionOnly({required String token, required AuthUser user}) {
    state = AuthState.sessionOnly(token: token, user: user);
  }

  /// Set fully authenticated state with an active operator.
  void setAuthenticated({
    required String token,
    required AuthUser user,
    required Operator activeOperator,
  }) {
    state = AuthState.withOperator(
      token: token,
      userToken: state.userToken ?? token,
      user: user,
      operator: activeOperator,
    );
  }

  /// Set the active operator on the current session.
  /// Requires a session-only state (token + user already present).
  void setActiveOperator(Operator operator) {
    if (state.token != null && state.user != null) {
      state = AuthState.withOperator(
        token: state.token!,
        userToken: state.userToken ?? state.token!,
        user: state.user!,
        operator: operator,
      );
    }
  }

  void restore(AuthState restored) {
    state = restored;
  }

  void setUnauthenticated() {
    state = const AuthState.unauthenticated();
  }
}

/// Provides AuthService wired to the current config.
final authServiceProvider = Provider<AuthService>((ref) {
  final config = ref.watch(appConfigProvider);
  return AuthService(
    dio: Dio(
      BaseOptions(
        baseUrl: config.apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
      ),
    ),
    config: config,
    localAuthEnabled: config.localAuthEnabled,
  );
});

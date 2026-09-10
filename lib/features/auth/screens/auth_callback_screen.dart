import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/user_facing_error.dart';
import '../../../core/auth/auth_callback_url.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/routing/route_names.dart';

/// Handles the SAML SSO callback — receives the JWT token from the
/// backend redirect to the browser callback URL and completes auth.
class AuthCallbackScreen extends ConsumerStatefulWidget {
  const AuthCallbackScreen({super.key, this.token});

  final String? token;

  @override
  ConsumerState<AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends ConsumerState<AuthCallbackScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.token?.isNotEmpty ?? false) clearAuthCallbackUrl();
    _processToken();
  }

  Future<void> _processToken() async {
    final token = widget.token;

    if (token == null || token.isEmpty) {
      setState(() => _error = 'No authentication token received');
      _redirectToLogin();
      return;
    }

    try {
      final authService = ref.read(authServiceProvider);
      final result = await authService.completeSamlAuth(token);

      if (!mounted) return;

      if (result.token != null && result.user != null) {
        ref
            .read(authStateProvider.notifier)
            .setSessionOnly(token: result.token!, user: result.user!);
        context.go(RouteNames.operatorSelect);
      } else {
        setState(() => _error = 'Authentication failed');
        _redirectToLogin();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userFacingError(e, action: 'sign in'));
      _redirectToLogin();
    }
  }

  void _redirectToLogin() {
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) context.go(RouteNames.login);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_error == null) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(
                'Completing sign in...',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ] else ...[
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Redirecting to login...',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

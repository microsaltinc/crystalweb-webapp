import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/user_facing_error.dart';
import '../../../core/auth/auth_provider.dart';

/// Duration after which a "still waiting" hint is shown during SSO login.
const _kWaitingHintDelay = Duration(seconds: 10);

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _isLoading = false;
  bool _showWaitingHint = false;
  String? _error;
  Timer? _waitingHintTimer;

  @override
  void dispose() {
    _waitingHintTimer?.cancel();
    super.dispose();
  }

  void _cancelLogin() {
    _waitingHintTimer?.cancel();
    if (mounted) {
      setState(() {
        _isLoading = false;
        _showWaitingHint = false;
        _error = 'Sign in cancelled';
      });
    }
  }

  void _startWaitingHintTimer() {
    _waitingHintTimer?.cancel();
    _waitingHintTimer = Timer(_kWaitingHintDelay, () {
      if (mounted && _isLoading) {
        setState(() => _showWaitingHint = true);
      }
    });
  }

  Future<void> _handleSamlLogin() async {
    setState(() {
      _isLoading = true;
      _showWaitingHint = false;
      _error = null;
    });
    _startWaitingHintTimer();

    try {
      final authService = ref.read(authServiceProvider);
      final result = await authService.signInWithSaml();

      if (!mounted) return;

      if (result.token != null && result.user != null) {
        ref
            .read(authStateProvider.notifier)
            .setSessionOnly(token: result.token!, user: result.user!);
      } else {
        setState(() => _error = 'Sign in cancelled or timed out');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = userFacingError(e, action: 'sign in'));
    } finally {
      _waitingHintTimer?.cancel();
      if (mounted) {
        setState(() {
          _isLoading = false;
          _showWaitingHint = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  'assets/icons/app_icon.png',
                  width: 96,
                  height: 96,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'CrystalApp',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Microsalt Crystal Analysis',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 48),
              if (_isLoading) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                if (_showWaitingHint) ...[
                  Text(
                    'Still waiting for browser login...',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.orange.shade700,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextButton(
                  onPressed: _cancelLogin,
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: _showWaitingHint ? 16 : 14,
                      fontWeight: _showWaitingHint
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ] else
                _SamlSignInButton(onPressed: _handleSamlLogin),
              const SizedBox(height: 16),
              Text(
                'Sign in with your Microsalt Google account',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SamlSignInButton extends StatelessWidget {
  const _SamlSignInButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.lock_open),
      label: const Text('Sign in with Microsalt SSO'),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(280, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

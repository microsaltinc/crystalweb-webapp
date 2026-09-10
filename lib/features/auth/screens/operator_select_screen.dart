import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/user_facing_error.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/routing/route_names.dart';
import '../../operators/models/operator.dart';
import '../../operators/providers/operator_provider.dart';

/// After SSO login, shows the list of operators for the current Microsalt user.
/// The user picks an operator, then enters their PIN.
/// If no operator exists for the logged-in user, one is auto-created.
class OperatorSelectScreen extends ConsumerStatefulWidget {
  const OperatorSelectScreen({super.key});

  @override
  ConsumerState<OperatorSelectScreen> createState() =>
      _OperatorSelectScreenState();
}

class _OperatorSelectScreenState extends ConsumerState<OperatorSelectScreen> {
  bool _autoCreating = false;
  bool _didAutoCreate = false;
  String? _autoCreateError;

  /// After SSO login, auto-create an operator for the logged-in user
  /// if none exists with their email.
  Future<void> _autoCreateOperator() async {
    if (_autoCreating) return;
    setState(() {
      _autoCreating = true;
      _autoCreateError = null;
    });

    try {
      final authState = ref.read(authStateProvider);
      final user = authState.user;
      if (user == null) return;

      final client = ref.read(apiClientProvider);
      // Try with full fields first; fall back to name-only if backend
      // hasn't been updated with email/managed_by columns yet.
      try {
        await client.dio.post(
          '/api/v1/operators',
          data: {
            'name': user.name,
            'email': user.email,
            'managed_by': user.email,
          },
        );
      } catch (_) {
        await client.dio.post('/api/v1/operators', data: {'name': user.name});
      }

      // Refresh the operator list
      _didAutoCreate = true;
      ref.invalidate(operatorListProvider);
    } catch (e) {
      _didAutoCreate = true;
      if (mounted) {
        setState(
          () =>
              _autoCreateError = userFacingError(e, action: 'create operator'),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _autoCreating = false);
      }
    }
  }

  Future<void> _handleSignOut() async {
    final authService = ref.read(authServiceProvider);
    await authService.signOut();
    ref.read(authStateProvider.notifier).setUnauthenticated();
  }

  void _handleOperatorTap(Operator operator) {
    final authState = ref.read(authStateProvider);
    final userName = authState.user?.name ?? '';
    context.go(
      '${RouteNames.operatorPin}/${operator.id}'
      '?name=${Uri.encodeComponent(operator.name)}'
      '&managedByName=${Uri.encodeComponent(userName)}'
      '&hasPin=${operator.hasPin}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final user = authState.user;
    final operatorsAsync = ref.watch(operatorListProvider);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Select Operator',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              if (user != null)
                Text(
                  'Signed in as ${user.name}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: Colors.grey),
                ),
              const SizedBox(height: 32),
              if (_autoCreating)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              operatorsAsync.when(
                data: (operators) {
                  dev.log(
                    'Operators loaded: ${operators.length}',
                    name: 'OperatorSelect',
                  );

                  // Auto-create only if the list is empty (backend already
                  // filters by created_by_user_id, so empty means this SSO
                  // user has no operators yet).
                  if (operators.isEmpty && !_autoCreating && !_didAutoCreate) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _autoCreateOperator();
                    });
                    return const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('Setting up your operator account...'),
                    );
                  }

                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: Column(
                      children: operators.map((op) {
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(child: Text(op.initials)),
                            title: Text(op.name),
                            subtitle: Text(op.email),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _handleOperatorTap(op),
                          ),
                        );
                      }).toList(),
                    ),
                  );
                },
                loading: () => const CircularProgressIndicator(),
                error: (error, _) => Text(
                  userFacingError(error, action: 'load operators'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              if (_autoCreateError != null) ...[
                const SizedBox(height: 16),
                Text(
                  _autoCreateError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 32),
              TextButton(
                onPressed: _handleSignOut,
                child: const Text('Sign Out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

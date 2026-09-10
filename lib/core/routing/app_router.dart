import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/images/screens/image_detail_screen.dart';
import '../../features/auth/screens/auth_callback_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/operator_pin_screen.dart';
import '../../features/auth/screens/operator_select_screen.dart';
import '../../features/batches/screens/batch_detail_screen.dart';
import '../../features/batches/screens/batch_list_screen.dart';
import '../../features/formulas/screens/formula_editor_screen.dart';
import '../../features/formulas/screens/formula_list_screen.dart';
import '../../features/operators/screens/operator_form_screen.dart';
import '../../features/operators/screens/operator_list_screen.dart';
import '../../features/rnd/screens/rnd_batch_list_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/shell/screens/app_shell.dart';
import '../auth/auth_callback_parameters.dart';
import '../auth/auth_provider.dart';
import 'route_names.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: RouteNames.batches,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final hasSession = authState.token != null && authState.user != null;
      final hasOperator = authState.activeOperator != null;
      final isFullyAuthed = hasSession && hasOperator;

      final isLoginRoute = location == RouteNames.login;
      final isAuthCallback = location == RouteNames.authCallback;
      final isOperatorSelect = location == RouteNames.operatorSelect;
      final isOperatorPin =
          location.startsWith(RouteNames.operatorPin) ||
          location.contains('/pin');

      // Always allow auth callback through
      if (isAuthCallback) return null;

      // No session at all → login
      if (!hasSession) {
        return isLoginRoute ? null : RouteNames.login;
      }

      // Has session but no operator → operator select
      if (hasSession && !hasOperator) {
        if (isOperatorSelect || isOperatorPin) return null;
        if (isLoginRoute) return RouteNames.operatorSelect;
        return RouteNames.operatorSelect;
      }

      // Fully authenticated → redirect away from login/operator select
      if (isFullyAuthed) {
        if (isLoginRoute || isOperatorSelect) {
          final roleNames = authState.activeOperator?.roleNames ?? [];
          final isResearcherOnly =
              roleNames.contains('researcher') &&
              !roleNames.contains('production');
          return isResearcherOnly ? RouteNames.rnd : RouteNames.batches;
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: RouteNames.login,
        builder: (context, state) => const LoginScreen(),
      ),
      // SAML SSO callback — receives token from backend redirect
      GoRoute(
        path: RouteNames.authCallback,
        builder: (context, state) {
          final values = authCallbackParameters(state.uri);
          return AuthCallbackScreen(token: values['token']);
        },
      ),
      // Operator selection screen — shown after SSO login
      GoRoute(
        path: RouteNames.operatorSelect,
        builder: (context, state) => const OperatorSelectScreen(),
      ),
      // Operator PIN screen — outside shell for auth flow (no sidebar)
      GoRoute(
        path: '${RouteNames.operatorPin}/:operatorId',
        builder: (context, state) {
          final opId = state.pathParameters['operatorId']!;
          final opName = state.uri.queryParameters['name'] ?? 'Operator';
          final managedByName = state.uri.queryParameters['managedByName'];
          final hasPin = state.uri.queryParameters['hasPin'] != 'false';
          return OperatorPinScreen(
            operatorId: opId,
            operatorName: opName,
            managedByName: managedByName,
            hasPin: hasPin,
          );
        },
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: RouteNames.batches,
            builder: (context, state) => const BatchListScreen(),
            routes: [
              GoRoute(
                path: ':batchId',
                builder: (context, state) {
                  final batchId = state.pathParameters['batchId']!;
                  return BatchDetailScreen(batchId: batchId);
                },
                routes: [
                  GoRoute(
                    path: 'images/:imageId',
                    builder: (context, state) {
                      final batchId = state.pathParameters['batchId']!;
                      final imageId = state.pathParameters['imageId']!;
                      return ImageDetailScreen(
                        batchId: batchId,
                        imageId: imageId,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: RouteNames.rnd,
            builder: (context, state) => const RndBatchListScreen(),
            routes: [
              GoRoute(
                path: ':batchId',
                builder: (context, state) {
                  final batchId = state.pathParameters['batchId']!;
                  return BatchDetailScreen(batchId: batchId, routeRoot: '/rnd');
                },
                routes: [
                  GoRoute(
                    path: 'images/:imageId',
                    builder: (context, state) {
                      final batchId = state.pathParameters['batchId']!;
                      final imageId = state.pathParameters['imageId']!;
                      return ImageDetailScreen(
                        batchId: batchId,
                        imageId: imageId,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/reports',
            redirect: (context, state) => RouteNames.batches,
          ),
          GoRoute(
            path: RouteNames.formulas,
            builder: (context, state) => const FormulaListScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const FormulaEditorScreen(),
              ),
              GoRoute(
                path: ':formulaId/edit',
                builder: (context, state) {
                  final formulaId = state.pathParameters['formulaId']!;
                  return FormulaEditorScreen(formulaId: formulaId);
                },
              ),
            ],
          ),
          GoRoute(
            path: RouteNames.operators,
            builder: (context, state) => const OperatorListScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (context, state) => const OperatorFormScreen(),
              ),
              GoRoute(
                path: ':operatorId/edit',
                builder: (context, state) {
                  final opId = state.pathParameters['operatorId']!;
                  return OperatorFormScreen(operatorId: opId);
                },
              ),
              GoRoute(
                path: ':operatorId/pin',
                builder: (context, state) {
                  final opId = state.pathParameters['operatorId']!;
                  final opName =
                      state.uri.queryParameters['name'] ?? 'Operator';
                  final managedByName =
                      state.uri.queryParameters['managedByName'];
                  final hasPin = state.uri.queryParameters['hasPin'] != 'false';
                  return OperatorPinScreen(
                    operatorId: opId,
                    operatorName: opName,
                    managedByName: managedByName,
                    hasPin: hasPin,
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: RouteNames.settings,
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
});

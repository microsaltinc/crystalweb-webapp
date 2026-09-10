import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crystalapp/core/auth/auth_provider.dart';
import 'package:crystalapp/core/auth/auth_state.dart';
import 'package:crystalapp/core/routing/app_router.dart';
import 'package:crystalapp/core/routing/route_names.dart';
import 'package:crystalapp/features/operators/models/operator.dart';

Operator _makeOperator({bool isResearcher = false}) {
  return Operator(
    id: 'op-1',
    name: 'Test Op',
    active: true,
    hasPin: true,
    createdAt: DateTime(2025, 1, 1),
    email: 'test@microsaltinc.com',
    managedBy: 'admin-1',
    roles: [
      OperatorRole(
        id: isResearcher ? 'researcher-role' : 'production-role',
        name: isResearcher ? 'researcher' : 'production',
      ),
    ],
  );
}

AuthUser _makeUser({UserRole role = UserRole.operator}) {
  return AuthUser(
    id: 'user-1',
    email: 'user@microsaltinc.com',
    name: 'Test User',
    role: role,
  );
}

void main() {
  group('Post-auth redirect landing route', () {
    testWidgets('researcher operator redirects to /rnd', (tester) async {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) {
            final notifier = AuthNotifier();
            notifier.setAuthenticated(
              token: 'tok',
              user: _makeUser(),
              activeOperator: _makeOperator(isResearcher: true),
            );
            return notifier;
          }),
        ],
      );

      final router = container.read(appRouterProvider);
      router.go(RouteNames.operatorSelect);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, RouteNames.rnd);
      container.dispose();
    });

    testWidgets('non-researcher operator redirects to /batches', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) {
            final notifier = AuthNotifier();
            notifier.setAuthenticated(
              token: 'tok',
              user: _makeUser(),
              activeOperator: _makeOperator(isResearcher: false),
            );
            return notifier;
          }),
        ],
      );

      final router = container.read(appRouterProvider);
      router.go(RouteNames.operatorSelect);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, RouteNames.batches);
      container.dispose();
    });

    testWidgets('admin with researcher operator redirects to /rnd', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) {
            final notifier = AuthNotifier();
            notifier.setAuthenticated(
              token: 'tok',
              user: _makeUser(role: UserRole.user),
              activeOperator: _makeOperator(isResearcher: true),
            );
            return notifier;
          }),
        ],
      );

      final router = container.read(appRouterProvider);
      router.go(RouteNames.operatorSelect);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, RouteNames.rnd);
      container.dispose();
    });
  });
}

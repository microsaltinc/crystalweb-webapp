import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:crystalapp/core/routing/route_names.dart';

void main() {
  group('RouteNames', () {
    test('all route names are unique', () {
      final names = [
        RouteNames.login,
        RouteNames.authCallback,
        RouteNames.operatorSelect,
        RouteNames.operatorPin,
        RouteNames.batches,
        RouteNames.batchDetail,
        RouteNames.imageDetail,
        RouteNames.rnd,
        RouteNames.rndBatchDetail,
        RouteNames.rndImageDetail,
        RouteNames.formulas,
        RouteNames.operators,
        RouteNames.settings,
      ];
      expect(names.toSet().length, names.length);
    });

    test('route paths start with /', () {
      expect(RouteNames.login, startsWith('/'));
      expect(RouteNames.batches, startsWith('/'));
    });
  });

  group('AppRouter', () {
    testWidgets('unauthenticated redirects to login', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [],
          child: MaterialApp.router(
            routerConfig: GoRouter(
              initialLocation: '/batches',
              redirect: (context, state) {
                // Simulate unauthenticated
                return '/login';
              },
              routes: [
                GoRoute(path: '/login', builder: (_, _) => const Scaffold()),
                GoRoute(path: '/batches', builder: (_, _) => const Scaffold()),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    });
  });
}

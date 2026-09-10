import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crystalapp/core/auth/auth_state.dart';
import 'package:crystalapp/core/auth/auth_service.dart';
import 'package:crystalapp/features/operators/models/operator.dart';

class MockAuthService extends Mock implements AuthService {}

const _testUser = AuthUser(
  id: '123',
  email: 'user@microsaltinc.com',
  name: 'Test User',
  role: UserRole.user,
);

final _testOperator = Operator(
  id: 'op1',
  name: 'Test User',
  active: true,
  hasPin: true,
  createdAt: DateTime.parse('2026-04-01T00:00:00Z'),
  email: 'user@microsaltinc.com',
  managedBy: 'user@microsaltinc.com',
);

void main() {
  group('AuthState', () {
    test('unauthenticated state', () {
      const state = AuthState.unauthenticated();
      expect(state.isAuthenticated, false);
      expect(state.isSessionOnly, false);
      expect(state.token, isNull);
      expect(state.user, isNull);
      expect(state.activeOperator, isNull);
    });

    test('sessionOnly state has token and user but no operator', () {
      final state = AuthState.sessionOnly(
        token: 'jwt-token',
        user: _testUser,
      );
      expect(state.isAuthenticated, false);
      expect(state.isSessionOnly, true);
      expect(state.token, 'jwt-token');
      expect(state.user?.email, 'user@microsaltinc.com');
      expect(state.activeOperator, isNull);
    });

    test('legacy authenticated() maps to sessionOnly', () {
      final state = AuthState.authenticated(
        token: 'jwt-token',
        user: _testUser,
      );
      expect(state.isAuthenticated, false);
      expect(state.isSessionOnly, true);
      expect(state.token, 'jwt-token');
      expect(state.user?.email, 'user@microsaltinc.com');
    });

    test('withOperator state is fully authenticated', () {
      final state = AuthState.withOperator(
        token: 'jwt-token',
        userToken: 'jwt-token',
        user: _testUser,
        operator: _testOperator,
      );
      expect(state.isAuthenticated, true);
      expect(state.isSessionOnly, false);
      expect(state.token, 'jwt-token');
      expect(state.user?.email, 'user@microsaltinc.com');
      expect(state.activeOperator?.name, 'Test User');
    });

    test('operator state has operator role', () {
      final state = AuthState.authenticated(
        token: 'operator-jwt',
        user: const AuthUser(
          id: '456',
          email: '',
          name: 'Operator A',
          role: UserRole.operator,
        ),
      );
      expect(state.user?.role, UserRole.operator);
      expect(state.isOperator, true);
    });
  });

  group('AuthUser', () {
    test('isMicrosaltDomain checks email domain', () {
      expect(_testUser.isMicrosaltDomain, true);
    });

    test('non-microsalt domain rejected', () {
      const user = AuthUser(
        id: '1',
        email: 'test@gmail.com',
        name: 'Test',
        role: UserRole.user,
      );
      expect(user.isMicrosaltDomain, false);
    });

    test('firstName and lastName parsed from name', () {
      expect(_testUser.firstName, 'Test');
      expect(_testUser.lastName, 'User');
    });

    test('single name has empty lastName', () {
      const user = AuthUser(
        id: '1',
        email: 'a@b.com',
        name: 'Madonna',
        role: UserRole.user,
      );
      expect(user.firstName, 'Madonna');
      expect(user.lastName, '');
    });
  });
}

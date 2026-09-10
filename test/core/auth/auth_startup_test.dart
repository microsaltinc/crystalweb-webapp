import 'package:crystalapp/core/auth/auth_provider.dart';
import 'package:crystalapp/core/auth/auth_service.dart';
import 'package:crystalapp/core/auth/auth_state.dart';
import 'package:crystalapp/features/operators/models/operator.dart';
import 'package:crystalapp/features/operators/providers/operator_provider.dart';
import 'package:crystalapp/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthService extends Mock implements AuthService {}

const _user = AuthUser(
  id: 'user-1',
  email: 'user@microsaltinc.com',
  name: 'Web User',
  role: UserRole.user,
);

final _operator = Operator(
  id: 'operator-1',
  name: 'Operator One',
  active: true,
  hasPin: true,
  createdAt: DateTime.utc(2026, 8, 18),
  email: 'user@microsaltinc.com',
  managedBy: 'user@microsaltinc.com',
);

void main() {
  testWidgets('Web fragment token completes before restore and routing', (
    tester,
  ) async {
    final authService = _MockAuthService();
    when(() => authService.completeSamlAuth('web-fragment-jwt')).thenAnswer(
      (_) async =>
          AuthState.sessionOnly(token: 'web-fragment-jwt', user: _user),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(authService),
          operatorListProvider.overrideWith((_) async => [_operator]),
        ],
        child: const CrystalApp(initialAuthToken: 'web-fragment-jwt'),
      ),
    );
    await tester.pumpAndSettle();

    verify(() => authService.completeSamlAuth('web-fragment-jwt')).called(1);
    verifyNever(authService.restoreSession);
    expect(find.text('Select Operator'), findsOneWidget);
    expect(find.text('Operator One'), findsOneWidget);
  });
}

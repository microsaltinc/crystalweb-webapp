import 'package:crystalapp/core/api/api_client.dart';
import 'package:crystalapp/core/auth/auth_provider.dart';
import 'package:crystalapp/core/auth/auth_state.dart';
import 'package:crystalapp/features/batches/models/batch.dart';
import 'package:crystalapp/features/batches/widgets/campaign_ownership_section.dart';
import 'package:crystalapp/features/operators/models/operator.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDio extends Mock implements Dio {}

Batch _batch({String? ownerId, bool? ownerActive}) => Batch(
  id: 'batch-1',
  lotCode: 'LOT',
  formulaCode: 'F',
  dryerCode: 'D',
  campaignNum: 1,
  sublotCount: 1,
  imageCount: 1,
  status: 'pending',
  createdAt: DateTime.utc(2026),
  ownerOperatorId: ownerId,
  ownerOperatorName: ownerId == null ? null : 'Maria',
  ownerOperatorActive: ownerActive,
  ownerEmail: ownerId == null ? null : 'maria@microsaltinc.com',
  ownerSessionEmail: ownerId == null ? null : 'lab@microsaltinc.com',
);

Operator _operator(String id) => Operator(
  id: id,
  name: 'Maria',
  active: true,
  hasPin: true,
  createdAt: DateTime.utc(2026),
  email: 'maria@microsaltinc.com',
  sessionEmail: 'lab@microsaltinc.com',
  managedBy: '',
);

AuthNotifier _authNotifier(String operatorId) {
  final notifier = AuthNotifier();
  notifier.setAuthenticated(
    token: 'token',
    user: const AuthUser(
      id: 'user-1',
      email: 'lab@microsaltinc.com',
      name: 'Lab',
      role: UserRole.operator,
    ),
    activeOperator: _operator(operatorId),
  );
  return notifier;
}

Future<void> _pump(
  WidgetTester tester,
  Batch batch, {
  String operatorId = 'op-1',
  Dio? dio,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => _authNotifier(operatorId)),
        if (dio != null)
          apiClientProvider.overrideWithValue(ApiClient.withDio(dio)),
      ],
      child: MaterialApp(
        home: Scaffold(body: CampaignOwnershipSection(batch: batch)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => registerFallbackValue(Options()));

  testWidgets('unassigned campaigns show Assign action', (tester) async {
    await _pump(tester, _batch());

    expect(find.text('Unassigned'), findsOneWidget);
    expect(find.text('Assign'), findsOneWidget);
  });

  testWidgets('assigned campaign shows Reassign to any active operator', (
    tester,
  ) async {
    await _pump(tester, _batch(ownerId: 'op-1', ownerActive: true));

    expect(find.text('Reassign'), findsOneWidget);
    expect(find.text('Release'), findsNothing);
  });

  testWidgets('inactive owner remains identified and can be reassigned', (
    tester,
  ) async {
    await _pump(tester, _batch(ownerId: 'op-2', ownerActive: false));

    expect(find.text('Maria — maria (inactive)'), findsOneWidget);
    expect(find.text('Reassign'), findsOneWidget);
  });

  testWidgets('reassignment names both owners and waits for confirmation', (
    tester,
  ) async {
    final dio = MockDio();
    when(
      () => dio.get(
        '/api/v1/batches/batch-1/assignment-candidates',
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/assignment-candidates'),
        data: [
          {
            'id': 'op-2',
            'name': 'Ingrid',
            'email': 'ingrid@microsaltinc.com',
          },
        ],
      ),
    );
    when(
      () => dio.post(
        '/api/v1/batches/batch-1/assign',
        data: {
          'target_operator_id': 'op-2',
          'expected_ownership_version': 1,
        },
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/assign'),
        data: {
          'id': 'batch-1',
          'lot_code': 'LOT',
          'campaign_num': 1,
          'created_at': '2026-01-01T00:00:00Z',
          'owner_operator_id': 'op-2',
          'ownership_version': 2,
        },
      ),
    );
    await _pump(
      tester,
      _batch(ownerId: 'op-1', ownerActive: true),
      dio: dio,
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Reassign'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ingrid'));
    await tester.pumpAndSettle();

    expect(find.text('Reassign from Maria to Ingrid?'), findsOneWidget);
    verifyNever(
      () => dio.post(
        any(),
        data: any(named: 'data'),
        options: any(named: 'options'),
      ),
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Reassign').last);
    await tester.pumpAndSettle();
    verify(
      () => dio.post(
        '/api/v1/batches/batch-1/assign',
        data: {
          'target_operator_id': 'op-2',
          'expected_ownership_version': 1,
        },
        options: any(named: 'options'),
      ),
    ).called(1);
  });
}

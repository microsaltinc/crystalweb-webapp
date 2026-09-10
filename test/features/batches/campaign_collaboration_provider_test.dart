import 'package:crystalapp/core/api/api_client.dart';
import 'package:crystalapp/core/auth/auth_provider.dart';
import 'package:crystalapp/core/auth/auth_state.dart';
import 'package:crystalapp/features/batches/models/campaign_comment.dart';
import 'package:crystalapp/features/batches/providers/campaign_collaboration_provider.dart';
import 'package:crystalapp/features/operators/models/operator.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDio extends Mock implements Dio {}

Operator _operator() => Operator(
  id: 'op-1',
  name: 'Maria',
  active: true,
  hasPin: true,
  createdAt: DateTime.utc(2026),
  email: 'contact@microsaltinc.com',
  sessionEmail: 'lab@microsaltinc.com',
  managedBy: '',
);

AuthNotifier _authNotifier() {
  final notifier = AuthNotifier();
  notifier.setAuthenticated(
    token: 'operator-token',
    user: const AuthUser(
      id: 'user-1',
      email: 'lab@microsaltinc.com',
      name: 'Lab',
      role: UserRole.operator,
    ),
    activeOperator: _operator(),
  );
  return notifier;
}

Map<String, dynamic> _batchJson({String? ownerId}) => {
  'id': 'batch-1',
  'lot_code': 'LOT-1',
  'campaign_num': 1,
  'created_at': '2026-08-11T12:00:00Z',
  'owner_operator_id': ownerId,
  'owner_operator_name': ownerId == null ? null : 'Maria',
  'owner_operator_active': ownerId == null ? null : true,
  'owner_email': ownerId == null ? null : 'maria@microsaltinc.com',
  'owner_session_email': ownerId == null ? null : 'lab@microsaltinc.com',
  'ownership_version': ownerId == null ? 1 : 2,
};

void main() {
  setUpAll(() {
    registerFallbackValue(Options());
  });

  test('ownership filters produce API query values', () {
    expect(const OwnershipFilter.all().queryValue, 'all');
    expect(const OwnershipFilter.mine().queryValue, 'mine');
    expect(const OwnershipFilter.unassigned().queryValue, 'unassigned');
    expect(const OwnershipFilter.specificOwner('op-1').queryValue, 'op-1');
  });

  test('specific owner labels use operator identity not email-only', () {
    final operator = _operator();

    expect(
      const OwnershipFilter.specificOwner('op-1').label([operator]),
      'Maria — contact',
    );
  });

  test('campaign comment parses author projection', () {
    final comment = CampaignComment.fromJson({
      'id': 'comment-1',
      'batch_id': 'batch-1',
      'author_operator_id': 'op-1',
      'author_operator_name': 'Maria',
      'author_operator_active': false,
      'author_session_email': 'lab@microsaltinc.com',
      'author_requires_operator_name': true,
      'text': 'Shift note',
      'created_at': '2026-08-11T12:00:00Z',
    });

    expect(comment.authorDisplayLabel, 'lab@microsaltinc.com — Maria');
    expect(
      comment.authorDisplayWithStatus,
      'lab@microsaltinc.com — Maria (inactive)',
    );
  });

  test('claim posts to ownership endpoint and returns updated batch', () async {
    final dio = MockDio();
    when(
      () => dio.post(
        '/api/v1/batches/batch-1/claim',
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/api/v1/batches/batch-1/claim'),
        data: _batchJson(ownerId: 'op-1'),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(ApiClient.withDio(dio)),
        authStateProvider.overrideWith((ref) => _authNotifier()),
      ],
    );
    addTearDown(container.dispose);

    final batch = await claimCampaign(container, 'batch-1');

    expect(batch.ownerOperatorId, 'op-1');
    verify(
      () => dio.post(
        '/api/v1/batches/batch-1/claim',
        options: any(named: 'options'),
      ),
    ).called(1);
  });

  test('transfer and comment creation send exact payloads', () async {
    final dio = MockDio();
    when(
      () => dio.post(
        '/api/v1/batches/batch-1/transfer',
        data: {'target_operator_id': 'op-2'},
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(
          path: '/api/v1/batches/batch-1/transfer',
        ),
        data: _batchJson(ownerId: 'op-2'),
      ),
    );
    when(
      () => dio.post(
        '/api/v1/batches/batch-1/comments',
        data: {'text': 'Shift note'},
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(
          path: '/api/v1/batches/batch-1/comments',
        ),
        data: {
          'id': 'comment-1',
          'batch_id': 'batch-1',
          'author_operator_id': 'op-1',
          'author_operator_name': 'Maria',
          'author_operator_active': true,
          'author_session_email': 'lab@microsaltinc.com',
          'text': 'Shift note',
          'created_at': '2026-08-11T12:00:00Z',
        },
      ),
    );
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(ApiClient.withDio(dio)),
        authStateProvider.overrideWith((ref) => _authNotifier()),
      ],
    );
    addTearDown(container.dispose);

    final batch = await transferCampaign(
      container,
      'batch-1',
      targetOperatorId: 'op-2',
    );
    final comment = await createCampaignComment(
      container,
      'batch-1',
      text: 'Shift note',
    );

    expect(batch.ownerOperatorId, 'op-2');
    expect(comment.text, 'Shift note');
  });

  test('loads minimal candidates and sends ownership CAS assignment', () async {
    final dio = MockDio();
    when(
      () => dio.get(
        '/api/v1/batches/batch-1/assignment-candidates',
        options: any(named: 'options'),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(
          path: '/api/v1/batches/batch-1/assignment-candidates',
        ),
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
        requestOptions: RequestOptions(
          path: '/api/v1/batches/batch-1/assign',
        ),
        data: _batchJson(ownerId: 'op-2'),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(ApiClient.withDio(dio)),
        authStateProvider.overrideWith((ref) => _authNotifier()),
      ],
    );
    addTearDown(container.dispose);

    final candidates = await container.read(
      campaignAssignmentCandidatesProvider('batch-1').future,
    );
    final assigned = await assignCampaign(
      container,
      'batch-1',
      targetOperatorId: candidates.single.id,
      expectedOwnershipVersion: 1,
    );

    expect(candidates.single.accountLabel, '(ingrid)');
    expect(assigned.ownerOperatorId, 'op-2');
    expect(assigned.ownershipVersion, 2);
  });
}

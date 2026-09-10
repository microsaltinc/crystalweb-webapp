import 'dart:convert';
import 'dart:typed_data';

import 'package:crystalapp/core/api/api_client.dart';
import 'package:crystalapp/features/batches/providers/campaign_lock_coordinator.dart';
import 'package:crystalapp/features/batches/providers/campaign_locking_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordedRequest {
  RecordedRequest(this.options, this.body);
  final RequestOptions options;
  final Object? body;
}

class CampaignAdapter implements HttpClientAdapter {
  final requests = <RecordedRequest>[];
  final responses = <String, List<Object>>{};

  void enqueue(String path, Object body, {int status = 200}) {
    responses.putIfAbsent(path, () => []).add((status, body));
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = requestStream == null
        ? <int>[]
        : await requestStream.expand((value) => value).toList();
    final body =
        options.data ?? (bytes.isEmpty ? null : jsonDecode(utf8.decode(bytes)));
    requests.add(RecordedRequest(options, body));
    final queued = responses[options.path];
    final item = queued == null || queued.isEmpty
        ? (500, {'detail': 'unexpected request'})
        : queued.removeAt(0) as (int, Object);
    return ResponseBody.fromString(
      jsonEncode(item.$2),
      item.$1,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ProviderContainer containerFor(CampaignAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://secret.invalid'));
  dio.httpClientAdapter = adapter;
  return ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(ApiClient.withDio(dio))],
  );
}

Map<String, Object?> transition({
  String state = 'locked',
  int version = 2,
  bool changed = true,
}) => {
  'batch_id': 'b',
  'edit_state': state,
  'edit_state_version': version,
  'content_revision': 7,
  'changed': changed,
};

void main() {
  test(
    'readiness and unresolved conflicts decode through typed providers',
    () async {
      final adapter = CampaignAdapter()
        ..enqueue('/api/v1/batches/b/lock-readiness', {
          'batch_id': 'b',
          'edit_state': 'editable',
          'edit_state_version': 4,
          'content_revision': 7,
          'ready': false,
          'evaluated_at': '2026-08-12T00:00:00Z',
          'blockers': [
            {
              'category': 'image_review_incomplete',
              'message': 'Review image',
              'count': 1,
            },
          ],
        })
        ..enqueue('/api/v1/batches/b/registration-conflicts', [
          {
            'id': 'c',
            'batch_id': 'b',
            'object': {'bucket': 'safe', 'key': 'input.tif'},
            'safe_reason': 'Campaign is locked.',
            'occurrence_count': 1,
            'can_retry': true,
          },
        ]);
      final container = containerFor(adapter);
      addTearDown(container.dispose);
      final readiness = await container.read(
        campaignLockReadinessProvider('b').future,
      );
      final conflicts = await container.read(
        registrationConflictsProvider('b').future,
      );
      expect(readiness.blockers.single.message, 'Review image');
      expect(conflicts.single.object.key, 'input.tif');
      expect(
        adapter.requests.last.options.queryParameters['resolved'],
        isFalse,
      );
    },
  );

  test(
    'Lock and Unlock send version payload and preserve same-state result',
    () async {
      final adapter = CampaignAdapter()
        ..enqueue('/api/v1/batches/b/lock', transition())
        ..enqueue(
          '/api/v1/batches/b/unlock',
          transition(state: 'editable', changed: false),
        );
      final container = containerFor(adapter);
      addTearDown(container.dispose);
      final actions = container.read(campaignLockingActionsProvider);
      final locked = await actions.lock(
        'b',
        expectedEditStateVersion: 1,
        reason: ' final ',
      );
      final unlocked = await actions.unlock('b', expectedEditStateVersion: 2);
      expect(locked.changed, isTrue);
      expect(unlocked.changed, isFalse);
      final lockRequest = adapter.requests.singleWhere(
        (request) => request.options.path.endsWith('/lock'),
      );
      final unlockRequest = adapter.requests.singleWhere(
        (request) => request.options.path.endsWith('/unlock'),
      );
      expect(lockRequest.body, {
        'expected_edit_state_version': 1,
        'reason': 'final',
      });
      expect(unlockRequest.body, {'expected_edit_state_version': 2});
    },
  );

  test('Retry sends If-Match and returns typed resolution', () async {
    final adapter = CampaignAdapter()
      ..enqueue('/api/v1/batches/b/registration-conflicts/c/retry', {
        'conflict_id': 'c',
        'resolved': true,
        'registration_action': 'activated',
        'result_image_id': 'i',
        'content_revision': 8,
      });
    final container = containerFor(adapter);
    addTearDown(container.dispose);
    final result = await container
        .read(campaignLockingActionsProvider)
        .retryConflict('b', 'c', expectedEditStateVersion: 5);
    expect(result.registrationAction, 'activated');
    expect(
      adapter.requests.single.options.headers['If-Match'],
      '"campaign-edit-5"',
    );
  });

  test('Done coordinator reports advisory and lock-time blockers', () async {
    final advisory = CampaignAdapter()
      ..enqueue('/api/v1/batches/b/lock-readiness', {
        'batch_id': 'b',
        'edit_state': 'editable',
        'edit_state_version': 1,
        'content_revision': 1,
        'ready': false,
        'evaluated_at': '2026-08-12T00:00:00Z',
        'blockers': [
          {
            'category': 'campaign_report_missing',
            'message': 'Generate report',
            'count': 1,
          },
        ],
      });
    final first = containerFor(advisory);
    addTearDown(first.dispose);
    final blocked = await first
        .read(campaignLockCoordinatorProvider)
        .lockCampaignIfReady('b');
    expect((blocked as CampaignLockBlocked).blockers, ['Generate report']);

    final raced = CampaignAdapter()
      ..enqueue('/api/v1/batches/b/lock-readiness', {
        'batch_id': 'b',
        'edit_state': 'editable',
        'edit_state_version': 1,
        'content_revision': 1,
        'ready': true,
        'evaluated_at': '2026-08-12T00:00:00Z',
        'blockers': [],
      })
      ..enqueue('/api/v1/batches/b/lock', {
        'detail': {
          'code': 'campaign_not_ready',
          'message': 'Not ready.',
          'readiness': {
            'content_revision': 1,
            'ready': false,
            'evaluated_at': '2026-08-12T00:00:00Z',
            'blockers': [
              {
                'category': 'image_job_active',
                'message': 'Analysis started',
                'count': 1,
              },
            ],
          },
        },
      }, status: 409);
    final second = containerFor(raced);
    addTearDown(second.dispose);
    final raceResult = await second
        .read(campaignLockCoordinatorProvider)
        .lockCampaignIfReady('b');
    expect((raceResult as CampaignLockBlocked).blockers, ['Analysis started']);
  });

  test('access and transport errors fail closed without diagnostics', () async {
    final adapter = CampaignAdapter()
      ..enqueue('/api/v1/batches/b/lock-readiness', {
        'detail': 'Forbidden',
      }, status: 403);
    final container = containerFor(adapter);
    addTearDown(container.dispose);
    final result = await container
        .read(campaignLockCoordinatorProvider)
        .lockCampaignIfReady('b');
    expect(result, isA<CampaignLockUnavailable>());
    expect(result.toString(), isNot(contains('secret.invalid')));
  });
}

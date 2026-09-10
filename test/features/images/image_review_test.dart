import 'dart:convert';
import 'dart:typed_data';

import 'package:crystalapp/core/api/api_client.dart';
import 'package:crystalapp/core/api/user_facing_error.dart';
import 'package:crystalapp/features/images/models/image_model.dart';
import 'package:crystalapp/features/images/providers/image_provider.dart';
import 'package:crystalapp/features/images/widgets/image_review_status.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class ReviewAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final bodies = <Object?>[];
  final responses = <Object>[];
  final statuses = <int>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final bytes = requestStream == null
        ? <int>[]
        : await requestStream.expand((value) => value).toList();
    bodies.add(
      options.data ?? (bytes.isEmpty ? null : jsonDecode(utf8.decode(bytes))),
    );
    final isReview =
        options.path.endsWith('/review-complete') ||
        options.path.endsWith('/review-clear');
    final response = isReview && responses.isNotEmpty
        ? responses.removeAt(0)
        : options.path == '/api/v1/images'
        ? <Object>[]
        : imageJson(complete: false);
    final status = isReview && statuses.isNotEmpty ? statuses.removeAt(0) : 200;
    return ResponseBody.fromString(
      jsonEncode(response),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> imageJson({bool complete = true}) => {
  'id': 'i',
  'batch_id': 'b',
  'created_at': '2026-08-12T00:00:00Z',
  'review_complete': complete,
  'campaign_edit_state': 'editable',
  'campaign_edit_state_version': 4,
};

ProviderContainer reviewContainer(ReviewAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://private.invalid'));
  dio.httpClientAdapter = adapter;
  return ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(ApiClient.withDio(dio))],
  );
}

void main() {
  test('parses review provenance and parent campaign state', () {
    final image = ImageModel.fromJson({
      'id': 'i',
      'batch_id': 'b',
      'created_at': '2026-08-12T00:00:00Z',
      'review_complete': true,
      'review_completed_at': '2026-08-12T01:00:00Z',
      'reviewed_by_operator_name': 'Ana',
      'reviewed_content_revision': 4,
      'campaign_edit_state': 'locked',
      'campaign_edit_state_version': 2,
    });
    expect(image.reviewComplete, isTrue);
    expect(image.reviewedByOperatorName, 'Ana');
    expect(image.reviewedContentRevision, 4);
    expect(image.campaignIsLocked, isTrue);
  });

  test('legacy and malformed review values have safe defaults', () {
    final image = ImageModel.fromJson({
      'id': 'i',
      'batch_id': 'b',
      'created_at': '2026-08-12T00:00:00Z',
      'review_completed_at': 'bad',
    });
    expect(image.reviewComplete, isFalse);
    expect(image.reviewCompletedAt, isNull);
    expect(image.campaignEditStateVersion, 1);
  });

  test(
    'Complete and Clear send observed state and explicit clear reason',
    () async {
      final adapter = ReviewAdapter()
        ..responses.addAll([imageJson(), imageJson(complete: false)]);
      final container = reviewContainer(adapter);
      addTearDown(container.dispose);
      final actions = container.read(imageReviewActionsProvider);
      final completed = await actions.complete(
        'i',
        batchId: 'b',
        expectedEditStateVersion: 4,
      );
      final cleared = await actions.clear(
        'i',
        batchId: 'b',
        expectedEditStateVersion: 4,
      );
      expect(completed.reviewComplete, isTrue);
      expect(cleared.reviewComplete, isFalse);
      final reviewBodies = <Object?>[];
      final reviewHeaders = <Object?>[];
      for (var index = 0; index < adapter.requests.length; index++) {
        if (adapter.requests[index].path.contains('/review-')) {
          reviewHeaders.add(adapter.requests[index].headers['If-Match']);
          reviewBodies.add(adapter.bodies[index]);
        }
      }
      expect(reviewHeaders, ['"campaign-edit-4"', '"campaign-edit-4"']);
      expect(reviewBodies, [
        null,
        {'reason': 'operator_correction'},
      ]);
    },
  );

  test(
    'review conflict has safe user-facing error without request diagnostics',
    () async {
      final adapter = ReviewAdapter()
        ..responses.add({
          'detail': {
            'code': 'campaign_locked',
            'message': 'Unlock this campaign before changing review.',
          },
        })
        ..statuses.add(409);
      final container = reviewContainer(adapter);
      addTearDown(container.dispose);
      Object? failure;
      try {
        await container
            .read(imageReviewActionsProvider)
            .complete('i', batchId: 'b', expectedEditStateVersion: 4);
      } catch (error) {
        failure = error;
      }
      expect(failure, isNotNull);
      final message = userFacingError(failure!);
      expect(message, 'Unlock this campaign before changing review.');
      expect(message, isNot(contains('private.invalid')));
      expect(message, isNot(contains('Dio')));
    },
  );
  testWidgets(
    'review status distinguishes complete and invalidated retained review',
    (tester) async {
      final complete = ImageModel.fromJson({
        ...imageJson(),
        'review_complete': true,
        'reviewed_by_operator_name': 'Ana',
        'review_completed_at': '2026-08-12T01:00:00Z',
      });
      final invalidated = ImageModel.fromJson({
        ...imageJson(),
        'review_complete': true,
        'invalidated_at': '2026-08-12T02:00:00Z',
      });
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  ImageReviewStatus(image: complete, showActions: false),
                  ImageReviewStatus(image: invalidated, showActions: false),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Review complete'), findsOneWidget);
      expect(
        find.text('Review complete · retained but excluded'),
        findsOneWidget,
      );
    },
  );

  testWidgets('locked image review action is disabled', (tester) async {
    final image = ImageModel.fromJson({
      ...imageJson(complete: false),
      'campaign_edit_state': 'locked',
      'processing_status': 'complete',
    });
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: ImageReviewStatus(image: image)),
        ),
      ),
    );
    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Complete review'),
    );
    expect(button.onPressed, isNull);
  });
}

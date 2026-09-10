import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crystalapp/core/api/api_client.dart';
import 'package:crystalapp/features/batches/models/campaign_qualification.dart';
import 'package:crystalapp/features/batches/providers/campaign_qualification_provider.dart';
import 'package:crystalapp/features/batches/widgets/campaign_qualification_section.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

CampaignQualification _qualification({String editState = 'editable'}) =>
    CampaignQualification.fromJson({
      'batch_id': 'batch-1',
      'mode': 'production',
      'edit_state': editState,
      'edit_state_version': 3,
      'content_revision': 8,
      'campaign': {'status': 'accepted_with_exclusions'},
      'included_bags': [
        {
          'id': 'bag-a',
          'sublot_id': 'sublot-a',
          'sublot_identifier': 'A',
          'number': 1,
          'status': 'accepted',
          'image_count': 2,
          'operator_reviewed': true,
        },
        {
          'id': 'bag-a-pending',
          'sublot_id': 'sublot-a',
          'sublot_identifier': 'A',
          'number': 3,
          'status': 'pending_review',
          'image_count': 1,
          'operator_reviewed': true,
        },
        {
          'id': 'bag-c-4',
          'sublot_id': 'sublot-c',
          'sublot_identifier': 'C',
          'number': 4,
          'status': 'accepted',
          'image_count': 2,
          'operator_reviewed': true,
        },
        {
          'id': 'bag-c-5',
          'sublot_id': 'sublot-c',
          'sublot_identifier': 'C',
          'number': 5,
          'status': 'accepted',
          'image_count': 1,
          'operator_reviewed': true,
        },
      ],
      'excluded_bags': [
        {
          'id': 'bag-b',
          'sublot_id': 'sublot-b',
          'sublot_identifier': 'B',
          'number': 2,
          'status': 'rejected',
          'reason_code': 'other',
          'notes': 'Visible contamination',
          'image_count': 1,
        },
      ],
      'pending_bag_ids': ['bag-a-pending'],
      'can_finalize_as': ['accepted_with_exclusions', 'rejected'],
      'finalization_blockers': <Map<String, Object?>>[],
    });

Widget _app(CampaignQualification value) => ProviderScope(
  overrides: [
    campaignQualificationProvider.overrideWith((ref, id) async => value),
  ],
  child: const MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: CampaignQualificationSection(
          batchId: 'batch-1',
          readOnly: false,
        ),
      ),
    ),
  ),
);

class _PendingQualificationAdapter implements HttpClientAdapter {
  final Completer<void> complete = Completer<void>();
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    await complete.future;
    return ResponseBody.fromString(
      jsonEncode({
        'changed': true,
        'batch_id': 'batch-1',
        'sublot_id': 'sublot-a',
        'accepted_bag_ids': ['bag-a-pending'],
        'already_accepted_bag_ids': ['bag-a'],
        'skipped_bag_ids': <String>[],
        'campaign_status': 'accepted_with_exclusions',
        'campaign_reset': false,
        'edit_state_version': 3,
        'content_revision': 9,
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Widget _appWithApi(CampaignQualification value, ApiClient apiClient) =>
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(apiClient),
        campaignQualificationProvider.overrideWith((ref, id) async => value),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CampaignQualificationSection(
              batchId: 'batch-1',
              readOnly: false,
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets(
    'shows collapsed Sublot summaries and independently expands their Bags',
    (tester) async {
      await tester.pumpWidget(_app(_qualification()));
      await tester.pumpAndSettle();

      expect(find.text('Accepted with Exclusions'), findsOneWidget);
      expect(find.text('Excluded Bags'), findsNothing);
      expect(find.text('Sublot A'), findsOneWidget);
      expect(find.text('Sublot B'), findsOneWidget);
      expect(find.text('Sublot C'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('qualification-sublot-sublot-c-ready')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('qualification-sublot-sublot-a-ready')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('qualification-sublot-sublot-b-ready')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('accept-operator-reviewed-sublot-sublot-a')),
        findsNothing,
      );
      expect(
        find.byTooltip('Accept all Bags reviewed by an operator'),
        findsNothing,
      );
      expect(find.text('Accept all'), findsNothing);
      expect(find.text('Bag 1'), findsNothing);
      expect(find.text('Bag 2'), findsNothing);
      expect(find.text('Bag 3'), findsNothing);
      expect(find.textContaining('Visible contamination'), findsNothing);

      Finder summaryCount(String sublotId, String status) => find.descendant(
        of: find.byKey(
          ValueKey('qualification-sublot-$sublotId-summary-$status'),
        ),
        matching: find.byType(Text),
      );
      expect(
        tester.widget<Text>(summaryCount('sublot-a', 'accepted')).data,
        '1',
      );
      expect(
        tester.widget<Text>(summaryCount('sublot-a', 'pending_review')).data,
        '1',
      );
      expect(
        tester.widget<Text>(summaryCount('sublot-a', 'rejected')).data,
        '0',
      );
      expect(
        tester.widget<Text>(summaryCount('sublot-b', 'accepted')).data,
        '0',
      );
      expect(
        tester.widget<Text>(summaryCount('sublot-b', 'pending_review')).data,
        '0',
      );
      expect(
        tester.widget<Text>(summaryCount('sublot-b', 'rejected')).data,
        '1',
      );

      await tester.tap(find.text('Sublot A'));
      await tester.pumpAndSettle();
      expect(find.text('Bag 1'), findsOneWidget);
      expect(find.text('Bag 3'), findsOneWidget);
      expect(find.text('Bag 2'), findsNothing);
      final expandedAction = find.byKey(
        const ValueKey('accept-operator-reviewed-sublot-sublot-a'),
      );
      expect(expandedAction, findsOneWidget);
      expect(find.text('Accept all'), findsOneWidget);
      expect(
        tester.getTopLeft(expandedAction).dy,
        lessThan(
          tester
              .getTopLeft(find.byKey(const ValueKey('qualification-bag-bag-a')))
              .dy,
        ),
      );
      expect(
        tester.widget<OutlinedButton>(expandedAction).onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<TextButton>(
              find.byKey(
                const ValueKey('accept-qualification-bag-bag-a-pending'),
              ),
            )
            .onPressed,
        isNotNull,
      );

      await tester.tap(
        find.byKey(const ValueKey('expand-qualification-sublot-sublot-b')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bag 1'), findsOneWidget);
      expect(find.text('Bag 3'), findsOneWidget);
      expect(find.text('Bag 2'), findsOneWidget);
      expect(find.textContaining('Visible contamination'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('accept-qualification-bag-bag-b')),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.byTooltip(
          'Add an operator-created annotation before accepting this Bag',
        ),
        findsOneWidget,
      );
      expect(find.text('Reject Campaign'), findsOneWidget);
    },
  );

  testWidgets('bulk action sends request once and shows loading progress', (
    tester,
  ) async {
    final adapter = _PendingQualificationAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://private.invalid'));
    dio.httpClientAdapter = adapter;
    await tester.pumpWidget(
      _appWithApi(_qualification(), ApiClient.withDio(dio)),
    );
    await tester.pumpAndSettle();

    final action = find.byKey(
      const ValueKey('accept-operator-reviewed-sublot-sublot-a'),
    );
    expect(action, findsNothing);
    await tester.tap(find.text('Sublot A'));
    await tester.pumpAndSettle();
    expect(action, findsOneWidget);
    await tester.ensureVisible(action);
    expect(find.text('Bag 1'), findsOneWidget);
    final button = tester.widget<OutlinedButton>(action);
    expect(button.onPressed, isNotNull);
    button.onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    final callbackException = tester.takeException();
    expect(callbackException, isNull);

    expect(adapter.request?.method, 'PUT');
    expect(
      adapter.request?.path,
      '/api/v1/sublots/sublot-a/qualification/accept-operator-reviewed',
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<OutlinedButton>(action).onPressed, isNull);
    expect(find.text('Bag 1'), findsOneWidget);

    adapter.complete.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('campaign rejection requires an explicit reason dialog', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_qualification()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Reject Campaign'));
    await tester.tap(find.text('Reject Campaign'));
    await tester.pumpAndSettle();

    expect(
      find.byType(DropdownButtonFormField<QualificationReason>),
      findsOneWidget,
    );
    expect(find.text('Reason'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Reject Campaign'), findsWidgets);
  });

  testWidgets(
    'closing campaign rejection does not reuse a disposed controller',
    (tester) async {
      await tester.pumpWidget(_app(_qualification()));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Reject Campaign'));
      await tester.tap(find.text('Reject Campaign'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets(
    'Locked qualification remains readable without mutation controls',
    (tester) async {
      await tester.pumpWidget(_app(_qualification(editState: 'locked')));
      await tester.pumpAndSettle();

      expect(find.text('Locked — qualification is read-only.'), findsOneWidget);
      expect(find.text('Sublot A'), findsOneWidget);
      expect(find.text('Sublot B'), findsOneWidget);
      expect(find.text('Bag 1'), findsNothing);
      expect(
        find.byKey(const ValueKey('accept-operator-reviewed-sublot-sublot-a')),
        findsNothing,
      );
      expect(find.text('Reject & Exclude'), findsNothing);
      expect(find.text('Reject Campaign'), findsNothing);
    },
  );
}

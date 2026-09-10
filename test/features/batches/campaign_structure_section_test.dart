import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crystalapp/core/api/api_client.dart';
import 'package:crystalapp/features/batches/models/campaign_structure.dart';
import 'package:crystalapp/features/batches/providers/campaign_structure_provider.dart';
import 'package:crystalapp/features/batches/widgets/campaign_structure_section.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

CampaignStructure _structure({String editState = 'editable'}) =>
    CampaignStructure.fromJson({
      'batch_id': 'batch-1',
      'lot_code': 'CURRENT-LOT',
      'source_lot_code': 'SOURCE-LOT',
      'mode': 'production',
      'edit_state': editState,
      'edit_state_version': 2,
      'content_revision': 7,
      'active_sublots': [
        {
          'id': 'sublot-a',
          'identifier': 'B',
          'source_identifier': 'A',
          'label': 'Current line',
          'archived': false,
          'can_delete': false,
          'can_archive': true,
          'can_restore': false,
          'blockers': <String>[],
          'bags': [
            {
              'id': 'bag-1',
              'sublot_id': 'sublot-a',
              'number': 2,
              'source_sublot_id': 'sublot-a',
              'source_number': 1,
              'qualification_status': 'rejected',
              'reason_code': 'other',
              'image_count': 3,
              'archived': false,
              'effectively_archived': false,
              'can_delete': false,
              'can_archive': true,
              'can_restore': false,
              'blockers': <String>[],
            },
          ],
        },
      ],
      'excluded_bags': <Map<String, Object?>>[],
      'archived_sublots': <Map<String, Object?>>[],
      'archived_bags': <Map<String, Object?>>[],
    });

Widget _app(
  CampaignStructure value, {
  bool readOnly = false,
  ApiClient? apiClient,
  bool supportsMicroscopeUpload = true,
}) => ProviderScope(
  overrides: [
    campaignStructureProvider.overrideWith((ref, id) async => value),
    if (apiClient != null) apiClientProvider.overrideWithValue(apiClient),
  ],
  child: MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: CampaignStructureSection(
          batchId: 'batch-1',
          readOnly: readOnly,
          supportsMicroscopeUpload: supportsMicroscopeUpload,
        ),
      ),
    ),
  ),
);

class _BagMutationAdapter implements HttpClientAdapter {
  Map<String, dynamic>? body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = requestStream == null
        ? <int>[]
        : await requestStream.expand((value) => value).toList();
    if (options.path.endsWith('/sublot-a/bags')) {
      body = Map<String, dynamic>.from(
        options.data is Map
            ? options.data as Map
            : jsonDecode(utf8.decode(bytes)) as Map,
      );
      return ResponseBody.fromString(
        jsonEncode({
          'changed': true,
          'batch_id': 'batch-1',
          'entity_type': 'bag',
          'entity_id': 'bag-800',
          'action': 'created',
          'campaign_reset': false,
          'edit_state_version': 2,
          'content_revision': 8,
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    return ResponseBody.fromString('{}', 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  testWidgets('shows current/source structure and all editable controls', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_structure()));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('CURRENT-LOT (source: SOURCE-LOT)'),
      findsOneWidget,
    );
    expect(find.textContaining('Source Sublot A'), findsOneWidget);
    await tester.tap(find.textContaining('Sublot B'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Bag 2 — Excluded'), findsOneWidget);
    expect(find.textContaining('Source Bag 1'), findsOneWidget);
    expect(find.byTooltip('Edit Lot Code'), findsOneWidget);
    expect(find.byTooltip('Edit Sublot'), findsOneWidget);
    expect(find.byTooltip('Add Bag'), findsOneWidget);
    expect(find.byTooltip('Add microscope files'), findsOneWidget);
    expect(find.byTooltip('Edit or move Bag'), findsOneWidget);
    expect(find.byTooltip('Archive Bag'), findsOneWidget);
  });

  testWidgets(
    'explains campaign hierarchy and references operator documentation',
    (tester) async {
      await tester.pumpWidget(_app(_structure()));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(CampaignStructureSection));
      unawaited(showCampaignStructureHelp(context));
      await tester.pumpAndSettle();

      expect(find.text('Campaign structure'), findsOneWidget);
      expect(
        find.textContaining('Campaign → Sublot → Bag → SEM Images'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Qualification is recorded at Bag and Campaign levels',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Source identity never changes'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Campaign Qualification and Bag/Sublot Management'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'tech/projects/crystal_analysis/features/campaign-qualification',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'closing an edit dialog keeps its controller alive through route teardown',
    (tester) async {
      await tester.pumpWidget(_app(_structure()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Edit Lot Code'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets(
    'Add Bag accepts the displayed Bag prefix and submits its number',
    (tester) async {
      final adapter = _BagMutationAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://private.invalid'));
      dio.httpClientAdapter = adapter;

      await tester.pumpWidget(
        _app(_structure(), apiClient: ApiClient.withDio(dio)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Add Bag'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Bag 800');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(adapter.body, {'number': 800});
      expect(find.text('Add Bag'), findsNothing);
    },
  );

  testWidgets('Locked structure stays readable with every mutation hidden', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_structure(editState: 'locked')));
    await tester.pumpAndSettle();

    expect(find.text('Locked — structure is read-only.'), findsOneWidget);
    await tester.tap(find.textContaining('Sublot B'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Bag 2 — Excluded'), findsOneWidget);
    expect(find.byTooltip('Edit Lot Code'), findsNothing);
    expect(find.byTooltip('Edit Sublot'), findsNothing);
    expect(find.byTooltip('Add Bag'), findsNothing);
    expect(find.byTooltip('Add microscope files'), findsNothing);
    expect(find.byTooltip('Edit or move Bag'), findsNothing);
  });
}

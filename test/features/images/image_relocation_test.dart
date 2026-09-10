import 'dart:convert';
import 'dart:typed_data';

import 'package:crystalapp/core/api/api_client.dart';
import 'package:crystalapp/features/batches/models/campaign_structure.dart';
import 'package:crystalapp/features/images/models/image_model.dart';
import 'package:crystalapp/features/images/providers/image_provider.dart';
import 'package:crystalapp/features/images/widgets/image_grid.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class RelocationAdapter implements HttpClientAdapter {
  RequestOptions? relocationRequest;
  Object? relocationBody;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = requestStream == null
        ? <int>[]
        : await requestStream.expand((value) => value).toList();
    if (options.path.endsWith('/relocate')) {
      relocationRequest = options;
      relocationBody = options.data ?? jsonDecode(utf8.decode(bytes));
      return ResponseBody.fromString(
        jsonEncode({
          'changed': true,
          'campaign_reset': true,
          'edit_state_version': 3,
          'content_revision': 8,
          'image': imageJson(bagId: 'bag-b', sublot: 'B', bagNumber: 2),
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode(<Object>[]),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> imageJson({
  String bagId = 'bag-a',
  String sublot = 'A',
  int bagNumber = 1,
}) => {
  'id': 'image-1',
  'batch_id': 'batch-1',
  'bag_id': bagId,
  'sublot_id': 'sublot-${sublot.toLowerCase()}',
  'sublot_letter': sublot,
  'bag_number': bagNumber,
  'image_number': 1,
  's3_key': 'source.tif',
  'width_px': 100,
  'height_px': 100,
  'processing_status': 'complete',
  'crystal_count': 2,
  'created_at': '2026-08-13T00:00:00Z',
};

CampaignBagDestination destination(
  String bagId,
  String sublot,
  int number, {
  String? label,
}) => CampaignBagDestination(
  sublotIdentifier: sublot,
  sublotLabel: label,
  bag: CampaignBag(
    id: bagId,
    sublotId: 'sublot-${sublot.toLowerCase()}',
    number: number,
    sourceSublotId: 'sublot-${sublot.toLowerCase()}',
    sourceNumber: number,
    qualificationStatus: 'pending_review',
    imageCount: 0,
    archived: false,
    effectivelyArchived: false,
    capabilities: const StructureCapabilities(
      canDelete: false,
      canArchive: true,
      canRestore: false,
    ),
  ),
);

void main() {
  test(
    'structure exposes only active relocation destinations in display order',
    () {
      final structure = CampaignStructure.fromJson({
        'batch_id': 'batch-1',
        'lot_code': 'LOT',
        'source_lot_code': 'LOT',
        'mode': 'production',
        'edit_state': 'editable',
        'edit_state_version': 3,
        'content_revision': 7,
        'active_sublots': [
          {
            'id': 'sublot-b',
            'identifier': 'B',
            'source_identifier': 'B',
            'archived': false,
            'can_delete': false,
            'can_archive': true,
            'can_restore': false,
            'blockers': <Object>[],
            'bags': [
              {
                'id': 'bag-b',
                'sublot_id': 'sublot-b',
                'number': 2,
                'source_sublot_id': 'sublot-b',
                'source_number': 2,
                'qualification_status': 'pending_review',
                'archived': false,
                'effectively_archived': false,
                'can_delete': false,
                'can_archive': true,
                'can_restore': false,
                'blockers': <Object>[],
              },
            ],
          },
        ],
        'excluded_bags': <Object>[],
        'archived_sublots': <Object>[],
        'archived_bags': <Object>[],
      });

      expect(structure.activeBagDestinations, hasLength(1));
      expect(structure.activeBagDestinations.single.label, 'Sublot B · Bag 2');
    },
  );

  test(
    'relocation action sends destination and composite precondition',
    () async {
      final adapter = RelocationAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://private.invalid'));
      dio.httpClientAdapter = adapter;
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(ApiClient.withDio(dio)),
        ],
      );
      addTearDown(container.dispose);

      final result = await container
          .read(imageRelocationActionsProvider)
          .relocate(
            'image-1',
            batchId: 'batch-1',
            destinationBagId: 'bag-b',
            expectedEditStateVersion: 3,
            expectedContentRevision: 7,
          );

      expect(
        adapter.relocationRequest?.path,
        '/api/v1/images/image-1/relocate',
      );
      expect(
        adapter.relocationRequest?.headers['If-Match'],
        '"campaign-edit-3-content-7"',
      );
      expect(adapter.relocationBody, {'destination_bag_id': 'bag-b'});
      expect(result.image.bagId, 'bag-b');
      expect(result.campaignReset, isTrue);
      expect(result.contentRevision, 8);
    },
  );

  testWidgets('relocation dialog expands available Bags under each Sublot', (
    tester,
  ) async {
    final image = ImageModel.fromJson(imageJson());
    CampaignBagDestination? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: ImageGrid(
              images: [image],
              onImageTap: (_) {},
              onInvalidate: (_) {},
              relocationDestinations: [
                destination('bag-a', 'A', 1),
                destination('bag-a2', 'A', 4),
                destination('bag-b', 'B', 2, label: 'Retest'),
                destination('bag-b2', 'B', 3, label: 'Retest'),
              ],
              onRelocate: (image, target) async => selected = target,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Relocate'), findsOneWidget);
    expect(find.text('Discard Image'), findsOneWidget);

    await tester.tap(find.text('Relocate'));
    await tester.pumpAndSettle();
    expect(find.text('Relocate SEM Image'), findsOneWidget);
    final dialog = find.byType(AlertDialog);
    Finder dialogText(String text) =>
        find.descendant(of: dialog, matching: find.text(text));
    expect(dialogText('Sublot A'), findsOneWidget);
    expect(dialogText('Sublot B'), findsOneWidget);
    expect(dialogText('Bag 1'), findsNothing);
    expect(dialogText('Bag 2'), findsNothing);
    expect(dialogText('Bag 3'), findsNothing);
    expect(dialogText('Bag 4'), findsNothing);
    expect(dialogText('Retest'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('expand-relocate-sublot-A')));
    await tester.pumpAndSettle();
    expect(dialogText('Bag 1'), findsNothing);
    expect(dialogText('Bag 4'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('expand-relocate-sublot-B')));
    await tester.pumpAndSettle();
    expect(dialogText('Bag 2'), findsOneWidget);
    expect(dialogText('Bag 3'), findsOneWidget);
    expect(dialogText('Retest'), findsOneWidget);
    expect(dialogText('Bag 4'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('relocate-destination-bag-b')));
    await tester.pumpAndSettle();
    expect(selected?.bag.id, 'bag-b');
  });

  testWidgets('discarded image menu also offers relocation', (tester) async {
    final discarded = ImageModel.fromJson({
      ...imageJson(),
      'invalidated_at': '2026-08-13T01:00:00Z',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: ImageGrid(
              images: const [],
              invalidatedImages: [discarded],
              onImageTap: (_) {},
              onRevalidate: (_) {},
              relocationDestinations: [
                destination('bag-a', 'A', 1),
                destination('bag-b', 'B', 2),
              ],
              onRelocate: (_, _) async {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Relocate'), findsOneWidget);
    expect(find.text('Restore Image'), findsOneWidget);
  });

  testWidgets('relocation dialog explains when no destination exists', (
    tester,
  ) async {
    final image = ImageModel.fromJson(imageJson());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            child: ImageGrid(
              images: [image],
              onImageTap: (_) {},
              relocationDestinations: [destination('bag-a', 'A', 1)],
              onRelocate: (_, _) async {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Relocate'));
    await tester.pumpAndSettle();
    expect(
      find.text('No other active Bags are available in this campaign.'),
      findsOneWidget,
    );
  });
}

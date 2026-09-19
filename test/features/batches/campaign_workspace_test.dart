import 'package:crystalapp/features/batches/models/batch.dart';
import 'package:crystalapp/features/batches/models/campaign_structure.dart';
import 'package:crystalapp/features/batches/models/campaign_qualification.dart';
import 'package:crystalapp/features/batches/providers/batch_provider.dart';
import 'package:crystalapp/features/batches/providers/campaign_structure_provider.dart';
import 'package:crystalapp/features/batches/providers/campaign_qualification_provider.dart';
import 'package:crystalapp/features/batches/screens/batch_detail_screen.dart';
import 'package:crystalapp/features/images/models/image_model.dart';
import 'package:crystalapp/features/images/providers/image_provider.dart';
import 'package:crystalapp/features/reports/providers/report_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

CampaignStructure structure({bool locked = false, int bags = 1}) =>
    CampaignStructure.fromJson({
      'batch_id': 'batch',
      'lot_code': 'LOT',
      'source_lot_code': 'SOURCE',
      'mode': 'production',
      'edit_state': locked ? 'locked' : 'editable',
      'edit_state_version': 2,
      'content_revision': 3,
      'active_sublots': [
        {
          'id': 'sub',
          'identifier': 'A',
          'source_identifier': 'A',
          'archived': false,
          'can_archive': true,
          'bags': [
            for (var i = 1; i <= bags; i++)
              {
                'id': 'bag-$i',
                'sublot_id': 'sub',
                'number': i,
                'source_sublot_id': 'sub',
                'source_number': i,
                'qualification_status': 'pending_review',
                'image_count': 1,
                'archived': false,
                'effectively_archived': false,
                'can_archive': true,
              },
          ],
        },
      ],
    });
CampaignQualification qualification({bool locked = false, int bags = 1}) =>
    CampaignQualification.fromJson({
      'batch_id': 'batch',
      'mode': 'production',
      'edit_state': locked ? 'locked' : 'editable',
      'edit_state_version': 2,
      'content_revision': 3,
      'campaign': {'status': 'pending_review'},
      'included_bags': [
        for (var i = 1; i <= bags; i++)
          {
            'id': 'bag-$i',
            'sublot_id': 'sub',
            'sublot_identifier': 'A',
            'number': i,
            'status': 'pending_review',
            'image_count': 1,
            'operator_reviewed': false,
          },
      ],
      'pending_bag_ids': [for (var i = 1; i <= bags; i++) 'bag-$i'],
      'can_finalize_as': [],
      'finalization_blockers': [],
    });
ImageModel image(int bag, {String status = 'complete', int number = 1}) =>
    ImageModel(
      id: 'image-$bag-$number',
      batchId: 'batch',
      bagId: 'bag-$bag',
      sublotId: 'sub',
      sublotLetter: 'A',
      bagNumber: bag,
      imageNumber: number,
      s3Key: 'local',
      widthPx: 80,
      heightPx: 64,
      processingStatus: status,
      crystalCount: 3,
      createdAt: DateTime.utc(2026),
    );
Widget app({
  bool locked = false,
  int bags = 1,
  bool rnd = false,
  Future<List<ImageModel>> Function()? loadImages,
  bool qualificationError = false,
  Future<CampaignQualification> Function()? loadQualification,
  Future<CampaignStructure> Function()? loadStructure,
  GoRouter? router,
}) => ProviderScope(
  overrides: [
    batchDetailProvider.overrideWith(
      (ref, id) async => Batch.fromJson({
        'id': 'batch',
        'lot_code': 'LOT',
        'formula_code': 'FORMULA',
        'dryer_code': 'E',
        'campaign_num': 1,
        'sublot_count': 1,
        'image_count': bags,
        'processed_count': bags,
        'status': 'complete',
        'created_at': '2026-09-19T00:00:00Z',
        'edit_state': locked ? 'locked' : 'editable',
        'mode': rnd ? 'rnd' : 'production',
      }),
    ),
    campaignStructureProvider.overrideWith(
      (ref, id) async => loadStructure != null
          ? await loadStructure()
          : structure(locked: locked, bags: bags),
    ),
    campaignQualificationProvider.overrideWith((ref, id) async {
      if (qualificationError) throw Exception('unavailable');
      if (loadQualification != null) return await loadQualification();
      return qualification(locked: locked, bags: bags);
    }),
    imagesForBatchProvider.overrideWith(
      (ref, id) async => loadImages != null
          ? await loadImages()
          : [for (var i = 1; i <= bags; i++) image(i)],
    ),
    reportsForBatchProvider.overrideWith((ref, id) async => []),
  ],
  child: router != null
      ? MaterialApp.router(routerConfig: router)
      : MaterialApp(
          home: BatchDetailScreen(
            batchId: 'batch',
            routeRoot: rnd ? '/rnd' : '/batches',
          ),
        ),
);

void main() {
  Future<void> size(WidgetTester tester, Size value) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = value;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets(
    'single bag opens images with clear states and acceptance prerequisite',
    (tester) async {
      await size(tester, const Size(1440, 1100));
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('workspace-upload')), findsOneWidget);
      expect(find.text('Analysis: 1/1 ready'), findsOneWidget);
      expect(find.text('Human review: 0/1 complete'), findsOneWidget);
      expect(find.textContaining('Acceptance requires'), findsOneWidget);
      expect(find.text('Physical Structure'), findsNothing);
      expect(find.text('Review next image'), findsOneWidget);
      final accept = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Accept bag'),
      );
      expect(accept.onPressed, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'bag navigation scopes images and reports tab does not duplicate structure',
    (tester) async {
      await size(tester, const Size(1440, 1100));
      await tester.pumpWidget(app(bags: 8));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-bag-bag-4')));
      await tester.pumpAndSettle();
      expect(find.text('Sublot A · Bag 4'), findsOneWidget);
      expect(find.text('1 images · 0 reviewed'), findsOneWidget);
      expect(find.byKey(const Key('workspace-upload')), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Reports'));
      await tester.pumpAndSettle();
      expect(find.text('Bag Reports'), findsOneWidget);
      expect(find.byKey(const Key('workspace-upload')), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Images & review'));
      await tester.pumpAndSettle();
      expect(find.text('Sublot A · Bag 4'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('locked experiment retains browsing with mutations hidden', (
    tester,
  ) async {
    await size(tester, const Size(1440, 1100));
    await tester.pumpWidget(app(locked: true, rnd: true));
    await tester.pumpAndSettle();
    expect(find.text('R&D experiment'), findsOneWidget);
    expect(find.text('Project: Unassigned'), findsOneWidget);
    expect(find.text('Locked · view details'), findsOneWidget);
    expect(find.byKey(const Key('workspace-upload')), findsNothing);
    expect(find.text('Accept bag'), findsNothing);
    expect(find.text('Review next image'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('narrow workspace stays usable without horizontal overflow', (
    tester,
  ) async {
    await size(tester, const Size(390, 844));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('workspace-scope-picker')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'active progress refresh keeps bag scope and stops after completion',
    (tester) async {
      await size(tester, const Size(1440, 1100));
      var loads = 0;
      await tester.pumpWidget(
        app(
          bags: 2,
          loadImages: () async {
            loads++;
            return [
              image(1, status: loads == 1 ? 'analyzing' : 'complete'),
              image(2),
            ];
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-bag-bag-2')));
      await tester.pumpAndSettle();
      expect(find.text('1 analyzing'), findsOneWidget);
      await tester.pump(const Duration(seconds: 8));
      await tester.pumpAndSettle();
      expect(loads, 2);
      expect(find.text('Analysis: 2/2 ready'), findsOneWidget);
      expect(find.text('Sublot A · Bag 2'), findsOneWidget);
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(loads, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('missing qualification does not expose acceptance controls', (
    tester,
  ) async {
    await size(tester, const Size(1440, 1100));
    await tester.pumpWidget(app(qualificationError: true));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Bag decisions could not be loaded'),
      findsOneWidget,
    );
    expect(find.text('Accept bag'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'failed refresh retains scope but hides stale mutation controls',
    (tester) async {
      await size(tester, const Size(1440, 1100));
      var qualificationLoads = 0;
      var structureLoads = 0;
      await tester.pumpWidget(
        app(
          loadQualification: () async {
            if (++qualificationLoads > 1) throw Exception('offline');
            return qualification();
          },
          loadStructure: () async {
            if (++structureLoads > 1) throw Exception('offline');
            return structure();
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('workspace-upload')), findsOneWidget);
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(find.text('Sublot A · Bag 1'), findsOneWidget);
      expect(find.text('Accept bag'), findsNothing);
      expect(find.byKey(const Key('workspace-upload')), findsNothing);
      expect(find.textContaining('Could not refresh progress'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('next review follows gallery order within the selected bag', (
    tester,
  ) async {
    await size(tester, const Size(1440, 1100));
    final router = GoRouter(
      initialLocation: '/batches/batch',
      routes: [
        GoRoute(
          path: '/batches/batch',
          builder: (_, _) => const BatchDetailScreen(batchId: 'batch'),
        ),
        GoRoute(
          path: '/batches/batch/images/:id',
          builder: (_, state) =>
              Text('Reviewing ${state.pathParameters['id']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      app(
        router: router,
        loadImages: () async => [image(1, number: 9), image(1, number: 2)],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review next image'));
    await tester.pumpAndSettle();
    expect(find.text('Reviewing image-1-2'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

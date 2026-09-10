import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crystalapp/features/images/models/crystal.dart';
import 'package:crystalapp/features/images/providers/annotation_provider.dart';
import 'package:crystalapp/features/images/widgets/crystal_list_panel.dart';

Crystal _makeCrystal({
  String id = '1',
  bool discarded = false,
  CrystalSource source = CrystalSource.auto,
}) {
  return Crystal(
    id: id,
    imageId: 'img-1',
    quad: [
      const Point(0, 0),
      const Point(10, 0),
      const Point(10, 10),
      const Point(0, 10),
    ],
    confidence: 0.9,
    areaUm2: 10.0,
    equivalentDiameterUm: 1.5,
    partialVisible: false,
    discarded: discarded,
    source: source,
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SizedBox(width: 320, height: 600, child: child)),
  );
}

void main() {
  group('CrystalListPanel numbered labels', () {
    testWidgets('shows numbered CircleAvatar instead of icon', (tester) async {
      final crystals = [
        _makeCrystal(id: '1'),
        _makeCrystal(id: '2'),
        _makeCrystal(id: '3'),
      ];

      await tester.pumpWidget(
        _wrap(
          CrystalListPanel(
            crystals: crystals,
            annotationState: const AnnotationState(),
            onSelect: (_) {},
            onToggleDiscard: (_) {},
            onMarkPartial: (_, _) {},
            onToggleShowDiscarded: () {},
            onToggleOverlay: () {},
            onToggleNumbers: () {},
            onSubmit: () {},
          ),
        ),
      );

      // Should find CircleAvatars with numbers
      expect(find.byType(CircleAvatar), findsNWidgets(3));
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('no longer uses circle icon for crystal tiles', (tester) async {
      final crystals = [_makeCrystal()];

      await tester.pumpWidget(
        _wrap(
          CrystalListPanel(
            crystals: crystals,
            annotationState: const AnnotationState(),
            onSelect: (_) {},
            onToggleDiscard: (_) {},
            onMarkPartial: (_, _) {},
            onToggleShowDiscarded: () {},
            onToggleOverlay: () {},
            onToggleNumbers: () {},
            onSubmit: () {},
          ),
        ),
      );

      // The leading widget should be a CircleAvatar, not an Icon with circle
      expect(find.byType(CircleAvatar), findsOneWidget);
    });
  });

  group('CrystalListPanel control buttons', () {
    testWidgets('shows control buttons when crystal is selected', (
      tester,
    ) async {
      final crystals = [_makeCrystal(id: 'c1')];

      await tester.pumpWidget(
        _wrap(
          CrystalListPanel(
            crystals: crystals,
            annotationState: const AnnotationState(selectedCrystalId: 'c1'),
            onSelect: (_) {},
            onToggleDiscard: (_) {},
            onMarkPartial: (_, _) {},
            onToggleShowDiscarded: () {},
            onToggleOverlay: () {},
            onToggleNumbers: () {},
            onSubmit: () {},
            onNudge: (dx, dy) {},
            onScale: (factor) {},
            onUndo: (id) {},
          ),
        ),
      );

      // Should find arrow buttons
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
      // Scale buttons
      expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
      // Discard button
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('hides control buttons when no crystal selected', (
      tester,
    ) async {
      final crystals = [_makeCrystal(id: 'c1')];

      await tester.pumpWidget(
        _wrap(
          CrystalListPanel(
            crystals: crystals,
            annotationState: const AnnotationState(),
            onSelect: (_) {},
            onToggleDiscard: (_) {},
            onMarkPartial: (_, _) {},
            onToggleShowDiscarded: () {},
            onToggleOverlay: () {},
            onToggleNumbers: () {},
            onSubmit: () {},
          ),
        ),
      );

      expect(find.byIcon(Icons.arrow_upward), findsNothing);
      expect(find.byIcon(Icons.add_circle_outline), findsNothing);
    });

    testWidgets('shows undo button when crystal has pending change', (
      tester,
    ) async {
      final crystals = [_makeCrystal(id: 'c1')];
      final changes = {
        'c1': AnnotationChange(crystalId: 'c1', discarded: true),
      };

      await tester.pumpWidget(
        _wrap(
          CrystalListPanel(
            crystals: crystals,
            annotationState: AnnotationState(
              selectedCrystalId: 'c1',
              changes: changes,
            ),
            onSelect: (_) {},
            onToggleDiscard: (_) {},
            onMarkPartial: (_, _) {},
            onToggleShowDiscarded: () {},
            onToggleOverlay: () {},
            onToggleNumbers: () {},
            onSubmit: () {},
            onNudge: (dx, dy) {},
            onScale: (factor) {},
            onUndo: (id) {},
          ),
        ),
      );

      expect(find.byIcon(Icons.undo), findsOneWidget);
    });

    testWidgets('hides undo button when crystal has no pending change', (
      tester,
    ) async {
      final crystals = [_makeCrystal(id: 'c1')];

      await tester.pumpWidget(
        _wrap(
          CrystalListPanel(
            crystals: crystals,
            annotationState: const AnnotationState(selectedCrystalId: 'c1'),
            onSelect: (_) {},
            onToggleDiscard: (_) {},
            onMarkPartial: (_, _) {},
            onToggleShowDiscarded: () {},
            onToggleOverlay: () {},
            onToggleNumbers: () {},
            onSubmit: () {},
            onNudge: (dx, dy) {},
            onScale: (factor) {},
            onUndo: (id) {},
          ),
        ),
      );

      expect(find.byIcon(Icons.undo), findsNothing);
    });

    testWidgets('nudge up button calls onNudge with (0, -5)', (tester) async {
      final crystals = [_makeCrystal(id: 'c1')];
      double? capturedDx;
      double? capturedDy;

      await tester.pumpWidget(
        _wrap(
          CrystalListPanel(
            crystals: crystals,
            annotationState: const AnnotationState(selectedCrystalId: 'c1'),
            onSelect: (_) {},
            onToggleDiscard: (_) {},
            onMarkPartial: (_, _) {},
            onToggleShowDiscarded: () {},
            onToggleOverlay: () {},
            onToggleNumbers: () {},
            onSubmit: () {},
            onNudge: (dx, dy) {
              capturedDx = dx;
              capturedDy = dy;
            },
            onScale: (factor) {},
            onUndo: (id) {},
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.pump();

      expect(capturedDx, 0);
      expect(capturedDy, -5);
    });

    testWidgets('scale down calls onScale with 0.95', (tester) async {
      final crystals = [_makeCrystal(id: 'c1')];
      double? capturedFactor;

      await tester.pumpWidget(
        _wrap(
          CrystalListPanel(
            crystals: crystals,
            annotationState: const AnnotationState(selectedCrystalId: 'c1'),
            onSelect: (_) {},
            onToggleDiscard: (_) {},
            onMarkPartial: (_, _) {},
            onToggleShowDiscarded: () {},
            onToggleOverlay: () {},
            onToggleNumbers: () {},
            onSubmit: () {},
            onNudge: (dx, dy) {},
            onScale: (factor) => capturedFactor = factor,
            onUndo: (id) {},
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.remove_circle_outline));
      await tester.pump();

      expect(capturedFactor, 0.95);
    });
  });

  group('CrystalListPanel existing features preserved', () {
    testWidgets('shows crystal count in header', (tester) async {
      final crystals = [_makeCrystal(id: '1'), _makeCrystal(id: '2')];

      await tester.pumpWidget(
        _wrap(
          CrystalListPanel(
            crystals: crystals,
            annotationState: const AnnotationState(),
            onSelect: (_) {},
            onToggleDiscard: (_) {},
            onMarkPartial: (_, _) {},
            onToggleShowDiscarded: () {},
            onToggleOverlay: () {},
            onToggleNumbers: () {},
            onSubmit: () {},
          ),
        ),
      );

      expect(find.text('Crystals (2)'), findsOneWidget);
    });

    testWidgets('shows submit button when changes exist', (tester) async {
      final crystals = [_makeCrystal(id: 'c1')];
      final changes = {
        'c1': AnnotationChange(crystalId: 'c1', discarded: true),
      };

      await tester.pumpWidget(
        _wrap(
          CrystalListPanel(
            crystals: crystals,
            annotationState: AnnotationState(changes: changes),
            onSelect: (_) {},
            onToggleDiscard: (_) {},
            onMarkPartial: (_, _) {},
            onToggleShowDiscarded: () {},
            onToggleOverlay: () {},
            onToggleNumbers: () {},
            onSubmit: () {},
          ),
        ),
      );

      expect(find.text('Submit 1 change(s)'), findsOneWidget);
    });

    testWidgets('shows "No crystals detected" when list is empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          CrystalListPanel(
            crystals: const [],
            annotationState: const AnnotationState(),
            onSelect: (_) {},
            onToggleDiscard: (_) {},
            onMarkPartial: (_, _) {},
            onToggleShowDiscarded: () {},
            onToggleOverlay: () {},
            onToggleNumbers: () {},
            onSubmit: () {},
          ),
        ),
      );

      expect(find.text('No crystals detected'), findsOneWidget);
    });
  });
}

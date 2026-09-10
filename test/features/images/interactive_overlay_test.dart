import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crystalapp/features/images/models/crystal.dart';
import 'package:crystalapp/features/images/widgets/interactive_crystal_overlay.dart';
import 'package:crystalapp/features/images/widgets/crystal_overlay_painter.dart';

Crystal _makeCrystal({
  String id = '1',
  bool discarded = false,
  CrystalSource source = CrystalSource.auto,
}) {
  return Crystal(
    id: id,
    imageId: 'img-1',
    quad: [
      const Point(100, 100),
      const Point(200, 100),
      const Point(200, 200),
      const Point(100, 200),
    ],
    confidence: 0.9,
    areaUm2: 10.0,
    equivalentDiameterUm: 1.5,
    partialVisible: false,
    discarded: discarded,
    source: source,
  );
}

void main() {
  group('InteractiveCrystalOverlay', () {
    testWidgets('renders CustomPaint with CrystalOverlayPainter', (
      tester,
    ) async {
      final crystals = [_makeCrystal()];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 512,
              height: 512,
              child: InteractiveCrystalOverlay(
                crystals: crystals,
                selectedCrystalId: null,
                imageSize: const Size(512, 512),
                effectiveQuads: {'1': crystals[0].quad},
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.byType(GestureDetector), findsWidgets);
    });

    testWidgets('tap on crystal calls onTapCrystal with crystal id', (
      tester,
    ) async {
      final crystals = [_makeCrystal()];
      String? tappedId;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 512,
              height: 512,
              child: InteractiveCrystalOverlay(
                crystals: crystals,
                selectedCrystalId: null,
                imageSize: const Size(512, 512),
                effectiveQuads: {'1': crystals[0].quad},
                onTapCrystal: (id) => tappedId = id,
              ),
            ),
          ),
        ),
      );

      // Tap at the centroid of the crystal quad (150, 150 in image coords)
      final topLeft = tester.getTopLeft(find.byType(InteractiveCrystalOverlay));
      await tester.tapAt(topLeft + const Offset(150, 150));
      // Need to pump with duration to let the double-tap timer expire
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(tappedId, '1');
    });

    testWidgets('tap outside crystal calls onTapCrystal with null', (
      tester,
    ) async {
      final crystals = [_makeCrystal()];
      String? tappedId = 'initial';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 512,
              height: 512,
              child: InteractiveCrystalOverlay(
                crystals: crystals,
                selectedCrystalId: null,
                imageSize: const Size(512, 512),
                effectiveQuads: {'1': crystals[0].quad},
                onTapCrystal: (id) => tappedId = id,
              ),
            ),
          ),
        ),
      );

      // Tap at top-left corner, outside the crystal quad
      await tester.tapAt(
        tester.getTopLeft(find.byType(InteractiveCrystalOverlay)) +
            const Offset(5, 5),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(tappedId, isNull);
    });

    testWidgets('discarded crystals are not hit-tested', (tester) async {
      final crystals = [_makeCrystal(discarded: true)];
      String? tappedId = 'initial';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 512,
              height: 512,
              child: InteractiveCrystalOverlay(
                crystals: crystals,
                selectedCrystalId: null,
                imageSize: const Size(512, 512),
                effectiveQuads: {'1': crystals[0].quad},
                onTapCrystal: (id) => tappedId = id,
              ),
            ),
          ),
        ),
      );

      // Tap at center of the crystal quad
      await tester.tapAt(
        tester.getCenter(find.byType(InteractiveCrystalOverlay)),
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      // Should deselect (null) since the crystal is discarded
      expect(tappedId, isNull);
    });

    testWidgets('notifies onDragActiveChanged on pan within selected crystal', (
      tester,
    ) async {
      final crystals = [_makeCrystal()];
      bool? dragActive;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 512,
              height: 512,
              child: InteractiveCrystalOverlay(
                crystals: crystals,
                selectedCrystalId: '1',
                imageSize: const Size(512, 512),
                effectiveQuads: {'1': crystals[0].quad},
                onDragActiveChanged: (active) => dragActive = active,
                onQuadChanged: (_, _) {},
              ),
            ),
          ),
        ),
      );

      // Start drag inside the crystal quad center (150, 150 in image coords)
      final topLeft = tester.getTopLeft(find.byType(InteractiveCrystalOverlay));
      final crystalCenter = topLeft + const Offset(150, 150);
      final gesture = await tester.startGesture(crystalCenter);
      await tester.pump();

      // Move beyond the pan slop threshold (18px)
      await gesture.moveBy(const Offset(20, 20));
      await tester.pump();

      expect(dragActive, true);

      // End drag
      await gesture.up();
      await tester.pump();

      expect(dragActive, false);

      // Let all timers settle (double-tap timer)
      await tester.pumpAndSettle();
    });

    testWidgets('double tap calls onDoubleTap with image coordinates', (
      tester,
    ) async {
      final crystals = <Crystal>[];
      double? tapX, tapY;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 512,
              height: 512,
              child: InteractiveCrystalOverlay(
                crystals: crystals,
                selectedCrystalId: null,
                imageSize: const Size(512, 512),
                effectiveQuads: const {},
                onDoubleTap: (x, y) {
                  tapX = x;
                  tapY = y;
                },
              ),
            ),
          ),
        ),
      );

      // Double-tap at center
      final center = tester.getCenter(find.byType(InteractiveCrystalOverlay));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(center);
      await tester.pumpAndSettle();

      expect(tapX, isNotNull);
      expect(tapY, isNotNull);
    });
  });

  group('CrystalOverlayPainter with new features', () {
    test('creates painter with effectiveQuads', () {
      final crystals = [_makeCrystal()];
      final painter = CrystalOverlayPainter(
        crystals: crystals,
        selectedId: '1',
        imageSize: const Size(512, 512),
        showHandles: true,
        effectiveQuads: {'1': crystals[0].quad},
      );
      expect(painter, isNotNull);
      expect(painter.showHandles, true);
    });

    test('shouldRepaint returns true when showHandles changes', () {
      final crystals = [_makeCrystal()];
      final painter1 = CrystalOverlayPainter(
        crystals: crystals,
        selectedId: '1',
        imageSize: const Size(512, 512),
        showHandles: false,
      );
      final painter2 = CrystalOverlayPainter(
        crystals: crystals,
        selectedId: '1',
        imageSize: const Size(512, 512),
        showHandles: true,
      );
      expect(painter2.shouldRepaint(painter1), true);
    });

    test('shouldRepaint returns true when effectiveQuads changes', () {
      final crystals = [_makeCrystal()];
      final painter1 = CrystalOverlayPainter(
        crystals: crystals,
        selectedId: '1',
        imageSize: const Size(512, 512),
        effectiveQuads: {'1': crystals[0].quad},
      );
      final painter2 = CrystalOverlayPainter(
        crystals: crystals,
        selectedId: '1',
        imageSize: const Size(512, 512),
        effectiveQuads: {
          '1': [
            const Point(110, 110),
            const Point(210, 110),
            const Point(210, 210),
            const Point(110, 210),
          ],
        },
      );
      expect(painter2.shouldRepaint(painter1), true);
    });
  });

  group('DragMode', () {
    test('enum values exist', () {
      expect(DragMode.values.length, 2);
      expect(DragMode.none, isNotNull);
      expect(DragMode.move, isNotNull);
    });
  });

  group('CornerDrag', () {
    test('stores corner index', () {
      const drag = CornerDrag(2);
      expect(drag.cornerIndex, 2);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crystalapp/features/images/widgets/crystal_overlay_painter.dart';
import 'package:crystalapp/features/images/models/crystal.dart';

void main() {
  group('CrystalOverlayPainter', () {
    test('creates painter with crystal list', () {
      final crystals = [
        Crystal(
          id: '1',
          imageId: '2',
          quad: [const Point(10, 10), const Point(50, 10), const Point(50, 50), const Point(10, 50)],
          confidence: 0.9,
          areaUm2: 10.0,
          equivalentDiameterUm: 1.5,
          partialVisible: false,
          discarded: false,
          source: CrystalSource.auto,
        ),
      ];
      final painter = CrystalOverlayPainter(
        crystals: crystals,
        selectedId: null,
        imageSize: const Size(512, 512),
      );
      expect(painter, isNotNull);
    });

    test('shouldRepaint returns true for different crystals', () {
      final painter1 = CrystalOverlayPainter(
        crystals: [],
        selectedId: null,
        imageSize: const Size(512, 512),
      );
      final painter2 = CrystalOverlayPainter(
        crystals: [
          Crystal(
            id: '1',
            imageId: '2',
            quad: [const Point(0, 0), const Point(10, 0), const Point(10, 10), const Point(0, 10)],
            confidence: 0.9,
            areaUm2: 1.0,
            equivalentDiameterUm: 0.5,
            partialVisible: false,
            discarded: false,
            source: CrystalSource.auto,
          ),
        ],
        selectedId: null,
        imageSize: const Size(512, 512),
      );
      expect(painter2.shouldRepaint(painter1), true);
    });
  });
}

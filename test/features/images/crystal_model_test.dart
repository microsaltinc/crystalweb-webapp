import 'package:flutter_test/flutter_test.dart';

import 'package:crystalapp/features/images/models/crystal.dart';

void main() {
  group('Crystal model', () {
    test('fromJson parses quad points', () {
      final json = {
        'id': '123',
        'image_id': '456',
        'quad': [[10, 20], [50, 20], [50, 60], [10, 60]],
        'confidence': 0.92,
        'area_um2': 36.5,
        'equivalent_diameter_um': 6.82,
        'partial_visible': false,
        'discarded': false,
        'source': 'model',
      };
      final crystal = Crystal.fromJson(json);
      expect(crystal.quad.length, 4);
      expect(crystal.confidence, 0.92);
      expect(crystal.source, CrystalSource.auto);
    });

    test('isLarge based on 1.0um threshold', () {
      final crystal = Crystal(
        id: '1',
        imageId: '2',
        quad: [const Point(0, 0), const Point(10, 0), const Point(10, 10), const Point(0, 10)],
        confidence: 0.9,
        areaUm2: 10.0,
        equivalentDiameterUm: 1.5,
        partialVisible: false,
        discarded: false,
        source: CrystalSource.auto,
      );
      expect(crystal.isLarge(), true);
    });

    test('small crystal below threshold', () {
      final crystal = Crystal(
        id: '1',
        imageId: '2',
        quad: [const Point(0, 0), const Point(5, 0), const Point(5, 5), const Point(0, 5)],
        confidence: 0.9,
        areaUm2: 2.0,
        equivalentDiameterUm: 0.8,
        partialVisible: false,
        discarded: false,
        source: CrystalSource.auto,
      );
      expect(crystal.isLarge(), false);
    });

    test('discarded crystal excluded from counts', () {
      final crystal = Crystal(
        id: '1',
        imageId: '2',
        quad: [const Point(0, 0), const Point(10, 0), const Point(10, 10), const Point(0, 10)],
        confidence: 0.9,
        areaUm2: 10.0,
        equivalentDiameterUm: 1.5,
        partialVisible: false,
        discarded: true,
        source: CrystalSource.auto,
      );
      expect(crystal.discarded, true);
    });

    test('fromJson handles null optional fields', () {
      final json = {
        'id': '123',
        'image_id': '456',
        'quad': [[10, 20], [50, 20], [50, 60], [10, 60]],
        'confidence': 0.85,
        'area_um2': 20.0,
        'equivalent_diameter_um': 5.0,
        'partial_visible': false,
        'discarded': false,
        'source': 'model',
        'diameter_um': null,
        'shell_adjacent': null,
        'area_px': null,
      };
      final crystal = Crystal.fromJson(json);
      expect(crystal.diameterUm, isNull);
      expect(crystal.shellAdjacent, isNull);
      expect(crystal.areaPx, isNull);
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'id': '123',
        'image_id': '456',
        'quad': [[0, 0], [10, 0], [10, 10], [0, 10]],
        'confidence': 0.9,
        'area_um2': 5.0,
        'equivalent_diameter_um': 2.0,
        'partial_visible': true,
        'discarded': false,
        'source': 'operator',
      };
      final crystal = Crystal.fromJson(json);
      expect(crystal.diameterUm, isNull);
      expect(crystal.shellAdjacent, isNull);
      expect(crystal.areaPx, isNull);
      expect(crystal.source, CrystalSource.operator);
      expect(crystal.partialVisible, true);
    });

    test('bestDiameterUm returns diameterUm when available', () {
      final crystal = Crystal(
        id: '1',
        imageId: '2',
        quad: [const Point(0, 0), const Point(10, 0), const Point(10, 10), const Point(0, 10)],
        confidence: 0.9,
        areaUm2: 10.0,
        equivalentDiameterUm: 1.5,
        partialVisible: false,
        discarded: false,
        source: CrystalSource.auto,
        diameterUm: 2.3,
      );
      expect(crystal.bestDiameterUm, 2.3);
    });

    test('bestDiameterUm falls back to equivalentDiameterUm', () {
      final crystal = Crystal(
        id: '1',
        imageId: '2',
        quad: [const Point(0, 0), const Point(10, 0), const Point(10, 10), const Point(0, 10)],
        confidence: 0.9,
        areaUm2: 10.0,
        equivalentDiameterUm: 1.5,
        partialVisible: false,
        discarded: false,
        source: CrystalSource.auto,
      );
      expect(crystal.bestDiameterUm, 1.5);
    });

    test('isLarge returns true above threshold', () {
      final crystal = Crystal(
        id: '1',
        imageId: '2',
        quad: [const Point(0, 0), const Point(10, 0), const Point(10, 10), const Point(0, 10)],
        confidence: 0.9,
        areaUm2: 10.0,
        equivalentDiameterUm: 1.5,
        partialVisible: false,
        discarded: false,
        source: CrystalSource.auto,
      );
      expect(crystal.isLarge(), true);
      expect(crystal.isLarge(thresholdUm: 1.0), true);
    });

    test('isLarge returns false below threshold', () {
      final crystal = Crystal(
        id: '1',
        imageId: '2',
        quad: [const Point(0, 0), const Point(5, 0), const Point(5, 5), const Point(0, 5)],
        confidence: 0.9,
        areaUm2: 2.0,
        equivalentDiameterUm: 0.5,
        partialVisible: false,
        discarded: false,
        source: CrystalSource.auto,
      );
      expect(crystal.isLarge(), false);
      expect(crystal.isLarge(thresholdUm: 2.0), false);
    });

    test('isLarge returns true at exact threshold', () {
      final crystal = Crystal(
        id: '1',
        imageId: '2',
        quad: [const Point(0, 0), const Point(10, 0), const Point(10, 10), const Point(0, 10)],
        confidence: 0.9,
        areaUm2: 5.0,
        equivalentDiameterUm: 1.0,
        partialVisible: false,
        discarded: false,
        source: CrystalSource.auto,
      );
      expect(crystal.isLarge(thresholdUm: 1.0), true);
    });
  });
}

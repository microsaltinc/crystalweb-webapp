import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dio/dio.dart';

import 'package:crystalapp/core/api/api_client.dart';
import 'package:crystalapp/features/images/models/crystal.dart';
import 'package:crystalapp/features/images/providers/annotation_provider.dart';

class MockDio extends Mock implements Dio {}

Crystal _makeCrystal({
  String id = '1',
  List<Point>? quad,
}) {
  return Crystal(
    id: id,
    imageId: 'img-1',
    quad: quad ??
        [
          const Point(100, 100),
          const Point(200, 100),
          const Point(200, 200),
          const Point(100, 200),
        ],
    confidence: 0.9,
    areaUm2: 10.0,
    equivalentDiameterUm: 1.5,
    partialVisible: false,
    discarded: false,
    source: CrystalSource.auto,
  );
}

void main() {
  late MockDio mockDio;
  late ApiClient apiClient;
  late ProviderContainer container;

  setUp(() {
    mockDio = MockDio();
    apiClient = ApiClient.withDio(mockDio);
    container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(apiClient),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  AnnotationNotifier notifier() =>
      container.read(annotationProvider('img-1').notifier);

  AnnotationState state() => container.read(annotationProvider('img-1'));

  group('effectiveQuad', () {
    test('returns original quad when no pending changes', () {
      final crystal = _makeCrystal();
      final quad = notifier().effectiveQuad(crystal);
      expect(quad.length, 4);
      expect(quad[0].x, 100);
      expect(quad[0].y, 100);
    });

    test('returns changed quad when pending change exists', () {
      final crystal = _makeCrystal();
      final newQuad = [
        const Point(110, 110),
        const Point(210, 110),
        const Point(210, 210),
        const Point(110, 210),
      ];
      notifier().updateQuad(crystal, newQuad);
      final quad = notifier().effectiveQuad(crystal);
      expect(quad[0].x, 110);
      expect(quad[0].y, 110);
    });
  });

  group('nudgeQuad', () {
    test('translates all 4 points by (dx, dy)', () {
      final crystal = _makeCrystal();
      notifier().nudgeQuad(crystal, 5, 0);

      final change = state().changes['1']!;
      expect(change.quad, isNotNull);
      expect(change.quad![0].x, closeTo(105, 0.01));
      expect(change.quad![0].y, closeTo(100, 0.01));
      expect(change.quad![1].x, closeTo(205, 0.01));
      expect(change.quad![1].y, closeTo(100, 0.01));
      expect(change.quad![2].x, closeTo(205, 0.01));
      expect(change.quad![2].y, closeTo(200, 0.01));
      expect(change.quad![3].x, closeTo(105, 0.01));
      expect(change.quad![3].y, closeTo(200, 0.01));
    });

    test('nudge accumulates with previous nudge', () {
      final crystal = _makeCrystal();
      notifier().nudgeQuad(crystal, 5, 0);
      notifier().nudgeQuad(crystal, 0, -3);

      final change = state().changes['1']!;
      expect(change.quad![0].x, closeTo(105, 0.01));
      expect(change.quad![0].y, closeTo(97, 0.01));
    });

    test('nudge negative values work', () {
      final crystal = _makeCrystal();
      notifier().nudgeQuad(crystal, -10, -10);

      final change = state().changes['1']!;
      expect(change.quad![0].x, closeTo(90, 0.01));
      expect(change.quad![0].y, closeTo(90, 0.01));
    });
  });

  group('rotateQuad', () {
    test('rotates around centroid by given degrees', () {
      final crystal = _makeCrystal();
      notifier().rotateQuad(crystal, 90);

      final change = state().changes['1']!;
      expect(change.quad, isNotNull);

      // Original centroid is (150, 150)
      // After 90deg rotation, (100,100) relative to centroid is (-50,-50)
      // Rotated: (-50*cos90 - (-50)*sin90, -50*sin90 + (-50)*cos90)
      // = (0 + 50, -50 + 0) = (50, -50) relative
      // Absolute: (150 + 50, 150 - 50) = (200, 100)
      expect(change.quad![0].x, closeTo(200, 0.5));
      expect(change.quad![0].y, closeTo(100, 0.5));
    });

    test('360 degree rotation returns to original', () {
      final crystal = _makeCrystal();
      notifier().rotateQuad(crystal, 360);

      final change = state().changes['1']!;
      expect(change.quad![0].x, closeTo(100, 0.5));
      expect(change.quad![0].y, closeTo(100, 0.5));
      expect(change.quad![2].x, closeTo(200, 0.5));
      expect(change.quad![2].y, closeTo(200, 0.5));
    });

    test('small rotation preserves approximate positions', () {
      final crystal = _makeCrystal();
      notifier().rotateQuad(crystal, 5);

      final change = state().changes['1']!;
      // After 5 degrees the points should be close to original
      expect(change.quad![0].x, closeTo(100, 10));
      expect(change.quad![0].y, closeTo(100, 10));
    });
  });

  group('undoChange', () {
    test('removes pending change for given crystal', () {
      final crystal = _makeCrystal();
      notifier().nudgeQuad(crystal, 5, 5);
      expect(state().hasChanges, true);

      notifier().undoChange('1');
      expect(state().hasChanges, false);
      expect(state().changes.containsKey('1'), false);
    });

    test('does not affect other crystals', () {
      final crystal1 = _makeCrystal(id: '1');
      final crystal2 = _makeCrystal(id: '2');
      notifier().nudgeQuad(crystal1, 5, 5);
      notifier().nudgeQuad(crystal2, 10, 10);
      expect(state().changes.length, 2);

      notifier().undoChange('1');
      expect(state().changes.length, 1);
      expect(state().changes.containsKey('2'), true);
    });

    test('no-op when crystal has no pending change', () {
      notifier().undoChange('nonexistent');
      expect(state().hasChanges, false);
    });
  });

  group('updateQuad preserves other changes', () {
    test('preserves discarded flag when updating quad', () {
      final crystal = _makeCrystal();
      notifier().toggleDiscard(crystal);
      final newQuad = [
        const Point(110, 110),
        const Point(210, 110),
        const Point(210, 210),
        const Point(110, 210),
      ];
      notifier().updateQuad(crystal, newQuad);

      final change = state().changes['1']!;
      expect(change.discarded, true);
      expect(change.quad, isNotNull);
    });
  });
}

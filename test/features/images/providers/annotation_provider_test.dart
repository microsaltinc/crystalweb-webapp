import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:crystalapp/core/api/api_client.dart';
import 'package:crystalapp/features/images/models/crystal.dart';
import 'package:crystalapp/features/images/providers/annotation_provider.dart';

class MockDio extends Mock implements Dio {}

Crystal _makeCrystal({
  String id = '1',
  bool discarded = false,
  bool partialVisible = false,
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
    partialVisible: partialVisible,
    discarded: discarded,
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
      overrides: [apiClientProvider.overrideWithValue(apiClient)],
    );
  });

  tearDown(() {
    container.dispose();
  });

  AnnotationNotifier notifier() =>
      container.read(annotationProvider('img-1').notifier);

  AnnotationState state() => container.read(annotationProvider('img-1'));

  group('selectCrystal', () {
    test('updates selectedCrystalId', () {
      notifier().selectCrystal('crystal-5');
      expect(state().selectedCrystalId, 'crystal-5');
    });

    test('with null clears selection', () {
      notifier().selectCrystal('crystal-5');
      expect(state().selectedCrystalId, 'crystal-5');

      notifier().selectCrystal(null);
      expect(state().selectedCrystalId, isNull);
    });
  });

  group('toggleDiscard', () {
    test('sets discarded to true for non-discarded crystal', () {
      final crystal = _makeCrystal(discarded: false);
      notifier().toggleDiscard(crystal);

      expect(state().changes['1'], isNotNull);
      expect(state().changes['1']!.discarded, true);
    });

    test('sets discarded to false for discarded crystal', () {
      final crystal = _makeCrystal(discarded: true);
      notifier().toggleDiscard(crystal);

      expect(state().changes['1'], isNotNull);
      expect(state().changes['1']!.discarded, false);
    });

    test(
      'double toggleDiscard removes change entry (returns to original state)',
      () {
        final crystal = _makeCrystal(discarded: false);

        // First toggle: discarded = true (changed from original false)
        notifier().toggleDiscard(crystal);
        expect(state().hasChanges, true);
        expect(state().changes['1']!.discarded, true);

        // Second toggle with SAME crystal (server state unchanged):
        // toggleDiscard reads pending change (discarded=true), flips to false,
        // sees false == crystal.discarded (false), so removes the change entry.
        notifier().toggleDiscard(crystal);
        // The change entry should be removed since we're back to original
        expect(state().changes.containsKey('1'), false);
        expect(state().hasChanges, false);
      },
    );
  });

  group('markPartial', () {
    test('records partial_visible change', () {
      final crystal = _makeCrystal();
      notifier().markPartial(crystal, true);

      expect(state().changes['1'], isNotNull);
      expect(state().changes['1']!.partialVisible, true);
    });

    test('preserves existing changes when marking partial', () {
      final crystal = _makeCrystal();
      notifier().toggleDiscard(crystal);
      notifier().markPartial(crystal, true);

      final change = state().changes['1']!;
      expect(change.discarded, true);
      expect(change.partialVisible, true);
    });
  });

  group('hasChanges', () {
    test('returns false when no changes', () {
      expect(state().hasChanges, false);
    });

    test('returns true when changes exist', () {
      final crystal = _makeCrystal();
      notifier().toggleDiscard(crystal);
      expect(state().hasChanges, true);
    });
  });

  group('submit', () {
    test(
      'sends correct payload structure with updates/deletions/additions',
      () async {
        final crystal = _makeCrystal();
        notifier().toggleDiscard(crystal);

        Map<String, dynamic>? capturedData;
        when(
          () => mockDio.post(
            '/api/v1/images/img-1/annotations/submit',
            data: any(named: 'data'),
          ),
        ).thenAnswer((invocation) async {
          capturedData =
              invocation.namedArguments[const Symbol('data')]
                  as Map<String, dynamic>;
          return Response(
            requestOptions: RequestOptions(
              path: '/api/v1/images/img-1/annotations/submit',
            ),
            statusCode: 200,
            data: {'ok': true},
          );
        });

        final success = await notifier().submit();

        expect(success, true);
        expect(capturedData, isNotNull);
        // Verify the payload has updates/deletions/additions keys
        expect(capturedData!.containsKey('updates'), true);
        expect(capturedData!.containsKey('deletions'), true);
        expect(capturedData!.containsKey('additions'), true);
        // Our toggle-discard is an update (existing crystal, changed field)
        expect(capturedData!['updates'], isA<List>());
      },
    );

    test('clears changes on success', () async {
      final crystal = _makeCrystal();
      notifier().toggleDiscard(crystal);
      expect(state().hasChanges, true);

      when(
        () => mockDio.post(
          '/api/v1/images/img-1/annotations/submit',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(
            path: '/api/v1/images/img-1/annotations/submit',
          ),
          statusCode: 200,
          data: {'ok': true},
        ),
      );

      await notifier().submit();

      expect(state().hasChanges, false);
      expect(state().changes, isEmpty);
    });

    test('sets error on failure', () async {
      final crystal = _makeCrystal();
      notifier().toggleDiscard(crystal);

      when(
        () => mockDio.post(
          '/api/v1/images/img-1/annotations/submit',
          data: any(named: 'data'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(
            path: '/api/v1/images/img-1/annotations/submit',
          ),
          message: 'Network error',
        ),
      );

      final success = await notifier().submit();

      expect(success, false);
      expect(
        state().submitError,
        'Could not submit annotations. Something went wrong. Please try again.',
      );
      expect(state().submitError, isNot(contains('DioException')));
      expect(state().submitError, isNot(contains('Network error')));
      expect(state().isSubmitting, false);
      // Changes should be preserved on failure
      expect(state().hasChanges, true);
    });

    test('returns true with no-op when no changes', () async {
      final success = await notifier().submit();
      expect(success, true);
      // No API call should be made
      verifyNever(() => mockDio.post(any(), data: any(named: 'data')));
    });
  });
}
